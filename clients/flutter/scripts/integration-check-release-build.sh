#!/usr/bin/env bash

# generate a temporary signing key adn apply its configuration
cd android
KEYFILE="$(pwd)/key.jks"
echo "Generating signing configuration with $KEYFILE..."
keytool -genkey -keyalg RSA -alias key -keysize 4096 -dname "cn=Liza CI, ou=Head of bad integration tests, o=Prodamus, c=TLH" -keypass LIZA -storepass LIZA -validity 1 -keystore "$KEYFILE" -storetype "pkcs12"
echo "storePassword=LIZA" >> key.properties
echo "keyPassword=LIZA" >> key.properties
echo "keyAlias=key" >> key.properties
echo "storeFile=$KEYFILE" >> key.properties
ls | grep key
cd ..

# build release mode APK
flutter pub get
flutter build apk --release

# install and launch APK
flutter install
adb shell am start -n com.prodamus.laba.liza/com.prodamus.laba.liza.MainActivity

sleep 5

# check whether Liza runs
adb shell ps | awk '{print $9}' | grep com.prodamus.laba.liza
