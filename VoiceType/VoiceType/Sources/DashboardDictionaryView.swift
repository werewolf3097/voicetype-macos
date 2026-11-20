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
                            .font(ClaudeFonts.pageTitle)
                            .tracking(-0.35)
                            .foregroundStyle(theme.ink)
                        Text("Имена, бренды и термины, которые точнее распознаются в речи (до \(maxTerms) терминов на проект)")
                            .font(ClaudeFonts.small)
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
                            ClaudeIcon(name: "arrow.clockwise", size: 11, weight: .light)
                            Text("Обновить")
                        }
                    }
                    .buttonStyle(ClaudeSecondaryButtonStyle(compact: true))
                    .disabled(settings.gapiToken.isEmpty || isLoading)
                }

                if settings.gapiToken.isEmpty {
                    VStack(spacing: 10) {
                        ClaudeIcon(name: "key.slash", size: 22, weight: .ultraLight)
                            .foregroundStyle(theme.warning)
                        Text("Не задан токен gapi")
                            .font(ClaudeFonts.uiMedium)
                            .foregroundStyle(theme.ink)
                        Text("Укажите API-токен в разделе «Настройки», чтобы синхронизировать словарь с console.gapi.uz.")
                            .font(ClaudeFonts.small)
                            .foregroundStyle(theme.secondaryInk)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 28)
                    .claudeCard(theme, cornerRadius: 12, padding: 16)
                } else {
                    // Add term composer bar
                    HStack(spacing: 8) {
                        TextField("Новый термин (например, Korzinka или EPAM)", text: $newTerm)
                            .textFieldStyle(.plain)
                            .font(ClaudeFonts.ui)
                            .foregroundStyle(theme.ink)
                            .onSubmit(addTerm)

                        Button("Добавить", action: addTerm)
                            .buttonStyle(ClaudePrimaryButtonStyle(compact: true))
                            .disabled(newTerm.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || terms.count >= maxTerms)
                    }
                    .padding(.horizontal, 11)
                    .padding(.vertical, 7)
                    .background(theme.surface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(theme.border, lineWidth: 1)
                    )

                    if let errorMessage {
                        HStack(spacing: 6) {
                            ClaudeIcon(name: "exclamationmark.triangle", size: 11.5, weight: .light)
                            Text(errorMessage)
                                .font(ClaudeFonts.small)
                        }
                        .foregroundStyle(theme.danger)
                    }

                    if terms.isEmpty && !isLoading {
                        VStack(spacing: 8) {
                            ClaudeIcon(name: "book.closed", size: 22, weight: .ultraLight)
                                .foregroundStyle(theme.tertiaryInk)
                            Text("Словарь пока пуст")
                                .font(ClaudeFonts.uiMedium)
                                .foregroundStyle(theme.secondaryInk)
                            Text("Добавьте до \(maxTerms) специфичных слов, аббревиатур или имён.")
                                .font(ClaudeFonts.small)
                                .foregroundStyle(theme.tertiaryInk)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 28)
                        .claudeCard(theme, cornerRadius: 12, padding: 16)
                    } else {
                        VStack(spacing: 0) {
                            ForEach(Array(terms.enumerated()), id: \.element) { idx, term in
                                HStack(spacing: 9) {
                                    ClaudeIcon(name: "tag", size: 12, weight: .light)
                                        .foregroundStyle(theme.secondaryInk)
                                    Text(term)
                                        .font(ClaudeFonts.ui)
                                        .foregroundStyle(theme.ink)
                                    Spacer()
                                    Button {
                                        remove(term)
                                    } label: {
                                        ClaudeIcon(name: "xmark", size: 10.5, weight: .light)
                                            .foregroundStyle(theme.secondaryInk)
                                            .frame(width: 24, height: 24)
                                            .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                    .help("Удалить термин")
                                }
                                .padding(.horizontal, 14)
                                .padding(.vertical, 9)

                                if idx < terms.count - 1 {
                                    Divider().overlay(theme.border)
                                }
                            }
                        }
                        .background(theme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .strokeBorder(theme.border, lineWidth: 1)
                        )

                        Text("Использовано \(terms.count) из \(maxTerms) терминов")
                            .font(ClaudeFonts.small.monospacedDigit())
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
