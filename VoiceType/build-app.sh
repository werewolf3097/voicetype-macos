#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

xcodegen generate

xcodebuild -project VoiceType.xcodeproj -scheme VoiceType -configuration Release build \
  CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO

BUILT_APP=$(xcodebuild -project VoiceType.xcodeproj -scheme VoiceType -configuration Release -showBuildSettings 2>/dev/null \
  | awk -F ' = ' '/ BUILT_PRODUCTS_DIR /{print $2; exit}')

DEST="$(pwd)/../VoiceType.app"
rm -rf "$DEST"
cp -R "$BUILT_APP/VoiceType.app" "$DEST"

/System/Library/Frameworks/CoreServices.framework/Versions/Current/Frameworks/LaunchServices.framework/Versions/Current/Support/lsregister -f -R -trusted "$DEST"

codesign --verify --deep "$DEST" && echo "Готово: $DEST"
