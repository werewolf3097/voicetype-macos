#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

# Выбираем стабильный сертификат подписи кода (чтобы macOS TCC не сбрасывал разрешения при пересборках).
# Можно переопределить вручную: VOICETYPE_SIGN_IDENTITY="Apple Development: ..." ./build-app.sh
SIGN_IDENTITY="${VOICETYPE_SIGN_IDENTITY:-}"
if [ -z "$SIGN_IDENTITY" ]; then
  SIGN_IDENTITY=$(security find-identity -v -p codesigning 2>/dev/null \
    | awk -F'"' '/Developer ID Application:|Apple Development:/ {print $2; exit}')
fi
if [ -z "$SIGN_IDENTITY" ]; then
  SIGN_IDENTITY=$(security find-identity -v -p codesigning 2>/dev/null \
    | awk -F'"' '/^ *[0-9]+\)/ {print $2; exit}')
fi
if [ -z "$SIGN_IDENTITY" ]; then
  SIGN_IDENTITY="-"
  echo "⚠️  Валидный сертификат подписи кода не найден — используется ad-hoc подпись (-)."
else
  echo "🔐 Подпись сертификатом: $SIGN_IDENTITY"
fi

xcodegen generate

xcodebuild -project VoiceType.xcodeproj -scheme VoiceType -configuration Release build \
  CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO

BUILT_APP=$(xcodebuild -project VoiceType.xcodeproj -scheme VoiceType -configuration Release -showBuildSettings 2>/dev/null \
  | awk -F ' = ' '/ BUILT_PRODUCTS_DIR /{print $2; exit}')

DEST="$(pwd)/../VoiceType.app"
rm -rf "$DEST"
cp -R "$BUILT_APP/VoiceType.app" "$DEST"

if [ "$SIGN_IDENTITY" != "-" ]; then
  codesign --force --deep --sign "$SIGN_IDENTITY" --timestamp=none "$DEST"
fi

/System/Library/Frameworks/CoreServices.framework/Versions/Current/Frameworks/LaunchServices.framework/Versions/Current/Support/lsregister -f -R -trusted "$DEST"

codesign --verify --deep --strict "$DEST" && echo "Готово: $DEST"
codesign -d -r - "$DEST" 2>&1 || true
