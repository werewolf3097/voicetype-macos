# VoiceType macOS — Память проекта и рабочие правила

Этот файл хранит ключевые решения, настройки окружения, архитектурные договорённости и предпочтения пользователя, чтобы в будущих сессиях сразу работать с полным контекстом.

## 1. Общие сведения о проекте
- **Приложение:** VoiceType для macOS (`com.farrukh.voicetype`), SwiftUI + AppKit, target macOS 14.0+, Swift 5.0.
- **Структура:** исходники в `VoiceType/VoiceType/Sources/`, тесты в `VoiceType/VoiceTypeTests/`, конфигурация XcodeGen в `VoiceType/project.yml`, собранный бандл — `VoiceType.app` в корне репозитория.
- **Важно про XcodeGen:** `VoiceType/project.yml` подхватывает всё из `VoiceType/Sources` для основного таргета, но в таргете `VoiceTypeTests` файлы перечислены явно. При добавлении нового `.swift` файла нужно прописывать его в `VoiceTypeTests` (если тестируется) и запускать `xcodegen generate`.
- **Коммуникация:** общаться с пользователем на **русском языке**, кратко, честно и по делу.

## 2. Сборка и подпись кода (важно для TCC-разрешений)
- **Команда сборки:** `bash VoiceType/build-app.sh`
  - Генерирует `VoiceType.xcodeproj` через `xcodegen generate`, собирает `Release`, копирует в `VoiceType.app`, подписывает бандл, регистрирует через `lsregister` и проверяет `codesign --verify --deep --strict`.
- **Юнит-тесты:** `cd VoiceType && xcodebuild -project VoiceType.xcodeproj -scheme VoiceType test CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO`
- **Сертификат разработчика:**
  - В Keychain установлен валидный сертификат `Apple Development: Farruh Abdujabborov (YH7G2JS3CM)` (Team ID `FHNJ2HBUNU`).
  - В `~/Library/Keychains/login.keychain-db` установлен промежуточный сертификат `AppleWWDRCAG3.cer` (Apple WWDR G3, действителен до 2030 года). Без него `security find-identity -v -p codesigning` не видит валидных идентичностей (в System Keychain лежит только истёкший WWDR G1 2023 года).
  - `VoiceType/build-app.sh` автоматически находит этот сертификат (или `Developer ID Application`) и подписывает `VoiceType.app` с `--force --deep --sign "$SIGN_IDENTITY" --timestamp=none`.
  - Стабильный `Designated Requirement` (`identifier "com.farrukh.voicetype"` + сертификат, без привязки к `cdhash`) позволяет **не сбрасывать разрешения macOS** (Микрофон, Мониторинг ввода, Accessibility, Запись экрана / системный звук) при пересборках.
- **Hardened Runtime:** в `VoiceType/project.yml` выставлено `ENABLE_HARDENED_RUNTIME: false`, отдельного `.entitlements` файла нет. Не включать `--options runtime` при подписи без добавления соответствующих entitlements (`com.apple.security.device.audio-input` и др.).
- **Перезапуск после сборки:** указывать полный путь к бандлу:
  `pkill -x VoiceType || true; sleep 0.5; open "/Users/farrukh/orca/workspaces/voicetype-macos/telegram-dictation-style-integration/VoiceType.app"`

## 3. Дизайн и предпочтения по UI
- **Утверждённая тема (Paper UI):** `PaperTheme.swift`, `PaperComponents.swift`, `PaperTextureGenerator.swift`.
  - В оформлении оставлены чистые базовые темы **Светлая («Чистый лист»)** и **Тёмная («Графит»)** + режим **Системная** (`AppearanceMode` переключается в `PaperSegmentedControl`).
  - **Выбор 9 бумажных текстур и слайдеры глубины/зерна выпилены из UI Настроек** по решению пользователя (визуальная разница между светлыми бумагами была почти незаметна).
  - Системная тема отслеживается через `SystemAppearanceObserver` (`NSApp.observe(\.effectiveAppearance)` + `AppleInterfaceThemeChangedNotification`), а `PaperEnvironmentModifier` сам выставляет единый `.preferredColorScheme(resolved.isDark ? .dark : .light)` — не дублировать `.preferredColorScheme` внутри `SettingsView` или `MenuBarView`, иначе залипает переключение `Светлая → Системная`.
  - **Контуры в светлой теме:** `PaperTokens.hairline = 1.0` (`0.5pt` давало обрывистые линии на Retina/1x), и в `.l2OnPaper` нельзя накладывать белый highlight `.strokeBorder` поверх внешней рамки — highlight делается с `.padding(1)` внутри рамки.
- **Навигация:** пункт **«Встречи»** обязательно остаётся в главном левом сайдбаре и в поповере строки меню (`MenuBarView.swift`).
- **Шрифты (`FontPreset`):** оставлено несколько вариантов, применяются единообразно во всех разделах включая «Встречи» (`DashboardMeetingsView`):
  - `Бумага (New York + SF)` (по умолчанию), `Книжный (Charter + SF)`, `Системный (SF)`, `Мягкий (SF Rounded)`, `Редакционный (Cormorant + Inter)`.
- **Отклонённый эксперимент:** стиль Mac OS X 10.7 Lion / Late Aqua (2011) (ветка `style/lion-aqua`) был отклонён.
- **Правило для экспериментов:** крупные визуальные редизайны делать в отдельной ветке после чистого чекпойнта на `main`.

## 4. Распознавание речи (STT) и раздельные очереди
Реализованы **две независимые настраиваемые очереди** приоритетов в `SettingsStore.swift` с управлением `↑`/`↓` и вкл/выкл в `DashboardSettingsView.swift`:
1. **Диктовка (`sttDictationRoute` / `STTDictationSource`):**
   - `localGateway` (Домашний шлюз Tailscale / Opus 24 кбит/с, синхронизирован с `useHomeServer`), `gapi` (`gapi.uz`), `gemini` (`Google Gemini`), `openai` (`OpenAI whisper-1`).
   - Обрабатывается через `DictationTranscriptionCoordinator` с каскадным переходом `#1 → #2 → #3 → #4`.
2. **Встречи (`sttMeetingRoute` / `STTMeetingSource`):**
   - `localWhisper` (Локальный сервер встреч Whisper — URL вынесен на видное место в карточку STT), `gapi` (`gapi.uz`), `gemini` (Gemini Audio), `openai` (OpenAI Whisper).
   - Настройка `waitForLocalMeetingServerInQueue`: если включена и локальный сервер #1 оффлайн, встреча ждёт в очереди (с кнопкой ручной отправки в следующий облачный сервис); если выключена — сразу переходит к `#2` и далее.

### Специфика STT-провайдеров (`CloudAudioSTTProviders.swift`, проверено по документации)
- **Anthropic Claude (`docs.anthropic.com`):** Messages API **не принимает аудиофайлы** (только текст и изображения), поэтому Anthropic **не включён в STT-очереди** (используется только для LLM-очистки текста и рекапов).
- **Google Gemini (`ai.google.dev/gemini-api/docs/audio`):** принимает аудио (до ~9.5 ч), но **автоматически сводит стерео в моно**. Поэтому `GeminiAudioSTTProvider` для встреч нарезает дорожки `micURL` (спикер 1 «Вы») и `sysURL` (спикер 2 «Собеседники») через VAD (`WhisperWindowsClient.analyzeSpeechSlices`, чанки до 180 с, сжатие AAC/M4A при >12 МБ) и отправляет **раздельно**, запрашивая JSON с относительными таймкодами и склеивая через `mergeAndCleanSegments`.
- **OpenAI (`platform.openai.com/docs/guides/speech-to-text`):** строгий лимит **25 МБ на запрос**; `verbose_json` с таймкодами сегментов поддерживает `whisper-1` (тогда как `gpt-4o-mini-transcribe` отдаёт только `json`/`text`). `OpenAIAudioSTTProvider` нарезает аудио через VAD и при >23 МБ сжимает в AAC/M4A, отправляет `mic` и `sys` раздельно через `whisper-1` (`verbose_json`).
- **`gapi.uz`:** облачный STT-провайдер, особенно хорош для узбекской и смешанной рус/узб речи (диктовка + стерео-встречи).

## 5. Постобработка текста ИИ (LLM), модели и стили
- **Мультипровайдер (`LLMPostProcessor.swift`):** поддерживаются `Anthropic Claude` (по умолчанию `claude-haiku-5-5`), `OpenAI` (`gpt-5-mini`), `Google Gemini` (`gemini-3.8-flash`), `Другой (OpenAI-совм.)` (OpenRouter, Groq, DeepSeek, Ollama, LM Studio). Ключи хранятся в macOS Keychain (`KeychainStore.swift`).
- **Поле модели (драфтовый UX):** значения моделей по умолчанию хранятся как `""` (в поле виден серый драфт `defaultModel`, работает автовыбор), пользователь может кликнуть и вписать любую модель (например, `gemini-4-hydrogen`), сбросить кнопкой `×` или выбрать из живого списка `/models` в меню `▾`.
- **Критичные особенности API-моделей (исправлено):**
  - **Thinking-модели Gemini (`gemini-4-hydrogen`, `gemini-3.8-flash` и др.):** тратят `maxOutputTokens` сначала на внутреннее размышление (`thoughtsTokenCount`). В `testConnection()` используется `maxTokens: 1024` (вместо 16, из-за которых приходил пустой ответ `MAX_TOKENS`), в `cleanup`/`recap` — `8192`, а при парсинге отфильтровываются части `thought == true`.
  - **OpenAI reasoning-модели (`gpt-5*`, `o1*`, `o3*`, `o4*`, `codex*`):** требуют `max_completion_tokens` вместо `max_tokens` и не принимают `temperature: 0.2` (используется `OpenAIModernBody` с `temperature = nil` для reasoning-моделей).
- **4 категории стилей диктовки (`CleanupStyle`) + общая база:**
  - `Без обработки` (0% правок), `Дружественный` (лёгкая правка, живой чат/Telegram), `Деловой` (средняя правка, коллеги/письма/заметки), `Формальный` (полная редактура на «Вы», документы).
  - Во всех 3 ИИ-стилях всегда зашита общая база: пунктуация, орфография, падежи, удаление слов-паразитов и самоисправлений.
  - Есть 5 надстроек (`CleanupModifiers`): `Без воды`, `Списки и абзацы`, `Код и термины` (по умолчанию вкл.), `Автотон по приложению` (по имени активного окна `Telegram/Slack` → Дружественный, `Mail/Notes/Cursor/Xcode/Terminal` → Деловой), `Свой акцент` (доп. инструкция).
- **Телеметрия и безопасный fallback (`AppState.swift`, `HistoryStore.swift`):**
  - В каждой записи истории (`TranscriptionRecord.llmSummary`) сохраняется точный итог ИИ (`ИИ: Gemini · ... (540 мс)`, `Без ИИ (...)` или `Ошибка ...`) и отображается на главном экране и в Истории. При ошибке LLM текст больше не теряется — вставляется исходная расшифровка.

## 6. Известные технические нюансы (не сломать при правках)
- **MenuBarExtra (`MenuBarView.swift`):** поповер в строке меню обязан явно закрываться через `dismissMenuBar()` (`dismiss()` + `windowBox.window?.close()`) при клике по пунктам, открывающим главное окно или запускающим действия, иначе поповер остаётся висеть поверх окна. У `PaperMenuRowButton` нужно следить за корректным сбросом hover-состояния и контрастом текста при наведении.
- **Логика STT-очереди в тесте `HistoryStore` / `SettingsStore`:** старые `rawValue` стилей (`"Умная коррекция (Typeless)"`, `"Заметка"`, `"Сообщение/письмо"`, `"Без LLM-обработки"`) мигрируют автоматически через `CleanupStyle.fromStored(...)`.
