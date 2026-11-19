import SwiftUI

struct DashboardDictionaryView: View {
    @EnvironmentObject var settings: SettingsStore
    @Environment(\.colorScheme) private var colorScheme

    @State private var terms: [String] = []
    @State private var newTerm: String = ""
    @State private var isLoading = false
    @State private var isSaving = false
    @State private var errorMessage: String?

    private let maxTerms = 20
    private var theme: ClaudeTheme { ClaudeTheme(scheme: colorScheme) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .center, spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Словарь терминов")
                            .font(.system(size: 24, weight: .medium, design: .serif))
                            .foregroundStyle(theme.ink)
                        Text("Имена, бренды и термины, которые точнее распознаются в речи (до \(maxTerms) терминов на проект)")
                            .font(.caption)
                            .foregroundStyle(theme.secondaryInk)
                    }

                    Spacer()

                    if isLoading || isSaving {
                        ProgressView().controlSize(.small)
                    }

                    Button {
                        Task { await load() }
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "arrow.clockwise")
                            Text("Обновить")
                        }
                    }
                    .buttonStyle(ClaudeSecondaryButtonStyle(compact: true))
                    .disabled(settings.gapiToken.isEmpty || isLoading)
                }

                if settings.gapiToken.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "key.slash")
                            .font(.title2)
                            .foregroundStyle(theme.warning)
                        Text("Не задан токен gapi")
                            .font(.callout.weight(.semibold))
                            .foregroundStyle(theme.ink)
                        Text("Укажите API-токен в разделе «Настройки», чтобы синхронизировать словарь с console.gapi.uz.")
                            .font(.caption)
                            .foregroundStyle(theme.secondaryInk)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 28)
                    .claudeCard(theme, cornerRadius: 14, padding: 16)
                } else {
                    // Add term composer bar
                    HStack(spacing: 8) {
                        TextField("Новый термин (например, Korzinka или EPAM)", text: $newTerm)
                            .textFieldStyle(.plain)
                            .font(.callout)
                            .foregroundStyle(theme.ink)
                            .onSubmit(addTerm)

                        Button("Добавить", action: addTerm)
                            .buttonStyle(ClaudePrimaryButtonStyle(compact: true))
                            .disabled(newTerm.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || terms.count >= maxTerms)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(theme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(theme.border, lineWidth: 1)
                    )

                    if let errorMessage {
                        Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(theme.danger)
                    }

                    if terms.isEmpty && !isLoading {
                        VStack(spacing: 8) {
                            Image(systemName: "text.book.closed")
                                .font(.title2)
                                .foregroundStyle(theme.tertiaryInk)
                            Text("Словарь пока пуст")
                                .font(.callout.weight(.medium))
                                .foregroundStyle(theme.secondaryInk)
                            Text("Добавьте до \(maxTerms) специфичных слов, аббревиатур или имён.")
                                .font(.caption)
                                .foregroundStyle(theme.tertiaryInk)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 28)
                        .claudeCard(theme, cornerRadius: 14, padding: 16)
                    } else {
                        VStack(spacing: 0) {
                            ForEach(Array(terms.enumerated()), id: \.element) { idx, term in
                                HStack {
                                    Label(term, systemImage: "tag")
                                        .font(.callout)
                                        .foregroundStyle(theme.ink)
                                    Spacer()
                                    Button {
                                        remove(term)
                                    } label: {
                                        Image(systemName: "xmark")
                                            .font(.caption)
                                            .foregroundStyle(theme.secondaryInk)
                                            .frame(width: 24, height: 24)
                                            .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                    .help("Удалить термин")
                                }
                                .padding(.horizontal, 14)
                                .padding(.vertical, 10)

                                if idx < terms.count - 1 {
                                    Divider().overlay(theme.border)
                                }
                            }
                        }
                        .background(theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .strokeBorder(theme.border, lineWidth: 1)
                        )

                        Text("Использовано \(terms.count) из \(maxTerms) терминов")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(theme.secondaryInk)
                    }
                }
            }
            .frame(maxWidth: 720, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.horizontal, 28)
            .padding(.vertical, 24)
        }
        .background(theme.canvas)
        .task { await load() }
    }

    private func addTerm() {
        let trimmed = newTerm.trimmingCharacters(in: .whitespacesAndNewlines)
        newTerm = ""
        guard !trimmed.isEmpty, terms.count < maxTerms else { return }
        guard !terms.contains(where: { $0.caseInsensitiveCompare(trimmed) == .orderedSame }) else { return }
        terms.append(trimmed)
        Task { await save() }
    }

    private func remove(_ term: String) {
        terms.removeAll { $0 == term }
        Task { await save() }
    }

    private func load() async {
        guard !settings.gapiToken.isEmpty else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            terms = try await GapiClient(token: settings.gapiToken).getVocabulary()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func save() async {
        guard !settings.gapiToken.isEmpty else { return }
        isSaving = true
        defer { isSaving = false }
        do {
            try await GapiClient(token: settings.gapiToken).setVocabulary(terms)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
