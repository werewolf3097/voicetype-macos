import SwiftUI

struct DashboardDictionaryView: View {
    @EnvironmentObject var settings: SettingsStore
    @EnvironmentObject var dictionary: DictionaryStore
    @Environment(\.paperTheme) private var paperTheme
    @Environment(\.paperFontPreset) private var fontPreset

    @State private var isAddingInline = false
    @State private var newHeard = ""
    @State private var newWritten = ""
    @FocusState private var heardFocused: Bool

    // Опциональная синхронизация терминов в облако gapi.uz
    @State private var showGapiSync = false
    @State private var gapiTerms: [String] = []
    @State private var newGapiTerm = ""
    @State private var isLoadingGapi = false
    @State private var gapiError: String?

    private let maxGapiTerms = 20
    private var fonts: PaperFonts { PaperFonts(preset: fontPreset) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                PaperPageHeader(
                    "Словарь",
                    subtitle: "Пары замен «слышится → пишется» применяются к каждому тексту после распознавания.",
                    systemImage: "book.closed",
                    tileTint: PaperTokens.dictionaryTeal
                )

                VStack(spacing: 0) {
                    if isAddingInline {
                        inlineAddRow
                    } else {
                        Button {
                            withAnimation(.easeOut(duration: 0.14)) {
                                isAddingInline = true
                            }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                                heardFocused = true
                            }
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "plus")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(PaperTokens.dictionaryTeal)
                                Text("Новое слово")
                                    .font(fonts.uiMedium)
                                    .foregroundStyle(paperTheme.inkColor)
                                Spacer()
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }

                    if !dictionary.entries.isEmpty {
                        Rectangle()
                            .fill(paperTheme.borderColor)
                            .frame(height: PaperTokens.hairline)

                        ForEach(Array(dictionary.entries.enumerated()), id: \.element.id) { idx, entry in
                            HStack(spacing: 12) {
                                Text(entry.heard)
                                    .font(fonts.body)
                                    .foregroundStyle(paperTheme.secondaryInkColor)
                                    .frame(minWidth: 120, alignment: .leading)

                                Image(systemName: "arrow.right")
                                    .font(.system(size: 10.5, weight: .regular))
                                    .foregroundStyle(paperTheme.tertiaryInkColor)

                                Text(entry.written)
                                    .font(fonts.bodyMedium)
                                    .foregroundStyle(paperTheme.inkColor)

                                Spacer()

                                Button {
                                    dictionary.remove(id: entry.id)
                                } label: {
                                    Image(systemName: "xmark")
                                        .font(.system(size: 10.5, weight: .medium))
                                        .foregroundStyle(paperTheme.secondaryInkColor)
                                        .frame(width: 24, height: 24)
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .help("Удалить правило")
                                .accessibilityLabel("Удалить замену \(entry.heard)")
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)

                            if idx < dictionary.entries.count - 1 {
                                Rectangle()
                                    .fill(paperTheme.borderColor)
                                    .frame(height: PaperTokens.hairline)
                            }
                        }
                    }
                }
                .background(
                    paperTheme.isDark ? paperTheme.surfaceColor.opacity(0.92) : paperTheme.surfaceColor.opacity(0.84),
                    in: RoundedRectangle(cornerRadius: PaperTokens.cardRadius, style: .continuous)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: PaperTokens.cardRadius, style: .continuous)
                        .strokeBorder(paperTheme.borderColor, lineWidth: 0.75)
                )

                if dictionary.entries.isEmpty && !isAddingInline {
                    Text("Например: «эпам → EPAM», «корзинка → Korzinka» или имя коллеги.")
                        .font(fonts.caption)
                        .foregroundStyle(paperTheme.secondaryInkColor)
                        .padding(.horizontal, 4)
                }

                if !settings.gapiToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    gapiVocabularySection
                }
            }
            .frame(maxWidth: 680, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(PaperTokens.contentPadding)
        }
        .background { PaperBackground() }
    }

    private var inlineAddRow: some View {
        HStack(spacing: 10) {
            PaperInsetField(cornerRadius: PaperTokens.chipRadius, horizontalPadding: 9, verticalPadding: 5) {
                TextField("Слышится (например, эпам)", text: $newHeard)
                    .textFieldStyle(.plain)
                    .font(fonts.ui)
                    .foregroundStyle(paperTheme.inkColor)
                    .focused($heardFocused)
                    .onSubmit { commitInlineAdd() }
            }

            Image(systemName: "arrow.right")
                .font(.system(size: 11))
                .foregroundStyle(paperTheme.secondaryInkColor)

            PaperInsetField(cornerRadius: PaperTokens.chipRadius, horizontalPadding: 9, verticalPadding: 5) {
                TextField("Пишется (EPAM)", text: $newWritten)
                    .textFieldStyle(.plain)
                    .font(fonts.ui)
                    .foregroundStyle(paperTheme.inkColor)
                    .onSubmit { commitInlineAdd() }
            }

            Button("Добавить") {
                commitInlineAdd()
            }
            .buttonStyle(PaperButtonStyle(role: .primary, compact: true))
            .disabled(newHeard.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                      || newWritten.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

            Button {
                withAnimation(.easeOut(duration: 0.14)) {
                    newHeard = ""
                    newWritten = ""
                    isAddingInline = false
                }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(paperTheme.secondaryInkColor)
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Отменить добавление")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private func commitInlineAdd() {
        let heard = newHeard.trimmingCharacters(in: .whitespacesAndNewlines)
        let written = newWritten.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !heard.isEmpty, !written.isEmpty else { return }
        dictionary.add(heard: heard, written: written)
        newHeard = ""
        newWritten = ""
        isAddingInline = false
    }

    // MARK: - Optional gapi.uz Cloud Vocabulary

    private var gapiVocabularySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                withAnimation(.easeOut(duration: 0.15)) {
                    showGapiSync.toggle()
                }
                if showGapiSync && gapiTerms.isEmpty {
                    Task { await loadGapi() }
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: showGapiSync ? "chevron.down" : "chevron.right")
                        .font(.system(size: 10, weight: .medium))
                    Text("Подсказки для gapi.uz (\(gapiTerms.count)/\(maxGapiTerms))")
                        .font(fonts.captionMedium)
                    Spacer()
                }
                .foregroundStyle(paperTheme.secondaryInkColor)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if showGapiSync {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Эти термины отправляются в проект gapi.uz как подсказки распознавания.")
                        .font(fonts.caption)
                        .foregroundStyle(paperTheme.secondaryInkColor)

                    HStack(spacing: 8) {
                        PaperInsetField(cornerRadius: PaperTokens.chipRadius, horizontalPadding: 9, verticalPadding: 5) {
                            TextField("Термин для gapi.uz", text: $newGapiTerm)
                                .textFieldStyle(.plain)
                                .font(fonts.ui)
                                .foregroundStyle(paperTheme.inkColor)
                                .onSubmit { addGapiTerm() }
                        }

                        Button("Добавить", action: addGapiTerm)
                            .buttonStyle(PaperButtonStyle(role: .secondary, compact: true))
                            .disabled(newGapiTerm.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || gapiTerms.count >= maxGapiTerms)

                        if isLoadingGapi {
                            ProgressView().controlSize(.small)
                        }
                    }

                    if let gapiError {
                        HStack(spacing: 8) {
                            Text(gapiError)
                                .font(fonts.caption)
                                .foregroundStyle(paperTheme.errorColor)
                            Spacer()
                            Button("Повторить") {
                                Task { await loadGapi() }
                            }
                            .buttonStyle(PaperButtonStyle(role: .secondary, compact: true))
                        }
                    }

                    if !gapiTerms.isEmpty {
                        ClaudeFlowLayout(horizontalSpacing: 6, verticalSpacing: 6) {
                            ForEach(gapiTerms, id: \.self) { term in
                                HStack(spacing: 5) {
                                    Text(term)
                                        .font(fonts.caption)
                                        .foregroundStyle(paperTheme.inkColor)
                                    Button {
                                        gapiTerms.removeAll { $0 == term }
                                        Task { await saveGapi() }
                                    } label: {
                                        Image(systemName: "xmark")
                                            .font(.system(size: 9, weight: .medium))
                                            .foregroundStyle(paperTheme.secondaryInkColor)
                                    }
                                    .buttonStyle(.plain)
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .paperSurface(level: .l2OnPaper, cornerRadius: PaperTokens.chipRadius)
                            }
                        }
                    }
                }
                .padding(14)
                .background(
                    paperTheme.surfaceColor.opacity(0.4),
                    in: RoundedRectangle(cornerRadius: PaperTokens.cardRadius, style: .continuous)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: PaperTokens.cardRadius, style: .continuous)
                        .strokeBorder(paperTheme.borderColor, lineWidth: PaperTokens.hairline)
                )
            }
        }
        .padding(.top, 8)
    }

    private func addGapiTerm() {
        let trimmed = newGapiTerm.trimmingCharacters(in: .whitespacesAndNewlines)
        newGapiTerm = ""
        guard !trimmed.isEmpty, gapiTerms.count < maxGapiTerms else { return }
        guard !gapiTerms.contains(where: { $0.caseInsensitiveCompare(trimmed) == .orderedSame }) else { return }
        gapiTerms.append(trimmed)
        Task { await saveGapi() }
    }

    private func loadGapi() async {
        guard !settings.gapiToken.isEmpty else { return }
        isLoadingGapi = true
        defer { isLoadingGapi = false }
        do {
            gapiTerms = try await GapiClient(token: settings.gapiToken).getVocabulary()
            gapiError = nil
        } catch {
            gapiError = error.localizedDescription
        }
    }

    private func saveGapi() async {
        guard !settings.gapiToken.isEmpty else { return }
        isLoadingGapi = true
        defer { isLoadingGapi = false }
        do {
            try await GapiClient(token: settings.gapiToken).setVocabulary(gapiTerms)
            gapiError = nil
        } catch {
            gapiError = error.localizedDescription
        }
    }
}
