import AVFoundation
import AppKit
import Foundation

enum RecordingStatus: Equatable {
    case idle
    case recording
    case transcribing
    case cleaning
    case error(String)
}

@MainActor
final class AppState: ObservableObject {
    @Published var status: RecordingStatus = .idle {
        didSet { indicator.update(status: status) }
    }
    @Published var selectedSection: DashboardSection? = .home
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
            try recorder.start()
            recordingStartedAt = Date()
            status = .recording
        } catch {
            hotkeys.notifyRecordingEndedExternally()
            status = .error("Не удалось начать запись: \(error.localizedDescription)")
        }
    }

    private func finishRecording() {
        guard status == .recording else { return }
        let duration = recordingStartedAt.map { Date().timeIntervalSince($0) } ?? 0
        recordingStartedAt = nil

        guard let fileURL = recorder.stop() else {
            hotkeys.notifyRecordingEndedExternally()
            status = .idle
            return
        }

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

    private func transcribeAndInsert(fileURL: URL, durationSeconds: Double) async {
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let gapiToken = settings.gapiToken.trimmingCharacters(in: .whitespacesAndNewlines)
        let coordinator: DictationTranscriptionCoordinator

        if settings.useHomeServer {
            let gatewayToken = settings.homeServerToken.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !gatewayToken.isEmpty else {
                let message = "Не задан токен домашнего сервера. Откройте настройки."
                history.add(text: "", durationSeconds: durationSeconds, status: .failed, targetApp: currentTargetAppName(), errorMessage: message, style: settings.cleanupStyle)
                hotkeys.notifyRecordingEndedExternally()
                status = .error(message)
                return
            }
            let homeProvider = HomeServerProvider(config: settings.homeServerConfig)
            let fallbackProvider: (any TranscriptionProvider)? = gapiToken.isEmpty
                ? nil
                : GapiTranscriptionProvider(token: gapiToken)
            coordinator = DictationTranscriptionCoordinator(
                primary: homeProvider,
                fallback: fallbackProvider
            ) { reason in
                NotificationHelper.notify(
                    title: "Домашний сервер недоступен",
                    body: "Переключился на gapi.uz (\(reason))."
                )
            }
        } else {
            guard !gapiToken.isEmpty else {
                let message = "Не задан токен gapi. Откройте настройки."
                history.add(text: "", durationSeconds: durationSeconds, status: .failed, targetApp: currentTargetAppName(), errorMessage: message, style: settings.cleanupStyle)
                hotkeys.notifyRecordingEndedExternally()
                status = .error(message)
                return
            }
            coordinator = DictationTranscriptionCoordinator(
                primary: GapiTranscriptionProvider(token: gapiToken)
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
            let activeStyle = settings.cleanupStyle
            let anthropicKey = settings.anthropicApiKey.trimmingCharacters(in: .whitespacesAndNewlines)

            if activeStyle != .off && !anthropicKey.isEmpty {
                status = .cleaning
                let inputForClaude = GapiTranscription(
                    text: finalText,
                    languageCode: result.languageCode,
                    languageConfidence: nil,
                    languageShare: nil,
                    segments: [],
                    audioSeconds: result.audioSeconds
                )
                finalText = try await ClaudeClient(apiKey: anthropicKey).cleanup(
                    transcription: inputForClaude,
                    style: activeStyle,
                    uzbekStyle: settings.uzbekStyle
                )
                finalText = dictionary.apply(to: finalText)
            }

            try Task.checkCancellation()
            guard !Task.isCancelled else { return }

            let targetApp = currentTargetAppName()
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
                latencyMs: result.latencyMs
            )
            hotkeys.notifyRecordingEndedExternally()
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
        let anthropicKey = settings.anthropicApiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !anthropicKey.isEmpty, style != .off else { return }

        let input = GapiTranscription(
            text: record.text,
            languageCode: record.languageCode,
            languageConfidence: nil,
            languageShare: nil,
            segments: []
        )
        do {
            let cleaned = try await ClaudeClient(apiKey: anthropicKey).cleanup(
                transcription: input,
                style: style,
                uzbekStyle: settings.uzbekStyle
            )
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
                    latencyMs: item.latencyMs
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

    func retryMeetingOnWindows(_ meetingID: UUID) {
        Task {
            await transcribeMeetingOnWindowsOrQueue(meetingID: meetingID)
        }
    }

    func transcribeMeetingUrgentGapi(_ meetingID: UUID) {
        guard let current = meetings.meeting(withID: meetingID) else { return }
        guard let micURL = meetings.audioFileURL(for: current) else {
            meetings.update(meetingID) { record in
                record.status = .error("Аудиофайл записи не найден.")
            }
            return
        }

        guard !settings.gapiToken.isEmpty else {
            meetings.update(meetingID) { record in
                record.status = .error("Не задан токен gapi. Откройте настройки.")
            }
            return
        }

        if let existingTask = meetingTranscriptionTask {
            existingTask.cancel()
        }

        let sysURL = meetings.sysAudioFileURL(for: current)
        let expectedDuration = current.durationSeconds > 0 ? current.durationSeconds : nil
        let token = UUID()
        activeTranscriptionMeetingID = meetingID
        activeTranscriptionToken = token

        meetingTranscriptionTask = Task { [weak self] in
            guard let self else { return }
            defer {
                if self.activeTranscriptionToken == token {
                    self.activeTranscriptionMeetingID = nil
                    self.activeTranscriptionToken = nil
                    self.meetingTranscriptionTask = nil
                    self.meetingTranscriptionProgress.removeValue(forKey: meetingID)
                }
            }

            self.meetings.update(meetingID) { record in
                record.status = .transcribing
                record.progressSeconds = 0
                record.transcriptionEngine = "gapi.uz"
            }
            self.meetingTranscriptionProgress[meetingID] = MeetingTranscriptionProgress(
                stage: .preparingAudio,
                overallFraction: 0.01,
                uploadPhaseEndFraction: 0.25,
                uploadCompleted: false,
                processedSeconds: 0,
                totalSeconds: expectedDuration
            )

            var uploadURL = micURL
            var stereoParties = false
            var tempStereoURL: URL? = nil

            if let sysURL {
                let candidateURL = self.meetings.folderURL(for: meetingID).appendingPathComponent("stereo_gapi.wav")
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

            do {
                try Task.checkCancellation()
                let client = GapiClient(token: self.settings.gapiToken)
                let rawTranscription = try await client.transcribeMeeting(
                    fileURL: uploadURL,
                    stereoParties: stereoParties,
                    enableSummary: self.settings.enableGapiSummary,
                    expectedDuration: expectedDuration
                ) { [weak self] progress in
                    Task { @MainActor in
                        self?.applyTranscriptionProgress(progress, for: meetingID, token: token)
                    }
                }

                try Task.checkCancellation()
                let transcription = UzbekDialectConverter.applyIfNeeded(rawTranscription, style: self.settings.uzbekStyle)

                self.meetings.update(meetingID) { record in
                    record.stereoParties = transcription.stereoParties ?? stereoParties
                    record.segments = transcription.segments
                    record.languageCode = transcription.languageCode
                    record.languageSummary = transcription.languageSummary
                    record.gapiSummary = transcription.summaryText
                    record.transcriptionEngine = "gapi.uz"
                    if let audioSec = transcription.audioSeconds, audioSec > 0 {
                        record.durationSeconds = audioSec
                    }
                    record.status = .summarizing
                }

                self.cleanupAudioIfNotKeeping(for: meetingID, micURL: micURL, sysURL: sysURL)
                await self.regenerateRecap(for: meetingID)
            } catch is CancellationError {
                return
            } catch let error as URLError where error.code == .cancelled {
                return
            } catch {
                guard !Task.isCancelled else { return }
                self.meetings.update(meetingID) { record in
                    record.status = .error("Ошибка gapi.uz: \(error.localizedDescription)")
                }
            }
        }
    }

    func transcribeMeetingOnWindowsOrQueue(meetingID: UUID) async {
        guard let current = meetings.meeting(withID: meetingID) else { return }
        guard let micURL = meetings.audioFileURL(for: current) else {
            meetings.update(meetingID) { record in
                record.status = .error("Аудиофайл записи не найден.")
            }
            return
        }

        if !settings.hasExternalWhisperServer {
            transcribeMeetingUrgentGapi(meetingID)
            return
        }

        if let busyID = activeTranscriptionMeetingID, busyID != meetingID {
            meetings.update(meetingID) { record in
                record.status = .queued("В очереди за другой расшифровкой")
            }
            return
        }

        if activeTranscriptionMeetingID == meetingID {
            meetingTranscriptionTask?.cancel()
            meetingTranscriptionTask = nil
        }

        let client = WhisperWindowsClient(baseURLString: settings.whisperServerURL)
        let engineLabel = client.engineDisplayName
        let reachable = await client.isReachable(timeout: 2.5)
        guard reachable else {
            meetings.update(meetingID) { record in
                record.status = .queued("Сервер распознавания недоступен (либо отправьте через gapi.uz)")
            }
            return
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

            self.meetings.update(meetingID) { record in
                record.status = .transcribing
                record.progressSeconds = 0
                record.transcriptionEngine = engineLabel
            }
            self.meetingTranscriptionProgress[meetingID] = MeetingTranscriptionProgress(
                stage: .preparingAudio,
                overallFraction: 0.01,
                uploadPhaseEndFraction: 0.05,
                uploadCompleted: false,
                processedSeconds: 0,
                totalSeconds: expectedDuration
            )

            do {
                let transcription = try await client.transcribeMeeting(
                    micURL: micURL,
                    sysURL: sysURL,
                    expectedDuration: expectedDuration
                ) { [weak self] progress in
                    Task { @MainActor in
                        self?.applyTranscriptionProgress(progress, for: meetingID, token: token)
                    }
                }

                try Task.checkCancellation()

                self.meetings.update(meetingID) { record in
                    record.stereoParties = transcription.stereoParties ?? (sysURL != nil)
                    record.segments = transcription.segments
                    record.languageCode = transcription.languageCode ?? "ru"
                    record.languageSummary = "Русский"
                    record.transcriptionEngine = engineLabel
                    if let audioSec = transcription.audioSeconds, audioSec > 0 {
                        record.durationSeconds = audioSec
                    }
                    record.status = .summarizing
                }

                self.cleanupAudioIfNotKeeping(for: meetingID, micURL: micURL, sysURL: sysURL)
                await self.regenerateRecap(for: meetingID)
            } catch is CancellationError {
                return
            } catch let error as URLError where error.code == .cancelled {
                return
            } catch let error as WhisperWindowsError {
                guard !Task.isCancelled else { return }
                switch error {
                case .serverUnavailable:
                    self.meetings.update(meetingID) { record in
                        record.status = .queued("Связь с сервером распознавания прервалась — запись сохранена в очереди")
                    }
                default:
                    self.meetings.update(meetingID) { record in
                        record.status = .error(error.localizedDescription)
                    }
                }
            } catch is URLError {
                guard !Task.isCancelled else { return }
                self.meetings.update(meetingID) { record in
                    record.status = .queued("Связь с сервером распознавания прервалась — запись сохранена в очереди")
                }
            } catch {
                guard !Task.isCancelled else { return }
                self.meetings.update(meetingID) { record in
                    record.status = .error(error.localizedDescription)
                }
            }
        }

        meetingTranscriptionTask = task
        await task.value
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
            anthropicApiKey: settings.anthropicApiKey
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

