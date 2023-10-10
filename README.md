# .ipa Frida Injector
A simple script to inject Frida gadget in an iOS application, so that it can be tested on non-jailbroken iPhones  

## Prerequisites
1. Xcode installed
2. A provisioning profile configured in Xcode
3. A provisioning file (to create it, you need to start a new blank project in Xcode and deploy it on the iPhone you're going to use for tests)
4. ios-deploy

## How to
Simply launch the script in a folder with the ipa file.  
```bash
ipa-frida-Injector.sh <ipa file> <provisioning file>
```
The provisioning file is usually located at
```
~/Library/Developer/Xcode/DerivedData/<app>-<randomstring>/Build/Products/Debug-iphoneos/<app>.app/embedded.mobileprovision
```

This script need to be run on macOS to work properly.
