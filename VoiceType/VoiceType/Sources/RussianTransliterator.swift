import AppKit
import Foundation

/// Converts Russian speech transcribed in Uzbek Latin phonetics by gapi.uz into standard Russian Cyrillic.
///
/// According to https://console.gapi.uz/docs/ru/result.html:
/// - gapi's acoustic ASR model is trained on Uzbek Latin script (`oʻ`, `gʻ`, `sh`, `ch`, `ya`, `yu`, `ye`)
///   and never outputs Cyrillic characters directly.
/// - gapi's `language_detection` model identifies the spoken language per segment and per recording (`"ru"`, `"uz"`, etc.).
/// - Because Uzbek Latin lacks `ы` and `ь`, this converter combines phonetic digraph mapping with
///   macOS's native Russian spellchecker (`NSSpellChecker`) to restore `ы`, `ь`, and Russian word endings offline.
enum RussianTransliterator {

    private static let exactWordOverrides: [String: String] = [
        "ochen": "очень",
        "toje": "тоже",
        "takje": "также",
        "chtobi": "чтобы",
        "potomu": "потому",
        "poetomu": "поэтому",
        "zdes": "здесь",
        "seychas": "сейчас",
        "tolko": "только",
        "skolko": "сколько",
        "neskolko": "несколько",
        "voobsche": "вообще",
        "voobshe": "вообще",
        "konechno": "конечно",
        "chto": "что",
        "chtoto": "что-то",
        "ktoto": "кто-то",
        "gdeto": "где-то",
        "kakto": "как-то",
        "kogdato": "когда-то",
        "pochemu": "почему",
        "zachem": "зачем",
        "kogda": "когда",
        "togda": "тогда",
        "vsegda": "всегда",
        "nikogda": "никогда",
        "ego": "его",
        "yego": "его",
        "eyo": "её",
        "yeyo": "её",
        "ix": "их",
        "ih": "их",
        "im": "им",
        "imi": "ими",
        "mi": "мы",
        "vi": "вы",
        "ti": "ты",
        "bil": "был",
        "bila": "была",
        "bilo": "было",
        "bili": "были",
        "budet": "будет",
        "budut": "будут",
        "bit": "быть",
        "est": "есть",
        "yest": "есть",
        "net": "нет",
        "da": "да",
        "ili": "или",
        "esli": "если",
        "yesli": "если",
        "dlya": "для",
        "pri": "при",
        "pro": "про",
        "bez": "без",
        "cherez": "через",
        "posle": "после",
        "pered": "перед",
        "mejdu": "между",
        "okolo": "около",
        "vokrug": "вокруг",
        "teper": "теперь",
        "opyat": "опять",
        "vsyo": "всё",
        "vse": "все",
        "esho": "ещё",
        "yesho": "ещё",
        "eshe": "ещё",
        "yeshe": "ещё",
        "uje": "уже",
        "ewyo": "ещё",
        "idea": "идея",
        "ideya": "идея",
        "googla": "гугла",
        "google": "гугл",
    ]

    /// Restores Cyrillic for a `GapiTranscription` based on `language_detection` results.
    static func applyIfNeeded(_ transcription: GapiTranscription) -> GapiTranscription {
        let trimmed = transcription.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return transcription }

        let overallIsRussian = transcription.languageCode == "ru"
            || (transcription.languageShare?["ru"] ?? 0) >= 0.5

        let hasPerSegmentLanguages = transcription.segments.contains { $0.languageCode != nil }

        if hasPerSegmentLanguages && transcription.segments.count > 1 {
            // Mixed or multi-segment recording: transliterate Russian segments, keep Uzbek segments in Latin
            let updatedSegments = transcription.segments.map { seg -> GapiTranscription.Segment in
                let isRuSeg = (seg.languageCode == "ru") || (seg.languageCode == nil && overallIsRussian)
                guard isRuSeg else { return seg }
                return GapiTranscription.Segment(
                    index: seg.index,
                    start: seg.start,
                    end: seg.end,
                    speaker: seg.speaker,
                    text: convertSentence(seg.text),
                    languageCode: seg.languageCode,
                    languageConfidence: seg.languageConfidence
                )
            }
            let hasAnyRussianSegment = transcription.segments.contains { $0.languageCode == "ru" } || overallIsRussian
            guard hasAnyRussianSegment else { return transcription }

            let joinedText: String
            let allSegmentsRussian = updatedSegments.allSatisfy { ($0.languageCode ?? (overallIsRussian ? "ru" : "uz")) == "ru" }
            if allSegmentsRussian {
                joinedText = convertSentence(transcription.text)
            } else {
                joinedText = updatedSegments.map(\.text).joined(separator: " ")
            }

            return GapiTranscription(
                text: joinedText,
                languageCode: transcription.languageCode,
                languageConfidence: transcription.languageConfidence,
                languageShare: transcription.languageShare,
                segments: updatedSegments,
                summaryText: transcription.summaryText,
                stereoParties: transcription.stereoParties,
                speakerCount: transcription.speakerCount,
                audioSeconds: transcription.audioSeconds
            )
        }

        // Single segment or no segment language breakdown
        if overallIsRussian || (transcription.languageCode == nil && looksLikeRussianInLatin(trimmed)) {
            let converted = convertSentence(transcription.text)
            let updatedSegments = transcription.segments.map { seg in
                GapiTranscription.Segment(
                    index: seg.index,
                    start: seg.start,
                    end: seg.end,
                    speaker: seg.speaker,
                    text: convertSentence(seg.text),
                    languageCode: seg.languageCode ?? "ru",
                    languageConfidence: seg.languageConfidence
                )
            }
            return GapiTranscription(
                text: converted,
                languageCode: transcription.languageCode ?? "ru",
                languageConfidence: transcription.languageConfidence,
                languageShare: transcription.languageShare,
                segments: updatedSegments,
                summaryText: transcription.summaryText,
                stereoParties: transcription.stereoParties,
                speakerCount: transcription.speakerCount,
                audioSeconds: transcription.audioSeconds
            )
        }

        return transcription
    }

    /// Heuristic for short recordings (< 2s) where gapi omits the top-level `language` block.
    private static func looksLikeRussianInLatin(_ text: String) -> Bool {
        // Uzbek-specific characters (`oʻ`, `gʻ`, `q`) strongly indicate Uzbek
        let lower = text.lowercased()
        if lower.contains("oʻ") || lower.contains("gʻ") || lower.contains("o‘") || lower.contains("g‘")
            || lower.contains("o'") || lower.contains("g'") || lower.contains("q") {
            return false
        }
        let words = lower
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count >= 2 }
        guard !words.isEmpty else { return false }

        var validCount = 0
        for w in words {
            let ru = transliterateWord(w)
            if isValidRussian(ru) {
                validCount += 1
            }
        }
        return Double(validCount) / Double(words.count) >= 0.75
    }

    static func convertSentence(_ text: String) -> String {
        let ns = text as NSString
        guard let regex = try? NSRegularExpression(pattern: "[A-Za-z\u{02BB}\u{2018}'-]+") else {
            return text
        }

        let matches = regex.matches(in: text, range: NSRange(location: 0, length: ns.length))
        guard !matches.isEmpty else { return text }

        // First pass: transliterate each word token
        var convertedWords: [String] = []
        var rawWords: [String] = []
        for match in matches {
            let word = ns.substring(with: match.range)
            rawWords.append(word)
            convertedWords.append(transliterateWord(word))
        }

        // Second pass: contextual verb infinitive restoration (e.g. "чтобы это оценит" -> "чтобы это оценить",
        // "требуется сделат" -> "требуется сделать")
        let infinitiveTriggers: Set<String> = [
            "чтобы", "надо", "нужно", "можно", "нельзя", "хочу", "хотим", "хотел", "хотела",
            "буду", "будем", "будет", "будут", "могу", "может", "могут", "должен", "должна",
            "должны", "требуется", "стоит", "пора", "прошу", "попробуй", "попробую", "давай", "давайте"
        ]
        var seenTriggerInClause = false
        for i in 0..<convertedWords.count {
            let w = convertedWords[i]
            if infinitiveTriggers.contains(w) {
                seenTriggerInClause = true
                continue
            }
            if seenTriggerInClause {
                if (w.hasSuffix("ит") || w.hasSuffix("ат") || w.hasSuffix("ят") || w.hasSuffix("ет") || w.hasSuffix("ут"))
                    && isValidRussian(w + "ь") {
                    convertedWords[i] = w + "ь"
                    seenTriggerInClause = false
                }
            }
        }

        // Reconstruct string with original punctuation and capitalization
        var result = ""
        var lastIdx = 0
        for (idx, match) in matches.enumerated() {
            let betweenRange = NSRange(location: lastIdx, length: match.range.location - lastIdx)
            let between = ns.substring(with: betweenRange)
            result += between

            let original = rawWords[idx]
            var ru = convertedWords[idx]
            if let first = original.first, first.isUppercase, let ruFirst = ru.first {
                if original.count > 1 && original == original.uppercased() {
                    ru = ru.uppercased()
                } else {
                    ru = String(ruFirst).uppercased() + ru.dropFirst()
                }
            }
            result += ru
            lastIdx = match.range.location + match.range.length
        }
        if lastIdx < ns.length {
            result += ns.substring(from: lastIdx)
        }

        result = result.replacingOccurrences(of: "то ест ", with: "то есть ")
        result = result.replacingOccurrences(of: "То ест ", with: "То есть ")
        result = applyRussianPunctuationAndCleanup(result)
        return result
    }

    /// Applies Typeless-style smart punctuation, filler/stutter removal, and introductory word commas for Russian text.
    static func applyRussianPunctuationAndCleanup(_ input: String) -> String {
        var s = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return input }

        // 1. Remove pure vocal hesitation sounds ("э-э", "ээ", "эм", "м-м", "мм", "хм")
        if let fillerRegex = try? NSRegularExpression(
            pattern: "(?i)(?:^|\\s+)(?:э-э+|ээ+|эм+|м-м+|мм+|хм+|а-а+)(?=[\\s,.!?]|$)"
        ) {
            s = fillerRegex.stringByReplacingMatches(in: s, range: NSRange(s.startIndex..., in: s), withTemplate: "")
        }

        // 2. Collapse immediate word stutters / duplicates ("я я думаю" -> "я думаю", "мы мы" -> "мы")
        if let stutterRegex = try? NSRegularExpression(
            pattern: "(?i)\\b([а-яё]{1,15})\\s+\\1\\b"
        ) {
            s = stutterRegex.stringByReplacingMatches(in: s, range: NSRange(s.startIndex..., in: s), withTemplate: "$1")
        }

        // 3. Hyphenate common Russian particles that ASR splits ("по русски" -> "по-русски", "во первых" -> "во-первых")
        let hyphenFixes: [(String, String)] = [
            ("(?i)\\bво первых\\b", "во-первых"),
            ("(?i)\\bво вторых\\b", "во-вторых"),
            ("(?i)\\bв третьих\\b", "в-третьих"),
            ("(?i)\\bпо русски\\b", "по-русски"),
            ("(?i)\\bпо узбекски\\b", "по-узбекски"),
            ("(?i)\\bпо английски\\b", "по-английски"),
            ("(?i)\\bпо моему\\b", "по-моему"),
            ("(?i)\\bпо твоему\\b", "по-твоему"),
            ("(?i)\\bпо своему\\b", "по-своему"),
            ("(?i)\\bпо новому\\b", "по-новому"),
            ("(?i)\\bпо старому\\b", "по-старому"),
            ("(?i)\\bкак нибудь\\b", "как-нибудь"),
            ("(?i)\\bчто нибудь\\b", "что-нибудь"),
            ("(?i)\\bкто нибудь\\b", "кто-нибудь"),
            ("(?i)\\bгде нибудь\\b", "где-нибудь"),
            ("(?i)\\bкогда нибудь\\b", "когда-нибудь"),
            ("(?i)\\bпочему то\\b", "почему-то"),
            ("(?i)\\bзачем то\\b", "зачем-то"),
            ("(?i)\\bкакой то\\b", "какой-то"),
            ("(?i)\\bкакая то\\b", "какая-то"),
            ("(?i)\\bкакое то\\b", "какое-то"),
            ("(?i)\\bкакие то\\b", "какие-то"),
            ("(?i)\\bвсё таки\\b", "всё-таки"),
            ("(?i)\\bвсе таки\\b", "всё-таки"),
            ("(?i)\\bиз за\\b", "из-за"),
            ("(?i)\\bиз под\\b", "из-под"),
        ]
        for (pattern, replacement) in hyphenFixes {
            if let rx = try? NSRegularExpression(pattern: pattern) {
                s = rx.stringByReplacingMatches(in: s, range: NSRange(s.startIndex..., in: s), withTemplate: replacement)
            }
        }

        // 4. Multi-word subordinate conjunctions: place comma before the entire phrase
        // (unless preceded by "не", "и", "или", "даже", "только", "лишь", or existing punctuation)
        let multiWordConjunctions = [
            "потому что", "так как", "для того чтобы", "вместо того чтобы", "с тем чтобы",
            "несмотря на то что", "после того как", "перед тем как", "в то время как",
            "по мере того как", "из-за того что", "благодаря тому что", "при том что",
            "так что", "то есть", "а именно", "а также", "нежели чем", "прежде чем"
        ]
        let multiAlternation = multiWordConjunctions.joined(separator: "|")
        if let multiRx = try? NSRegularExpression(
            pattern: "(?i)(?<![,.;:!?—\\-])\\b(?<!\\bне\\s)(?<!\\bи\\s)(?<!\\bили\\s)(?<!\\bдаже\\s)(?<!\\bтолько\\s)(?<!\\bлишь\\s)([а-яё]+)\\s+(\(multiAlternation))\\b"
        ) {
            s = multiRx.stringByReplacingMatches(in: s, range: NSRange(s.startIndex..., in: s), withTemplate: "$1, $2")
        }

        // Protect internal words of multi-word conjunctions from single-word comma insertion
        let protectedTokens: [(String, String)] = [
            ("потому что", "потому\u{00A0}что"),
            ("Потому что", "Потому\u{00A0}что"),
            ("для того чтобы", "для\u{00A0}того\u{00A0}чтобы"),
            ("вместо того чтобы", "вместо\u{00A0}того\u{00A0}чтобы"),
            ("с тем чтобы", "с\u{00A0}тем\u{00A0}чтобы"),
            ("несмотря на то что", "несмотря\u{00A0}на\u{00A0}то\u{00A0}что"),
            ("после того как", "после\u{00A0}того\u{00A0}как"),
            ("перед тем как", "перед\u{00A0}тем\u{00A0}как"),
            ("в то время как", "в\u{00A0}то\u{00A0}время\u{00A0}как"),
            ("по мере того как", "по\u{00A0}мере\u{00A0}того\u{00A0}как"),
            ("из-за того что", "из-за\u{00A0}того\u{00A0}что"),
            ("благодаря тому что", "благодаря\u{00A0}тому\u{00A0}что"),
            ("при том что", "при\u{00A0}том\u{00A0}что"),
            ("так что", "так\u{00A0}что"),
            ("Так что", "Так\u{00A0}что"),
            ("так как", "так\u{00A0}как"),
            ("Так как", "Так\u{00A0}как"),
            ("прежде чем", "прежде\u{00A0}чем"),
            ("то есть", "то\u{00A0}есть"),
            ("То есть", "То\u{00A0}есть"),
        ]
        for (plain, prot) in protectedTokens {
            s = s.replacingOccurrences(of: plain, with: prot)
        }

        // 5. Single-word subordinate and adversative conjunctions
        let singleConjunctions = [
            "что", "чтобы", "если", "когда", "пока", "хотя", "будто", "словно", "поскольку", "ибо",
            "который", "которая", "которое", "которые", "которого", "которой", "которому",
            "которую", "которым", "которыми", "которых",
            "где", "куда", "откуда", "зачем", "почему", "насколько",
            "а", "но", "однако", "зато", "причём", "притом"
        ]
        let singleAlternation = singleConjunctions.joined(separator: "|")
        if let singleRx = try? NSRegularExpression(
            pattern: "(?i)\\b([а-яё]{2,})\\s+(\(singleAlternation))\\b"
        ) {
            let nonCommaPredecessors: Set<String> = [
                "не", "ни", "и", "или", "либо", "даже", "только", "лишь", "особенно",
                "именно", "просто", "почти", "вроде", "типа", "сразу", "вдруг", "ещё", "уже"
            ]
            let matches = singleRx.matches(in: s, range: NSRange(s.startIndex..., in: s)).reversed()
            let ns = NSMutableString(string: s)
            for m in matches {
                let prevWord = ns.substring(with: m.range(at: 1)).lowercased()
                let conjWord = ns.substring(with: m.range(at: 2))
                guard !nonCommaPredecessors.contains(prevWord) else { continue }
                ns.replaceCharacters(in: m.range, with: "\(ns.substring(with: m.range(at: 1))), \(conjWord)")
            }
            s = ns as String
        }

        // Restore protected spaces
        s = s.replacingOccurrences(of: "\u{00A0}", with: " ")

        // 6. Introductory words / phrases (вводные слова)
        let introPhrases = [
            "конечно", "безусловно", "разумеется", "наверное", "вероятно", "кажется",
            "пожалуй", "видимо", "очевидно", "кстати", "впрочем", "следовательно",
            "во-первых", "во-вторых", "в-третьих", "например", "к счастью", "к сожалению",
            "честно говоря", "короче говоря", "мягко говоря", "грубо говоря", "собственно говоря",
            "по-моему", "по-твоему", "более того", "кроме того", "между прочим"
        ]
        let introAlt = introPhrases.joined(separator: "|")
        // At sentence start: "Кстати мы..." -> "Кстати, мы..."
        if let startIntroRx = try? NSRegularExpression(
            pattern: "(?i)(^|[.!?]\\s+)(\(introAlt))\\s+(?=[а-яё])"
        ) {
            s = startIntroRx.stringByReplacingMatches(in: s, range: NSRange(s.startIndex..., in: s), withTemplate: "$1$2, ")
        }
        // Mid-sentence: "... мы конечно сделаем ..." -> "... мы, конечно, сделаем ..."
        if let midIntroRx = try? NSRegularExpression(
            pattern: "(?i)\\b([а-яё]{2,})\\s+(\(introAlt))\\s+(?=[а-яё])"
        ) {
            s = midIntroRx.stringByReplacingMatches(in: s, range: NSRange(s.startIndex..., in: s), withTemplate: "$1, $2, ")
        }

        // 7. Interrogative sentence ending restoration ("?" when starting with question words or containing " ли ")
        if let questionRx = try? NSRegularExpression(
            pattern: "(?i)(^|[.!?]\\s+)((?:подскажи(?:те)?|скажи(?:те)?),?\\s+)?(как|когда|где|куда|откуда|почему|зачем|сколько|какой|какая|какое|какие|кто|что|чей|чья|чьё|чьи)\\s+([^.!?]{2,})\\."
        ) {
            s = questionRx.stringByReplacingMatches(in: s, range: NSRange(s.startIndex..., in: s), withTemplate: "$1$2$3 $4?")
        }
        if let liQuestionRx = try? NSRegularExpression(
            pattern: "(?i)(^|[.!?]\\s+)([^.!?]+\\s+ли\\s+[^.!?]+)\\."
        ) {
            s = liQuestionRx.stringByReplacingMatches(in: s, range: NSRange(s.startIndex..., in: s), withTemplate: "$1$2?")
        }

        // 8. Clean up duplicate commas or spaces around punctuation
        if let cleanPunctRx = try? NSRegularExpression(pattern: "\\s+([,.:;!?])") {
            s = cleanPunctRx.stringByReplacingMatches(in: s, range: NSRange(s.startIndex..., in: s), withTemplate: "$1")
        }
        while s.contains(",,") {
            s = s.replacingOccurrences(of: ",,", with: ",")
        }
        while s.contains("  ") {
            s = s.replacingOccurrences(of: "  ", with: " ")
        }

        // Ensure first character is capitalized and sentence ends with punctuation if >= 3 words
        if let first = s.first, first.isLowercase {
            s = String(first).uppercased() + s.dropFirst()
        }
        if let last = s.last, !".!?:;".contains(last), s.split(whereSeparator: \.isWhitespace).count >= 2 {
            s.append(".")
        }

        return s
    }

    private static func transliterateWord(_ rawWord: String) -> String {
        let lower = rawWord.lowercased()
        if let exact = exactWordOverrides[lower] {
            return exact
        }

        var s = lower
        let replacements: [(String, String)] = [
            ("shch", "щ"),
            ("yo\u{02BB}", "ё"), ("yo\u{2018}", "ё"), ("yo'", "ё"),
            ("o\u{02BB}", "о"), ("o\u{2018}", "о"), ("o'", "о"),
            ("g\u{02BB}", "г"), ("g\u{2018}", "г"), ("g'", "г"),
            ("yetsya", "ется"),
            ("utsya", "ются"),
            ("yutsya", "ются"),
            ("yutya", "ются"),
            ("tsya", "тся"),
            ("jayetsya", "жается"),
            ("jhaetsya", "жается"),
            ("jaetsya", "жается"),
            ("jh", "ж"),
            ("aye", "ае"), ("oye", "ое"), ("uye", "уе"), ("iye", "ие"), ("eye", "ее"),
            ("sh", "ш"),
            ("ch", "ч"),
            ("ya", "я"),
            ("yu", "ю"),
            ("ye", "е"),
            ("yo", "ё"),
            ("zh", "ж"),
            ("ts", "ц"),
            ("dj", "дж"),
            ("sj", "сж"),
            ("sc", "сц"),
        ]
        for (from, to) in replacements {
            s = s.replacingOccurrences(of: from, with: to)
        }

        var out = ""
        let chars = Array(s)
        for i in 0..<chars.count {
            let c = chars[i]
            switch c {
            case "a": out.append("а")
            case "b": out.append("б")
            case "v": out.append("в")
            case "g": out.append("г")
            case "d": out.append("д")
            case "e":
                if i == 0 { out.append("э") } else { out.append("е") }
            case "j": out.append("ж")
            case "z": out.append("з")
            case "i": out.append("и")
            case "y":
                let prevIsVowel = i > 0 && "aeiouаеэиоуыюя".contains(chars[i - 1])
                if i == chars.count - 1 && !prevIsVowel {
                    out.append("и")
                } else {
                    out.append("й")
                }
            case "k", "q": out.append("к")
            case "l": out.append("л")
            case "m": out.append("м")
            case "n": out.append("н")
            case "o": out.append("о")
            case "p": out.append("п")
            case "r": out.append("р")
            case "s": out.append("с")
            case "t": out.append("т")
            case "u": out.append("у")
            case "f": out.append("ф")
            case "x", "h": out.append("х")
            case "c": out.append("к")
            case "w": out.append("в")
            default: out.append(c)
            }
        }

        if isValidRussian(out) {
            return out
        }

        // Generate targeted candidates for letters missing in Uzbek Latin (`ь` and `ы`)
        var candidates: [String] = []
        candidates.append(out + "ь")
        if out.hasSuffix("и") {
            candidates.append(String(out.dropLast()) + "ы")
        }
        if out.hasSuffix("еа") {
            candidates.append(String(out.dropLast(2)) + "ея")
        }

        let outChars = Array(out)
        for i in 0..<outChars.count where outChars[i] == "и" {
            var mod = outChars
            mod[i] = "ы"
            let cand = String(mod)
            candidates.append(cand)
            candidates.append(cand + "ь")
        }
        for i in 0..<(outChars.count - 1) {
            if "лнртсздбвпм".contains(outChars[i]) {
                var mod = outChars
                mod.insert("ь", at: i + 1)
                let cand = String(mod)
                candidates.append(cand)
            }
        }

        for cand in candidates {
            if isValidRussian(cand) {
                return cand
            }
        }

        return out
    }

    private static func isValidRussian(_ word: String) -> Bool {
        guard !word.isEmpty else { return false }
        let checker = NSSpellChecker.shared
        let range = checker.checkSpelling(
            of: word,
            startingAt: 0,
            language: "ru",
            wrap: false,
            inSpellDocumentWithTag: 0,
            wordCount: nil
        )
        return range.location == NSNotFound
    }
}
