import Foundation

enum ResponseSanitizer {
    static func sanitize(_ text: String, prompt: String, action: CopilotAction? = nil) -> String {
        var lines = normalizedLines(in: text)

        lines = stripLeadingChrome(from: lines)
        lines = stripPromptResidue(from: lines, prompt: prompt, action: action)
        lines = lines.filter { !isPromptPlaceholderLine($0) && !isQuestionSlideLine($0) }
        if action == nil || action == .translate {
            lines = dropLeadingUntilEnglishContent(from: lines)
        }
        lines = stripTrailingSuggestions(from: lines)
        lines = lines.filter { !isExactUILine($0) && !isHomePageLine($0) && !isPromptChromeLine($0) && !isIconJunkLine($0) }
        if let action {
            lines = focusOnAnswerLines(lines, for: action)
        }
        if action == nil || action == .translate {
            lines = dropLeadingUntilEnglishContent(from: lines)
        }

        var collapsed: [String] = []
        for line in lines {
            if line.isEmpty {
                if collapsed.last?.isEmpty == false {
                    collapsed.append("")
                }
                continue
            }
            collapsed.append(normalizeAnswerLine(line))
        }

        while collapsed.first?.isEmpty == true {
            collapsed.removeFirst()
        }
        while collapsed.last?.isEmpty == true {
            collapsed.removeLast()
        }

        return collapsed.joined(separator: "\n")
    }

    static func isPlausibleAnswer(_ text: String, prompt: String, action: CopilotAction) -> Bool {
        let cleaned = sanitize(text, prompt: prompt, action: action)
        if isHomePage(cleaned) { return false }
        if isPromptResidue(cleaned, prompt: prompt) { return false }
        if isPromptInstruction(cleaned) { return false }

        switch action {
        case .translate:
            return isShortTermTranslation(cleaned)
                || (cleaned.count >= 24 && containsLatin(cleaned) && chineseCharacterCount(cleaned) >= 20)
                || (cleaned.count >= 24 && containsLatin(cleaned) && chineseCharacterCount(cleaned) >= 8 && looksLikeInterlinearTranslation(cleaned))
        case .explain:
            guard cleaned.count >= 24 else { return false }
            return chineseCharacterCount(cleaned) >= 20 && looksLikeExplainAnswer(cleaned)
        case .directAnswer:
            guard cleaned.count >= 18 else { return false }
            return chineseCharacterCount(cleaned) >= 8 && looksLikeDirectAnswer(cleaned)
        case .sayInClass:
            guard cleaned.count >= 32 else { return false }
            return looksLikeSayInClassAnswer(cleaned)
        case .backToClass:
            return true
        }
    }

    static func isStreamingCandidate(_ text: String, prompt: String, action: CopilotAction) -> Bool {
        let cleaned = sanitize(text, prompt: prompt, action: action)
        guard cleaned.count >= 18 else { return false }
        if isHomePage(cleaned) || isPromptResidue(cleaned, prompt: prompt) || isPromptInstruction(cleaned) {
            return false
        }

        switch action {
        case .translate:
            return isShortTermTranslation(cleaned) || (chineseCharacterCount(cleaned) >= 8 && containsLatin(cleaned))
        case .explain:
            return chineseCharacterCount(cleaned) >= 8 && looksLikeExplainAnswer(cleaned)
        case .directAnswer:
            return chineseCharacterCount(cleaned) >= 8 && looksLikeDirectAnswer(cleaned)
        case .sayInClass:
            return looksLikeSayInClassAnswer(cleaned)
        case .backToClass:
            return true
        }
    }

    static func score(_ text: String, prompt: String, action: CopilotAction) -> Int {
        let cleaned = sanitize(text, prompt: prompt, action: action)
        guard isPlausibleAnswer(cleaned, prompt: prompt, action: action) else { return 0 }

        var value = min(cleaned.count, 1600)
        if isHomePage(cleaned) { return 0 }

        switch action {
        case .translate:
            if looksLikeTranslateGlossary(cleaned) {
                value -= 90
            }
            if looksLikeInterlinearTranslation(cleaned) {
                value += 120
            } else if containsChinese(cleaned) && containsLatin(cleaned) {
                value += 10
            } else {
                value -= 40
            }
        case .explain:
            if cleaned.contains("核心") { value += 40 }
            if cleaned.contains("结构") { value += 25 }
            if cleaned.contains("关系") { value += 25 }
            if cleaned.contains("最重要的一句话") { value += 40 }
            if cleaned.contains("PK") && cleaned.contains("FK") { value += 30 }
            if compact(cleaned).contains("Question") { value -= 120 }
        case .directAnswer:
            if cleaned.contains("答案") { value += 50 }
            if cleaned.contains("原因") { value += 80 }
            if cleaned.contains("其他选项") { value += 25 }
            if cleaned.contains("直接答案") { value += 15 }
            if hasQuestionBlock(cleaned) { value -= 220 }
            if directAnswerPayload(in: cleaned) != nil { value += 180 }
        case .sayInClass:
            if looksLikeSayInClassAnswer(cleaned) { value += 220 }
            if hasQuestionBlock(cleaned) { value -= 260 }
        case .backToClass:
            break
        }

        return value
    }

    static func isHomePage(_ text: String) -> Bool {
        let compact = text.replacingOccurrences(of: " ", with: "")
        if compact.contains("有什么我能帮你的吗") { return true }
        if compact.components(separatedBy: "资讯：").count >= 3 { return true }
        if compact.components(separatedBy: "资讯:").count >= 3 { return true }

        let suggestionHits = ["告诉我如何", "推荐一些", "有哪些好处", "有哪些健康"].filter { compact.contains($0) }
        if suggestionHits.count >= 2 { return true }

        let questionLines = normalizedLines(in: text).filter { looksLikeHomeSuggestionChip($0) }
        return questionLines.count >= 2 && !containsLatin(text)
    }

    private static func isPromptResidue(_ text: String, prompt: String) -> Bool {
        let compactText = compact(text)
        let compactPrompt = compact(prompt)
        guard compactText.count >= 12, compactPrompt.count >= 12 else { return false }
        if compactPrompt.contains(compactText) { return true }

        let instructional = [
            "不要输出推荐问题",
            "不要写长篇",
            "严禁输出",
            "模式：Translate",
            "模式：Explain",
            "模式：Direct Answer",
            "模式：Say in Class"
        ]
        let instructionalHits = instructional.filter { text.contains($0) }.count
        let uniqueAnswerLength = compactText.count
        return instructionalHits >= 2 && uniqueAnswerLength < 180
    }

    private static func isPromptInstruction(_ text: String) -> Bool {
        let instructional = [
            "必须做逐句",
            "只有当截图几乎只有",
            "不要漏掉截图里的主要内容",
            "严禁输出",
            "不要输出推荐问题",
            "假设我是正在上",
            "假设我是",
            "请按这个结构回答",
            "请只给答案",
            "不要逐句翻译",
            "不要翻译整页",
            "不要解释背景",
            "只输出英文回答",
            "用 1-2 句中文说明",
            "1-2 个短要点",
            "2-4句",
            "一句话说明这页",
            "像学生在说话",
            "1 到 2 句自然口语",
            "不要复述题干"
        ]
        return instructional.contains { text.contains($0) }
    }

    private static func chineseCharacterCount(_ text: String) -> Int {
        text.unicodeScalars.filter { $0.value >= 0x4E00 && $0.value <= 0x9FFF }.count
    }

    private static func stripPromptResidue(from lines: [String], prompt: String, action: CopilotAction? = nil) -> [String] {
        let compactPrompt = compact(prompt)
        return lines.filter { line in
            guard !line.isEmpty else { return true }
            if isStructuralAnswerLine(line) { return true }
            if action == .sayInClass, looksLikeSpokenEnglishLine(line) { return true }
            if action == .explain, isExplainDiagramLine(line) { return true }
            if isPromptChromeLine(line) { return false }
            if isPromptPlaceholderLine(line) || isQuestionSlideLine(line) { return false }
            if line.hasPrefix("模式：") || line.hasPrefix("模式:") { return false }
            if line.hasPrefix("任务：") || line.hasPrefix("任务:") { return false }
            if looksLikeNumberedPromptRule(line) { return false }
            if looksLikeGarbledPromptRule(line) { return false }
            let fingerprint = compact(line)
            if fingerprint.count >= 8, compactPrompt.contains(fingerprint) {
                return false
            }
            return true
        }
    }

    private static func isPromptChromeLine(_ line: String) -> Bool {
        let core = compact(stripLeadingBullet(line))
        if core.isEmpty { return true }
        let exact = [
            "解答", "回答", "答案", "禁止输出", "单词规则", "单词解释格式",
            "默认规则", "正确示例", "输出格式", "输出格式必须严格遵守",
            "直接答案", "要点"
        ]
        if exact.contains(core) { return true }
        if core.hasPrefix("回答要清楚") { return true }
        if core.hasPrefix("只有当截图几乎只有") { return true }
        if core.hasPrefix("重要关键词写成") { return true }
        if core.hasPrefix("不要漏掉截图") { return true }
        if core.hasPrefix("不要添加截图外") { return true }
        if core.hasPrefix("严禁输出") { return true }
        if core.hasPrefix("严禁只挑") { return true }
        if core.hasPrefix("不要输出推荐问题") { return true }
        if core.hasPrefix("不要说以下是翻译") { return true }
        if core.hasPrefix("不要把多个英文句子") { return true }
        if core.hasPrefix("不要使用英文中文标签") { return true }
        if core.hasPrefix("请按这个结构回答") { return true }
        if core.hasPrefix("请只给答案") { return true }
        if core.hasPrefix("输出版式必须严格遵守") { return true }
        if core.hasPrefix("每组之间空一行") { return true }
        if core.hasPrefix("如果截图是完整句子") { return true }
        if core.hasPrefix("英文原文") { return true }
        if core.hasPrefix("对应中文翻译") { return true }
        if core.hasPrefix("禁止") && (core.contains("词汇表") || core.contains("推荐问题") || core.contains("无关说明")) { return true }
        if core.hasPrefix("假设我是正在上") { return true }
        if core.hasPrefix("不要逐句翻译") { return true }
        if core.hasPrefix("不要翻译整页") { return true }
        if core.hasPrefix("不要解释背景") { return true }
        if core.hasPrefix("要求") { return true }
        if core.hasPrefix("自然简单口语化") { return true }
        if core.hasPrefix("只输出英文回答") { return true }
        if core.hasPrefix("对上面的英文发言做自然中文翻译") { return true }
        if core == "2-4句" || core == "24句" { return true }
        if core == "term" || core == "简单意思" { return true }
        return false
    }

    private static func focusOnAnswerLines(_ lines: [String], for action: CopilotAction) -> [String] {
        switch action {
        case .directAnswer:
            if let index = lines.indices.last(where: { isDirectAnswerStartLine(lines[$0]) }) {
                return Array(lines[index...])
            }
            return lines
        case .explain:
            if let index = lastExplainStartWithContent(in: lines) {
                return Array(lines[index...])
            }
            return lines
        case .sayInClass:
            if let index = lines.indices.last(where: { isSayInClassStartLine(lines[$0]) }) {
                return Array(lines[index...])
            }
            if let index = lines.indices.last(where: { compact(stripLeadingBullet(lines[$0])).hasPrefix("英文发言") }) {
                return Array(lines[index...])
            }
            return lines
        case .translate:
            return focusOnTranslateLines(lines)
        case .backToClass:
            return lines
        }
    }

    private static func focusOnTranslateLines(_ lines: [String]) -> [String] {
        let meaningful = lines.filter { !$0.isEmpty && !isPromptChromeLine($0) && !isIconJunkLine($0) }
        guard meaningful.count >= 2 else { return lines }

        for index in meaningful.indices {
            let line = meaningful[index]
            guard isEnglishContentLine(line) else { continue }

            let lookahead = meaningful.dropFirst(index + 1).prefix(3)
            if lookahead.contains(where: { containsChinese($0) && !isPromptChromeLine($0) }) {
                return Array(meaningful[index...])
            }
        }

        if let index = meaningful.firstIndex(where: { containsChinese($0) && containsLatin($0) }) {
            return Array(meaningful[index...])
        }

        return lines
    }

    private static func isDirectAnswerStartLine(_ line: String) -> Bool {
        let compactLine = compact(stripLeadingBullet(line))
        return compactLine.hasPrefix("直接答案") ||
            compactLine.hasPrefix("直接结论") ||
            compactLine.hasPrefix("答案")
    }

    static func isStructuralAnswerLine(_ line: String) -> Bool {
        let compactLine = compact(stripLeadingBullet(line))
        let prefixes = [
            "核心",
            "结构",
            "关系",
            "最重要的一句话",
            "答案",
            "原因",
            "其他选项",
            "你可以很口语地回答",
            "直接答案",
            "这页真正意思"
        ]
        return prefixes.contains { compactLine.hasPrefix($0) }
    }

    private static func isExplainAnswerStartLine(_ line: String) -> Bool {
        let compactLine = compact(stripLeadingBullet(line))
        return compactLine.hasPrefix("1.这页真正意思") ||
            compactLine.hasPrefix("1这页真正意思") ||
            compactLine.hasPrefix("这页真正意思") ||
            compactLine.hasPrefix("核心")
    }

    private static func lastExplainStartWithContent(in lines: [String]) -> Int? {
        var last: Int?
        for index in lines.indices where isExplainAnswerStartLine(lines[index]) {
            let headingPayload = payloadAfterColon(in: lines[index])
            let following = lines.dropFirst(index + 1).prefix(8)
            let hasContent = headingPayload.map(isMeaningfulExplainContent) == true
                || following.contains { line in
                    !isExplainHeading(line) && isMeaningfulExplainContent(line)
                }
            if hasContent {
                last = index
            }
        }
        if last != nil { return last }

        return lines.indices.first { index in
            compact(stripLeadingBullet(lines[index])).hasPrefix("结构")
        }
    }

    static func isPromptPlaceholderLine(_ line: String) -> Bool {
        let compactLine = compact(stripLeadingBullet(line))
        guard compactLine.count >= 6 else { return false }
        let placeholders = [
            "一句话说明这页在讲什么",
            "如果有表或关系",
            "用最少文字标出",
            "谁是1，谁是many",
            "谁是1谁是many",
            "用一句人话",
            "写出这页真正要记住",
            "foreignkey放在manyside",
            "术语写成中文",
            "假设我是",
            "不要推荐问题",
            "不要写长",
            "按这个顺序写",
            "只输出解释",
            "1到2句自然口语",
            "像学生在说话",
            "不要复述题干",
            "可以不用ithink",
            "一句话说明为什么",
            "a错一句话",
            "c错一句话",
            "d错一句话"
        ]
        return placeholders.contains { compactLine.contains($0) }
    }

    static func isQuestionSlideLine(_ line: String) -> Bool {
        let compactLine = compact(stripLeadingBullet(line)).lowercased()
        return compactLine.hasPrefix("问答题") ||
            compactLine.hasPrefix("参考答案") ||
            compactLine.contains("whereshouldtheforeignkey") ||
            compactLine.contains("whichofthefollowing") ||
            compactLine.contains("whichstatement")
    }

    static func isExplainDiagramLine(_ line: String) -> Bool {
        let compactLine = compact(stripLeadingBullet(line))
        if ["↓", "↑", "→", "←"].contains(compactLine) {
            return true
        }
        if compactLine.hasPrefix("PK") || compactLine.hasPrefix("FK") {
            return true
        }
        return compactLine.range(of: #"^[A-Z]{2,20}"#, options: .regularExpression) != nil &&
            compactLine.count <= 24
    }

    private static func looksLikeSpokenEnglishLine(_ line: String) -> Bool {
        let compactLine = compact(stripLeadingBullet(line)).lowercased()
        if isQuestionSlideLine(line) { return false }
        let words = latinWordCount(in: line)
        guard words >= 6, chineseCharacterCount(line) <= 2 else { return false }
        let starters = ["theforeignkey", "theprimarykey", "ithink", "iwouldsay", "thisis", "weshould", "itgoes"]
        return starters.contains { compactLine.contains($0) } || line.contains(".")
    }

    private static func isSayInClassStartLine(_ line: String) -> Bool {
        let compactLine = compact(stripLeadingBullet(line)).lowercased()
        return compactLine.hasPrefix("你可以很口语地回答") ||
            compactLine.hasPrefix("ithink") ||
            compactLine.hasPrefix("iwouldsay") ||
            compactLine.hasPrefix("myanswer") ||
            compactLine.hasPrefix("thebestanswer") ||
            compactLine.hasPrefix("inmyopinion") ||
            compactLine.hasPrefix("theforeignkey")
    }

    private static func looksLikeNumberedPromptRule(_ line: String) -> Bool {
        let core = compact(stripLeadingBullet(line))
        guard core.range(of: #"^\d+[\.。、]"#, options: .regularExpression) != nil else {
            return false
        }

        let markers = [
            "必须",
            "不要",
            "中文要",
            "保留原来",
            "每一句英文",
            "截图里",
            "添加截图外"
        ]
        return markers.contains { core.contains($0) }
    }

    private static func looksLikeGarbledPromptRule(_ line: String) -> Bool {
        let core = compact(stripLeadingBullet(line))
        guard !containsLatin(core) else { return false }

        let markers = ["问", "题", "延", "例", "输出", "翻译", "截图", "词汇表"]
        let hits = markers.filter { core.contains($0) }.count
        return core.count >= 10 && hits >= 2
    }

    private static func stripLeadingBullet(_ line: String) -> String {
        var result = line.trimmingCharacters(in: .whitespacesAndNewlines)
        let prefixes = ["•", "·", "-", "—", "*", "●"]
        for prefix in prefixes where result.hasPrefix(prefix) {
            result = String(result.dropFirst()).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return result
    }

    private static func stripLeadingChrome(from lines: [String]) -> [String] {
        var result = lines
        while let first = result.first, first.isEmpty || isExactUILine(first) || isHomePageLine(first) || isPromptChromeLine(first) {
            result.removeFirst()
        }
        return result
    }

    private static func stripTrailingSuggestions(from lines: [String]) -> [String] {
        var kept: [String] = []
        for line in lines {
            if line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                kept.append("")
                continue
            }
            if isIconJunkLine(line) {
                continue
            }
            if !kept.isEmpty, isTrailingInterfaceBoundary(line) {
                break
            }
            if let range = suggestionRange(in: line) {
                let prefix = String(line[..<range.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
                if prefix.isEmpty {
                    if !kept.isEmpty { break }
                    continue
                }
                kept.append(prefix)
                break
            }
            kept.append(line)
        }
        return kept
    }

    private static func isTrailingInterfaceBoundary(_ line: String) -> Bool {
        if line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return false }
        if looksLikeSuggestion(line) || looksLikeHomeSuggestionChip(line) { return true }
        if isExactUILine(line) || isHomePageLine(line) || isPromptChromeLine(line) || isIconJunkLine(line) { return true }

        let compactLine = compact(line)
        let boundaries = [
            "发消息",
            "按住空格",
            "AI生成可能有误",
            "注意核实",
            "图像生成",
            "音乐生成",
            "视频生成",
            "录音转写"
        ]
        return boundaries.contains { compactLine.contains($0) }
    }

    private static func normalizeAnswerLine(_ line: String) -> String {
        line
            .replacingOccurrences(of: "Ilook", with: "I look")
            .replacingOccurrences(of: "Iook", with: "I look")
            .replacingOccurrences(of: "21th", with: "21st")
            .replacingOccurrences(of: "**英文：**", with: "英文：")
            .replacingOccurrences(of: "**英文:**", with: "英文：")
            .replacingOccurrences(of: "**中文：**", with: "中文：")
            .replacingOccurrences(of: "**中文:**", with: "中文：")
            .replacingOccurrences(of: "英文:", with: "英文：")
            .replacingOccurrences(of: "中文:", with: "中文：")
            .replacingOccurrences(of: "**", with: "")
            .replacingOccurrences(of: #"</?[^>]+>"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func isExactUILine(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        let exact = [
            "新对话", "新办公任务", "历史对话", "历史记录", "AI 浏览器", "AI浏览器",
            "AI创作", "云盘", "技能", "帮助", "更多", "发送", "复制", "分享", "删除",
            "图像生成", "帮我写作", "音乐生成", "翻译", "视频生成", "AI播客", "录音转写",
            "发消息或按住空格说话", "AI 生成可能有误", "注意核实", "完成更新",
            "AI 生成可能有误 注意核实", "Q 搜索", "Q 搜索..", "主对话", "搜索", "解答", "回答"
        ]
        return exact.contains(trimmed)
    }

    private static func isHomePageLine(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.contains("有什么我能帮你的吗") { return true }
        if trimmed.hasPrefix("资讯：") || trimmed.hasPrefix("资讯:") { return true }
        return looksLikeSuggestion(trimmed)
    }

    private static func looksLikeSuggestion(_ line: String) -> Bool {
        suggestionRange(in: line) != nil && line.count <= 80
    }

    private static func looksLikeHomeSuggestionChip(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (8...40).contains(trimmed.count), !containsLatin(trimmed) else { return false }
        return trimmed.contains("？") || trimmed.contains("?")
    }

    private static func suggestionRange(in line: String) -> Range<String.Index>? {
        let compactLine = line.replacingOccurrences(of: " ", with: "")
        let prefixes = ["什么是", "如何", "为什么", "这三个", "推荐一些", "用英文写", "提供一些", "告诉我如何", "把录取", "把这段", "有哪些", "多久", "哪些", "学校", "课程", "怎样", "我应该"]
        for prefix in prefixes {
            guard let range = compactLine.range(of: prefix), range.lowerBound == compactLine.startIndex else {
                continue
            }
            let suffix = String(compactLine[range.lowerBound...])
            let hasQuestionShape = suffix.contains("？") ||
                suffix.contains("?") ||
                suffix.hasSuffix("一") ||
                prefix == "用英文写" ||
                prefix == "提供一些" ||
                prefix == "推荐一些"
            guard hasQuestionShape else { continue }
            return line.startIndex..<line.endIndex
        }
        return nil
    }

    private static func dropLeadingUntilEnglishContent(from lines: [String]) -> [String] {
        guard lines.contains(where: isEnglishContentLine) else { return lines }
        var result = lines
        while let first = result.first, !isEnglishContentLine(first) {
            result.removeFirst()
        }
        return result
    }

    private static func isEnglishContentLine(_ line: String) -> Bool {
        let latin = line.unicodeScalars.filter { CharacterSet.letters.contains($0) && $0.value < 0x80 }.count
        return latin >= 8
    }

    private static func isIconJunkLine(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return false }
        let compactLine = compact(trimmed)
        if ["↓", "↑", "→", "←"].contains(compactLine) {
            return false
        }
        let junk = ["口", "凸", "□", "■", "我应该", "一", "—", "–"]
        if junk.contains(compactLine) { return true }
        if compactLine.count <= 4,
           compactLine.contains("凸") || compactLine.contains("』") || compactLine.contains("⑦") {
            return true
        }
        if compactLine.count <= 1, !containsLatin(trimmed) {
            if ["表", "列", "字段", "关系"].contains(compactLine) { return false }
            return true
        }
        if compactLine.hasPrefix("我应该") { return true }
        if compactLine.hasSuffix("一") || compactLine.hasSuffix("—"), compactLine.contains("？") {
            return true
        }
        return false
    }

    private static func looksLikeInterlinearTranslation(_ text: String) -> Bool {
        let lines = normalizedLines(in: text).filter { !$0.isEmpty }
        guard lines.count >= 2, containsChinese(text), containsLatin(text) else { return false }

        var pairs = 0
        var index = 0
        while index + 1 < lines.count {
            if containsLatin(lines[index]) && containsChinese(lines[index + 1]) {
                let words = lines[index].split { $0.isWhitespace || $0 == ":" }.filter { !$0.isEmpty }.count
                if words >= 4 || lines[index].contains(".") || lines[index].contains("?") {
                    pairs += 1
                }
                index += 2
            } else {
                index += 1
            }
        }
        return pairs >= 1
    }

    private static func looksLikeTranslateGlossary(_ text: String) -> Bool {
        let lines = normalizedLines(in: text).filter { !$0.isEmpty }
        let english = lines.filter { line in
            let latin = line.unicodeScalars.filter { CharacterSet.letters.contains($0) && $0.value < 0x80 }.count
            let chinese = chineseCharacterCount(line)
            return latin >= 3 && latin > chinese
        }
        guard english.count >= 2 else { return false }

        let glossary = english.filter { line in
            let compactUpper = compact(line).uppercased()
            if ["FOREIGNKEY", "PRIMARYKEY", "PARENTTABLE", "CHILDTABLE"].contains(where: { compactUpper.contains($0) }) {
                return true
            }
            if line.range(of: #"^[A-Z][A-Z0-9]+\s+[Tt]ables?$"#, options: .regularExpression) != nil {
                return true
            }
            let words = line.split { $0.isWhitespace }.filter { !$0.isEmpty }
            return (1...3).contains(words.count) && words.allSatisfy { word in
                let token = String(word)
                return token.uppercased() == token || token.lowercased() == "table" || token.lowercased() == "key"
            }
        }
        return glossary.count * 2 >= english.count
    }

    private static func looksLikeExplainAnswer(_ text: String) -> Bool {
        let lines = normalizedLines(in: text)
            .map { normalizeAnswerLine($0) }
            .filter { !$0.isEmpty }

        var hasHeading = false
        var inExplainSection = false
        var hasContent = false

        for line in lines {
            if isExplainHeading(line) {
                hasHeading = true
                inExplainSection = true
                if let payload = payloadAfterColon(in: line),
                   isMeaningfulExplainContent(payload) {
                    hasContent = true
                }
                continue
            }

            if inExplainSection, isMeaningfulExplainContent(line) {
                hasContent = true
            }
        }

        if hasHeading && hasContent {
            return !containsPromptPlaceholder(text)
        }

        let compactText = compact(text).lowercased()
        let substance = ["主键", "外键", "一对多", "父表", "foreignkey", "primarykey"]
        return chineseCharacterCount(text) >= 24 &&
            substance.contains(where: { compactText.contains($0) }) &&
            !containsPromptPlaceholder(text)
    }

    private static func containsPromptPlaceholder(_ text: String) -> Bool {
        normalizedLines(in: text).contains { isPromptPlaceholderLine($0) }
    }

    private static func isExplainHeading(_ line: String) -> Bool {
        let compactLine = compact(stripLeadingBullet(line))
        return compactLine.contains("这页真正意思") ||
            compactLine.contains("老师可能想强调") ||
            compactLine.contains("老师想强调") ||
            compactLine.contains("重要概念") ||
            compactLine.contains("关键概念") ||
            compactLine.hasPrefix("核心") ||
            compactLine.hasPrefix("结构") ||
            compactLine.hasPrefix("关系") ||
            compactLine.contains("最重要的一句话")
    }

    private static func isMeaningfulExplainContent(_ text: String) -> Bool {
        let compactText = compact(stripLeadingBullet(text))
        guard chineseCharacterCount(text) >= 4 else { return false }
        let placeholders = [
            "用1-2句中文说明",
            "用12句中文说明",
            "1-2个短要点",
            "12个短要点",
            "中文Englishterm",
            "一句话解释",
            "不逐句翻译",
            "一句话说明这页",
            "如果有表或关系",
            "用最少文字标出",
            "谁是1",
            "用一句人话",
            "写出这页真正要记住",
            "foreignkey放在manyside",
            "术语写成",
            "假设我是"
        ]
        return !placeholders.contains { compactText.contains($0) }
    }

    private static func looksLikeDirectAnswer(_ text: String) -> Bool {
        directAnswerPayload(in: text) != nil
    }

    private static func looksLikeSayInClassAnswer(_ text: String) -> Bool {
        let lines = normalizedLines(in: text).filter { !$0.isEmpty && !isQuestionSlideLine($0) }
        let joined = lines.joined(separator: "\n")
        guard containsLatin(joined), !hasQuestionBlock(joined) else {
            return false
        }

        let compactText = compact(joined).lowercased()
        let forbidden = [
            "whichofthefollowing",
            "requirements",
            "requirement",
            "a.tostore",
            "b.touniquely",
            "c.toconnect",
            "d.tosort",
            "问答题",
            "参考答案"
        ]
        if forbidden.contains(where: { compactText.contains($0) }) {
            return false
        }

        let words = latinWordCount(in: joined)
        guard (6...90).contains(words) else { return false }

        let sentenceCount = englishSentenceCount(in: joined)
        guard (1...4).contains(sentenceCount) else { return false }

        if compactText.contains("你可以很口语地回答") {
            return true
        }

        let classroomStarters = [
            "i think",
            "i would say",
            "my answer",
            "the best answer",
            "in my opinion",
            "i choose",
            "the foreign key",
            "the primary key"
        ]
        return classroomStarters.contains { compactText.contains($0.replacingOccurrences(of: " ", with: "")) }
            || looksLikeSpokenEnglishLine(joined)
    }

    private static func latinWordCount(in text: String) -> Int {
        (try? NSRegularExpression(pattern: #"[A-Za-z]+(?:'[A-Za-z]+)?"#)
            .numberOfMatches(in: text, range: NSRange(text.startIndex..<text.endIndex, in: text))) ?? 0
    }

    private static func payloadAfterColon(in line: String) -> String? {
        guard let colon = line.range(of: "：") ?? line.range(of: ":") else {
            return nil
        }
        return String(line[colon.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func directAnswerPayload(in text: String) -> String? {
        let lines = normalizedLines(in: text)
            .map { normalizeAnswerLine($0) }
            .filter { !$0.isEmpty }

        for line in lines.reversed() {
            let stripped = stripLeadingBullet(line)
            let compactLine = compact(stripped)
            guard compactLine.hasPrefix("直接答案") ||
                    compactLine.hasPrefix("直接结论") ||
                    compactLine.hasPrefix("答案") else {
                continue
            }

            if let colonRange = stripped.range(of: "：") ?? stripped.range(of: ":") {
                let payload = String(stripped[colonRange.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
                if isMeaningfulDirectAnswerPayload(payload) || isChoiceLetter(payload) {
                    return payload
                }
            }
            if isMeaningfulDirectAnswerPayload(stripped) {
                return stripped
            }
        }

        guard let markerIndex = lines.lastIndex(where: isDirectAnswerStartLine) else {
            return nil
        }

        for line in lines.dropFirst(markerIndex + 1) {
            if isDirectAnswerSectionBoundary(line) {
                return nil
            }
            if isMeaningfulDirectAnswerPayload(line) {
                return line
            }
        }

        return nil
    }

    private static func isDirectAnswerSectionBoundary(_ line: String) -> Bool {
        let compactLine = compact(stripLeadingBullet(line))
        return compactLine.hasPrefix("要点") ||
            compactLine.hasPrefix("Question") ||
            compactLine.hasPrefix("问题") ||
            compactLine == "解答" ||
            compactLine == "回答"
    }

    private static func isMeaningfulDirectAnswerPayload(_ text: String) -> Bool {
        let compactText = compact(stripLeadingBullet(text))
        if isChoiceLetter(text) { return true }
        guard compactText.count >= 2 else { return false }
        if compactText.hasPrefix("答案"), compactText.range(of: #"[A-D]"#, options: .regularExpression) != nil {
            return true
        }
        let placeholders = [
            "用1句话给出结论",
            "如有必要",
            "保留关键英文术语",
            "直接",
            "解答",
            "回答"
        ]
        if placeholders.contains(where: { compactText.contains($0) }) { return false }
        return containsChinese(text) || text.range(of: #"\b[A-D][\.\)]"#, options: .regularExpression) != nil
    }

    private static func isChoiceLetter(_ text: String) -> Bool {
        let compactText = compact(text)
        return compactText.range(of: #"^[A-D]$"#, options: .regularExpression) != nil
    }

    private static func hasQuestionBlock(_ text: String) -> Bool {
        let compactText = compact(text)
        return compactText.contains("Question") ||
            compactText.contains("Whichofthefollowing") ||
            compactText.contains("A.To") ||
            compactText.contains("B.To")
    }

    private static func englishSentenceCount(in text: String) -> Int {
        let matches = text.matches(of: /[.!?]/)
        if !matches.isEmpty { return matches.count }
        return text.split(separator: "\n").filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.count
    }

    private static func isShortTermTranslation(_ text: String) -> Bool {
        let lines = normalizedLines(in: text).filter { !$0.isEmpty }
        let leadingLines = Array(lines.prefix(5))
        guard !leadingLines.isEmpty,
              containsLatin(text),
              chineseCharacterCount(text) >= 2,
              !isPromptInstruction(text),
              !isPromptResidue(text, prompt: "") else {
            return false
        }

        return leadingLines.contains { line in
            let latin = line.unicodeScalars.filter { CharacterSet.letters.contains($0) && $0.value < 0x80 }.count
            let words = line.split { !$0.isLetter && !$0.isNumber }
            return latin >= 2 && latin <= 40 && words.count <= 5
        }
    }

    private static func containsChinese(_ text: String) -> Bool {
        text.range(of: #"\p{Han}"#, options: .regularExpression) != nil
    }

    private static func containsLatin(_ text: String) -> Bool {
        text.range(of: #"[A-Za-z]"#, options: .regularExpression) != nil
    }

    private static func normalizedLines(in text: String) -> [String] {
        text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
    }

    private static func compact(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\n", with: "")
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "\t", with: "")
            .replacingOccurrences(of: "*", with: "")
            .replacingOccurrences(of: "•", with: "")
            .replacingOccurrences(of: "·", with: "")
            .replacingOccurrences(of: "“", with: "")
            .replacingOccurrences(of: "”", with: "")
            .replacingOccurrences(of: "\"", with: "")
            .replacingOccurrences(of: "‘", with: "")
            .replacingOccurrences(of: "’", with: "")
            .replacingOccurrences(of: "'", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
