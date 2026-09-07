import AppKit
import ApplicationServices
import Vision

final class DoubaoResponseReader {
    private let chatAppNames = ["豆包", "Doubao"]
    private let browserAppNames = ["豆包浏览器", "Doubao Browser"]
    private let copyIconFinder = CopyIconFinder()

    var restoreClassApp: (() -> Void)?
    var onPartialAnswer: ((String) -> Void)?

    func currentVisibleText() -> String {
        let apps = runningDoubaoProcesses()
        guard !apps.isEmpty else {
            DebugLog.write("Doubao reader: app is not running")
            return ""
        }

        let texts = apps.map { app -> String in
            let appElement = AXUIElementCreateApplication(app.processIdentifier)
            var lines: [String] = []
            collectText(from: appElement, into: &lines, depth: 0)
            let text = normalize(lines.joined(separator: "\n"))
            DebugLog.write("Doubao reader: read \(text.count) characters from \(app.localizedName ?? "unknown")")
            return text
        }

        return normalize(texts.joined(separator: "\n"))
    }

    func captureCompletedResponse(prompt: String, action: CopilotAction, timeout: TimeInterval = 40) -> String? {
        _ = timeout
        let normalizedPrompt = normalize(prompt)
        restoreClassApp?()
        let baselineText = conversationBaselineText()
        DebugLog.write("capture: one-shot extract, no peek loop")

        if let background = ocrAnswer(
            in: captureDoubaoWindow(region: .answerBand),
            baselineText: baselineText,
            prompt: normalizedPrompt,
            action: action
        ), ResponseSanitizer.isPlausibleAnswer(background, prompt: normalizedPrompt, action: action) {
            DebugLog.write("capture: extracted from background window (\(background.count) chars)")
            publish(background)
            return background
        }

        DebugLog.write("capture: one extract visit to Doubao")
        activateChatApp()
        _ = AXAccess.waitUntil(timeout: 0.6) {
            captureDoubaoWindow(region: .conversation) != nil
        }

        var best = ""
        var bestScore = 0
        func consider(_ candidate: String, region: OCRRegion, pass: Int) {
            let score = ResponseSanitizer.score(candidate, prompt: normalizedPrompt, action: action)
            if score > bestScore || (score == bestScore && candidate.count > best.count + 6) {
                best = candidate
                bestScore = score
                publish(candidate)
                DebugLog.write("capture: extract \(region) pass \(pass) (\(candidate.count) chars, score \(score))")
            }
        }

        for region in [OCRRegion.conversation, .answerBand] {
            if let candidate = ocrAnswer(
                in: captureDoubaoWindow(region: region),
                baselineText: baselineText,
                prompt: normalizedPrompt,
                action: action
            ) {
                consider(candidate, region: region, pass: 1)
            }
        }

        scrollToBottomOfDoubaoConversation()
        Thread.sleep(forTimeInterval: 0.25)

        for region in [OCRRegion.answerBand, .conversation] {
            if let candidate = ocrAnswer(
                in: captureDoubaoWindow(region: region),
                baselineText: baselineText,
                prompt: normalizedPrompt,
                action: action
            ) {
                consider(candidate, region: region, pass: 2)
            }
        }

        restoreClassApp?()

        if ResponseSanitizer.isPlausibleAnswer(best, prompt: normalizedPrompt, action: action) {
            DebugLog.write("capture: using one-shot OCR (\(best.count) chars)")
            return best
        }

        DebugLog.write("capture: no usable Doubao answer")
        return nil
    }

    private func ocrAnswer(in image: CGImage?, baselineText: String, prompt: String, action: CopilotAction) -> String? {
        guard let image else { return nil }

        let rawText = recognizeText(in: image)
        DebugLog.write("Doubao OCR quiet: \(preview(rawText))")
        saveOCRDebugImage(image, name: "last-ocr-answer.png")

        let newContent = extractResponse(current: rawText, baseline: baselineText, prompt: prompt)
        var sources: [String] = []
        if newContent.count >= 12 {
            DebugLog.write("capture: OCR diff vs send baseline (\(newContent.count) chars)")
            sources.append(newContent)
        }
        if rawText.count >= 12, rawText != newContent {
            sources.append(rawText)
        }

        var best = ""
        var bestScore = 0
        for source in sources {
            let candidate = preparedAnswer(extractOCRResponse(current: source, prompt: prompt), prompt: prompt, action: action)
            let plausible = ResponseSanitizer.isPlausibleAnswer(candidate, prompt: prompt, action: action)
                || ResponseSanitizer.isStreamingCandidate(candidate, prompt: prompt, action: action)
            guard plausible else {
                DebugLog.write("capture: OCR candidate rejected (\(candidate.count) chars) \(preview(candidate))")
                continue
            }
            let score = ResponseSanitizer.score(candidate, prompt: prompt, action: action)
            if score > bestScore || (score == bestScore && candidate.count > best.count) {
                best = candidate
                bestScore = max(score, 1)
            }
        }
        return best.isEmpty ? nil : best
    }

    private func readVisibleResponseAfterScrolling(prompt: String, action: CopilotAction) -> String? {
        scrollToBottomOfDoubaoConversation()
        Thread.sleep(forTimeInterval: 0.35)

        if let copied = usableCopiedResponse(prompt: prompt, action: action) {
            publish(copied)
            DebugLog.write("capture: scrolled copy response captured")
            return copied
        }

        if let ocr = ocrVisibleResponse(prompt: prompt, action: action) {
            publish(ocr)
            DebugLog.write("capture: scrolled OCR response captured")
            return ocr
        }

        return nil
    }

    private func publish(_ text: String) {
        onPartialAnswer?(text)
    }

    private enum CopyIconClickResult {
        case copied(String)
        case missedClick
        case notFound
    }

    private func clickVisibleCopyIcon(prompt: String, action: CopilotAction) -> CopyIconClickResult {
        guard let target = largestDoubaoWindow() else {
            DebugLog.write("Copy icon: Doubao window not found")
            return .notFound
        }

        guard let image = CGWindowListCreateImage(target.bounds, .optionIncludingWindow, target.windowID, .bestResolution) else {
            DebugLog.write("Copy icon: window image capture failed")
            return .notFound
        }

        guard let finder = copyIconFinder else {
            DebugLog.write("Copy icon: template not loaded")
            return .notFound
        }

        guard let match = finder.match(in: image, windowBounds: target.bounds) else {
            return .notFound
        }

        DebugLog.write(String(format: "Copy icon click at %@ score %.3f", "\(match.point)", match.score))
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        let previousChangeCount = pasteboard.changeCount

        activateChatApp()
        Thread.sleep(forTimeInterval: 0.12)
        click(at: match.point)

        var copied: String?
        let startedAt = Date()
        while Date().timeIntervalSince(startedAt) < 1.2 {
            Thread.sleep(forTimeInterval: 0.12)
            if pasteboard.changeCount != previousChangeCount,
               let value = pasteboard.string(forType: .string),
               !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                copied = value
                break
            }
        }

        guard let copied else {
            DebugLog.write("Copy icon click did not change clipboard")
            return .missedClick
        }

        let candidate = preparedAnswer(cleanupCopiedResponse(copied, prompt: prompt), prompt: prompt, action: action)
        guard ResponseSanitizer.isPlausibleAnswer(candidate, prompt: prompt, action: action) else {
            DebugLog.write("Copy icon clipboard ignored: \(preview(candidate))")
            return .missedClick
        }

        return .copied(candidate)
    }

    private func ocrWithoutInteracting(prompt: String, action: CopilotAction) -> String? {
        guard let image = captureDoubaoWindow(region: .answerBand) ?? captureDoubaoWindow(region: .conversation) else { return nil }
        let rawText = recognizeText(in: image)
        DebugLog.write("Doubao OCR quiet: \(preview(rawText))")
        saveOCRDebugImage(image, name: "last-ocr-answer.png")
        let candidate = preparedAnswer(extractOCRResponse(current: rawText, prompt: prompt), prompt: prompt, action: action)
        if ResponseSanitizer.isPlausibleAnswer(candidate, prompt: prompt, action: action)
            || ResponseSanitizer.isStreamingCandidate(candidate, prompt: prompt, action: action) {
            return candidate
        }
        return nil
    }

    private func click(at point: CGPoint) {
        let source = CGEventSource(stateID: .hidSystemState)
        CGWarpMouseCursorPosition(point)
        Thread.sleep(forTimeInterval: 0.04)
        guard let down = CGEvent(mouseEventSource: source, mouseType: .leftMouseDown, mouseCursorPosition: point, mouseButton: .left),
              let up = CGEvent(mouseEventSource: source, mouseType: .leftMouseUp, mouseCursorPosition: point, mouseButton: .left) else {
            return
        }
        down.post(tap: .cghidEventTap)
        Thread.sleep(forTimeInterval: 0.04)
        up.post(tap: .cghidEventTap)
    }

    func ocrVisibleResponse(prompt: String, action: CopilotAction) -> String? {
        let rawText = captureDoubaoTextAcrossVisiblePages()
        DebugLog.write("Doubao OCR: raw preview \(preview(rawText))")
        if ResponseSanitizer.isHomePage(rawText) {
            DebugLog.write("Doubao OCR: ignored Doubao home page")
            return nil
        }

        let candidate = preparedAnswer(extractOCRResponse(current: rawText, prompt: prompt), prompt: prompt, action: action)
        if ResponseSanitizer.isPlausibleAnswer(candidate, prompt: prompt, action: action) {
            DebugLog.write("Doubao OCR: response captured with \(candidate.count) characters")
            return candidate
        }

        DebugLog.write("Doubao OCR: no usable text captured; raw count \(rawText.count), candidate \(preview(candidate))")
        return nil
    }

    private func usableCopiedResponse(prompt: String, action: CopilotAction) -> String? {
        hoverLatestAnswerArea()
        Thread.sleep(forTimeInterval: 0.35)
        let buttons = conversationCopyButtons()
        DebugLog.write("Doubao copy: after hover found \(buttons.count) conversation copy buttons")
        guard !buttons.isEmpty else { return nil }
        return copyLatestVisibleResponse(prompt: prompt, action: action)
    }

    func copyLatestVisibleResponse(prompt: String, action: CopilotAction) -> String? {
        hoverLatestAnswerArea()
        Thread.sleep(forTimeInterval: 0.25)

        let buttons = conversationCopyButtons()
        DebugLog.write("Doubao copy: found \(buttons.count) conversation copy buttons")

        for (index, button) in buttons.enumerated() {
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            let previousChangeCount = pasteboard.changeCount
            DebugLog.write("Doubao copy: pressing button \(index): \(elementDebugLabel(button))")

            guard AXUIElementPerformAction(button, kAXPressAction as CFString) == .success else {
                continue
            }

            let startedAt = Date()
            var copied: String?
            while Date().timeIntervalSince(startedAt) < 2.0 {
                Thread.sleep(forTimeInterval: 0.2)
                if pasteboard.changeCount != previousChangeCount,
                   let value = pasteboard.string(forType: .string),
                   !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    copied = value
                    break
                }
            }

            guard let copied else {
                continue
            }

            DebugLog.write("Doubao copy: copied \(copied.count) characters")
            let candidate = preparedAnswer(cleanupCopiedResponse(copied, prompt: prompt), prompt: prompt, action: action)
            if ResponseSanitizer.isPlausibleAnswer(candidate, prompt: prompt, action: action) {
                DebugLog.write("Doubao copy: response captured with \(candidate.count) characters")
                return candidate
            }
        }

        DebugLog.write("Doubao copy: no usable copied response")
        return nil
    }

    private func consider(_ candidate: String, prompt: String, action: CopilotAction, source: String, best: inout String) {
        let prepared = preparedAnswer(candidate, prompt: prompt, action: action)
        guard !isLoadingText(prepared),
              !isSystemMenuText(prepared),
              ResponseSanitizer.isPlausibleAnswer(prepared, prompt: prompt, action: action) else {
            if !candidate.isEmpty {
                DebugLog.write("Doubao reader: ignored \(source) candidate with \(candidate.count) characters: \(preview(candidate))")
            }
            return
        }

        if prepared.count > best.count + 8 || (best.isEmpty && !prepared.isEmpty) {
            DebugLog.write("Doubao reader: \(source) candidate \(prepared.count) characters")
            best = prepared
        }
    }

    private func preparedAnswer(_ text: String, prompt: String, action: CopilotAction) -> String {
        ResponseSanitizer.sanitize(text, prompt: prompt, action: action)
    }

    private func captureDoubaoTextAcrossVisiblePages() -> String {
        scrollToBottomOfDoubaoConversation()
        Thread.sleep(forTimeInterval: 0.45)

        if let answerBand = captureDoubaoWindow(region: .answerBand) {
            let text = recognizeText(in: answerBand)
            DebugLog.write("Doubao OCR: answer-band raw count \(text.count) \(preview(text))")
            saveOCRDebugImage(answerBand, name: "last-ocr-answer.png")
            if text.count >= 24 {
                return deduplicatedLines(in: text)
            }
        }

        if let conversation = captureDoubaoWindow(region: .conversation) {
            let text = recognizeText(in: conversation)
            DebugLog.write("Doubao OCR: conversation raw count \(text.count) \(preview(text))")
            saveOCRDebugImage(conversation, name: "last-ocr.png")
            if !text.isEmpty {
                return deduplicatedLines(in: text)
            }
        }

        return ""
    }

    private func conversationBaselineText() -> String {
        guard FileManager.default.fileExists(atPath: DoubaoWindow.conversationBaselineURL.path),
              let image = NSImage(contentsOf: DoubaoWindow.conversationBaselineURL),
              let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            DebugLog.write("capture: no send baseline")
            return ""
        }

        let text = normalize(recognizeText(in: cgImage))
        DebugLog.write("capture: loaded send baseline (\(text.count) chars) \(preview(text))")
        return text
    }

    private func recognizeText(in image: CGImage) -> String {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.recognitionLanguages = ["zh-Hans", "en-US"]

        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        do {
            try handler.perform([request])
        } catch {
            DebugLog.write("Doubao OCR failed: \(error.localizedDescription)")
            return ""
        }

        return request.results?
            .compactMap { $0.topCandidates(1).first?.string }
            .joined(separator: "\n") ?? ""
    }

    private func scrollToBottomOfDoubaoConversation() {
        clickDoubaoReadingArea()
        Thread.sleep(forTimeInterval: 0.15)
        for _ in 0..<3 {
            scrollDoubaoConversation(delta: -24)
            Thread.sleep(forTimeInterval: 0.05)
        }
    }

    private func extractResponse(current: String, baseline: String, prompt: String) -> String {
        let promptLines = Set(nonEmptyLines(prompt).filter { $0.count >= 8 })
        let baselineLines = Set(nonEmptyLines(baseline))
        let newLines = nonEmptyLines(current).filter { line in
            if ResponseSanitizer.isStructuralAnswerLine(line) {
                return true
            }
            if ResponseSanitizer.isExplainDiagramLine(line) {
                return true
            }
            return !baselineLines.contains(line) && !promptLines.contains(line)
        }
        let fromDiff = cleanupResponse(removeTrailingSuggestions(from: newLines.joined(separator: "\n")))

        var fromSuffix = ""
        if !prompt.isEmpty, let range = current.range(of: prompt, options: [.backwards]) {
            fromSuffix = cleanupResponse(removeTrailingSuggestions(from: String(current[range.upperBound...])))
        }

        if fromDiff.count >= fromSuffix.count {
            return fromDiff
        }
        return fromSuffix
    }

    private func cleanupResponse(_ text: String) -> String {
        let ignoredExact = [
            "Lecture Copilot",
            "新对话",
            "历史记录",
            "搜索",
            "翻译截图英文内容",
            "发送",
            "重新生成",
            "复制",
            "分享",
            "删除",
            "帮助"
        ]

        var seen = Set<String>()
        let lines = normalize(text)
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .filter { line in
                !ignoredExact.contains(line)
            }
            .filter { line in
                if line.hasSuffix(" - 豆包") || line.hasSuffix(" - Doubao") {
                    return false
                }
                return true
            }
            .filter { line in
                if seen.contains(line) { return false }
                seen.insert(line)
                return true
            }

        return lines.joined(separator: "\n")
    }

    private func cleanupCopiedResponse(_ text: String, prompt: String) -> String {
        var cleaned = normalize(text)
        let normalizedPrompt = normalize(prompt)

        if !normalizedPrompt.isEmpty,
           let range = cleaned.range(of: normalizedPrompt, options: [.backwards]) {
            cleaned = String(cleaned[range.upperBound...])
        }

        return cleanupResponse(removeTrailingSuggestions(from: cleaned))
    }

    private func extractOCRResponse(current: String, prompt: String) -> String {
        var text = normalize(current)
        let normalizedPrompt = normalize(prompt)

        if !normalizedPrompt.isEmpty,
           let range = text.range(of: normalizedPrompt, options: [.backwards]) {
            text = String(text[range.upperBound...])
        }

        var lines = text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        let compactPrompt = compactForComparison(normalizedPrompt)
        lines.removeAll { line in
            if ResponseSanitizer.isStructuralAnswerLine(line) || ResponseSanitizer.isExplainDiagramLine(line) {
                return false
            }
            let fingerprint = compactForComparison(line)
            return fingerprint.count >= 8 && compactPrompt.contains(fingerprint)
        }

        if let markerIndex = lines.lastIndex(where: isOCRAnswerStartMarker) {
            lines = Array(lines.dropFirst(markerIndex + 1))
        }

        while let first = lines.first, !isLikelyOCRAnswerLine(first) {
            lines.removeFirst()
        }

        var answerLines: [String] = []
        for line in lines {
            if !answerLines.isEmpty, isOCRAnswerEndLine(line) {
                break
            }

            guard !isOCRJunkLine(line) else { continue }
            answerLines.append(line)
        }

        return cleanupResponse(removeTrailingSuggestions(from: answerLines.joined(separator: "\n")))
    }

    private func removeTrailingSuggestions(from text: String) -> String {
        let lines = normalize(text)
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }

        var kept: [String] = []
        for line in lines {
            guard !line.isEmpty else {
                kept.append(line)
                continue
            }

            if !kept.isEmpty, isOCRAnswerEndLine(line) {
                break
            }

            let lineWithoutSuggestions = removeInlineSuggestion(from: line)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if lineWithoutSuggestions.isEmpty {
                if !kept.isEmpty {
                    break
                }
                continue
            }

            kept.append(lineWithoutSuggestions)
        }

        return kept.joined(separator: "\n")
    }

    private func removeInlineSuggestion(from line: String) -> String {
        guard let range = firstSuggestionRange(in: line, allowInline: true) else {
            return line
        }

        return String(line[..<range.lowerBound])
    }

    private func isLoadingText(_ text: String) -> Bool {
        let phrases = ["正在思考", "思考中", "生成中", "正在生成", "正在回复", "正在输入"]
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard phrases.contains(where: { trimmed.contains($0) }) else { return false }
        return trimmed.count < 80 || nonEmptyLines(trimmed).count <= 3
    }

    private func isSystemMenuText(_ text: String) -> Bool {
        let menuFragments = [
            "关于本机",
            "系统信息",
            "系统设置",
            "App Store",
            "最近使用的项目",
            "应用程序",
            "在访达中显示"
        ]
        return menuFragments.filter { text.contains($0) }.count >= 2
    }

    private func isDoubaoInterfaceOnlyText(_ text: String, prompt: String) -> Bool {
        let trimmed = normalize(text)
        guard !trimmed.isEmpty else { return true }

        let lines = trimmed
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        if lines.allSatisfy(isOCRJunkLine) {
            return true
        }

        if trimmed.hasSuffix("- 豆包") || trimmed.hasSuffix("- Doubao") {
            return true
        }

        if ResponseSanitizer.isHomePage(trimmed) {
            return true
        }

        if trimmed.count < 40 {
            let interfaceFragments = ["豆包", "Doubao", "帮助", "搜索", "新对话", "截图", "主要英文内容"]
            if interfaceFragments.contains(where: { trimmed.contains($0) }) {
                return true
            }
        }

        let compactText = compactForComparison(trimmed)
        let compactPrompt = compactForComparison(prompt)
        if compactText.count >= 6,
           compactPrompt.contains(compactText.replacingOccurrences(of: "豆包", with: "")) {
            return true
        }

        return false
    }

    private func isOCRAnswerStartMarker(_ line: String) -> Bool {
        line.contains("AI 生成可能有误") ||
            line.contains("注意核实") ||
            line.contains("完成更新") ||
            compactLine(line) == "解答" ||
            compactLine(line) == "回答"
    }

    private func isLikelyOCRAnswerLine(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        if ResponseSanitizer.isStructuralAnswerLine(trimmed) {
            return !isOCRJunkLine(trimmed)
        }
        guard trimmed.count >= 4,
              !isOCRJunkLine(trimmed),
              !isOCRAnswerEndLine(trimmed) else {
            return false
        }

        return trimmed.range(of: #"[A-Za-z\u{4E00}-\u{9FFF}]"#, options: .regularExpression) != nil
    }

    private func isOCRJunkLine(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        let exactJunk = [
            "Q 搜索..",
            "Q 搜索",
            "巴 新对话",
            "新对话",
            "新办公任务",
            "AI 浏览器",
            "AI创作",
            "云盘",
            "技能",
            "历史对话",
            "翻译截图英文内容",
            "主对话",
            "AI 生成可能有误 注意核实",
            "AI 生成可能有误",
            "注意核实",
            "完成更新",
            "发消息或按住空格说话",
            "帮助",
            "更多",
            "图像生成",
            "帮我写作",
            "音乐生成",
            "翻译",
            "视频生成",
            "AI播客",
            "录音转写",
            "解答",
            "回答",
            "口",
            "凸",
            "我应该"
        ]

        if exactJunk.contains(trimmed) { return true }
        if compactLine(trimmed) == "解答" || compactLine(trimmed) == "回答" { return true }
        if compactLine(trimmed).hasPrefix("问答题") || compactLine(trimmed).hasPrefix("参考答案") {
            return true
        }
        if ["口", "凸", "□", "我应该"].contains(compactLine(trimmed)) { return true }
        if compactLine(trimmed).count <= 4,
           compactLine(trimmed).contains("凸") || compactLine(trimmed).contains("』") || compactLine(trimmed).contains("⑦") {
            return true
        }
        if trimmed.count <= 3,
           trimmed.range(of: #"[A-Za-z\u{4E00}-\u{9FFF}]"#, options: .regularExpression) == nil {
            return true
        }

        let junkFragments = [
            "新对话",
            "历史对话",
            "翻译截图英文内容",
            "- 豆包",
            "发消息",
            "按住空格",
            "图像生成",
            "音乐生成",
            "视频生成",
            "录音转写"
        ]
        return junkFragments.contains { trimmed.contains($0) }
    }

    private func isOCRAnswerEndLine(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.contains("发消息") || trimmed.contains("按住空格") {
            return true
        }

        let toolFragments = ["图像生成", "帮我写作", "音乐生成", "视频生成", "AI播客", "录音转写", "更多"]
        if toolFragments.contains(where: { trimmed.contains($0) }) {
            return true
        }

        return firstSuggestionRange(in: trimmed, allowInline: false) != nil
    }

    private func firstSuggestionRange(in line: String, allowInline: Bool) -> Range<String.Index>? {
        let normalizedLine = line
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "　", with: "")
            .replacingOccurrences(of: "•", with: "")
            .replacingOccurrences(of: "口", with: "")
            .replacingOccurrences(of: "心", with: "")

        let suggestionPrefixes = [
            "什么是",
            "如何",
            "为什么",
            "这三个",
            "推荐一些",
            "用英文写",
            "提供一些",
            "能不能",
            "可以",
            "学校",
            "课程",
            "怎样",
            "我应该",
            "有哪些"
        ]

        var bestRange: Range<String.Index>?
        for prefix in suggestionPrefixes {
            guard let normalizedRange = normalizedLine.range(of: prefix) else { continue }
            let startsAtBeginning = normalizedRange.lowerBound == normalizedLine.startIndex
            guard allowInline || startsAtBeginning else { continue }

            let sourceOffset = normalizedLine.distance(from: normalizedLine.startIndex, to: normalizedRange.lowerBound)
            guard let sourceIndex = line.index(line.startIndex, offsetBy: sourceOffset, limitedBy: line.endIndex) else {
                continue
            }

            let suffix = String(normalizedLine[normalizedRange.lowerBound...])
            let hasQuestionShape = suffix.contains("？") ||
                suffix.contains("?") ||
                suffix.hasSuffix("一") ||
                prefix == "用英文写" ||
                prefix == "提供一些" ||
                prefix == "推荐一些"

            guard hasQuestionShape else { continue }

            let sourceRange = sourceIndex..<line.endIndex
            if bestRange == nil || sourceRange.lowerBound < bestRange!.lowerBound {
                bestRange = sourceRange
            }
        }

        return bestRange
    }

    private func compactForComparison(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\n", with: "")
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "\t", with: "")
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: "•", with: "")
            .replacingOccurrences(of: "·", with: "")
            .replacingOccurrences(of: "“", with: "")
            .replacingOccurrences(of: "”", with: "")
            .replacingOccurrences(of: "\"", with: "")
            .replacingOccurrences(of: "'", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func collectText(from element: AXUIElement, into lines: inout [String], depth: Int) {
        guard depth < 12 else { return }

        for attribute in [kAXValueAttribute, kAXTitleAttribute, kAXDescriptionAttribute] {
            if let value = copyAttribute(attribute, from: element) as? String {
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.count >= 2 {
                    lines.append(trimmed)
                }
            }
        }

        if let children = copyAttribute(kAXChildrenAttribute, from: element) as? [AXUIElement] {
            for child in children {
                collectText(from: child, into: &lines, depth: depth + 1)
            }
        }
    }

    private func conversationCopyButtons() -> [AXUIElement] {
        copyButtons()
            .filter { isConversationCopyButton($0) }
            .sorted { lhs, rhs in
                (elementFrame(lhs)?.maxY ?? 0) > (elementFrame(rhs)?.maxY ?? 0)
            }
    }

    private func isConversationCopyButton(_ element: AXUIElement) -> Bool {
        let label = elementLabel(element)
        let lowered = label.lowercased()
        if lowered.contains("标签") ||
            lowered.contains("tab") ||
            lowered.contains("链接") ||
            lowered.contains("link") ||
            lowered.contains("地址") {
            return false
        }

        if label == "复制" || label == "Copy" {
            return true
        }

        guard let frame = elementFrame(element),
              frame.width >= 8,
              frame.height >= 8 else {
            return false
        }

        return true
    }

    private func copyButtons() -> [AXUIElement] {
        var buttons: [AXUIElement] = []

        for app in runningDoubaoProcesses() {
            let appElement = AXUIElementCreateApplication(app.processIdentifier)
            collectCopyButtons(from: appElement, into: &buttons, depth: 0)
        }

        return buttons
    }

    private func collectCopyButtons(from element: AXUIElement, into buttons: inout [AXUIElement], depth: Int) {
        guard depth < 20 else { return }

        if elementLooksLikeCopyButton(element) {
            buttons.append(element)
        }

        if let children = copyAttribute(kAXChildrenAttribute, from: element) as? [AXUIElement] {
            for child in children {
                collectCopyButtons(from: child, into: &buttons, depth: depth + 1)
            }
        }
    }

    private func elementLooksLikeCopyButton(_ element: AXUIElement) -> Bool {
        var actionNames: CFArray?
        let actionsResult = AXUIElementCopyActionNames(element, &actionNames)
        guard actionsResult == .success,
              let actions = actionNames as? [String],
              actions.contains(kAXPressAction) else {
            return false
        }

        let label = [
            copyAttribute(kAXTitleAttribute, from: element) as? String,
            copyAttribute(kAXDescriptionAttribute, from: element) as? String,
            copyAttribute(kAXHelpAttribute, from: element) as? String,
            copyAttribute(kAXValueAttribute, from: element) as? String
        ]
            .compactMap(\.self)
            .joined(separator: " ")

        let normalizedLabel = label.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalizedLabel == "复制" ||
            normalizedLabel == "Copy" ||
            normalizedLabel.contains("复制") ||
            normalizedLabel.localizedCaseInsensitiveContains("copy")
    }

    private func elementLabel(_ element: AXUIElement) -> String {
        [
            copyAttribute(kAXTitleAttribute, from: element) as? String,
            copyAttribute(kAXDescriptionAttribute, from: element) as? String,
            copyAttribute(kAXHelpAttribute, from: element) as? String,
            copyAttribute(kAXValueAttribute, from: element) as? String
        ]
            .compactMap(\.self)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func elementFrame(_ element: AXUIElement) -> CGRect? {
        guard let positionValue = copyAttribute(kAXPositionAttribute, from: element),
              let sizeValue = copyAttribute(kAXSizeAttribute, from: element) else {
            return nil
        }

        var point = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(positionValue as! AXValue, .cgPoint, &point),
              AXValueGetValue(sizeValue as! AXValue, .cgSize, &size) else {
            return nil
        }

        return CGRect(origin: point, size: size)
    }

    private func elementDebugLabel(_ element: AXUIElement) -> String {
        let label = [
            copyAttribute(kAXTitleAttribute, from: element) as? String,
            copyAttribute(kAXDescriptionAttribute, from: element) as? String,
            copyAttribute(kAXHelpAttribute, from: element) as? String,
            copyAttribute(kAXValueAttribute, from: element) as? String
        ]
            .compactMap(\.self)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let position = copyAttribute(kAXPositionAttribute, from: element).map { "\($0)" } ?? "unknown"
        let size = copyAttribute(kAXSizeAttribute, from: element).map { "\($0)" } ?? "unknown"
        if !label.isEmpty {
            return "\(label) position=\(position) size=\(size)"
        }

        return "position=\(position) size=\(size)"
    }

    private func hoverLatestAnswerArea() {
        moveCursor(in: largestDoubaoWindow(), xRatio: 0.64, yRatio: 0.78)
    }

    private func clickDoubaoReadingArea() {
        click(in: largestDoubaoWindow(), xRatio: 0.58, yRatio: 0.40)
    }

    private func scrollDoubaoConversation(delta: Int32) {
        guard let window = largestDoubaoWindow() else { return }
        let point = pointInWindow(window, xRatio: 0.58, yRatio: 0.40)
        CGWarpMouseCursorPosition(point)

        for _ in 0..<4 {
            guard let event = CGEvent(
                scrollWheelEvent2Source: nil,
                units: .line,
                wheelCount: 1,
                wheel1: delta,
                wheel2: 0,
                wheel3: 0
            ) else {
                return
            }
            event.post(tap: .cghidEventTap)
            Thread.sleep(forTimeInterval: 0.03)
        }
    }

    private func click(in window: (bounds: CGRect, windowID: CGWindowID)?, xRatio: CGFloat, yRatio: CGFloat) {
        guard let window else { return }
        let point = pointInWindow(window, xRatio: xRatio, yRatio: yRatio)
        CGWarpMouseCursorPosition(point)
        guard let down = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: point, mouseButton: .left),
              let up = CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: point, mouseButton: .left) else {
            return
        }
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }

    private func moveCursor(in window: (bounds: CGRect, windowID: CGWindowID)?, xRatio: CGFloat, yRatio: CGFloat) {
        guard let window else { return }
        CGWarpMouseCursorPosition(pointInWindow(window, xRatio: xRatio, yRatio: yRatio))
    }

    private func pointInWindow(_ window: (bounds: CGRect, windowID: CGWindowID), xRatio: CGFloat, yRatio: CGFloat) -> CGPoint {
        CGPoint(
            x: window.bounds.minX + window.bounds.width * xRatio,
            y: window.bounds.minY + window.bounds.height * yRatio
        )
    }

    private func copyAttribute(_ attribute: String, from element: AXUIElement) -> AnyObject? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        guard result == .success else { return nil }
        return value
    }

    private func hasChineseAnswer(_ text: String) -> Bool {
        text.unicodeScalars.filter { $0.value >= 0x4E00 && $0.value <= 0x9FFF }.count >= 12
    }

    private func compactLine(_ line: String) -> String {
        line
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "•", with: "")
            .replacingOccurrences(of: "·", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func normalize(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func runningDoubaoProcesses() -> [NSRunningApplication] {
        let chat = appsNamed(chatAppNames)
        if !chat.isEmpty {
            return chat
        }
        return appsNamed(browserAppNames)
    }

    private func appsNamed(_ names: [String]) -> [NSRunningApplication] {
        NSWorkspace.shared.runningApplications.filter { app in
            names.contains(app.localizedName ?? "")
        }
    }

    private func activateChatApp() {
        runningDoubaoProcesses().first?.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
    }

    private func captureLargestDoubaoWindow() -> CGImage? {
        captureDoubaoWindow(region: .conversation)
    }

    private enum OCRRegion {
        case conversation
        case answerBand
    }

    private func captureDoubaoWindow(region: OCRRegion) -> CGImage? {
        guard let target = largestDoubaoWindow() else { return nil }

        DebugLog.write("Doubao OCR: capturing window \(target.windowID) region \(region) bounds \(target.bounds)")
        guard let image = CGWindowListCreateImage(
            .null,
            .optionIncludingWindow,
            target.windowID,
            [.bestResolution, .boundsIgnoreFraming]
        ) else {
            return nil
        }

        return crop(image, region: region)
    }

    private func crop(_ image: CGImage, region: OCRRegion) -> CGImage {
        guard image.width >= 900, image.height >= 500 else {
            return image
        }

        let cropRect: CGRect
        switch region {
        case .conversation:
            cropRect = CGRect(
                x: Double(image.width) * 0.16,
                y: Double(image.height) * 0.06,
                width: Double(image.width) * 0.82,
                height: Double(image.height) * 0.88
            )
        case .answerBand:
            cropRect = CGRect(
                x: Double(image.width) * 0.16,
                y: Double(image.height) * 0.38,
                width: Double(image.width) * 0.82,
                height: Double(image.height) * 0.54
            )
        }

        return image.cropping(to: cropRect) ?? image
    }

    private func saveOCRDebugImage(_ image: CGImage, name: String) {
        let url = DebugLog.directory.appendingPathComponent(name)
        let bitmap = NSBitmapImageRep(cgImage: image)
        guard let png = bitmap.representation(using: .png, properties: [:]) else { return }
        try? png.write(to: url, options: .atomic)
    }

    private func largestDoubaoWindow() -> (bounds: CGRect, windowID: CGWindowID)? {
        let pids = Set(runningDoubaoProcesses().map(\.processIdentifier))
        guard !pids.isEmpty,
              let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return nil
        }

        let candidates: [(bounds: CGRect, windowID: CGWindowID)] = windows.compactMap { info in
            guard let pid = info[kCGWindowOwnerPID as String] as? pid_t,
                  pids.contains(pid),
                  let layer = info[kCGWindowLayer as String] as? Int,
                  layer == 0,
                  let windowNumber = info[kCGWindowNumber as String] as? UInt32,
                  let boundsDict = info[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsDict),
                  bounds.width >= 300,
                  bounds.height >= 200 else {
                return nil
            }

            return (bounds, CGWindowID(windowNumber))
        }

        guard let target = candidates.max(by: { lhs, rhs in
            lhs.bounds.width * lhs.bounds.height < rhs.bounds.width * rhs.bounds.height
        }) else {
            return nil
        }

        return target
    }

    private func nonEmptyLines(_ text: String) -> [String] {
        normalize(text)
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func deduplicatedLines(in text: String) -> String {
        var seen = Set<String>()
        let lines = normalize(text)
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .filter { line in
                if seen.contains(line) { return false }
                seen.insert(line)
                return true
            }

        return lines.joined(separator: "\n")
    }

    private func preview(_ text: String) -> String {
        let compact = normalize(text)
            .replacingOccurrences(of: "\n", with: " / ")
        return String(compact.prefix(220))
    }
}

private extension String {
    func removingCommonPrefix(with other: String) -> String {
        var index = startIndex
        var otherIndex = other.startIndex

        while index < endIndex,
              otherIndex < other.endIndex,
              self[index] == other[otherIndex] {
            formIndex(after: &index)
            other.formIndex(after: &otherIndex)
        }

        return String(self[index...])
    }
}
