import AVFoundation
import AppKit
import Foundation

@MainActor
final class AppState: ObservableObject {
    @Published var status: RecordingStatus = .idle {
        didSet {
            let outcome = pendingIndicatorOutcome
            pendingIndicatorOutcome = nil
            indicator.update(status: status, targetApp: activeTargetApp, insertOutcome: outcome)
        }
    }
    @Published var selectedSection: DashboardSection? = .home
    @Published var focusPermissionsInSettings: Bool = false
    @Published var lastText: String = ""
    @Published var lastTargetApp: String? = nil
    @Published var lastInsertOutcome: InsertStatus? = nil
    @Published var hotkeyActive: Bool = false
    @Published var microphoneAuthorized: Bool = PermissionsHelper.microphoneAuthorized()
    @Published var inputMonitoringAuthorized: Bool = PermissionsHelper.inputMonitoringAuthorized()
    @Published var accessibilityAuthorized: Bool = PermissionsHelper.accessibilityAuthorized()
    @Published var screenCaptureAuthorized: Bool = PermissionsHelper.screenCaptureAuthorized()
    @Published var activeMeetingID: UUID? = nil
    @Published var selectedMeetingID: UUID? = nil
    @Published var meetingElapsedSeconds: TimeInterval = 0
    @Published var activeMeetingSystemAudioCapturing: Bool = false
    @Published var activeMeetingSystemAudioError: String? = nil
    @Published var meetingTranscriptionProgress: [UUID: MeetingTranscriptionProgress] = [:]

    let settings: SettingsStore
    let history: HistoryStore
    let dictionary: DictionaryStore
    let meetings: MeetingsStore
    private let recorder = AudioRecorder()
    private let meetingRecorder = MeetingAudioRecorder()
    private let hotkeys = HotkeyManager()
    private let indicator = RecordingIndicatorController()
    private var recordingStartedAt: Date?
    private var dictationTask: Task<Void, Never>?
    private var meetingStartedAt: Date?
    private var meetingTimer: Timer?
    private var meetingQueueTimer: Timer?
    private var audioCleanupTimer: Timer?
    private var meetingTranscriptionTask: Task<Void, Never>?
    private var activeTranscriptionMeetingID: UUID?
    private var activeTranscriptionToken: UUID?
    private var lastNotifiedHotkeyIssue: HotkeyIssue?
    private var permissionsTimer: Timer?
    private var activeTargetApp: String?
    private var pendingIndicatorOutcome: InsertStatus?

    private enum HotkeyIssue: Equatable {
        case inputMonitoringMissing
        case needsRelaunch
    }

    init(
        settings: SettingsStore,
        history: HistoryStore,
        dictionary: DictionaryStore? = nil,
        meetings: MeetingsStore? = nil
    ) {
        self.settings = settings
        self.history = history
        self.dictionary = dictionary ?? DictionaryStore()
        self.meetings = meetings ?? MeetingsStore()
        indicator.configure(settings: settings)
        recorder.onAudioLevel = { [weak self] level in
            self?.indicator.updateAudioLevel(level)
        }
        hotkeys.onStart = { [weak self] in self?.beginRecording() }
        hotkeys.onStop = { [weak self] in self?.finishRecording() }
        hotkeys.onCancel = { [weak self] in self?.cancelRecording() }
        hotkeys.isRecording = { [weak self] in
            switch self?.status {
            case .recording, .transcribing, .cleaning:
                return true
            default:
                return false
            }
        }

        self.refreshPermissionsAndHotkey(forceRestartTap: true)
        self.cleanupExpiredMeetingAudio()

        NotificationCenter.default.addObserver(
            forName: NSApplication.didFinishLaunchingNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.refreshPermissionsAndHotkey()
            }
        }

        NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.refreshPermissionsAndHotkey()
            }
        }

        // Poll permissions every 2s so that toggling switches in System Settings
        // reflects in the UI and activates the hotkey immediately (like Typeless / Granola).
        permissionsTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refreshPermissionsAndHotkey()
            }
        }

        // Poll queued meetings every 30s so recordings waiting for external server auto-transcribe on reconnect.
        meetingQueueTimer = Timer.scheduledTimer(withTimeInterval: 30.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.processQueuedMeetingsIfNeeded()
            }
        }

        // Periodically purge expired meeting audio files according to retention setting.
        audioCleanupTimer = Timer.scheduledTimer(withTimeInterval: 6 * 3600, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.cleanupExpiredMeetingAudio()
            }
        }

        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            await self?.processQueuedMeetingsIfNeeded()
        }
    }

    func refreshPermissionsAndHotkey(forceRestartTap: Bool = false) {
        let mic = PermissionsHelper.microphoneAuthorized()
        let inputMon = PermissionsHelper.inputMonitoringAuthorized()
        let ax = PermissionsHelper.accessibilityAuthorized()
        let sc = PermissionsHelper.screenCaptureAuthorized()

        let permissionsChanged = (microphoneAuthorized != mic)
            || (inputMonitoringAuthorized != inputMon)
            || (accessibilityAuthorized != ax)

        if microphoneAuthorized != mic { microphoneAuthorized = mic }
        if inputMonitoringAuthorized != inputMon { inputMonitoringAuthorized = inputMon }
        if accessibilityAuthorized != ax { accessibilityAuthorized = ax }
        if screenCaptureAuthorized != sc { screenCaptureAuthorized = sc }

        hotkeys.mode = settings.shortcutMode

        // Don't interrupt an active recording
        guard status != .recording else { return }

        let keyChanged = hotkeys.shortcutKey != settings.shortcutKey || hotkeys.shortcutSide != settings.shortcutSide
        let swallowUpgradeAvailable = ax && !hotkeys.canSwallowEvents
        let needsStart = forceRestartTap || !hotkeys.isActive || keyChanged || swallowUpgradeAvailable || permissionsChanged

        if needsStart {
            restartHotkeyListener()
        }
    }

    func restartHotkeyListener() {
        hotkeys.shortcutKey = settings.shortcutKey
        hotkeys.shortcutSide = settings.shortcutSide
        hotkeys.mode = settings.shortcutMode
        let tapStarted = hotkeys.start()
        // CGEvent.tapCreate can report success and still never receive a single real
        // key event when Input Monitoring (or Accessibility) isn't actually granted.
        let inputMon = PermissionsHelper.inputMonitoringAuthorized()
        let ax = PermissionsHelper.accessibilityAuthorized()
        let mic = PermissionsHelper.microphoneAuthorized()
        let permissionGranted = inputMon || ax
        let newHotkeyActive = tapStarted && permissionGranted

        if inputMonitoringAuthorized != inputMon { inputMonitoringAuthorized = inputMon }
        if accessibilityAuthorized != ax { accessibilityAuthorized = ax }
        if microphoneAuthorized != mic { microphoneAuthorized = mic }
        if hotkeyActive != newHotkeyActive { hotkeyActive = newHotkeyActive }

        guard !newHotkeyActive else {
            lastNotifiedHotkeyIssue = nil
            return
        }

        // Missing permission and "granted but needs a relaunch to take effect" both
        // show up as the same failure here, so we tell them apart from IOHIDCheckAccess.
        let issue: HotkeyIssue = permissionGranted ? .needsRelaunch : .inputMonitoringMissing
        guard issue != lastNotifiedHotkeyIssue else { return }
        lastNotifiedHotkeyIssue = issue

        switch issue {
        case .inputMonitoringMissing:
            NotificationHelper.notify(
                title: "VoiceType не слышит хоткей",
                body: "Разрешите «Мониторинг ввода» для VoiceType: Настройки системы → Конфиденциальность и безопасность → Мониторинг ввода."
            )
        case .needsRelaunch:
            NotificationHelper.notify(
                title: "Перезапустите VoiceType",
                body: "Доступ к «Мониторингу ввода» выдан, но macOS применяет его только после перезапуска приложения."
            )
        }
    }

    private func beginRecording() {
        guard status == .idle || isError else { return }

        switch PermissionsHelper.microphoneStatus() {
        case .notDetermined:
            PermissionsHelper.requestMicrophone { [weak self] granted in
                guard let self else { return }
                self.microphoneAuthorized = granted
                self.hotkeys.notifyRecordingEndedExternally()
                if !granted {
                    self.status = .error("Нет доступа к микрофону. Разрешите в Настройках.")
                }
            }
            return
        case .denied, .restricted:
            microphoneAuthorized = false
            hotkeys.notifyRecordingEndedExternally()
            status = .error("Нет доступа к микрофону. Разрешите в Настройках.")
            return
        case .authorized:
            microphoneAuthorized = true
        @unknown default:
            break
        }

        do {
            activeTargetApp = currentTargetAppName()
            let devices = AudioInputDeviceManager.availableInputDevices()
            let targetDevice = AudioInputDeviceManager.resolveTargetDevice(
                from: devices,
                selectedUID: settings.selectedMicrophoneUID,
                preferBuiltInOverBluetooth: settings.preferBuiltInMicOverBluetooth
            )
            try recorder.start(deviceID: targetDevice?.id)
            recordingStartedAt = Date()
            status = .recording
            SoundCuePlayer.shared.play(.startRecording, enabled: settings.soundsEnabled, volume: settings.soundVolume)
        } catch {
            activeTargetApp = nil
            hotkeys.notifyRecordingEndedExternally()
            status = .error("Не удалось начать запись: \(error.localizedDescription)")
        }
    }

    private func finishRecording() {
        guard status == .recording else { return }
        let duration = recordingStartedAt.map { Date().timeIntervalSince($0) } ?? 0
        recordingStartedAt = nil

        guard let fileURL = recorder.stop() else {
            activeTargetApp = nil
            hotkeys.notifyRecordingEndedExternally()
            status = .idle
            return
        }

        if let frontApp = currentTargetAppName() {
            activeTargetApp = frontApp
        }
        SoundCuePlayer.shared.play(.stopRecording, enabled: settings.soundsEnabled, volume: settings.soundVolume)
        status = .transcribing
        dictationTask?.cancel()
        dictationTask = Task { [weak self] in
            await self?.transcribeAndInsert(fileURL: fileURL, durationSeconds: duration)
        }
    }

    private func cancelRecording() {
        switch status {
        case .recording, .transcribing, .cleaning:
            break
        default:
            return
        }
        recordingStartedAt = nil
        dictationTask?.cancel()
        dictationTask = nil
        recorder.cancel()
        hotkeys.notifyRecordingEndedExternally()
        status = .idle
    }

    private func currentTargetAppName() -> String? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        if app.bundleIdentifier == Bundle.main.bundleIdentifier {
            return app.localizedName
        }
        return app.localizedName
    }

    private func buildDictationProviders() -> [any TranscriptionProvider] {
        let terms = dictionary.entries.map(\.written)
        var providers: [any TranscriptionProvider] = []
        for step in settings.sttDictationRoute where step.isEnabled && settings.isDictationSourceConfigured(step.source) {
            switch step.source {
            case .localGateway:
                providers.append(HomeServerProvider(config: settings.homeServerConfig))
            case .gapi:
                providers.append(GapiTranscriptionProvider(token: settings.gapiToken.trimmingCharacters(in: .whitespacesAndNewlines)))
            case .gemini:
                providers.append(
                    GeminiAudioSTTProvider(
                        apiKey: settings.geminiApiKey,
                        model: settings.geminiModel,
                        vocabularyTerms: terms
                    )
                )
            case .openai:
                providers.append(
                    OpenAIAudioSTTProvider(
                        apiKey: settings.openaiApiKey,
                        model: "whisper-1",
                        vocabularyTerms: terms
                    )
                )
            }
        }
        return providers
    }

    private func transcribeAndInsert(fileURL: URL, durationSeconds: Double) async {
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let providers = buildDictationProviders()
        guard !providers.isEmpty else {
            let message = "Не настроен ни один сервис распознавания речи (укажите ключ gapi.uz, Gemini, OpenAI или домашний шлюз в Настройках)."
            history.add(text: "", durationSeconds: durationSeconds, status: .failed, targetApp: currentTargetAppName(), errorMessage: message, style: settings.cleanupStyle)
            hotkeys.notifyRecordingEndedExternally()
            status = .error(message)
            return
        }

        let coordinator = DictationTranscriptionCoordinator(providers: providers) { reason in
            NotificationHelper.notify(
                title: "Автопереключение STT",
                body: "Переключился на следующий источник (\(reason))."
            )
        }

        do {
            try Task.checkCancellation()
            let result = try await coordinator.transcribe(fileURL: fileURL)
            try Task.checkCancellation()

            let rawText = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !rawText.isEmpty else {
                let silenceReason = "Не удалось распознать (тишина)"
                history.add(
                    text: "",
                    durationSeconds: durationSeconds,
                    status: .failed,
                    targetApp: currentTargetAppName(),
                    errorMessage: silenceReason,
                    style: settings.cleanupStyle,
                    languageCode: result.languageCode,
                    languageSummary: result.languageSummary,
                    engine: result.engine,
                    latencyMs: result.latencyMs
                )
                hotkeys.notifyRecordingEndedExternally()
                status = .error(silenceReason)
                return
            }

            // Применяем локальный словарь замен «слышится → пишется»
            var finalText = dictionary.apply(to: rawText)
            let modifiers = settings.cleanupModifiers
            let targetAppForCleanup = currentTargetAppName() ?? activeTargetApp
            let activeStyle = modifiers.resolvedStyle(base: settings.cleanupStyle, targetAppName: targetAppForCleanup)
            let llmConfig = settings.activeLLMConfig
            let llmSummary: String

            if activeStyle == .off {
                llmSummary = "Без ИИ (выбран режим «Без обработки»)"
            } else if !llmConfig.isConfigured {
                llmSummary = "Без ИИ (не указан ключ \(llmConfig.provider.shortTitle))"
            } else {
                status = .cleaning
                let inputForLLM = GapiTranscription(
                    text: finalText,
                    languageCode: result.languageCode,
                    languageConfidence: nil,
                    languageShare: nil,
                    segments: [],
                    audioSeconds: result.audioSeconds
                )
                let llmStart = CFAbsoluteTimeGetCurrent()
                do {
                    let cleaned = try await LLMPostProcessor(config: llmConfig).cleanup(
                        transcription: inputForLLM,
                        style: settings.cleanupStyle,
                        uzbekStyle: settings.uzbekStyle,
                        modifiers: modifiers,
                        targetAppName: targetAppForCleanup
                    )
                    finalText = dictionary.apply(to: cleaned)
                    let llmMs = max(1, Int(((CFAbsoluteTimeGetCurrent() - llmStart) * 1000).rounded()))
                    llmSummary = "ИИ: \(llmConfig.provider.shortTitle) · \(llmConfig.resolvedModel) · \(activeStyle.shortTitle) (\(llmMs) мс)"
                } catch is CancellationError {
                    throw CancellationError()
                } catch let urlErr as URLError where urlErr.code == .cancelled {
                    throw urlErr
                } catch {
                    llmSummary = "Ошибка \(llmConfig.provider.shortTitle): \(error.localizedDescription) (вставлен исходный текст)"
                }
            }

            try Task.checkCancellation()
            guard !Task.isCancelled else { return }

            let targetApp = currentTargetAppName() ?? activeTargetApp
            activeTargetApp = targetApp
            let insertOutcome = TextInjector.insert(
                text: finalText,
                mode: settings.pasteMode,
                restoreClipboard: settings.restoreClipboard
            )

            lastText = finalText
            lastTargetApp = targetApp
            lastInsertOutcome = insertOutcome

            history.add(
                text: finalText,
                durationSeconds: durationSeconds,
                status: insertOutcome,
                targetApp: targetApp,
                style: activeStyle,
                languageCode: result.languageCode,
                languageSummary: result.languageSummary,
                engine: result.engine,
                latencyMs: result.latencyMs,
                llmSummary: llmSummary
            )
            hotkeys.notifyRecordingEndedExternally()
            if insertOutcome == .inserted {
                SoundCuePlayer.shared.play(.inserted, enabled: settings.soundsEnabled, volume: settings.soundVolume)
            }
            pendingIndicatorOutcome = insertOutcome
            status = .idle
        } catch is CancellationError {
            hotkeys.notifyRecordingEndedExternally()
            return
        } catch let error as URLError where error.code == .cancelled {
            hotkeys.notifyRecordingEndedExternally()
            return
        } catch {
            guard !Task.isCancelled else { return }
            let message = error.localizedDescription
            history.add(
                text: "",
                durationSeconds: durationSeconds,
                status: .failed,
                targetApp: currentTargetAppName(),
                errorMessage: message,
                style: settings.cleanupStyle
            )
            hotkeys.notifyRecordingEndedExternally()
            status = .error(message)
        }
    }

    @discardableResult
    func insertTextAgain(_ text: String) -> InsertStatus {
        let targetApp = currentTargetAppName()
        let outcome = TextInjector.insert(
            text: text,
            mode: settings.pasteMode,
            restoreClipboard: settings.restoreClipboard
        )
        lastTargetApp = targetApp
        lastInsertOutcome = outcome
        return outcome
    }

    func reprocessRecord(_ recordID: UUID, with style: CleanupStyle) async {
        guard let record = history.records.first(where: { $0.id == recordID }),
              !record.text.isEmpty else { return }
        let llmConfig = settings.activeLLMConfig
        guard llmConfig.isConfigured, style != .off else { return }

        let input = GapiTranscription(
            text: record.text,
            languageCode: record.languageCode,
            languageConfidence: nil,
            languageShare: nil,
            segments: []
        )
        do {
            let llmStart = CFAbsoluteTimeGetCurrent()
            let cleaned = try await LLMPostProcessor(config: llmConfig).cleanup(
                transcription: input,
                style: style,
                uzbekStyle: settings.uzbekStyle,
                modifiers: settings.cleanupModifiers,
                targetAppName: record.targetApp
            )
            let llmMs = max(1, Int(((CFAbsoluteTimeGetCurrent() - llmStart) * 1000).rounded()))
            let final = dictionary.apply(to: cleaned)
            history.update(id: recordID) { item in
                item = TranscriptionRecord(
                    id: item.id,
                    date: item.date,
                    text: final,
                    durationSeconds: item.durationSeconds,
                    status: item.status,
                    targetApp: item.targetApp,
                    errorMessage: nil,
                    style: style,
                    languageCode: item.languageCode,
                    languageSummary: item.languageSummary,
                    engine: item.engine,
                    latencyMs: item.latencyMs,
                    llmSummary: "ИИ: \(llmConfig.provider.shortTitle) · \(llmConfig.resolvedModel) · \(style.shortTitle) (\(llmMs) мс)"
                )
            }
        } catch {
            status = .error(error.localizedDescription)
        }
    }

    private var isError: Bool {
        if case .error = status { return true }
        return false
    }

    // MARK: - Meetings (Granola Mode)

    @discardableResult
    func startMeeting(
        title: String = "",
        template: MeetingTemplate = .general,
        audioSource: MeetingAudioSource? = nil
    ) -> UUID? {
        guard activeMeetingID == nil else { return activeMeetingID }

        let chosenSource = audioSource ?? settings.meetingAudioSource
        let draft = meetings.createDraftMeeting(
            title: title,
            template: template,
            audioSource: chosenSource
        )
        let dir = meetings.folderURL(for: draft.id)

        do {
            try meetingRecorder.start(in: dir, source: chosenSource)
            activeMeetingID = draft.id
            meetingStartedAt = Date()
            meetingElapsedSeconds = 0
            activeMeetingSystemAudioCapturing = false
            activeMeetingSystemAudioError = nil
            meetingTimer?.invalidate()
            meetingTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
                Task { @MainActor in
                    guard let self, let started = self.meetingStartedAt else { return }
                    self.meetingElapsedSeconds = Date().timeIntervalSince(started)
                    let sysActive = self.meetingRecorder.systemAudioActive
                    if self.activeMeetingSystemAudioCapturing != sysActive {
                        self.activeMeetingSystemAudioCapturing = sysActive
                    }
                    let sysError = self.meetingRecorder.systemAudioError
                    if self.activeMeetingSystemAudioError != sysError {
                        self.activeMeetingSystemAudioError = sysError
                    }
                }
            }
            return draft.id
        } catch {
            meetings.update(draft.id) { record in
                record.status = .error("Не удалось начать запись встречи: \(error.localizedDescription)")
            }
            return nil
        }
    }

    func finishMeeting() {
        guard let meetingID = activeMeetingID else { return }
        let duration = meetingStartedAt.map { Date().timeIntervalSince($0) } ?? meetingElapsedSeconds
        meetingTimer?.invalidate()
        meetingTimer = nil
        meetingStartedAt = nil
        activeMeetingID = nil
        meetingElapsedSeconds = 0
        activeMeetingSystemAudioCapturing = false
        activeMeetingSystemAudioError = nil

        meetings.update(meetingID) { record in
            record.durationSeconds = duration
            record.status = .transcribing
            record.progressSeconds = 0
        }

        Task {
            guard let output = await meetingRecorder.stop() else {
                meetings.update(meetingID) { record in
                    record.status = .error("Аудиозапись встречи не найдена.")
                }
                return
            }

            meetings.update(meetingID) { record in
                record.audioFileName = output.micFileURL.lastPathComponent
                record.sysAudioFileName = output.sysFileURL?.lastPathComponent
                record.stereoParties = output.stereoParties
                record.speakerNames = output.stereoParties ? [0: "Вы", 1: "Собеседники"] : [:]
                if record.durationSeconds <= 0 {
                    record.durationSeconds = duration
                }
            }

            await transcribeMeetingOnWindowsOrQueue(meetingID: meetingID)
        }
    }

    func cancelMeeting() {
        guard let meetingID = activeMeetingID else { return }
        meetingTimer?.invalidate()
        meetingTimer = nil
        meetingStartedAt = nil
        activeMeetingID = nil
        meetingElapsedSeconds = 0
        activeMeetingSystemAudioCapturing = false
        activeMeetingSystemAudioError = nil

        Task {
            await meetingRecorder.cancel()
            meetings.delete(meetingID)
        }
    }

    func deleteMeeting(_ meetingID: UUID) {
        if activeMeetingID == meetingID {
            cancelMeeting()
            return
        }
        if activeTranscriptionMeetingID == meetingID {
            meetingTranscriptionTask?.cancel()
            meetingTranscriptionTask = nil
            activeTranscriptionMeetingID = nil
            activeTranscriptionToken = nil
            meetingTranscriptionProgress.removeValue(forKey: meetingID)
        }
        meetings.delete(meetingID)
    }

    var nextCloudMeetingProviderTitle: String {
        for step in settings.sttMeetingRoute where step.source != .localWhisper && step.isEnabled && settings.isMeetingSourceConfigured(step.source) {
            return step.source.shortTitle
        }
        for step in settings.sttMeetingRoute where step.source != .localWhisper && settings.isMeetingSourceConfigured(step.source) {
            return step.source.shortTitle
        }
        return "облако"
    }

    func retryMeetingOnWindows(_ meetingID: UUID) {
        Task {
            await transcribeMeetingOnWindowsOrQueue(meetingID: meetingID)
        }
    }

    func transcribeMeetingUrgentGapi(_ meetingID: UUID) {
        Task {
            await runMeetingTranscriptionPipeline(meetingID: meetingID, skipLocalServer: true)
        }
    }

    func transcribeMeetingOnWindowsOrQueue(meetingID: UUID) async {
        await runMeetingTranscriptionPipeline(meetingID: meetingID, skipLocalServer: false)
    }

    private func runMeetingTranscriptionPipeline(meetingID: UUID, skipLocalServer: Bool) async {
        guard let current = meetings.meeting(withID: meetingID) else { return }
        guard let micURL = meetings.audioFileURL(for: current) else {
            meetings.update(meetingID) { record in
                record.status = .error("Аудиофайл записи не найден.")
            }
            return
        }

        var orderedSources: [STTMeetingSource] = settings.sttMeetingRoute
            .filter { step in
                if skipLocalServer && step.source == .localWhisper { return false }
                return step.isEnabled && settings.isMeetingSourceConfigured(step.source)
            }
            .map(\.source)

        // Если пользователь нажал «Отправить через облако», но все облачные шаги выключены — пробуем настроенные облачные ключи.
        if skipLocalServer && orderedSources.isEmpty {
            orderedSources = settings.sttMeetingRoute
                .filter { $0.source != .localWhisper && settings.isMeetingSourceConfigured($0.source) }
                .map(\.source)
        }

        guard !orderedSources.isEmpty else {
            meetings.update(meetingID) { record in
                record.status = .error("Не настроен ни один сервис распознавания встреч (укажите сервер Whisper или ключ gapi.uz / Gemini / OpenAI).")
            }
            return
        }

        if !skipLocalServer, let busyID = activeTranscriptionMeetingID, busyID != meetingID {
            meetings.update(meetingID) { record in
                record.status = .queued("В очереди за другой расшифровкой")
            }
            return
        }

        if activeTranscriptionMeetingID == meetingID || (skipLocalServer && activeTranscriptionMeetingID != nil) {
            meetingTranscriptionTask?.cancel()
            meetingTranscriptionTask = nil
        }

        let sysURL = meetings.sysAudioFileURL(for: current)
        let expectedDuration = current.durationSeconds > 0 ? current.durationSeconds : nil
        let token = UUID()
        activeTranscriptionMeetingID = meetingID
        activeTranscriptionToken = token

        let task = Task { [weak self] in
            guard let self else { return }
            defer {
                if self.activeTranscriptionToken == token {
                    self.activeTranscriptionMeetingID = nil
                    self.activeTranscriptionToken = nil
                    self.meetingTranscriptionTask = nil
                    self.meetingTranscriptionProgress.removeValue(forKey: meetingID)
                }
            }

            let customTerms = self.dictionary.entries.map(\.written)
            var lastErrorMessage = "Не удалось распознать встречу."

            for (index, source) in orderedSources.enumerated() {
                if Task.isCancelled { return }
                let hasNext = index + 1 < orderedSources.count
                let nextLabel = hasNext ? orderedSources[index + 1].shortTitle : nil

                do {
                    let transcription: GapiTranscription
                    let engineLabel: String

                    switch source {
                    case .localWhisper:
                        let client = WhisperWindowsClient(baseURLString: self.settings.whisperServerURL)
                        let reachable = await client.isReachable(timeout: 2.5)
                        guard reachable else {
                            if self.settings.waitForLocalMeetingServerInQueue && !skipLocalServer {
                                let actionHint = nextLabel.map { "либо отправьте через \($0)" } ?? "проверьте соединение"
                                self.meetings.update(meetingID) { record in
                                    record.status = .queued("Локальный сервер недоступен (\(actionHint))")
                                }
                                return
                            }
                            lastErrorMessage = "Локальный сервер Whisper недоступен."
                            continue
                        }

                        engineLabel = client.engineDisplayName
                        self.prepareMeetingProgressUI(for: meetingID, engineLabel: engineLabel, uploadEndFraction: 0.05, expectedDuration: expectedDuration)
                        transcription = try await client.transcribeMeeting(
                            micURL: micURL,
                            sysURL: sysURL,
                            customTerms: customTerms,
                            expectedDuration: expectedDuration
                        ) { [weak self] progress in
                            Task { @MainActor in
                                self?.applyTranscriptionProgress(progress, for: meetingID, token: token)
                            }
                        }

                    case .gapi:
                        engineLabel = "gapi.uz"
                        self.prepareMeetingProgressUI(for: meetingID, engineLabel: engineLabel, uploadEndFraction: 0.25, expectedDuration: expectedDuration)
                        transcription = try await self.transcribeMeetingWithGapi(
                            meetingID: meetingID,
                            micURL: micURL,
                            sysURL: sysURL,
                            expectedDuration: expectedDuration,
                            token: token
                        )

                    case .gemini:
                        let provider = GeminiAudioSTTProvider(
                            apiKey: self.settings.geminiApiKey,
                            model: self.settings.geminiModel,
                            vocabularyTerms: customTerms
                        )
                        engineLabel = "Gemini (\(provider.resolvedModel))"
                        self.prepareMeetingProgressUI(for: meetingID, engineLabel: engineLabel, uploadEndFraction: 0.05, expectedDuration: expectedDuration)
                        transcription = try await provider.transcribeMeeting(
                            micURL: micURL,
                            sysURL: sysURL,
                            customTerms: customTerms,
                            expectedDuration: expectedDuration
                        ) { [weak self] progress in
                            Task { @MainActor in
                                self?.applyTranscriptionProgress(progress, for: meetingID, token: token)
                            }
                        }

                    case .openai:
                        let provider = OpenAIAudioSTTProvider(
                            apiKey: self.settings.openaiApiKey,
                            model: "whisper-1",
                            vocabularyTerms: customTerms
                        )
                        engineLabel = "OpenAI (whisper-1)"
                        self.prepareMeetingProgressUI(for: meetingID, engineLabel: engineLabel, uploadEndFraction: 0.05, expectedDuration: expectedDuration)
                        transcription = try await provider.transcribeMeeting(
                            micURL: micURL,
                            sysURL: sysURL,
                            customTerms: customTerms,
                            expectedDuration: expectedDuration
                        ) { [weak self] progress in
                            Task { @MainActor in
                                self?.applyTranscriptionProgress(progress, for: meetingID, token: token)
                            }
                        }
                    }

                    try Task.checkCancellation()

                    self.meetings.update(meetingID) { record in
                        record.stereoParties = transcription.stereoParties ?? (sysURL != nil)
                        record.segments = transcription.segments
                        record.languageCode = transcription.languageCode ?? "ru"
                        if let langSummary = transcription.languageSummary, !langSummary.isEmpty {
                            record.languageSummary = langSummary
                        } else if record.languageSummary == nil {
                            record.languageSummary = "Русский"
                        }
                        if let gapiSum = transcription.summaryText, !gapiSum.isEmpty {
                            record.gapiSummary = gapiSum
                        }
                        record.transcriptionEngine = engineLabel
                        if let audioSec = transcription.audioSeconds, audioSec > 0 {
                            record.durationSeconds = audioSec
                        }
                        record.status = .summarizing
                    }

                    self.cleanupAudioIfNotKeeping(for: meetingID, micURL: micURL, sysURL: sysURL)
                    await self.regenerateRecap(for: meetingID)
                    return
                } catch is CancellationError {
                    return
                } catch let error as URLError where error.code == .cancelled {
                    return
                } catch {
                    guard !Task.isCancelled else { return }
                    lastErrorMessage = "\(source.shortTitle): \(error.localizedDescription)"
                    if source == .localWhisper && self.settings.waitForLocalMeetingServerInQueue && !skipLocalServer {
                        if let whisperErr = error as? WhisperWindowsError, case .serverUnavailable = whisperErr {
                            self.meetings.update(meetingID) { record in
                                record.status = .queued("Связь с локальным сервером прервалась — запись сохранена в очереди")
                            }
                            return
                        }
                        if error is URLError {
                            self.meetings.update(meetingID) { record in
                                record.status = .queued("Связь с локальным сервером прервалась — запись сохранена в очереди")
                            }
                            return
                        }
                    }
                    if hasNext {
                        continue
                    }
                }
            }

            self.meetings.update(meetingID) { record in
                record.status = .error(lastErrorMessage)
            }
        }

        meetingTranscriptionTask = task
        await task.value
    }

    private func prepareMeetingProgressUI(
        for meetingID: UUID,
        engineLabel: String,
        uploadEndFraction: Double,
        expectedDuration: Double?
    ) {
        meetings.update(meetingID) { record in
            record.status = .transcribing
            record.progressSeconds = 0
            record.transcriptionEngine = engineLabel
        }
        meetingTranscriptionProgress[meetingID] = MeetingTranscriptionProgress(
            stage: .preparingAudio,
            overallFraction: 0.01,
            uploadPhaseEndFraction: uploadEndFraction,
            uploadCompleted: false,
            processedSeconds: 0,
            totalSeconds: expectedDuration
        )
    }

    private func transcribeMeetingWithGapi(
        meetingID: UUID,
        micURL: URL,
        sysURL: URL?,
        expectedDuration: Double?,
        token: UUID
    ) async throws -> GapiTranscription {
        var uploadURL = micURL
        var stereoParties = false
        var tempStereoURL: URL? = nil

        if let sysURL {
            let candidateURL = meetings.folderURL(for: meetingID).appendingPathComponent("stereo_gapi.wav")
            try? FileManager.default.removeItem(at: candidateURL)
            let combined = await Task.detached(priority: .userInitiated) {
                MeetingAudioRecorder.combineMonoWAVsIntoStereo(
                    leftURL: micURL,
                    rightURL: sysURL,
                    outputURL: candidateURL
                )
            }.value
            if combined {
                uploadURL = candidateURL
                stereoParties = true
                tempStereoURL = candidateURL
            }
        }

        defer {
            if let tempStereoURL {
                try? FileManager.default.removeItem(at: tempStereoURL)
            }
        }

        let client = GapiClient(token: settings.gapiToken)
        let rawTranscription = try await client.transcribeMeeting(
            fileURL: uploadURL,
            stereoParties: stereoParties,
            enableSummary: settings.enableGapiSummary,
            expectedDuration: expectedDuration
        ) { [weak self] progress in
            Task { @MainActor in
                self?.applyTranscriptionProgress(progress, for: meetingID, token: token)
            }
        }
        return UzbekDialectConverter.applyIfNeeded(rawTranscription, style: settings.uzbekStyle)
    }

    private func applyTranscriptionProgress(
        _ progress: MeetingTranscriptionProgress,
        for meetingID: UUID,
        token: UUID
    ) {
        guard activeTranscriptionToken == token else { return }
        if let existing = meetingTranscriptionProgress[meetingID],
           progress.overallFraction < existing.overallFraction {
            return
        }
        meetingTranscriptionProgress[meetingID] = progress

        let existingSaved = meetings.meeting(withID: meetingID)?.progressSeconds ?? 0
        if progress.processedSeconds > 0, abs(progress.processedSeconds - existingSaved) >= 1.0 {
            meetings.update(meetingID) { record in
                record.progressSeconds = progress.processedSeconds
            }
        }
    }

    func processQueuedMeetingsIfNeeded() async {
        guard activeTranscriptionMeetingID == nil else { return }
        guard settings.hasExternalWhisperServer else { return }
        let queued = meetings.meetings.filter {
            if case .queued = $0.status { return true }
            return false
        }
        guard !queued.isEmpty else { return }

        let client = WhisperWindowsClient(baseURLString: settings.whisperServerURL)
        guard await client.isReachable(timeout: 2.0) else { return }

        for meeting in queued.reversed() {
            if activeTranscriptionMeetingID != nil { break }
            await transcribeMeetingOnWindowsOrQueue(meetingID: meeting.id)
            if let updated = meetings.meeting(withID: meeting.id),
               case .queued = updated.status {
                // Server went offline mid-batch; stop processing until next timer tick
                break
            }
        }
    }

    @discardableResult
    func cleanupExpiredMeetingAudio() -> Int {
        meetings.cleanupExpiredAudio(retention: settings.meetingAudioRetention)
    }

    private func cleanupAudioIfNotKeeping(for meetingID: UUID, micURL: URL, sysURL: URL?) {
        if !settings.keepMeetingAudio {
            try? FileManager.default.removeItem(at: micURL)
            if let sysURL {
                try? FileManager.default.removeItem(at: sysURL)
            }
            meetings.update(meetingID) { record in
                record.audioFileName = nil
                record.sysAudioFileName = nil
            }
        }
        cleanupExpiredMeetingAudio()
    }

    func regenerateRecap(for meetingID: UUID) async {
        guard let current = meetings.meeting(withID: meetingID) else { return }
        meetings.update(meetingID) { record in
            record.status = .summarizing
        }
        let generated = await MeetingRecapGenerator.generate(
            for: current,
            anthropicApiKey: settings.anthropicApiKey,
            llmConfig: settings.activeLLMConfig
        )
        meetings.update(meetingID) { record in
            record.recapMarkdown = generated.recapMarkdown
            if record.actionItems.isEmpty || !generated.actionItems.isEmpty {
                record.actionItems = generated.actionItems
            }
            record.status = .ready
        }
        if let updated = meetings.meeting(withID: meetingID) {
            await meetings.sendExportWebhookIfNeeded(for: updated)
        }
    }
}

