import Foundation

enum UzbekStyle: String, CaseIterable, Identifiable, Codable {
    case tashkent = "Ташкентский (Toshkent shevasi)"
    case literary = "Литературный (Adabiy til)"

    var id: String { rawValue }
}

/// Converts standard/literary Uzbek (Adabiy til) produced by gapi.uz's ASR into natural
/// Tashkent conversational dialect (Toshkent shevasi) when enabled.
enum UzbekDialectConverter {

    private static let phraseReplacements: [(String, String)] = [
        ("(?i)\\bbu yerda\\b", "botta"),
        ("(?i)\\bshu yerda\\b", "shotta"),
        ("(?i)\\bu yerda\\b", "utta"),
        ("(?i)\\bbu yerga\\b", "botga"),
        ("(?i)\\bshu yerga\\b", "shotga"),
        ("(?i)\\bu yerga\\b", "utga"),
        ("(?i)\\bbu yerdan\\b", "bottan"),
        ("(?i)\\bshu yerdan\\b", "shottan"),
        ("(?i)\\bnima uchun\\b", "nimaga"),
    ]

    private static let exactWordReplacements: [String: String] = [
        // qilmoq -> qivomman / qivosan / qivotti / qivommiz / qivossiz
        "qilyapman": "qivomman",
        "qilayapman": "qivomman",
        "qilyapsan": "qivosan",
        "qilayapsan": "qivosan",
        "qilyapti": "qivotti",
        "qilayapti": "qivotti",
        "qilyapmiz": "qivommiz",
        "qilayapmiz": "qivommiz",
        "qilyapsiz": "qivossiz",
        "qilayapsiz": "qivossiz",
        "qilyapsizlar": "qivossila",
        "qilyaptilar": "qivottila",
        "qilayotgan": "qivotgan",
        "qilyotgan": "qivotgan",

        // bo'lmoq -> bo'vomman / bo'votti
        "bo'lyapman": "bo'vomman",
        "bo‘lyapman": "bo‘vomman",
        "bo\u{02BB}lyapman": "bo\u{02BB}vomman",
        "bo'lyapsan": "bo'vosan",
        "bo‘lyapsan": "bo‘vosan",
        "bo\u{02BB}lyapsan": "bo\u{02BB}vosan",
        "bo'lyapti": "bo'votti",
        "bo‘lyapti": "bo‘votti",
        "bo\u{02BB}lyapti": "bo\u{02BB}votti",
        "bo'layapti": "bo'votti",
        "bo‘layapti": "bo‘votti",
        "bo\u{02BB}layapti": "bo\u{02BB}votti",
        "bo'lyapmiz": "bo'vommiz",
        "bo‘lyapmiz": "bo‘vommiz",
        "bo\u{02BB}lyapmiz": "bo\u{02BB}vommiz",
        "bo'layotgan": "bo'votgan",
        "bo‘layotgan": "bo‘votgan",
        "bo\u{02BB}layotgan": "bo\u{02BB}votgan",
        "bo'пти": "bo'pti",

        // kelmoq -> kevomman / kevotti / kevommiz
        "kelyapman": "kevomman",
        "kelayapman": "kevomman",
        "kelyapsan": "kevosan",
        "kelayapsan": "kevosan",
        "kelyapti": "kevotti",
        "kelayapti": "kevotti",
        "kelyapmiz": "kevommiz",
        "kelayapmiz": "kevommiz",
        "kelyapsiz": "kevossiz",
        "kelayapsiz": "kevossiz",
        "kelyaptilar": "kevottila",
        "kelayotgan": "kevotgan",
        "kelyotgan": "kevotgan",

        // aytmoq -> etvomman / etvotti / etdim / etdi
        "aytyapman": "etvomman",
        "aytayapman": "etvomman",
        "aytyapsan": "etvosan",
        "aytayapsan": "etvosan",
        "aytyapti": "etvotti",
        "aytayapti": "etvotti",
        "aytyapmiz": "etvommiz",
        "aytayapmiz": "etvommiz",
        "aytyapsiz": "etvossiz",
        "aytayapsiz": "etvossiz",
        "aytdim": "etdim",
        "aytdi": "etdi",
        "aytdik": "etdik",
        "aytgan": "etgan",
        "aytaman": "etaman",
        "aytasiz": "etasiz",
        "ayting": "eting",

        // Question & location words in Tashkent dialect
        "qayerda": "qatta",
        "qayerga": "qatga",
        "qayerdan": "qattan",
        "qayerdadir": "qattadir",
        "qayerdansiz": "qattansiz",
        "qayerdasan": "qattasan",
    ]

    static func applyIfNeeded(_ transcription: GapiTranscription, style: UzbekStyle) -> GapiTranscription {
        guard style == .tashkent else { return transcription }
        let trimmed = transcription.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return transcription }

        let updatedSegments = transcription.segments.map { seg -> GapiTranscription.Segment in
            let isUzSeg = (seg.languageCode == nil || seg.languageCode == "uz" || seg.languageCode == "uz-khorezm")
            guard isUzSeg else { return seg }
            return GapiTranscription.Segment(
                index: seg.index,
                start: seg.start,
                end: seg.end,
                speaker: seg.speaker,
                text: convertSentenceToTashkent(seg.text),
                languageCode: seg.languageCode,
                languageConfidence: seg.languageConfidence
            )
        }

        let convertedFullText = convertSentenceToTashkent(transcription.text)

        return GapiTranscription(
            text: convertedFullText,
            languageCode: transcription.languageCode,
            languageConfidence: transcription.languageConfidence,
            languageShare: transcription.languageShare,
            segments: updatedSegments,
            summaryText: transcription.summaryText.map { convertSentenceToTashkent($0) },
            stereoParties: transcription.stereoParties,
            speakerCount: transcription.speakerCount,
            audioSeconds: transcription.audioSeconds
        )
    }

    static func convertSentenceToTashkent(_ text: String) -> String {
        guard !text.isEmpty else { return text }
        var s = text

        // 1. Multi-word phrase replacements (preserving leading capitalization)
        for (pattern, replacement) in phraseReplacements {
            guard let rx = try? NSRegularExpression(pattern: pattern) else { continue }
            let matches = rx.matches(in: s, range: NSRange(s.startIndex..., in: s)).reversed()
            let ns = NSMutableString(string: s)
            for m in matches {
                let original = ns.substring(with: m.range)
                let rep = matchCase(of: original, to: replacement)
                ns.replaceCharacters(in: m.range, with: rep)
            }
            s = ns as String
        }

        // 2. Word-by-word morphological conversion for Uzbek Latin tokens
        guard let wordRx = try? NSRegularExpression(pattern: "[A-Za-z\u{02BB}\u{2018}']+"),
              !s.isEmpty else {
            return s
        }

        let ns = NSMutableString(string: s)
        let matches = wordRx.matches(in: s, range: NSRange(location: 0, length: ns.length)).reversed()
        for m in matches {
            let word = ns.substring(with: m.range)
            let converted = convertWordToTashkent(word)
            if converted != word {
                ns.replaceCharacters(in: m.range, with: converted)
            }
        }
        return ns as String
    }

    private static func convertWordToTashkent(_ rawWord: String) -> String {
        let lower = rawWord.lowercased()

        if let exact = exactWordReplacements[lower] {
            return matchCase(of: rawWord, to: exact)
        }

        // Morphological suffix rules for Uzbek verbs (Adabiy -> Toshkent shevasi)
        let suffixRules: [(String, String)] = [
            // Present continuous (-ayap... / -yap... -> -vo...)
            ("ayapman", "vomman"),
            ("yapman", "vomman"),
            ("ayapsan", "vosan"),
            ("yapsan", "vosan"),
            ("ayaptilar", "vottila"),
            ("yaptilar", "vottila"),
            ("ayapti", "votti"),
            ("yapti", "votti"),
            ("ayapmiz", "vommiz"),
            ("yapmiz", "vommiz"),
            ("ayapsizlar", "vossila"),
            ("yapsizlar", "vossila"),
            ("ayapsiz", "vossiz"),
            ("yapsiz", "vossiz"),

            // Formal continuous (-moqda... -> -vo...)
            ("moqdaman", "vomman"),
            ("moqdasan", "vosan"),
            ("moqdalar", "vottila"),
            ("moqda", "votti"),
            ("moqdamiz", "vommiz"),
            ("moqdasiz", "vossiz"),

            // Participles (-ayotgan / -yotgan -> -votgan)
            ("ayotganini", "votganini"),
            ("yotganini", "votganini"),
            ("ayotganingiz", "votganiz"),
            ("yotganingiz", "votganiz"),
            ("ayotgan", "votgan"),
            ("yotgan", "votgan"),
        ]

        for (fromSuffix, toSuffix) in suffixRules {
            if lower.hasSuffix(fromSuffix) && lower.count > fromSuffix.count + 1 {
                let stem = String(lower.dropLast(fromSuffix.count))
                let transformed: String
                // In Tashkent dialect, stems ending in "la" or "a" keep the vowel before "-vomman/-votti"
                // (e.g. "ishla" + "yapman" -> "ishlavomman", "o'yla" + "yapti" -> "o'ylavotti")
                if stem == "qil" {
                    transformed = "qi" + toSuffix
                } else if stem == "kel" {
                    transformed = "ke" + toSuffix
                } else if stem == "bo'l" || stem == "bo‘l" || stem == "bo\u{02BB}l" {
                    transformed = String(stem.dropLast()) + toSuffix
                } else if stem == "ayt" {
                    transformed = "et" + toSuffix
                } else {
                    transformed = stem + toSuffix
                }
                return matchCase(of: rawWord, to: transformed)
            }
        }

        return rawWord
    }

    private static func matchCase(of original: String, to replacement: String) -> String {
        guard let firstOrig = original.first, let firstRep = replacement.first else {
            return replacement
        }
        if original.count > 1 && original == original.uppercased() {
            return replacement.uppercased()
        }
        if firstOrig.isUppercase {
            return String(firstRep).uppercased() + replacement.dropFirst()
        }
        return replacement
    }
}
