# iOS-ipa-patcher-with-Frida
A simple script to inject Frida gadget in an iOS application, so that it can be tested on non-jailbroken iPhones  

## How to
Simply launch the script in a folder with the ipa file.  
```bash
ipa-frida-Injector.sh <ipa file> <provision file>
```
The provisioning file is usually located at
```
~/Library/Developer/Xcode/DerivedData/<app>-<randomstring>/Build/Products/Debug-iphoneos/<app>.app/embedded.mobileprovision
```

This script need to be run on macOS to work properly.
