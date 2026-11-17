import SwiftUI

struct DashboardHomeView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var settings: SettingsStore
    @EnvironmentObject var history: HistoryStore
    @Environment(\.colorScheme) private var colorScheme

    private var chrome: VoiceChrome { VoiceChrome(scheme: colorScheme) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .center, spacing: 16) {
                    Text("Говорите, не печатайте")
                        .font(.system(size: 30, weight: .semibold))
                        .foregroundStyle(chrome.ink)
                    Spacer(minLength: 12)
                    statusPill
                }

                if case .error(let message) = appState.status {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.orange)
                }

                if showsPermissionCard {
                    permissionCard
                }

                LazyVGrid(columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)], spacing: 14) {
                    statTile(title: "Расшифровок", value: "\(history.records.count)")
                    statTile(title: "Слов надиктовано", value: "\(totalWords)")
                    if let wpm = averageWordsPerMinute {
                        statTile(title: "Средняя скорость", value: "\(wpm) слов/мин")
                    }
                    statTile(title: "Активных дней", value: "\(activeDaysCount)")
                }

                if let last = history.records.first {
                    lastTranscriptCard(last)
                }

                hotkeyCard
            }
            .padding(.horizontal, 28)
            .padding(.top, 20)
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
    }

    private var statusPill: some View {
        HStack(spacing: 8) {
            statusIcon
                .font(.system(size: 13, weight: .semibold))
            Text(statusTitle)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(chrome.ink)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(chrome.card, in: Capsule())
        .overlay(Capsule().strokeBorder(chrome.hairline))
    }

    private var showsPermissionCard: Bool {
        !appState.hotkeyActive
            || !appState.microphoneAuthorized
            || (settings.autoPaste && !appState.accessibilityAuthorized)
    }

    private var permissionCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !appState.hotkeyActive {
                permissionRow(systemImage: "exclamationmark.triangle.fill") {
                    if appState.inputMonitoringAuthorized {
                        Text("Мониторинг ввода разрешён, но нужен перезапуск приложения.")
                        Spacer()
                        Button("Перезапустить") {
                            PermissionsHelper.relaunchApp()
                        }
                        .controlSize(.small)
                    } else {
                        Text("Мониторинг ввода не разрешён — хоткей не работает вне этого окна.")
                        Spacer()
                        Button("Разрешить") {
                            PermissionsHelper.openInputMonitoringSettings()
                        }
                        .controlSize(.small)
                    }
                }
            }

            if !appState.microphoneAuthorized {
                if !appState.hotkeyActive {
                    Divider()
                }
                permissionRow(systemImage: "mic.slash.fill") {
                    Text("Доступ к микрофону не разрешён — запись голоса невозможна.")
                    Spacer()
                    Button("Разрешить") {
                        PermissionsHelper.openMicrophoneSettings()
                    }
                    .controlSize(.small)
                }
            }

            if settings.autoPaste && !appState.accessibilityAuthorized {
                if !appState.hotkeyActive || !appState.microphoneAuthorized {
                    Divider()
                }
                permissionRow(systemImage: "hand.raised.fill") {
                    Text("Accessibility не разрешён — автовставка (Cmd+V) в поля ввода не сработает.")
                    Spacer()
                    Button("Разрешить") {
                        PermissionsHelper.openAccessibilitySettings()
                    }
                    .controlSize(.small)
                }
            }
        }
        .voiceCard(chrome)
    }

    private func permissionRow<Content: View>(
        systemImage: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .foregroundStyle(.orange)
                .frame(width: 16)
            content()
                .font(.caption)
                .foregroundStyle(chrome.ink)
        }
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch appState.status {
        case .idle: Image(systemName: "mic").foregroundStyle(chrome.accent)
        case .recording: Image(systemName: "mic.fill").foregroundStyle(.red)
        case .transcribing, .cleaning: Image(systemName: "waveform").foregroundStyle(chrome.accent)
        case .error: Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
        }
    }

    private var statusTitle: String {
        switch appState.status {
        case .idle: return "Готов слушать"
        case .recording: return "Идёт запись…"
        case .transcribing: return "Распознаю речь…"
        case .cleaning: return "Обрабатываю текст…"
        case .error: return "Ошибка"
        }
    }

    private func statTile(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(value)
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(chrome.ink)
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(chrome.quiet)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .voiceCard(chrome)
    }

    private func lastTranscriptCard(_ record: TranscriptionRecord) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text("Последняя расшифровка")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(chrome.ink)
                if let lang = record.languageSummary, !lang.isEmpty {
                    Text(lang)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(chrome.accent)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(chrome.accent.opacity(0.12), in: Capsule())
                }
                Spacer()
                Text(record.date, format: .dateTime.day().month().hour().minute())
                    .font(.caption)
                    .foregroundStyle(chrome.quiet)
            }
            Text(record.text)
                .font(.system(size: 15))
                .foregroundStyle(chrome.ink)
                .lineLimit(4)
            Button("Скопировать снова") {
                TextInjector.copyToClipboard(record.text)
            }
            .font(.caption)
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .voiceCard(chrome)
    }

    private var hotkeyCard: some View {
        HStack(spacing: 8) {
            Image(systemName: "keyboard")
            if settings.recordingMode == .toggle {
                Text("Нажмите **\(settings.hotkey.rawValue)** для старта — говорите — нажмите ещё раз для завершения. **Escape** отменяет и ничего не отправляет.")
            } else {
                Text("Зажмите **\(settings.hotkey.rawValue)** — говорите — отпустите. **Escape** отменяет и ничего не отправляет.")
            }
            Spacer(minLength: 12)
        }
        .font(.callout)
        .foregroundStyle(chrome.quiet)
        .padding(.top, 4)
    }

    private var totalWords: Int {
        history.records.reduce(0) { $0 + $1.wordCount }
    }

    private var averageWordsPerMinute: Int? {
        let timed = history.records.filter { $0.durationSeconds > 1 }
        guard !timed.isEmpty else { return nil }
        let totalMinutes = timed.reduce(0.0) { $0 + $1.durationSeconds } / 60
        guard totalMinutes > 0 else { return nil }
        let words = timed.reduce(0) { $0 + $1.wordCount }
        return Int((Double(words) / totalMinutes).rounded())
    }

    private var activeDaysCount: Int {
        let calendar = Calendar.current
        let days = Set(history.records.map { calendar.startOfDay(for: $0.date) })
        return days.count
    }
}

private extension View {
    func voiceCard(_ chrome: VoiceChrome) -> some View {
        padding(16)
            .background(chrome.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(chrome.hairline)
            )
            .shadow(color: chrome.shadow, radius: 10, y: 4)
    }
}
