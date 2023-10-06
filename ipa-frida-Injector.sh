#!/bin/bash

# Arguments check
if [ ! $# -eq 2 ]; then
	echo "Usage: $0 <ipa file> <provision file>"
  echo "The provisioning file is located in ~/Library/Developer/Xcode/DerivedData/<app>-<randomstring>/Build/Products/Debug-iphoneos/<app>.app/embedded.mobileprovision"
	exit 1
fi

if [ ! -f "$1" ]; then
  echo "File $1 not found"
  exit 1
fi

if [ ! -f "$2" ]; then
  echo "XCode generated provision file is needed"
  echo "If you need specific entitlements get them from original ipa and then write them in your project:"
  echo "security cms -D -i embedded.mobileprovision > profile.plist"
  echo "/usr/libexec/PlistBuddy -x -c 'Print :Entitlements' profile.plist > entitlements.plist"
  echo "PlistBuddy -c 'Set :CFBundleIdentifier com.yarix.redteam.\$APP_Repack' Payload/\$APP.app/Info.plist"
  exit 1
fi

if [ ! -d "Payload" ]; then
	# ipa unzip
	echo "[+] Unzipping ipa"
	unzip -q $1
fi

# Check requirements
echo "[?] Checking requirements..."
executables=("ios-deploy")
for executable in "${executables[@]}"; do
    if ! which "$executable" >/dev/null 2>&1; then
        echo "$executable need to be installed to run this script"
        echo "In order to install requirements run the following commands:"
        echo "brew install npm"
        echo "npm install -g ios-deploy"
        exit 1
    fi
done
echo "[*] Requirements OK!"
echo "[!] Setting up"
if [ ! -d insert_dylib ]; then 
	echo "[+] Downloading and building insert_dylib"
	git clone https://github.com/Tyilo/insert_dylib
	cd insert_dylib
	xcodebuild -quiet
  cd ..
else
	echo "[*] insert_dylib found in this folder!"
fi

# Retrieve last Frida gadget release
echo "[+] Getting last Frida Gadget"
FRIDA_URL='https://api.github.com/repos/frida/frida/releases/latest'
response=$(curl -s $FRIDA_URL)
tag_name=$(echo $response | grep -oE '"tag_name": "[^"]+"' | grep -oE "[0-9]+\.[0-9]+\.[0-9]+")
asset_url=$(echo $response | grep -oE '"browser_download_url": "[^"]+ios-universal.dylib.xz"' | grep -oE 'http[^"]+')
asset_name=$(echo $response | grep -oE '"name": "[^"]+ios-universal.dylib.xz"' | grep -oE 'frida-gadget[^"]+')
wget -q $asset_url

# Get developer key
devkey=$(security find-identity -p codesigning -v | grep -o '"[^"]\+"' | grep -o '[^"]\+')
echo "[+] Devkey Found: $devkey"

# Get app name and folders
app_folder=$(find "Payload" -type d -name "*.app" -print -quit)
app=$(basename "$app_folder" .app)
plugins_folder="Payload/$app.app/Plugins"
frameworks_folder="Payload/$app.app/Frameworks"
watch_folder="Payload/$app.app/Watch"
echo "[+] App name found: $app"

echo "[!] Starting patching"
echo "[*] Copying Frida in Frameworks folder"
# Copy Frida in $app.app/Frameworks
unxz $asset_name
mv "frida-gadget-$tag_name-ios-universal.dylib" FridaGadget.dylib
mv FridaGadget.dylib "$frameworks_folder"

# Loading the library
echo "[*] Loading the library"
insert_dylib/build/Release/insert_dylib --strip-codesig --inplace '@executable_path/Frameworks/FridaGadget.dylib' Payload/$app.app/$app

echo "[*] Copying provisioning file into app"
cp $2 Payload/$app.app/

# Set newline as split
oldIFS=$IFS
IFS=$'\n'

# Check if Plugin and Framework folders exist
if [ -d "$plugins_folder" ]; then
	echo "[!] Plugin folder found"
	echo "[-] Removing old signatures"
	find "$plugins_folder" -type f -name "_CodeSignature" -exec rm -rf {} +

	echo "[*] Signing plugins"
	pluginlist=$(find "$plugins_folder" -type d -name "*.appex")
	for plugin in $pluginlist; do
		pluginname=$(basename "$plugin" .appex)
		echo -e "\t[+] Signing plugin $pluginname"
		codesign -f -v -s "$devkey" "$plugin/$pluginname"
	done
fi

if [ -d "$frameworks_folder" ]; then
	echo "[!] Frameworks folder found"
	echo "[-] Removing old signatures"
	find "$frameworks_folder" -type f -name "_CodeSignature" -exec rm -rf {} +

	echo "[*] Signing Frameworks"
	frameworklist=$(find "$frameworks_folder" -type d -name "*.framework")
	for framework in $frameworklist; do
		frameworkname=$(basename "$framework" .framework)
		echo -e "\t[+] Signing framework $frameworkname"
		codesign -f -v -s "$devkey" "$framework/$frameworkname"
	done

	echo "[*] Signing dylib in Framework folder"
	dyliblist=$(find "$frameworks_folder" -type f -name "*.dylib")
	for dylib in $dyliblist; do
		dylibname=$(basename "$dylib" .dylib)
		echo -e "\t[+] Signing dylib $dylibname"
		codesign -f -v -s "$devkey" "$dylib"
	done
fi

# Check if Watch folder exists
if [ -d "$watch_folder" ]; then
  echo "[!] Watch folder found"
  echo "[-] Removing old signatures"
  cd $watch_folder/*.app
  find "." -type f -name "_CodeSignature" -exec rm -rf {} +

  echo "[*] Signing Frameworks"
  frameworklist=$(find "Frameworks" -type d -name "*.framework")
  for framework in $frameworklist; do
    frameworkname=$(basename "$framework" .framework)
    echo -e "\t[+] Signing framework $frameworkname"
    codesign -f -v -s "$devkey" "$framework/$frameworkname"
  done

  echo "[*] Signing dylib in Framework folder"
  dyliblist=$(find "Frameworks" -type f -name "*.dylib")
  for dylib in $dyliblist; do
    dylibname=$(basename "$dylib" .dylib)
    echo -e "\t[+] Signing dylib $dylibname"
    codesign -f -v -s "$devkey" "$dylib"
  done

  echo "[*] Signing plugins"
  pluginlist=$(find "Plugins" -type d -name "*.appex")
  for plugin in $pluginlist; do
    pluginname=$(basename "$plugin" .appex)
    echo -e "\t[+] Signing plugin $pluginname"
    codesign -f -v -s "$devkey" "$plugin/$pluginname"
  done
  cd -
fi

# Restore IFS
IFS=$oldIFS

echo "[+] Extracting entitlements"
security cms -D -i $2 > profile.plist
/usr/libexec/PlistBuddy -x -c 'Print :Entitlements' profile.plist > entitlements.plist

echo "[+] Signing executables"
codesign --force --sign "$devkey" --entitlements entitlements.plist "Payload/$app.app/$app"

# zip the app again
mkdir patched_ipa
echo "[*] Packing ipa"
zip -qry patched_ipa/$app"_patched.ipa" Payload/

# How to run the app without this script
echo "[!] IN 5 SECONDS THE APP WILL START AUTOMATICALLY IN DEBUG MODE, READ CAREFULLY:"
echo "[!] In order to manually run the app without this script use the following commands"
echo "[*] Get your version with"
echo -e "\tideviceinfo -k ProductVersion"
echo "[*] Mount the DeveloperDiskImage.dmg"
echo -e "\tideviceimagemounter /Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/DeviceSupport/<ios-version>/DeveloperDiskImage.dmg /Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/DeviceSupport/<ios-version>/DeveloperDiskImage.dmg.signature"
echo "[*] Launch the app in debug mode"
echo -e "\tidevicedebug -d run <app-package-name>"

echo "5..."
sleep 1
echo "4..."
sleep 1
echo "3..."
sleep 1
echo "2..."
sleep 1
echo "1..."
sleep 1


echo "[!] Launching app in debug mode..."
unzip patched_ipa/patched_codesign.ipa -d patched_ipa/
ios-deploy --bundle Payload/*.app --debug -W

