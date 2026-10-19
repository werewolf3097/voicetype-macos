import SwiftUI

struct DashboardHomeView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var settings: SettingsStore
    @EnvironmentObject var history: HistoryStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("Говорите, не печатайте")
                    .font(.system(size: 32, weight: .bold))

                statusCard

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
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
            .padding(24)
        }
    }

    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                statusIcon
                    .font(.title2)
                VStack(alignment: .leading, spacing: 2) {
                    Text(statusTitle).font(.headline)
                    if case .error(let message) = appState.status {
                        Text(message).font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer()
            }

            if !appState.hotkeyActive {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    if appState.inputMonitoringAuthorized {
                        Text("Мониторинг ввода разрешён, но нужен перезапуск приложения.")
                            .font(.caption)
                        Spacer()
                        Button("Перезапустить") {
                            PermissionsHelper.relaunchApp()
                        }
                        .controlSize(.small)
                    } else {
                        Text("Мониторинг ввода не разрешён — хоткей не работает вне этого окна.")
                            .font(.caption)
                        Spacer()
                        Button("Разрешить") {
                            PermissionsHelper.openInputMonitoringSettings()
                        }
                        .controlSize(.small)
                    }
                }
            }

            if !appState.microphoneAuthorized {
                HStack {
                    Image(systemName: "mic.slash.fill")
                        .foregroundStyle(.orange)
                    Text("Доступ к микрофону не разрешён — запись голоса невозможна.")
                        .font(.caption)
                    Spacer()
                    Button("Разрешить") {
                        PermissionsHelper.openMicrophoneSettings()
                    }
                    .controlSize(.small)
                }
            }

            if settings.autoPaste && !appState.accessibilityAuthorized {
                HStack {
                    Image(systemName: "hand.raised.fill")
                        .foregroundStyle(.orange)
                    Text("Accessibility не разрешён — автовставка (Cmd+V) в поля ввода не сработает.")
                        .font(.caption)
                    Spacer()
                    Button("Разрешить") {
                        PermissionsHelper.openAccessibilitySettings()
                    }
                    .controlSize(.small)
                }
            }
        }
        .padding(16)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch appState.status {
        case .idle: Image(systemName: "mic").foregroundStyle(.secondary)
        case .recording: Image(systemName: "mic.fill").foregroundStyle(.red)
        case .transcribing, .cleaning: Image(systemName: "waveform").foregroundStyle(.blue)
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
        VStack(alignment: .leading, spacing: 4) {
            Text(value).font(.system(size: 26, weight: .bold))
            Text(title).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(.background, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.separator))
    }

    private func lastTranscriptCard(_ record: TranscriptionRecord) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Последняя расшифровка").font(.headline)
                if let lang = record.languageSummary, !lang.isEmpty {
                    Text(lang)
                        .font(.caption2.weight(.medium))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(.quaternary, in: Capsule())
                }
                Spacer()
                Text(record.date, format: .dateTime.day().month().hour().minute())
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text(record.text)
                .font(.body)
                .lineLimit(4)
            Button("Скопировать снова") {
                TextInjector.copyToClipboard(record.text)
            }
            .font(.caption)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(.background, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.separator))
    }

    private var hotkeyCard: some View {
        HStack {
            Image(systemName: "keyboard")
            if settings.recordingMode == .toggle {
                Text("Нажмите **\(settings.hotkey.rawValue)** для старта — говорите — нажмите ещё раз для завершения.")
            } else {
                Text("Зажмите **\(settings.hotkey.rawValue)** — говорите — отпустите.")
            }
            Spacer()
            if settings.cleanupStyle != .off {
                Text(settings.cleanupStyle.rawValue)
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.quaternary, in: Capsule())
            }
        }
        .font(.callout)
        .foregroundStyle(.secondary)
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
