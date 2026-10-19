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
    @Published var hotkeyActive: Bool = false
    @Published var microphoneAuthorized: Bool = PermissionsHelper.microphoneAuthorized()
    @Published var inputMonitoringAuthorized: Bool = PermissionsHelper.inputMonitoringAuthorized()
    @Published var accessibilityAuthorized: Bool = PermissionsHelper.accessibilityAuthorized()
    @Published var activeMeetingID: UUID? = nil
    @Published var meetingElapsedSeconds: TimeInterval = 0

    let settings: SettingsStore
    let history: HistoryStore
    let meetings: MeetingsStore
    private let recorder = AudioRecorder()
    private let meetingRecorder = MeetingAudioRecorder()
    private let hotkeys = HotkeyManager()
    private let indicator = RecordingIndicatorController()
    private var recordingStartedAt: Date?
    private var meetingStartedAt: Date?
    private var meetingTimer: Timer?
    private var lastNotifiedHotkeyIssue: HotkeyIssue?
    private var permissionsTimer: Timer?

    private enum HotkeyIssue: Equatable {
        case inputMonitoringMissing
        case needsRelaunch
    }

    init(settings: SettingsStore, history: HistoryStore, meetings: MeetingsStore? = nil) {
        self.settings = settings
        self.history = history
        self.meetings = meetings ?? MeetingsStore()
        hotkeys.onStart = { [weak self] in self?.beginRecording() }
        hotkeys.onStop = { [weak self] in self?.finishRecording() }
        hotkeys.onToggle = { [weak self] in self?.toggleRecording() }
        hotkeys.onCancel = { [weak self] in self?.cancelRecording() }
        hotkeys.isRecording = { [weak self] in self?.status == .recording }

        self.refreshPermissionsAndHotkey(forceRestartTap: true)

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
    }

    func refreshPermissionsAndHotkey(forceRestartTap: Bool = false) {
        let mic = PermissionsHelper.microphoneAuthorized()
        let inputMon = PermissionsHelper.inputMonitoringAuthorized()
        let ax = PermissionsHelper.accessibilityAuthorized()

        let permissionsChanged = (microphoneAuthorized != mic)
            || (inputMonitoringAuthorized != inputMon)
            || (accessibilityAuthorized != ax)

        if microphoneAuthorized != mic { microphoneAuthorized = mic }
        if inputMonitoringAuthorized != inputMon { inputMonitoringAuthorized = inputMon }
        if accessibilityAuthorized != ax { accessibilityAuthorized = ax }

        hotkeys.mode = settings.recordingMode

        // Don't interrupt an active recording
        guard status != .recording else { return }

        let keyChanged = hotkeys.targetKeyCode != settings.hotkey.keyCode
        let swallowUpgradeAvailable = ax && !hotkeys.canSwallowEvents
        let needsStart = forceRestartTap || !hotkeys.isActive || keyChanged || swallowUpgradeAvailable || permissionsChanged

        if needsStart {
            restartHotkeyListener()
        }
    }

    func restartHotkeyListener() {
        hotkeys.targetKeyCode = settings.hotkey.keyCode
        hotkeys.mode = settings.recordingMode
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

    private func toggleRecording() {
        if status == .recording {
            finishRecording()
        } else if status == .idle || isError {
            beginRecording()
        }
    }

    private func beginRecording() {
        guard status == .idle || isError else { return }

        switch PermissionsHelper.microphoneStatus() {
        case .notDetermined:
            PermissionsHelper.requestMicrophone { [weak self] granted in
                guard let self else { return }
                self.microphoneAuthorized = granted
                if !granted {
                    self.status = .error("Нет доступа к микрофону. Разрешите в Настройках.")
                }
            }
            return
        case .denied, .restricted:
            microphoneAuthorized = false
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
            status = .error("Не удалось начать запись: \(error.localizedDescription)")
        }
    }

    private func finishRecording() {
        guard status == .recording else { return }
        let duration = recordingStartedAt.map { Date().timeIntervalSince($0) } ?? 0
        recordingStartedAt = nil

        guard let fileURL = recorder.stop() else {
            status = .idle
            return
        }

        status = .transcribing
        Task {
            await transcribeAndInsert(fileURL: fileURL, durationSeconds: duration)
        }
    }

    private func cancelRecording() {
        guard status == .recording else { return }
        recordingStartedAt = nil
        recorder.cancel()
        status = .idle
    }

    private func transcribeAndInsert(fileURL: URL, durationSeconds: Double) async {
        defer { try? FileManager.default.removeItem(at: fileURL) }

        guard !settings.gapiToken.isEmpty else {
            status = .error("Не задан токен gapi. Откройте настройки.")
            return
        }

        do {
            let rawResult = try await GapiClient(token: settings.gapiToken).transcribe(fileURL: fileURL)
            let result = UzbekDialectConverter.applyIfNeeded(rawResult, style: settings.uzbekStyle)
            var text = result.text.trimmingCharacters(in: .whitespacesAndNewlines)

            guard !text.isEmpty else {
                status = .idle
                return
            }

            if settings.cleanupStyle != .off && !settings.anthropicApiKey.isEmpty {
                status = .cleaning
                do {
                    text = try await ClaudeClient(apiKey: settings.anthropicApiKey)
                        .cleanup(
                            transcription: result,
                            style: settings.cleanupStyle,
                            uzbekStyle: settings.uzbekStyle
                        )
                } catch {
                    // Preserve raw gapi transcript even if Claude post-processing fails
                }
            }

            lastText = text
            history.add(
                text: text,
                durationSeconds: durationSeconds,
                languageCode: result.languageCode,
                languageSummary: result.languageSummary
            )
            TextInjector.copyToClipboard(text)
            if settings.autoPaste {
                if PermissionsHelper.accessibilityAuthorized() {
                    if TextInjector.canPasteIntoFocusedField() {
                        TextInjector.pasteAtCursor()
                    }
                } else {
                    _ = PermissionsHelper.requestAccessibility(prompt: true)
                }
            }
            status = .idle
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
            meetingTimer?.invalidate()
            meetingTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
                Task { @MainActor in
                    guard let self, let started = self.meetingStartedAt else { return }
                    self.meetingElapsedSeconds = Date().timeIntervalSince(started)
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

            await processMeetingRecording(
                meetingID: meetingID,
                output: output,
                fallbackDuration: duration
            )
        }
    }

    func cancelMeeting() {
        guard let meetingID = activeMeetingID else { return }
        meetingTimer?.invalidate()
        meetingTimer = nil
        meetingStartedAt = nil
        activeMeetingID = nil
        meetingElapsedSeconds = 0

        Task {
            await meetingRecorder.cancel()
            meetings.delete(meetingID)
        }
    }

    private func processMeetingRecording(
        meetingID: UUID,
        output: MeetingRecordingOutput,
        fallbackDuration: Double
    ) async {
        let keepAudio = settings.keepMeetingAudio
        defer {
            if !keepAudio {
                try? FileManager.default.removeItem(at: output.fileURL)
            }
        }

        guard !settings.gapiToken.isEmpty else {
            meetings.update(meetingID) { record in
                record.status = .error("Не задан токен gapi. Откройте настройки.")
            }
            return
        }

        do {
            let client = GapiClient(token: settings.gapiToken)
            let rawTranscription = try await client.transcribeMeeting(
                fileURL: output.fileURL,
                stereoParties: output.stereoParties,
                enableSummary: settings.enableGapiSummary
            ) { [weak self] progressSec in
                Task { @MainActor in
                    self?.meetings.update(meetingID) { record in
                        record.progressSeconds = progressSec
                    }
                }
            }
            let transcription = UzbekDialectConverter.applyIfNeeded(rawTranscription, style: settings.uzbekStyle)

            meetings.update(meetingID) { record in
                record.stereoParties = transcription.stereoParties ?? output.stereoParties
                record.segments = transcription.segments
                record.languageCode = transcription.languageCode
                record.languageSummary = transcription.languageSummary
                record.gapiSummary = transcription.summaryText
                if let audioSec = transcription.audioSeconds, audioSec > 0 {
                    record.durationSeconds = audioSec
                } else if record.durationSeconds <= 0 {
                    record.durationSeconds = fallbackDuration
                }
                record.audioFileName = keepAudio ? output.fileURL.lastPathComponent : nil
                record.status = .summarizing
            }

            await regenerateRecap(for: meetingID)
        } catch {
            meetings.update(meetingID) { record in
                record.audioFileName = keepAudio ? output.fileURL.lastPathComponent : nil
                record.status = .error(error.localizedDescription)
            }
        }
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
    }
}

