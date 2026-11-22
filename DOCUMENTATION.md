# VoiceType — проектная документация

Голосовой ввод и запись/транскрибация встреч для macOS (`com.farrukh.voicetype`): зажал клавишу, продиктовал, отпустил — текст расшифрован, очищен ИИ в выбранной тональности и вставлен в активное окно; во встречах — раздельная запись микрофона и системного звука, расшифровка, рекап и экспорт в Obsidian/Webhook.

Статус: **рабочее macOS-приложение (SwiftUI + AppKit, macOS 14.0+)**.

> Документация синхронизируется с разделом `VoiceType/` в личном хранилище заметок [pers_docs](https://github.com/werewolf3097/pers_docs).

---

## 0. Экосистема VoiceType

| Репозиторий | Платформа | Статус |
|---|---|---|
| [voicetype-macos](https://github.com/werewolf3097/voicetype-macos) *(этот репозиторий)* | macOS | Активная разработка |
| [voicetype-windows](https://github.com/werewolf3097/voicetype-windows) | Windows | Companion-репозиторий |
| [voicetype-docs](https://github.com/werewolf3097/voicetype-docs) | — | Контракты и матрица платформ |
| [pers_docs/VoiceType](https://github.com/werewolf3097/pers_docs) | Obsidian / Notes | Продуктовая документация и бэклог |
| iOS, Android | Мобильные | Отложено |

---

## 1. Поток данных: Диктовка и Встречи

### 1.1. Глобальная диктовка
```
[Хоткей: Удержание / Нажатие / Удержание или ×2] ──▶ HotkeyStateMachine + AudioRecorder (WAV 16 kHz mono)
                                                     (+ опционально встроенный микрофон вместо Bluetooth и звуки)
                                                               │
[Отпускание / стоп] ──▶ запись готова (Esc отменяет запись)
                                                               │
                                         DictationTranscriptionCoordinator
                       ┌───────────── последовательная очередь sttDictationRoute ──────────────┐
                       ▼                    ▼                         ▼                          ▼
                1. Домашний шлюз        2. gapi.uz             3. Google Gemini           4. OpenAI
                (AudioCompressor        (WAV multipart)        (inline audio ->           (whisper-1 ->
                 Opus 24 kbps CAF)                              generateContent)           /audio/transcriptions)
                       │                    │                         │                          │
                       └──── при сбое / таймауте ──▶ автопереход к следующему настроенному шагу ─┘
                                                               │
                                         DictionaryStore (локальные замены «слышится → пишется»)
                                                               │
                                         LLMPostProcessor (если CleanupStyle != .off и задан провайдер)
                      ┌────────────────────────┴────────────────────────┐
                      ▼                                                 ▼
             Успех: очищенный текст +                          Ошибка: безопасный fallback к исходному
             llmSummary («ИИ: Gemini · ... мс»)                тексту (диктовка не теряется) + запись причины
                                                               │
                                          TextInjector (буфер + ⌘V + опц. возврат буфера через ~400 мс)
                                                               │
                                          HistoryStore (history.json: text, style, engine, latencyMs, llmSummary)
```

Статус отображается одновременно в:
- **иконке строки меню** (`MenuBarIcon`: waveform-анимации, поповер `MenuBarView.swift`);
- **плавающей капсуле** (`RecordingIndicatorController` + `RecordingIndicatorView.swift`: размещение у «чёлки», в строке меню или снизу экрана; живые столбики уровня звука, анимации ожидания/ошибки).

### 1.2. Встречи (`MeetingsStore`, `MeetingAudioRecorder`)
1. Запись микрофона (`mic.wav` — спикер «Вы») и системного звука (`sys.wav` — спикер «Собеседники» через CoreAudio Process Tap / ScreenCapture).
2. После остановки запускается независимая от диктовки очередь **`sttMeetingRoute`**:
   - **Локальный сервер Whisper (`WhisperWindowsClient`):** локальный VAD делит аудио на речевые срезы (до 75 с), раздельно распознаёт `mic` и `sys`, склеивает сегменты (`mergeAndCleanSegments`). Если сервер недоступен и включено *«Ждать локальный сервер в очереди»*, встреча ставится в `.queued` с кнопкой ручной отправки в следующий облачный сервис; если ожидание выключено — сразу переходит к `#2`.
   - **`gapi.uz` (`GapiClient`):** при наличии `sys.wav` объединяет каналы в стерео-WAV, отправляет на `/v1/transcribe`, опционально запрашивает серверное резюме (`×1.3`) и прогоняет ташкентский/книжный диалект через `UzbekDialectConverter`.
   - **`Google Gemini` (`GeminiAudioSTTProvider`):** так как Gemini API сводит стерео-аудио в моно на входе, нарезает `mic` и `sys` раздельно через VAD (до 180 с, сжатие в AAC/M4A при >12 МБ), запрашивает JSON-сегменты с относительными таймкодами и склеивает роли **«Вы»** и **«Собеседники»**.
   - **`OpenAI` (`OpenAIAudioSTTProvider`):** соблюдает строгий лимит **25 МБ на запрос** — нарезает `mic` и `sys` через VAD (сжатие в AAC/M4A при >23 МБ) и отправляет раздельно на `/v1/audio/transcriptions` (`whisper-1`, `response_format=verbose_json`).
3. Далее `MeetingRecapGenerator` строит структурированный рекап и задачи через активного LLM-провайдера (или локальный fallback `LocalRecapBuilder`), и при настроенном пути экспорта сохраняет `*_vt.md` (Obsidian) или отправляет JSON на Webhook.

---

## 2. Структура репозитория

```
voicetype-macos/
├── AGENTS.md                         ← правила сборки, дизайна, STT/LLM-архитектуры и памяти
├── DOCUMENTATION.md                    ← этот файл
├── VoiceType.app                     ← собранный и подписанный Release-бандл
└── VoiceType/
    ├── project.yml                   ← описание таргетов VoiceType и VoiceTypeTests для XcodeGen
    ├── build-app.sh                  ← Release-сборка, копирование в VoiceType.app, подпись и проверка
    ├── scripts/benchmark-gateway.sh  ← бенчмарк домашнего шлюза
    ├── VoiceTypeTests/               ← 49 юнит-тестов (PaperTheme, HotkeyStateMachine, Phase2/3/6, HomeServer, LLM/STT)
    └── VoiceType/Sources/
        ├── AppDelegate.swift, VoiceTypeApp.swift
        ├── AppState.swift                       ← оркестрация диктовки и встреч, статус, fallback
        ├── SettingsStore.swift                  ← настройки, миграции, CleanupStyle, CleanupModifiers, очереди STT
        ├── KeychainStore.swift                  ← безопасное хранение всех токенов и API-ключей
        ├── PaperTheme.swift, PaperComponents.swift, PaperTextureGenerator.swift ← дизайн-система Paper UI
        ├── DashboardHomeView.swift              ← «Диктовка»: 4 капсулы стилей, 4 чипа надстроек, ?-памятка, статус ИИ
        ├── DashboardMeetingsView.swift          ← «Встречи»: рекордер, список, транскрипт, рекап, заметки, экспорт
        ├── DashboardHistoryView.swift           ← «История»: поиск, фильтры, переобработка стилем, llmSummary
        ├── DashboardDictionaryView.swift        ← «Словарь»: локальные замены + синхронизация словаря gapi.uz
        ├── DashboardSettingsView.swift          ← «Настройки»: тема/шрифт, очереди STT, LLM-провайдеры, ключи, разрешения
        ├── MenuBarView.swift, SettingsView.swift, PermissionsChecklistView.swift
        ├── AudioRecorder.swift, AudioCompressor.swift, AudioInputDeviceManager.swift, SoundCuePlayer.swift
        ├── HotkeyManager.swift, HotkeyStateMachine.swift, TextInjector.swift
        ├── TranscriptionProvider.swift, HomeServerProvider.swift, GapiClient.swift
        ├── WhisperWindowsClient.swift, CloudAudioSTTProviders.swift, TranscriptionProgress.swift
        ├── LLMPostProcessor.swift, ClaudeClient.swift, UzbekDialectConverter.swift
        ├── MeetingsStore.swift, MeetingAudioRecorder.swift, MeetingRecapGenerator.swift
        └── HistoryStore.swift, DictionaryStore.swift, DockIconController.swift, NotificationHelper.swift, PermissionsHelper.swift
```

---

## 3. Распознавание речи (STT) и раздельные очереди

В **Настройках** управляются две независимые очереди с изменением порядка (`↑` / `↓`), тумблерами вкл/выкл, индикатором готовности (`Готов` / кнопка быстрой настройки ключа или URL):

1. **Для диктовки (`sttDictationRoute` / `STTDictationSource`):**
   - `localGateway` — Домашний шлюз (`HomeServerProvider`, Tailscale, Opus 24 кбит/с CAF, connect-таймаут 3 с; синхронизирован с `useHomeServer`).
   - `gapi` — облачный STT `gapi.uz` (особенно хорош для узбекской и смешанной рус/узб речи).
   - `gemini` — `GeminiAudioSTTProvider`.
   - `openai` — `OpenAIAudioSTTProvider`.
2. **Для встреч (`sttMeetingRoute` / `STTMeetingSource`):**
   - `localWhisper` — Локальный сервер Whisper (`whisperServerURL`, вынесен в основной блок STT).
   - `gapi` — облачный STT `gapi.uz` (стерео-дорожки + опциональное резюме `×1.3`).
   - `gemini` — `GeminiAudioSTTProvider` (раздельная обработка `mic` и `sys`).
   - `openai` — `OpenAIAudioSTTProvider` (раздельная обработка `mic` и `sys` чанками <23 МБ).
   - Флаг `waitForLocalMeetingServerInQueue`: определяет, ждать ли локальный сервер в очереди при недоступности (с кнопкой ручной отправки в следующий облачный сервис) или сразу переходить к `#2` и далее.

### Почему Anthropic Claude не включён в STT
По официальной документации Anthropic Messages API (`docs.anthropic.com`), API принимает только текст и изображения — аудиовход не поддерживается. Anthropic используется исключительно в блоке **обработки текста и рекапов (LLM)**.

---

## 4. Постобработка текста ИИ (LLM), модели и стили

### 4.1. Провайдеры LLM (`LLMPostProcessor.swift`)
Поддерживается 4 варианта для очистки диктовки и генерации рекапов встреч:
- **Anthropic Claude** (`/v1/messages`, по умолчанию `claude-haiku-5-5`);
- **OpenAI** (`/v1/chat/completions`, по умолчанию `gpt-5-mini`);
- **Google Gemini** (`generateContent`, по умолчанию `gemini-3.8-flash`; устаревшая `gemini-2.5-flash` автоматически мигрирует);
- **Другой (OpenAI-совм.)** (пресеты OpenRouter, Groq, DeepSeek, Ollama, LM Studio + произвольный Base URL).

Особенности реализации:
- Поле модели по умолчанию хранит `""`, отображая серый драфт (`defaultModel`); при вводе своей модели появляется кнопка сброса `×`. В выпадающем меню `▾` можно выбрать популярную модель или подтянуть актуальный список через `/models` по вашему ключу.
- Для thinking-моделей Gemini (`gemini-4-hydrogen`, `gemini-3.8-flash` и др.) в `testConnection()` используется `maxTokens = 1024`, в `cleanup`/`recap` — `8192`, а части с `thought == true` отфильтровываются.
- Для reasoning-моделей OpenAI (`gpt-5*`, `o1*`, `o3*`, `o4*`, `codex*`) передаётся `max_completion_tokens` без параметра `temperature`.

### 4.2. 4 категории стилей и 5 надстроек
**База во всех 3 ИИ-категориях:** расстановка пунктуации, исправление орфографии/падежей/сбоев распознавания, удаление слов-паразитов (*«э-э», «ну», «как бы»*) и устных самоисправлений.

| Категория (`CleanupStyle`) | Нагрузка | Назначение |
|---|---|---|
| **Без обработки** | `0% правок` | Сырой текст от STT без задержки и правок |
| **Дружественный** | `Лёгкая правка` | Живой тон для Telegram, Slack и чатов с сохранением «ты/вы» |
| **Деловой** | `Средняя правка` | Собранный рабочий тон для коллег, писем, задач и заметок |
| **Формальный** | `Полная редактура` | Строгий официально-вежливый регистр на «Вы» для документов |

**5 надстроек (`CleanupModifiers`):**
1. **Без воды (`compactMode`)** — сжимает длинную речь до сути.
2. **Списки и абзацы (`structuredLists`)** — оформляет перечисления буллитами и абзацами.
3. **Код и термины (`preserveTechnicalTerms`, вкл. по умолчанию)** — защищает URL, пути, команды и `camelCase`/`snake_case`.
4. **Автотон по приложению (`autoToneByApp`)** — для `Telegram`/`Slack`/`WhatsApp`/`Discord` временно выбирает *Дружественный*, для `Mail`/`Notes`/`Notion`/`Obsidian`/`Cursor`/`VS Code`/`Xcode`/`Terminal` — *Деловой* (при активном *Без обработки* не вмешивается).
5. **Свой акцент (`customInstruction`)** — дополнительная пользовательская инструкция (например, перевод или запрет эмодзи).

На экране **Диктовка** доступна кнопка памятки `?` (`CleanupStyleGuideButton`) с примерами, а под **Последней диктовкой** и в **Истории** выводится строка `llmSummary` (`ИИ: Gemini · gemini-3.8-flash · Дружественный (540 мс)` или причина пропуска/ошибки с сохранением исходного текста).

---

## 5. UI и темы оформления (`PaperTheme.swift`)
- **Темы:** чистая светлая (**«Чистый лист»**) и тёмная (**«Графит»**) + **Системная** (`PaperSegmentedControl`), с живым отслеживанием `NSApp.effectiveAppearance` через `SystemAppearanceObserver` и единым `.preferredColorScheme` в `PaperEnvironmentModifier`.
- **Типографика (`FontPreset`):** 5 пресетов (`Бумага (New York + SF)`, `Книжный (Charter + SF)`, `Системный (SF)`, `Мягкий (SF Rounded)`, `Редакционный (Cormorant + Inter)`), применяемых единообразно во всех разделах включая «Встречи».
- **Разделы сайдбара:** `Диктовка`, `Встречи`, `История`, `Словарь`, `Настройки` (+ список недавних встреч и статусная плашка готовности).

---

## 6. Хранение секретов, подпись и разрешения macOS
- **Keychain (`KeychainStore.swift`):** все ключи и токены (`gapiToken`, `anthropicApiKey`, `openaiApiKey`, `geminiApiKey`, `customLLMApiKey`, `homeServerToken`).
- **Разрешения:** Микрофон, Мониторинг ввода (`CGEventTap` на `.cghidEventTap` + `IOHIDCheckAccess`), Универсальный доступ (автовставка `⌘V`), Запись системного звука (встречи).
- **Стабильная подпись (`VoiceType/build-app.sh`):** подписывает бандл сертификатом `Apple Development` (или `Developer ID`) при наличии промежуточного `AppleWWDRCAG3.cer` в Keychain, сохраняя стабильный `Designated Requirement` (`identifier "com.farrukh.voicetype"`), чтобы разрешения macOS не сбрасывались при пересборках. `ENABLE_HARDENED_RUNTIME: false`.

---

## 7. Сборка и тестирование
- **Юнит-тесты:**
  ```bash
  cd VoiceType && xcodegen generate && xcodebuild -project VoiceType.xcodeproj -scheme VoiceType test CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO
  ```
- **Сборка и подпись Release-бандла:**
  ```bash
  bash VoiceType/build-app.sh
  ```
- **Перезапуск:**
  ```bash
  pkill -x VoiceType || true; sleep 0.5; open "/Users/farrukh/orca/voicetype-macos/VoiceType.app"
  ```

---

## 8. Changelog

### 2026-11-22
- **Раздельные STT-очереди для диктовки и встреч (`sttDictationRoute`, `sttMeetingRoute`):** добавлены `GeminiAudioSTTProvider` (раздельная обработка `mic`/`sys` через VAD, т.к. Gemini сводит стерео в моно) и `OpenAIAudioSTTProvider` (`whisper-1`, `verbose_json`, нарезка чанками <23 МБ под лимит 25 МБ). Anthropic намеренно исключён из STT-списков.
- **4 категории стилей и 5 надстроек LLM:** `Без обработки`, `Дружественный`, `Деловой`, `Формальный` с общей базой пунктуации/орфографии, чипами надстроек (`Без воды`, `Списки`, `Код и термины`, `Авто по приложению`), полем `Свой акцент`, памяткой `?` и телеметрией `llmSummary` с безопасным fallback к сырому тексту.
- **Мультипровайдерный LLM (`LLMPostProcessor.swift`):** Claude, OpenAI, Gemini, OpenAI-совместимые сервисы; драфтовое поле модели + живая загрузка `/models`; исправлены thinking-ответы Gemini (`maxTokens = 1024`, фильтр `thought == true`) и OpenAI reasoning (`max_completion_tokens`, без `temperature`); добавлены `?`-подсказки со ссылками на документацию и кабинеты ключей.
- **Paper UI (Фазы 1–6):** светлая («Чистый лист») и тёмная («Графит») темы, `SystemAppearanceObserver`, единый `.preferredColorScheme`, `PaperTokens.hairline = 1.0`, 5 пресетов шрифтов во всех разделах включая «Встречи», звуковые cues, выбор микрофона и приоритет встроенного микрофона над Bluetooth, 3-режимная машина состояний хоткея и обновлённый плавающий индикатор.
- **Тесты (`VoiceTypeTests`):** расширены до 49 юнит-тестов (PaperTheme, HotkeyStateMachine, Phase2/3/6, HomeServer, LLM/STT парсинг и маршрутизация).

### 2026-11-20
- Подключён домашний шлюз (`HomeServerProvider`) с Opus/CAF сжатием и fallback на `gapi.uz`, добавлены `AudioCompressor`, `HistoryStore` (`engine`, `latencyMs`) и `VoiceTypeTests`.

### 2026-09-23
- Запуск хоткея при старте, точная проверка `IOHIDCheckAccess`, push-уведомления и переработка настроек.
