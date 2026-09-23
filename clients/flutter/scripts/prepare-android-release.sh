#!/usr/bin/env bash
# Подготовка Android release signing
# Переменные окружения:
#   ANDROID_SIGNING_KEY      - Base64-encoded JKS keystore
#   ANDROID_SIGNING_KEY_PASS - Пароль от keystore
#   PLAYSTORE_DEPLOY_KEY     - JSON ключ сервис-аккаунта Google Play
set -e
cd android
echo $ANDROID_SIGNING_KEY | base64 --decode --ignore-garbage > key.jks
echo "storePassword=${ANDROID_SIGNING_KEY_PASS}" > key.properties
echo "keyPassword=${ANDROID_SIGNING_KEY_PASS}" >> key.properties
echo "keyAlias=liza" >> key.properties
echo "storeFile=../key.jks" >> key.properties
echo $PLAYSTORE_DEPLOY_KEY > keys.json
ls | grep key
bundle install
bundle update fastlane
bundle exec fastlane set_build_code_internal
cd ..
