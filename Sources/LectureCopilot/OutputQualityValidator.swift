import Foundation

struct OutputValidationResult {
    let isValid: Bool
    let reason: String?
}

enum OutputQualityValidator {
    static func prepareForDisplay(_ text: String?, action: CopilotAction, prompt: String) -> String? {
        guard let text else { return nil }

        let cleaned = ResponseSanitizer.sanitize(text, prompt: prompt, action: action)
        guard ResponseSanitizer.isPlausibleAnswer(cleaned, prompt: prompt, action: action) else {
            DebugLog.write("Rejected \(action.displayName) response: not a plausible answer")
            return nil
        }

        let formatted = format(cleaned, for: action)
        let validation = validate(formatted, for: action)
        if validation.isValid {
            return formatted
        }

        DebugLog.write("Rejected \(action.displayName) response: \(validation.reason ?? "unknown reason")")
        return nil
    }

    static func validate(_ text: String, for action: CopilotAction) -> OutputValidationResult {
        let normalized = normalize(text)
        guard normalized.count >= 12 else {
            return .init(isValid: false, reason: "too short")
        }

        switch action {
        case .translate:
            return validateTranslate(normalized)
        case .explain:
            return validateExplain(normalized)
        case .directAnswer:
            return validateDirectAnswer(normalized)
        case .sayInClass:
            return validateSayInClass(normalized)
        case .backToClass:
            return .init(isValid: true, reason: nil)
        }
    }

    private static func validateTranslate(_ text: String) -> OutputValidationResult {
        let forbidden = [
            "核心关键词对照表",
            "关键词对照",
            "关键词表",
            "以下是关键词",
            "重点词汇",
            "词汇表"
        ]

        if forbidden.contains(where: { text.contains($0) }),
           !containsChineseOrAsciiColonLabel("英文", in: text) {
            return .init(isValid: false, reason: "translate returned vocabulary table")
        }

        if isShortTermTranslation(text) {
            return .init(isValid: true, reason: nil)
        }

        let chineseCount = chineseCharacterCount(text)
        if chineseCount < 20 {
            if chineseCount >= 8 && text.contains(".") && text.range(of: #"[A-Za-z]"#, options: .regularExpression) != nil {
                return .init(isValid: true, reason: nil)
            }
            return .init(isValid: false, reason: "translate missing Chinese")
        }

        return .init(isValid: true, reason: nil)
    }

    private static func validateExplain(_ text: String) -> OutputValidationResult {
        if text.contains("英文：") && text.contains("中文：") &&
            !text.contains("这页真正意思") && !text.contains("核心") {
            return .init(isValid: false, reason: "explain returned translation format")
        }

        if !looksLikeExplainAnswer(text) {
            return .init(isValid: false, reason: "explain missing required structure")
        }

        if normalize(text)
            .components(separatedBy: .newlines)
            .contains(where: { ResponseSanitizer.isPromptPlaceholderLine($0) }) {
            return .init(isValid: false, reason: "explain still contains prompt placeholders")
        }

        return .init(isValid: true, reason: nil)
    }

    private static func validateDirectAnswer(_ text: String) -> OutputValidationResult {
        if text.contains("英文：") && text.contains("中文：") &&
            !text.contains("直接答案") && !text.contains("答案") {
            return .init(isValid: false, reason: "direct answer returned translation format")
        }

        if !looksLikeDirectAnswer(text) {
            return .init(isValid: false, reason: "direct answer missing required structure")
        }

        return .init(isValid: true, reason: nil)
    }

    private static func validateSayInClass(_ text: String) -> OutputValidationResult {
        if hasQuestionBlock(text) {
            return .init(isValid: false, reason: "say in class contains question block")
        }

        let words = latinWordCount(in: text)
        if !(6...90).contains(words) {
            return .init(isValid: false, reason: "say in class word count out of range")
        }

        let sentenceCount = splitEnglishSentences(text).count
        if !(1...4).contains(sentenceCount) {
            return .init(isValid: false, reason: "say in class sentence count out of range")
        }

        return .init(isValid: true, reason: nil)
    }

    private static func format(_ text: String, for action: CopilotAction) -> String {
        switch action {
        case .translate:
            return formatTranslate(text)
        case .directAnswer:
            return formatDirectAnswer(text)
        case .sayInClass:
            return formatSayInClass(text)
        case .explain:
            return formatExplain(text)
        case .backToClass:
            return text
        }
    }

    private static func formatExplain(_ text: String) -> String {
        let lines = insertExplainStructureArrows(
            normalize(text)
                .components(separatedBy: .newlines)
                .map { cleanOCRLine($0) }
                .filter { !$0.isEmpty && !isDisplayJunkLine($0) && !ResponseSanitizer.isPromptPlaceholderLine($0) }
        )

        let joined = lines.joined(separator: "\n")
        let compactText = compact(joined)
        if compactText.contains("核心") || compactText.contains("最重要") || compactText.contains("这页真正意思") {
            return joined
        }

        var meaning: [String] = []
        var emphasis: [String] = []
        var concepts: [String] = []
        var section: ExplainSection?

        for line in lines {
            if let nextSection = explainSection(for: line) {
                section = nextSection
                if let payload = payloadAfterColon(in: line),
                   isMeaningfulExplainPayload(payload) {
                    appendExplainPayload(payload, to: nextSection, meaning: &meaning, emphasis: &emphasis, concepts: &concepts)
                }
                continue
            }

            guard let section, isMeaningfulExplainPayload(line) else {
                continue
            }

            appendExplainPayload(line, to: section, meaning: &meaning, emphasis: &emphasis, concepts: &concepts)
        }

        var output: [String] = []

        if !meaning.isEmpty {
            output.append("这页真正意思：")
            output.append(meaning.prefix(2).joined(separator: " "))
        }

        if !emphasis.isEmpty {
            if !output.isEmpty { output.append("") }
            output.append("老师可能想强调：")
            output.append(contentsOf: emphasis.prefix(2).map { normalizedBullet($0) })
        }

        if !concepts.isEmpty {
            if !output.isEmpty { output.append("") }
            output.append("重要概念：")
            output.append(contentsOf: concepts.prefix(4).map { normalizedBullet($0) })
        }

        return output.isEmpty ? lines.joined(separator: "\n") : output.joined(separator: "\n")
    }

    private enum ExplainSection {
        case meaning
        case emphasis
        case concepts
    }

    private static func explainSection(for line: String) -> ExplainSection? {
        let compactLine = compact(line)
        if compactLine.contains("这页真正意思") || compactLine.contains("真正意思") {
            return .meaning
        }
        if compactLine.contains("老师可能想强调") || compactLine.contains("老师想强调") {
            return .emphasis
        }
        if compactLine.contains("重要概念") || compactLine.contains("关键概念") {
            return .concepts
        }
        return nil
    }

    private static func appendExplainPayload(
        _ payload: String,
        to section: ExplainSection,
        meaning: inout [String],
        emphasis: inout [String],
        concepts: inout [String]
    ) {
        switch section {
        case .meaning:
            meaning.append(stripListPrefix(payload))
        case .emphasis:
            emphasis.append(stripListPrefix(payload))
        case .concepts:
            concepts.append(stripListPrefix(payload))
        }
    }

    private static func isMeaningfulExplainPayload(_ text: String) -> Bool {
        let compactText = compact(text)
        guard chineseCharacterCount(text) >= 4 else { return false }
        let placeholders = [
            "用1-2句说明",
            "用12句说明",
            "1-2个要点",
            "12个要点",
            "列出关键词",
            "一句话解释",
            "中文Englishterm"
        ]
        return !placeholders.contains { compactText.contains($0) }
    }

    private static func formatSayInClass(_ text: String) -> String {
        let lines = normalize(text)
            .components(separatedBy: .newlines)
            .map { cleanOCRLine($0) }
            .filter { !$0.isEmpty && !isDisplayJunkLine($0) && !ResponseSanitizer.isQuestionSlideLine($0) }

        var englishLines: [String] = []
        if let index = lines.lastIndex(where: { compact($0).contains("你可以很口语地回答") }) {
            englishLines = Array(lines.dropFirst(index + 1)).filter {
                latinWordCount(in: $0) >= 6 || (containsLatin($0) && !containsChinese($0))
            }
            if let payload = payloadAfterColon(in: lines[index]), latinWordCount(in: payload) >= 6 {
                englishLines.insert(payload, at: 0)
            }
        } else {
            englishLines = lines.filter { latinWordCount(in: $0) >= 6 }
        }

        let english = englishLines.joined(separator: " ")
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let sentences = splitEnglishSentences(english)
        let englishBlock = sentences.isEmpty ? english : Array(sentences.prefix(2)).joined(separator: " ")
        guard !englishBlock.isEmpty else {
            return lines.joined(separator: "\n")
        }

        return "你可以很口语地回答：\n\(englishBlock)"
    }

    private static func formatDirectAnswer(_ text: String) -> String {
        let lines = normalize(text)
            .components(separatedBy: .newlines)
            .map { cleanOCRLine($0) }
            .filter { !$0.isEmpty && !isDisplayJunkLine($0) && !ResponseSanitizer.isPromptPlaceholderLine($0) }

        var answer: String?
        var reason: [String] = []
        var others: [String] = []
        var collectingReason = false
        var collectingOthers = false

        for line in lines {
            let compactLine = compact(line)
            if compactLine.hasPrefix("答案") || compactLine.hasPrefix("直接答案") || compactLine.hasPrefix("直接结论") {
                if compactLine.contains("先给一句话") { continue }
                answer = line
                collectingReason = false
                collectingOthers = false
                continue
            }
            if compactLine.hasPrefix("原因") {
                if compactLine.contains("一句话说明为什么") { continue }
                reason = [line]
                collectingReason = true
                collectingOthers = false
                continue
            }
            if compactLine.hasPrefix("其他选项") {
                others = [line]
                collectingReason = false
                collectingOthers = true
                continue
            }
            if compactLine.range(of: #"^[A-D]错"#, options: .regularExpression) != nil {
                if compactLine.hasSuffix("一句话") { continue }
                others.append(line)
                collectingOthers = true
                collectingReason = false
                continue
            }
            if collectingReason {
                reason.append(line)
            } else if collectingOthers {
                others.append(line)
            }
        }

        var output: [String] = []
        if let answer { output.append(answer) }
        output.append(contentsOf: reason)
        output.append(contentsOf: others)
        return output.isEmpty ? lines.joined(separator: "\n") : output.joined(separator: "\n")
    }

    private static func normalizedDirectAnswerPoint(_ line: String) -> String? {
        let point = stripListPrefix(line)
        return point.isEmpty ? nil : "- \(point)"
    }

    private static func stripListPrefix(_ line: String) -> String {
        line.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: #"^[•\-]\s*"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"^\d+[\.、]\s*"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func normalizedBullet(_ line: String) -> String {
        "- \(stripListPrefix(line))"
    }

    private static func isDisplayJunkLine(_ line: String) -> Bool {
        let compactLine = compact(line)
        if ["口", "凸", "□", "■", "一", "—", "–"].contains(compactLine) { return true }
        if compactLine.count <= 4,
           compactLine.contains("凸") || compactLine.contains("』") || compactLine.contains("⑦") {
            return true
        }
        return false
    }

    private static func payloadAfterColon(in line: String) -> String? {
        guard let colon = line.range(of: "：") ?? line.range(of: ":") else {
            return nil
        }
        return String(line[colon.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func containsChinese(_ text: String) -> Bool {
        chineseCharacterCount(text) > 0
    }

    private static func containsLatin(_ text: String) -> Bool {
        text.range(of: #"[A-Za-z]"#, options: .regularExpression) != nil
    }

    private static func latinWordCount(in text: String) -> Int {
        (try? NSRegularExpression(pattern: #"[A-Za-z]+(?:'[A-Za-z]+)?"#)
            .numberOfMatches(in: text, range: NSRange(text.startIndex..<text.endIndex, in: text))) ?? 0
    }

    private static func splitEnglishSentences(_ text: String) -> [String] {
        let normalized = text
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !normalized.isEmpty else { return [] }

        let pattern = #"[^.!?]+[.!?]"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return [normalized]
        }

        let matches = regex.matches(
            in: normalized,
            range: NSRange(normalized.startIndex..<normalized.endIndex, in: normalized)
        )

        let sentences = matches.compactMap { match -> String? in
            guard let range = Range(match.range, in: normalized) else { return nil }
            let sentence = String(normalized[range]).trimmingCharacters(in: .whitespacesAndNewlines)
            return sentence.isEmpty ? nil : sentence
        }

        return sentences.isEmpty ? [normalized] : sentences
    }

    private static func hasQuestionBlock(_ text: String) -> Bool {
        let compactText = compact(text).lowercased()
        return compactText.contains("whichofthefollowing") ||
            compactText.contains("whichstatement") ||
            compactText.contains("a.tostore") ||
            compactText.contains("b.touniquely") ||
            compactText.contains("c.toconnect") ||
            compactText.contains("d.tosort") ||
            compactText.contains("问答题") ||
            compactText.contains("参考答案") ||
            compactText.contains("whereshouldtheforeignkey")
    }

    private static func formatTranslate(_ text: String) -> String {
        let lines = normalize(text)
            .components(separatedBy: .newlines)
            .map { cleanOCRLine($0) }
            .flatMap { splitJammedTranslateLine($0) }
            .flatMap { splitLeadingChineseSuffix($0) }
            .flatMap { splitRepeatedTermGloss(in: $0) }
            .flatMap { splitEmbeddedEnglishSentence(in: $0) }
            .filter { !$0.isEmpty }

        var merged: [String] = []
        for line in lines {
            guard let last = merged.last else {
                merged.append(line)
                continue
            }

            if shouldMerge(previous: last, current: line) {
                merged[merged.count - 1] = merge(last, line)
            } else {
                merged.append(line)
            }
        }

        let pairs = pairTranslateLines(merged)
        let kept = dropTranslateGlossaryPairs(pairs)
        guard !kept.isEmpty else {
            return renderTranslateLines(merged)
        }
        return renderTranslatePairs(kept)
    }

    private static func pairTranslateLines(_ lines: [String]) -> [(String, String)] {
        var pairs: [(String, String)] = []
        var index = 0
        while index < lines.count {
            let line = lines[index]
            if isMostlyEnglish(line) {
                var english = line
                index += 1
                while index < lines.count,
                      isMostlyEnglish(lines[index]),
                      !endsEnglishSentence(english),
                      !isTranslateGlossaryEnglish(english),
                      !isTranslateGlossaryEnglish(lines[index]) {
                    english = merge(english, lines[index])
                    index += 1
                }
                var chineseParts: [String] = []
                while index < lines.count, !isMostlyEnglish(lines[index]) {
                    chineseParts.append(lines[index])
                    index += 1
                }
                let chinese = joinChineseParts(chineseParts)
                if !chinese.isEmpty {
                    pairs.append((english, chinese))
                }
            } else {
                index += 1
            }
        }
        return pairs
    }

    private static func joinChineseParts(_ parts: [String]) -> String {
        var result = ""
        for part in parts {
            if result.isEmpty {
                result = part
            } else if endsChineseSentence(result) || isOrphanChineseSuffix(part) || part.hasPrefix("（") {
                result += part
            } else {
                result += " " + part
            }
        }
        return result
    }

    private static func dropTranslateGlossaryPairs(_ pairs: [(String, String)]) -> [(String, String)] {
        let hasContent = pairs.contains { isTranslateContentEnglish($0.0) }
        guard hasContent else { return pairs }
        return pairs.filter { !isTranslateGlossaryEnglish($0.0) }
    }

    private static func isTranslateContentEnglish(_ line: String) -> Bool {
        englishWordCount(line) >= 5 || line.contains(".") || line.contains("?") || line.contains("!")
    }

    private static func isTranslateGlossaryEnglish(_ line: String) -> Bool {
        let trimmed = line
            .replacingOccurrences(of: #"^[•\-·]\s*"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let compactUpper = compact(trimmed).uppercased()
        let labels = ["FOREIGNKEY", "PRIMARYKEY", "PARENTTABLE", "CHILDTABLE"]
        if labels.contains(where: { compactUpper.contains($0) }),
           !trimmed.contains("."),
           englishWordCount(trimmed) <= 8 {
            return true
        }
        if trimmed.range(of: #"^[A-Z][A-Z0-9]+\s+[Tt]ables?$"#, options: .regularExpression) != nil {
            return true
        }

        let words = trimmed.split { $0.isWhitespace || $0 == ":" }.filter { !$0.isEmpty }
        guard (1...3).contains(words.count) else { return false }

        let withoutTable = trimmed.replacingOccurrences(of: #"(?i)\btable\b"#, with: "", options: .regularExpression)
        let lowercase = withoutTable.unicodeScalars.filter { $0.value >= 97 && $0.value <= 122 }.count
        guard lowercase == 0 else { return false }

        return words.allSatisfy { word in
            let token = String(word)
            return token.uppercased() == token || token.lowercased() == "table" || token.lowercased() == "key"
        }
    }

    private static func looksLikeChineseLineStartingWithTerm(_ line: String) -> Bool {
        chineseCharacterCount(line) >= 6 &&
            line.range(
                of: #"^[A-Za-z][A-Za-z0-9]*(?:\s+[A-Za-z][A-Za-z0-9]*)?\s+\p{Han}"#,
                options: .regularExpression
            ) != nil
    }

    private static func englishWordCount(_ line: String) -> Int {
        line.split { !$0.isLetter && !$0.isNumber }.filter { token in
            token.unicodeScalars.contains { $0.value < 0x80 && CharacterSet.letters.contains($0) }
        }.count
    }

    private static func renderTranslatePairs(_ pairs: [(String, String)]) -> String {
        pairs.map { "\($0.0)\n\($0.1)" }.joined(separator: "\n\n")
    }

    private static func renderTranslateLines(_ lines: [String]) -> String {
        var output: [String] = []
        for (index, line) in lines.enumerated() {
            output.append(line)
            if index + 1 < lines.count,
               isMostlyChinese(line),
               isMostlyEnglish(lines[index + 1]) {
                output.append("")
            }
        }
        return output.joined(separator: "\n")
    }

    private static func insertExplainStructureArrows(_ lines: [String]) -> [String] {
        var output: [String] = []
        for (index, line) in lines.enumerated() {
            output.append(line)
            let compactLine = compact(line)
            guard compactLine.hasPrefix("PK") else { continue }
            guard index + 1 < lines.count else { continue }
            let next = compact(lines[index + 1])
            if next == "↓" || next.hasPrefix("FK") || next.hasPrefix("关系") || next.hasPrefix("最重要") || next.hasPrefix("核心") {
                continue
            }
            output.append("↓")
        }
        return output
    }

    private static func shouldMerge(previous: String, current: String) -> Bool {
        if hasUnclosedParenthesis(previous), closesParenthesis(current) {
            return true
        }

        if isOrphanChineseSuffix(current), containsLatin(previous) || isMostlyChinese(previous) {
            return true
        }

        if isMostlyEnglish(previous), isMostlyEnglish(current) {
            if isTranslateGlossaryEnglish(previous) || isTranslateGlossaryEnglish(current) {
                return false
            }
            return !endsEnglishSentence(previous)
        }

        if isMostlyChinese(previous), isMostlyChinese(current) || isParentheticalContinuation(current) {
            return !endsChineseSentence(previous)
        }

        return false
    }

    private static func merge(_ previous: String, _ current: String) -> String {
        if previous.hasSuffix("-") {
            return String(previous.dropLast()) + current
        }
        if isOrphanChineseSuffix(current) {
            return previous + current
        }
        return previous + " " + current
    }

    private static func isOrphanChineseSuffix(_ line: String) -> Bool {
        ["表", "字段", "关系", "列"].contains(compact(line))
    }

    private static func endsEnglishSentence(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.hasSuffix(".") ||
            trimmed.hasSuffix("?") ||
            trimmed.hasSuffix("!") ||
            trimmed.hasSuffix(":")
    }

    private static func endsChineseSentence(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.hasSuffix("。") ||
            trimmed.hasSuffix("？") ||
            trimmed.hasSuffix("！") ||
            trimmed.hasSuffix("：") ||
            trimmed.hasSuffix("；")
    }

    private static func isMostlyEnglish(_ line: String) -> Bool {
        if startsWithHan(line) || isTermGlossLine(line) { return false }
        let latin = line.unicodeScalars.filter { CharacterSet.letters.contains($0) && $0.value < 0x80 }.count
        let chinese = chineseCharacterCount(line)
        return latin >= 3 && latin > chinese
    }

    private static func isMostlyChinese(_ line: String) -> Bool {
        if startsWithHan(line) || isTermGlossLine(line) { return true }
        let latin = line.unicodeScalars.filter { CharacterSet.letters.contains($0) && $0.value < 0x80 }.count
        let chinese = chineseCharacterCount(line)
        return chinese >= 2 && chinese >= latin
    }

    private static func isTermGlossLine(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.range(
            of: #"^[A-Za-z][A-Za-z0-9]*\s*（\p{Han}+）[表字段关系列]*$"#,
            options: .regularExpression
        ) != nil
    }

    private static func startsWithHan(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: #"^[•\-·]\s*"#, with: "", options: .regularExpression)
        guard let first = trimmed.unicodeScalars.first(where: {
            CharacterSet.letters.contains($0) || ($0.value >= 0x4E00 && $0.value <= 0x9FFF)
        }) else {
            return false
        }
        return first.value >= 0x4E00 && first.value <= 0x9FFF
    }

    private static func splitJammedTranslateLine(_ line: String) -> [String] {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard containsChinese(trimmed), containsLatin(trimmed), !startsWithHan(trimmed) else {
            return [trimmed]
        }
        if looksLikeChineseLineStartingWithTerm(trimmed) {
            return [trimmed]
        }

        var parts: [String] = []
        var current = ""
        var currentIsChinese = false
        var parenthesisDepth = 0

        func flush() {
            let piece = current.trimmingCharacters(in: .whitespacesAndNewlines)
            if !piece.isEmpty {
                parts.append(piece)
            }
            current = ""
        }

        for character in trimmed {
            if character == "（" || character == "(" {
                parenthesisDepth += 1
                current.append(character)
                continue
            }
            if character == "）" || character == ")" {
                parenthesisDepth = max(0, parenthesisDepth - 1)
                current.append(character)
                if parenthesisDepth == 0, containsChinese(current) {
                    currentIsChinese = true
                }
                continue
            }

            let isHan = character.unicodeScalars.allSatisfy { $0.value >= 0x4E00 && $0.value <= 0x9FFF }
            if current.isEmpty {
                currentIsChinese = isHan
                current.append(character)
                continue
            }

            if parenthesisDepth > 0 {
                current.append(character)
                continue
            }

            if isHan && !currentIsChinese {
                flush()
                currentIsChinese = true
                current.append(character)
            } else if !isHan && currentIsChinese && character.isLetter && character.isASCII {
                flush()
                currentIsChinese = false
                current.append(character)
            } else {
                current.append(character)
            }
        }
        flush()
        return parts.count >= 2 ? parts : [trimmed]
    }

    private static func splitLeadingChineseSuffix(_ line: String) -> [String] {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let regex = try? NSRegularExpression(pattern: #"^(表|字段|关系|列)\s+(.+)$"#),
              let match = regex.firstMatch(
                in: trimmed,
                range: NSRange(trimmed.startIndex..<trimmed.endIndex, in: trimmed)
              ),
              let suffixRange = Range(match.range(at: 1), in: trimmed),
              let restRange = Range(match.range(at: 2), in: trimmed) else {
            return [trimmed]
        }
        return [String(trimmed[suffixRange]), String(trimmed[restRange])]
    }

    private static func splitRepeatedTermGloss(in line: String) -> [String] {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let regex = try? NSRegularExpression(
            pattern: #"^(.*\S)\s+([A-Z][A-Z0-9]+)\s*（([^）]+)）([表字段关系列]*)$"#
        ),
        let match = regex.firstMatch(
            in: trimmed,
            range: NSRange(trimmed.startIndex..<trimmed.endIndex, in: trimmed)
        ),
        let prefixRange = Range(match.range(at: 1), in: trimmed),
        let termRange = Range(match.range(at: 2), in: trimmed),
        let glossRange = Range(match.range(at: 3), in: trimmed) else {
            return [trimmed]
        }

        let prefix = String(trimmed[prefixRange]).trimmingCharacters(in: .whitespacesAndNewlines)
        let term = String(trimmed[termRange])
        let gloss = String(trimmed[glossRange])
        let suffixRange = Range(match.range(at: 4), in: trimmed)
        let suffix = suffixRange.map { String(trimmed[$0]) } ?? ""
        guard prefix.localizedCaseInsensitiveContains(term), prefix != term else {
            return [trimmed]
        }
        return [prefix, "\(term)（\(gloss)）\(suffix)"]
    }

    private static func cleanOCRLine(_ line: String) -> String {
        line
            .replacingOccurrences(of: "Ilook", with: "I look")
            .replacingOccurrences(of: "Iook", with: "I look")
            .replacingOccurrences(of: "| am", with: "I am")
            .replacingOccurrences(of: "vou", with: "you")
            .replacingOccurrences(of: "vour", with: "your")
            .replacingOccurrences(of: "vanuary", with: "January")
            .replacingOccurrences(of: "21th", with: "21st")
            .replacingOccurrences(of: " ，", with: "，")
            .replacingOccurrences(of: " 。", with: "。")
            .replacingOccurrences(of: " （", with: "（")
            .replacingOccurrences(of: "） ", with: "）")
            .replacingOccurrences(of: "）full-time", with: "） full-time")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func splitEmbeddedEnglishSentence(in line: String) -> [String] {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        let patterns = [
            #"([。！？；])\s+([A-Z][A-Za-z0-9'’(),&%\-\s]{16,})"#,
            #"([。！？；])([A-Z][A-Za-z0-9'’(),&%\-\s]{16,})"#
        ]

        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern),
                  let match = regex.firstMatch(
                    in: trimmed,
                    range: NSRange(trimmed.startIndex..<trimmed.endIndex, in: trimmed)
                  ),
                  let firstRange = Range(match.range(at: 1), in: trimmed),
                  let secondRange = Range(match.range(at: 2), in: trimmed) else {
                continue
            }

            let firstEnd = firstRange.upperBound
            let before = String(trimmed[..<firstEnd]).trimmingCharacters(in: .whitespacesAndNewlines)
            let after = String(trimmed[secondRange.lowerBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
            if before.count >= 4, after.count >= 12 {
                return [before, after]
            }
        }

        return [trimmed]
    }

    private static func hasUnclosedParenthesis(_ line: String) -> Bool {
        let open = line.filter { $0 == "（" || $0 == "(" }.count
        let close = line.filter { $0 == "）" || $0 == ")" }.count
        return open > close
    }

    private static func closesParenthesis(_ line: String) -> Bool {
        line.contains("）") || line.contains(")")
    }

    private static func isParentheticalContinuation(_ line: String) -> Bool {
        line.range(of: #"^[A-Z0-9 &/+\-]+[）)]"#, options: .regularExpression) != nil
    }

    private static func isShortTermTranslation(_ text: String) -> Bool {
        let lines = normalize(text)
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard (1...5).contains(lines.count),
              chineseCharacterCount(text) >= 2,
              text.range(of: #"[A-Za-z]"#, options: .regularExpression) != nil else {
            return false
        }

        return lines.contains { line in
            let latin = line.unicodeScalars.filter { CharacterSet.letters.contains($0) && $0.value < 0x80 }.count
            let words = line.split { !$0.isLetter && !$0.isNumber }
            return latin >= 2 && latin <= 40 && words.count <= 5
        }
    }

    private static func containsChineseOrAsciiColonLabel(_ label: String, in text: String) -> Bool {
        text.contains("\(label)：") || text.contains("\(label):")
    }

    private static func looksLikeExplainAnswer(_ text: String) -> Bool {
        let compactText = compact(text)
        return [
            "这页真正意思",
            "老师可能想强调",
            "重要概念",
            "真正意思",
            "核心",
            "最重要的一句话",
            "foreignkey",
            "primarykey"
        ].contains { compactText.lowercased().contains($0.lowercased()) }
    }

    private static func looksLikeDirectAnswer(_ text: String) -> Bool {
        directAnswerPayload(in: text) != nil
    }

    private static func directAnswerPayload(in text: String) -> String? {
        let lines = normalize(text)
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        for line in lines.reversed() {
            let compactLine = compact(line)
            guard compactLine.hasPrefix("直接答案") ||
                    compactLine.hasPrefix("直接结论") ||
                    compactLine.hasPrefix("答案") else {
                continue
            }

            if let colonRange = line.range(of: "：") ?? line.range(of: ":") {
                let payload = String(line[colonRange.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
                if isMeaningfulDirectAnswerPayload(payload) {
                    return payload
                }
            }
        }

        guard let markerIndex = lines.lastIndex(where: { line in
            let compactLine = compact(line)
            return compactLine.hasPrefix("直接答案") ||
                compactLine.hasPrefix("直接结论") ||
                compactLine.hasPrefix("答案")
        }) else {
            return nil
        }

        for line in lines.dropFirst(markerIndex + 1) {
            let compactLine = compact(line)
            if compactLine.hasPrefix("要点") || compactLine.hasPrefix("Question") || compactLine == "解答" {
                return nil
            }
            if isMeaningfulDirectAnswerPayload(line) {
                return line
            }
        }

        return nil
    }

    private static func isMeaningfulDirectAnswerPayload(_ text: String) -> Bool {
        let compactText = compact(text)
        if compactText.range(of: #"^[A-D]$"#, options: .regularExpression) != nil { return true }
        guard compactText.count >= 2 else { return false }
        if compactText.hasPrefix("答案"), compactText.range(of: #"[A-D]"#, options: .regularExpression) != nil {
            return true
        }
        let placeholders = ["用1句话给出结论", "如有必要", "保留关键英文术语", "直接", "解答", "回答"]
        if placeholders.contains(where: { compactText.contains($0) }) { return false }
        return chineseCharacterCount(text) > 0 || text.range(of: #"\b[A-D][\.\)]"#, options: .regularExpression) != nil
    }

    private static func chineseCharacterCount(_ text: String) -> Int {
        text.unicodeScalars.filter { $0.value >= 0x4E00 && $0.value <= 0x9FFF }.count
    }

    private static func compact(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\n", with: "")
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "\t", with: "")
            .replacingOccurrences(of: "：", with: "")
            .replacingOccurrences(of: ":", with: "")
    }

    private static func normalize(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
