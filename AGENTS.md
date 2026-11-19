# VoiceType macOS — Память проекта и рабочие правила

Этот файл хранит ключевые решения, настройки окружения и предпочтения пользователя, чтобы в будущих сессиях сразу работать с полным контекстом.

## 1. Общие сведения о проекте
- **Приложение:** VoiceType для macOS (`com.farrukh.voicetype`), SwiftUI + AppKit, target macOS 14.0+.
- **Структура:** исходники в `VoiceType/VoiceType/Sources/`, конфигурация XcodeGen в `VoiceType/project.yml`, собранный бандл — `VoiceType.app` в корне репозитория.
- **Основные возможности:** глобальная диктовка по хоткею, запись встреч (микрофон + системный звук / стерео), транскрибация через внешний Windows Whisper сервер или облако `gapi.uz` с единым прогресс-баром (`TranscriptionProgress.swift`), рекапы/задачи через Anthropic Claude, словарь терминов, история, автоэкспорт.
- **Коммуникация:** общаться с пользователем на **русском языке**, кратко и по делу.

## 2. Сборка и подпись кода (важно для TCC-разрешений)
- **Команда сборки:** `bash VoiceType/build-app.sh`
  - Генерирует `VoiceType.xcodeproj` через `xcodegen generate`, собирает `Release`, копирует в `VoiceType.app`, подписывает бандл, регистрирует через `lsregister` и проверяет `codesign --verify --deep --strict`.
- **Сертификат разработчика:**
  - В Keychain установлен валидный сертификат `Apple Development: Farruh Abdujabborov (YH7G2JS3CM)` (Team ID `FHNJ2HBUNU`).
  - В `~/Library/Keychains/login.keychain-db` установлен промежуточный сертификат `AppleWWDRCAG3.cer` (Apple WWDR G3, действителен до 2030 года). Без него `security find-identity -v -p codesigning` не видит валидных идентичностей (в System Keychain лежит только истёкший WWDR G1 2023 года).
  - `VoiceType/build-app.sh` автоматически находит этот сертификат (или `Developer ID Application`) и подписывает `VoiceType.app` с `--force --deep --sign "$SIGN_IDENTITY" --timestamp=none`.
  - Стабильный `Designated Requirement` (`identifier "com.farrukh.voicetype"` + сертификат, без привязки к `cdhash`) позволяет **не сбрасывать разрешения macOS** (Микрофон, Мониторинг ввода, Accessibility, Запись экрана / системный звук) при пересборках.
- **Hardened Runtime:** в `VoiceType/project.yml` выставлено `ENABLE_HARDENED_RUNTIME: false`, отдельного `.entitlements` файла нет. Не включать `--options runtime` при подписи без добавления соответствующих entitlements (`com.apple.security.device.audio-input` и др.).
- **Перезапуск после сборки:** `pkill -x VoiceType || true; sleep 0.5; open VoiceType.app`.

## 3. Дизайн и предпочтения по UI
- **Текущая основная тема (`main`):** минималистичный стиль **Claude** (`ClaudeTheme.swift` — тёплые спокойные поверхности, мягкие скругления, serif-заголовки, спокойная типографика, поддержка светлой/тёмной темы). Это утверждённый базовый стиль.
- **Отклонённый эксперимент:** пробовали редизайн в стиле **Mac OS X 10.7 Lion / Late Aqua (2011)** (металлические градиентные шапки, глянцевые Aqua Blue кнопки, жёсткие рамки, без засечек) в отдельной ветке `style/lion-aqua` — пользователю не зашло, ветку удалили и вернулись на `main`.
- **Правило для экспериментов:** любые крупные визуальные редизайны и рискованные эксперименты всегда делать в отдельной git-ветке после чистого чекпойнта на `main`, чтобы можно было мгновенно откатиться.

## 4. Известные технические нюансы (не сломать при правках)
- **MenuBarExtra (`MenuBarView.swift`):** поповер в строке меню обязан явно закрываться через `dismissMenuBar()` (`dismiss()` + `windowBox.window?.close()`) при клике по пунктам, открывающим главное окно или запускающим действия, иначе поповер остаётся висеть поверх окна. У `ClaudeMenuRowButton` нужно следить за корректным сбросом hover-состояния и контрастом текста при наведении.
