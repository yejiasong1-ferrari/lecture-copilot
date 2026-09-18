import AppKit
import QuartzCore

final class FloatingAnswerWindow {
    private var panel: NSPanel?
    private let headerView = HUDDragRegion()
    private let closeButton = NSButton()
    private let iconBadge = HUDPassthroughView()
    private let actionIcon = HUDPassthroughImageView()
    private let statusDot = HUDPassthroughView()
    private let kickerLabel = HUDPassthroughLabel(text: "LECTURE COPILOT")
    private let titleLabel = HUDPassthroughLabel(text: "Answer")
    private let modeChip = HUDClickRegion()
    private let modeLabel = HUDPassthroughLabel(text: "")
    private let sessionActionChip = HUDHeaderChip()
    private let hairline = HUDPassthroughView()
    private let accentLine = HUDPassthroughView()
    private let textView = NSTextView()
    private let scrollView = NSScrollView()
    private let closeTarget = ButtonTarget()
    private var hasPositioned = false
    private var frameObserver: NSObjectProtocol?
    private var isExpanded = false
    private var collapseWork: DispatchWorkItem?
    private var isApplyingHoverLayout = false
    private var wantsHoverCollapse = false
    private var pinsExpanded = false
    private var hoverGeneration = 0
    private let confirmOverlay = HUDConfirmOverlay()
    private var currentKind = "answer"
    private var currentAction: CopilotAction?
    private var sessionSnapshot: ClassHUDSnapshot?
    private var stayOnSessionAfterClose = false
    private let actionBar = NSView()
    private let primaryActionButton = HUDPillButton()
    private let secondaryActionButton = HUDPillButton()
    private let newActionButton = HUDPillButton()
    private let chipTarget = ButtonTarget()
    private var modeChipToSessionConstraint: NSLayoutConstraint?
    private var modeChipToCloseConstraint: NSLayoutConstraint?
    private var sessionChipWidthConstraint: NSLayoutConstraint?
    private var actionBarHeightConstraint: NSLayoutConstraint?
    private var actionBarBottomConstraint: NSLayoutConstraint?
    private var scrollToActionBarConstraint: NSLayoutConstraint?
    private var newLeadingAfterPrimary: NSLayoutConstraint?
    private var newLeadingAfterSecondary: NSLayoutConstraint?
    private var actionIconFillConstraints: [NSLayoutConstraint] = []
    private var actionIconSymbolConstraints: [NSLayoutConstraint] = []
    private var expandedSize = NSSize(width: 500, height: 590)

    var onStartClass: (() -> Void)?
    var onEndClass: (() -> Void)?
    var onSummarizeClass: (() -> Void)?
    var onReviewNote: (() -> Void)?
    var onSaveNote: (() -> Void)?
    var onNewClass: (() -> Void)?
    private var headerBottomConstraint: NSLayoutConstraint?
    private var scrollBottomConstraint: NSLayoutConstraint?
    private var userHidHUD = false

    private let collapsedHeight: CGFloat = 72
    private let collapsedMinWidth: CGFloat = 268
    private let expandedMinHeight: CGFloat = 460
    private let cornerRadius: CGFloat = 24
    private let chromeInset: CGFloat = 18
    private let darkAppearance = NSAppearance(named: .darkAqua)

    deinit {
        collapseWork?.cancel()
        if let frameObserver {
            NotificationCenter.default.removeObserver(frameObserver)
        }
    }

    func showLoading(_ message: String, action: CopilotAction? = nil) {
        show(title: "Lecture Copilot", text: message, kind: "loading", action: action, expand: false)
    }

    func showAnswer(_ text: String, action: CopilotAction? = nil) {
        show(title: "Answer", text: text, kind: "answer", action: action, expand: false)
    }

    func showClassSession(_ snapshot: ClassHUDSnapshot, detail: String? = nil) {
        sessionSnapshot = snapshot
        stayOnSessionAfterClose = snapshot.phase == .running
            || snapshot.phase == .ended
            || snapshot.phase == .summarizing
            || snapshot.phase == .summaryReady
        let expand = snapshot.phase == .ended
            || snapshot.phase == .summaryReady
            || snapshot.phase == .summarizing
            || snapshot.phase == .saved
        let action: CopilotAction? = (
            snapshot.phase == .ended
                || snapshot.phase == .summaryReady
                || snapshot.phase == .summarizing
                || snapshot.phase == .saved
        ) ? .classSummary : nil
        show(
            title: sessionTitle(snapshot),
            text: detail ?? sessionBody(snapshot),
            kind: sessionKind(snapshot),
            action: action,
            expand: expand
        )
    }

    func tickClassSession(_ snapshot: ClassHUDSnapshot) {
        sessionSnapshot = snapshot
        guard let panel, panel.isVisible else { return }
        if currentKind == "session", snapshot.phase == .running {
            titleLabel.stringValue = ClassHUDSnapshot.durationText(snapshot.elapsed)
            modeLabel.stringValue = noteChipTitle(snapshot.interactionCount)
            updateSessionActionButton()
            if isExpanded {
                render(sessionBody(snapshot), kind: "session", action: nil)
            }
            return
        }
        if snapshot.phase == .running {
            updateSessionActionButton()
            if currentKind == "answer" || currentKind == "loading" {
                kickerLabel.stringValue = "CLASS · \(ClassHUDSnapshot.durationText(snapshot.elapsed))"
            }
        }
    }

    func close() {
        collapseWork?.cancel()
        dismissConfirm()
        setDotPulsing(false)
        if stayOnSessionAfterClose,
           let sessionSnapshot,
           currentKind == "answer" || currentKind == "loading" {
            showClassSession(sessionSnapshot)
            return
        }
        panel?.orderOut(nil)
        hasPositioned = false
        isExpanded = false
    }

    var isHiddenByUser: Bool { userHidHUD }
    var hasPanel: Bool { panel != nil }
    var isPanelVisible: Bool { panel?.isVisible == true }

    func confirm(
        title: String,
        message: String,
        confirmTitle: String,
        onConfirm: @escaping () -> Void
    ) {
        if panel == nil {
            buildPanel()
        }
        pinsExpanded = true
        collapseWork?.cancel()
        wantsHoverCollapse = false
        panel?.ignoresMouseEvents = false
        applyExpanded(true, animated: true)
        panel?.orderFrontRegardless()
        confirmOverlay.present(
            title: title,
            message: message,
            confirmTitle: confirmTitle,
            style: .accent,
            onConfirm: { [weak self] in
                self?.dismissConfirm()
                onConfirm()
            },
            onCancel: { [weak self] in
                self?.dismissConfirm()
            }
        )
    }

    func presentSavePanel(_ savePanel: NSSavePanel, completion: @escaping (URL?) -> Void) {
        guard let host = panel else {
            savePanel.begin { response in
                completion(response == .OK ? savePanel.url : nil)
            }
            return
        }

        pinsExpanded = true
        collapseWork?.cancel()
        wantsHoverCollapse = false
        host.ignoresMouseEvents = false
        applyExpanded(true, animated: true)
        host.orderFrontRegardless()

        savePanel.beginSheetModal(for: host) { [weak self] response in
            self?.pinsExpanded = false
            completion(response == .OK ? savePanel.url : nil)
        }
        DispatchQueue.main.async { [weak self] in
            self?.keepAccessoryWindowsWithHUD(host)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self] in
            self?.keepAccessoryWindowsWithHUD(host)
        }
    }

    private func keepAccessoryWindowsWithHUD(_ host: NSWindow) {
        for window in NSApp.windows where window !== host {
            let isAccessory = window.parent === host
                || window.isSheet
                || window.level >= .modalPanel
                || window is NSSavePanel
            guard isAccessory, window.isVisible else { continue }
            window.collectionBehavior.insert(.canJoinAllSpaces)
            window.collectionBehavior.insert(.fullScreenAuxiliary)
            window.level = NSWindow.Level(rawValue: host.level.rawValue + 4)
            var frame = window.frame
            frame.origin.x = host.frame.midX - frame.width / 2
            frame.origin.y = host.frame.midY - frame.height / 2
            if let visible = host.screen?.visibleFrame ?? NSScreen.main?.visibleFrame {
                frame.origin.x = min(max(frame.origin.x, visible.minX + 12), visible.maxX - frame.width - 12)
                frame.origin.y = min(max(frame.origin.y, visible.minY + 12), visible.maxY - frame.height - 12)
            }
            window.setFrame(frame, display: true)
            window.orderFrontRegardless()
            window.makeKeyAndOrderFront(nil)
        }
    }

    private func dismissConfirm() {
        confirmOverlay.dismiss()
        pinsExpanded = false
        panel?.ignoresMouseEvents = false
        if !isMouseOverHUD(), isExpanded {
            wantsHoverCollapse = true
            scheduleCollapseIfNeeded()
        }
    }

    func toggleHiddenByUser() {
        setHiddenByUser(!userHidHUD)
    }

    func setHiddenByUser(_ hidden: Bool) {
        userHidHUD = hidden
        if hidden {
            dismissConfirm()
            panel?.orderOut(nil)
            DebugLog.write("HUD hidden by double-shift")
        } else if let panel {
            if !hasPositioned {
                position(panel)
            }
            panel.ignoresMouseEvents = false
            panel.orderFrontRegardless()
            DebugLog.write("HUD shown by double-shift")
        }
    }

    private func show(title: String, text: String, kind: String, action: CopilotAction?, expand: Bool) {
        if panel == nil {
            buildPanel()
        }

        currentKind = kind
        currentAction = action
        guard let panel else { return }
        if !confirmOverlay.isHidden {
            dismissConfirm()
        }
        panel.ignoresMouseEvents = false
        panel.title = title
        configurePresentation(kind: kind, action: action)
        configureActionBar(kind: kind)
        updateSessionActionButton()
        render(text, kind: kind, action: action)

        if !panel.isVisible || !hasPositioned {
            position(panel)
        }
        applyExpanded(expand || isMouseOverHUD(), animated: false)
        if userHidHUD {
            panel.orderOut(nil)
        } else {
            panel.orderFrontRegardless()
            reconcileHoverState()
        }
        textView.scrollToBeginningOfDocument(nil)
        LastOutputStore.save(kind: kind, action: action, title: title, text: text, panel: panel)
    }

    private func configurePresentation(kind: String, action: CopilotAction?) {
        let accent = accentColor(kind: kind, action: action)
        let isLoading = kind == "loading" || kind == "summary-loading"

        if kind == "session", let sessionSnapshot {
            kickerLabel.stringValue = sessionSnapshot.phase == .idle ? "LECTURE COPILOT" : "CLASS SESSION"
            titleLabel.stringValue = sessionTitle(sessionSnapshot)
            modeLabel.stringValue = sessionSnapshot.phase == .running || sessionSnapshot.phase == .ended
                ? noteChipTitle(sessionSnapshot.interactionCount)
                : sessionChipTitle(sessionSnapshot)
        } else if kind == "summary" || kind == "summary-loading" {
            kickerLabel.stringValue = "CLASS SESSION"
            titleLabel.stringValue = kind == "summary-loading" ? "Summarizing" : "Class Summary"
            modeLabel.stringValue = action?.chipTitle ?? "Summary"
        } else {
            kickerLabel.stringValue = sessionSnapshot?.phase == .running
                ? "CLASS · \(ClassHUDSnapshot.durationText(sessionSnapshot?.elapsed ?? 0))"
                : "LECTURE COPILOT"
            titleLabel.stringValue = isLoading && kind != "summary-loading" ? "Working" : "Answer"
            modeLabel.stringValue = action?.chipTitle ?? (isLoading ? "Sending" : "Ready")
        }

        statusDot.layer?.backgroundColor = accent.cgColor
        statusDot.layer?.shadowColor = accent.cgColor
        statusDot.layer?.shadowRadius = 6
        statusDot.layer?.shadowOpacity = 0.85
        statusDot.layer?.shadowOffset = .zero

        iconBadge.layer?.backgroundColor = accent.withAlphaComponent(0.14).cgColor
        iconBadge.layer?.borderColor = accent.withAlphaComponent(0.32).cgColor
        let showBrandLogo = kind == "session" || kind == "summary" || kind == "summary-loading"
        if showBrandLogo, let logo = BrandImage.hudLogo() {
            actionIcon.image = logo
            actionIcon.contentTintColor = nil
            actionIcon.imageScaling = .scaleProportionallyUpOrDown
            NSLayoutConstraint.deactivate(actionIconSymbolConstraints)
            NSLayoutConstraint.activate(actionIconFillConstraints)
            iconBadge.layer?.backgroundColor = NSColor.white.cgColor
            iconBadge.layer?.borderColor = NSColor.white.withAlphaComponent(0.35).cgColor
        } else {
            actionIcon.image = NSImage(
                systemSymbolName: actionSymbol(kind: kind, action: action),
                accessibilityDescription: modeLabel.stringValue
            )
            actionIcon.contentTintColor = accent.blended(withFraction: 0.16, of: .white) ?? accent
            actionIcon.imageScaling = .scaleProportionallyDown
            NSLayoutConstraint.deactivate(actionIconFillConstraints)
            NSLayoutConstraint.activate(actionIconSymbolConstraints)
        }

        modeChip.layer?.backgroundColor = accent.withAlphaComponent(0.12).cgColor
        modeChip.layer?.borderColor = accent.withAlphaComponent(0.38).cgColor
        modeLabel.textColor = accent.blended(withFraction: 0.2, of: .white) ?? accent
        accentLine.layer?.backgroundColor = accent.withAlphaComponent(0.72).cgColor
        accentLine.layer?.shadowColor = accent.cgColor
        accentLine.layer?.shadowOpacity = 0.45
        accentLine.layer?.shadowRadius = 5
        accentLine.layer?.shadowOffset = .zero
        hairline.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.09).cgColor

        setDotPulsing(isLoading || (kind == "session" && sessionSnapshot?.phase == .running))
    }

    private func render(_ text: String, kind: String, action: CopilotAction?) {
        textView.textStorage?.setAttributedString(styledAnswer(text, kind: kind, action: action))
        updateTextViewWidth()
    }

    private func styledAnswer(_ text: String, kind: String, action: CopilotAction?) -> NSAttributedString {
        let lines = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .components(separatedBy: "\n")
        let result = NSMutableAttributedString()

        if kind == "loading" || kind == "session" || kind == "summary-loading" {
            result.append(lineString(text, font: .systemFont(ofSize: 15, weight: .regular), color: GlassPalette.muted, spacing: 6, paragraphSpacing: 8))
            return result
        }

        for (index, raw) in lines.enumerated() {
            let trimmed = raw.trimmingCharacters(in: .whitespaces)
            let markdownHeading = trimmed.range(of: #"^#{1,6}\s+"#, options: .regularExpression) != nil
            let line = displayLine(trimmed)
            if line.isEmpty {
                result.append(NSAttributedString(string: "\n"))
                continue
            }

            let heading = markdownHeading || isHeadingLine(line)
            let chinese = isMostlyChinese(line)
            let font: NSFont
            let color: NSColor
            let spacing: CGFloat
            let paragraphSpacing: CGFloat

            if heading {
                font = .systemFont(ofSize: 13.5, weight: .semibold)
                color = accentColor(kind: kind, action: action).blended(withFraction: 0.2, of: .white) ?? GlassPalette.title
                spacing = 2
                paragraphSpacing = 8
            } else if action == .translate, chinese {
                font = .systemFont(ofSize: 14.5, weight: .regular)
                color = GlassPalette.muted
                spacing = 4
                paragraphSpacing = 16
            } else if action == .translate {
                font = .systemFont(ofSize: 15.5, weight: .medium)
                color = GlassPalette.body
                spacing = 3
                paragraphSpacing = 5
            } else if action == .sayInClass, !chinese {
                font = .systemFont(ofSize: 16, weight: .medium)
                color = GlassPalette.body
                spacing = 4
                paragraphSpacing = 10
            } else {
                font = .systemFont(ofSize: 15, weight: heading ? .semibold : .regular)
                color = chinese ? GlassPalette.muted : GlassPalette.body
                spacing = 3
                paragraphSpacing = 10
            }

            result.append(lineString(line, font: font, color: color, spacing: spacing, paragraphSpacing: paragraphSpacing))
            if index < lines.count - 1 {
                result.append(NSAttributedString(string: "\n"))
            }
        }

        return result
    }

    private func displayLine(_ line: String) -> String {
        line.replacingOccurrences(
            of: #"^\s{0,3}#{1,6}\s*"#,
            with: "",
            options: .regularExpression
        )
    }

    private func lineString(
        _ text: String,
        font: NSFont,
        color: NSColor,
        spacing: CGFloat,
        paragraphSpacing: CGFloat
    ) -> NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = spacing
        paragraph.paragraphSpacing = paragraphSpacing
        paragraph.lineBreakMode = .byWordWrapping
        return NSAttributedString(string: text, attributes: [
            .font: font,
            .foregroundColor: color,
            .paragraphStyle: paragraph,
            .kern: 0.15
        ])
    }

    private func isHeadingLine(_ line: String) -> Bool {
        let compact = displayLine(line).replacingOccurrences(of: " ", with: "")
        return [
            "解答", "核心", "结构", "关系", "最重要的一句话", "答案", "原因", "其他选项",
            "你可以很口语地回答", "这页真正意思",
            "Class Summary", "Key Concepts", "Important Questions",
            "Things I Got Wrong", "Useful In-Class Answers", "Review Checklist"
        ].contains { compact.hasPrefix($0) }
    }

    private func actionSymbol(kind: String, action: CopilotAction?) -> String {
        if kind == "loading" || kind == "summary-loading" {
            return "arrow.triangle.2.circlepath"
        }
        if kind == "session" { return "waveform" }
        switch action {
        case .translate: return "character.book.closed.fill"
        case .explain: return "lightbulb.max.fill"
        case .directAnswer: return "checkmark.seal.fill"
        case .sayInClass: return "quote.bubble.fill"
        case .classSummary: return "doc.text.fill"
        default: return "sparkles"
        }
    }

    private func isMostlyChinese(_ line: String) -> Bool {
        let chinese = line.unicodeScalars.filter { $0.value >= 0x4E00 && $0.value <= 0x9FFF }.count
        let latin = line.unicodeScalars.filter { CharacterSet.letters.contains($0) && $0.value < 0x80 }.count
        if let first = line.unicodeScalars.first(where: {
            CharacterSet.letters.contains($0) || ($0.value >= 0x4E00 && $0.value <= 0x9FFF)
        }), first.value >= 0x4E00, first.value <= 0x9FFF {
            return true
        }
        return chinese >= 2 && chinese >= latin
    }

    private func updateTextViewWidth() {
        let width = max(scrollView.contentView.bounds.width, 1)
        textView.minSize = NSSize(width: width, height: 0)
        textView.maxSize = NSSize(width: width, height: CGFloat.greatestFiniteMagnitude)
        textView.frame.size.width = width
        textView.textContainer?.containerSize = NSSize(width: width, height: .greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true
    }

    private func windowSize(cardWidth: CGFloat, cardHeight: CGFloat) -> NSSize {
        NSSize(
            width: cardWidth + chromeInset * 2,
            height: cardHeight + chromeInset * 2
        )
    }

    private func buildPanel() {
        let initial = windowSize(cardWidth: collapsedMinWidth, cardHeight: collapsedHeight)
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: initial),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.title = "Lecture Copilot"
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.isMovable = true
        panel.isMovableByWindowBackground = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.acceptsMouseMovedEvents = true
        panel.ignoresMouseEvents = false
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.appearance = darkAppearance
        panel.animationBehavior = .utilityWindow
        panel.minSize = windowSize(cardWidth: 320, cardHeight: collapsedHeight)

        let root = ClearRootView(frame: NSRect(origin: .zero, size: initial))
        root.cornerRadius = cornerRadius
        panel.contentView = root

        let shadowHost = ShadowHostView(frame: .zero)
        shadowHost.cornerRadius = cornerRadius
        shadowHost.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(shadowHost)
        root.cardView = shadowHost

        let content = HoverView(frame: .zero)
        content.cornerRadius = cornerRadius
        content.material = .hudWindow
        content.blendingMode = .behindWindow
        content.state = .active
        content.appearance = darkAppearance
        content.translatesAutoresizingMaskIntoConstraints = false
        content.onHoverChange = { [weak self] hovering in
            self?.handleHover(hovering)
        }
        shadowHost.addSubview(content)

        let glassTint = PassthroughOverlay()
        glassTint.wantsLayer = true
        glassTint.layer?.backgroundColor = NSColor(calibratedWhite: 0.025, alpha: 0.48).cgColor
        glassTint.translatesAutoresizingMaskIntoConstraints = false

        let glassBorder = PassthroughOverlay()
        glassBorder.wantsLayer = true
        glassBorder.layer?.backgroundColor = NSColor.clear.cgColor
        glassBorder.layer?.borderWidth = 1
        glassBorder.layer?.borderColor = NSColor.white.withAlphaComponent(0.18).cgColor
        glassBorder.layer?.cornerRadius = cornerRadius
        glassBorder.layer?.cornerCurve = .continuous
        glassBorder.layer?.masksToBounds = true
        glassBorder.translatesAutoresizingMaskIntoConstraints = false

        headerView.wantsLayer = true
        headerView.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.025).cgColor
        headerView.translatesAutoresizingMaskIntoConstraints = false

        closeButton.bezelStyle = .inline
        closeButton.isBordered = false
        closeButton.wantsLayer = true
        closeButton.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.07).cgColor
        closeButton.layer?.cornerRadius = 9
        closeButton.layer?.cornerCurve = .continuous
        closeButton.image = NSImage(systemSymbolName: "xmark", accessibilityDescription: "Close")
        closeButton.imagePosition = .imageOnly
        closeButton.contentTintColor = GlassPalette.dim
        closeButton.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 9, weight: .semibold)
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        closeTarget.onTap = { [weak self] in self?.close() }
        closeButton.target = closeTarget
        closeButton.action = #selector(ButtonTarget.tap)

        iconBadge.wantsLayer = true
        iconBadge.layer?.cornerRadius = 15
        iconBadge.layer?.cornerCurve = .continuous
        iconBadge.layer?.borderWidth = 1
        iconBadge.layer?.masksToBounds = true
        iconBadge.translatesAutoresizingMaskIntoConstraints = false

        actionIcon.imageScaling = .scaleProportionallyUpOrDown
        actionIcon.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)
        actionIcon.translatesAutoresizingMaskIntoConstraints = false

        statusDot.wantsLayer = true
        statusDot.layer?.cornerRadius = 3.5
        statusDot.layer?.borderWidth = 1.5
        statusDot.layer?.borderColor = NSColor(calibratedWhite: 0.08, alpha: 0.9).cgColor
        statusDot.translatesAutoresizingMaskIntoConstraints = false

        kickerLabel.font = .monospacedSystemFont(ofSize: 9, weight: .medium)
        kickerLabel.textColor = GlassPalette.kicker
        kickerLabel.cell?.lineBreakMode = .byTruncatingTail
        kickerLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        kickerLabel.translatesAutoresizingMaskIntoConstraints = false

        titleLabel.font = .systemFont(ofSize: 15.5, weight: .semibold)
        titleLabel.textColor = GlassPalette.title
        titleLabel.cell?.lineBreakMode = .byTruncatingTail
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        modeChip.wantsLayer = true
        modeChip.layer?.cornerRadius = 11
        modeChip.layer?.cornerCurve = .continuous
        modeChip.layer?.borderWidth = 1
        modeChip.setContentCompressionResistancePriority(.required, for: .horizontal)
        modeChip.setContentHuggingPriority(.required, for: .horizontal)
        modeChip.translatesAutoresizingMaskIntoConstraints = false

        modeLabel.font = .systemFont(ofSize: 10.5, weight: .semibold)
        modeLabel.alignment = .center
        modeLabel.translatesAutoresizingMaskIntoConstraints = false

        sessionActionChip.onTap = { [weak self] in self?.handleSessionActionTap() }

        hairline.wantsLayer = true
        hairline.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.16).cgColor
        hairline.translatesAutoresizingMaskIntoConstraints = false

        accentLine.wantsLayer = true
        accentLine.layer?.cornerRadius = 1
        accentLine.translatesAutoresizingMaskIntoConstraints = false

        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.isRichText = true
        textView.font = .systemFont(ofSize: 15)
        textView.textColor = GlassPalette.body
        textView.appearance = darkAppearance
        textView.textContainerInset = NSSize(width: 18, height: 18)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.heightTracksTextView = false
        textView.textContainer?.lineFragmentPadding = 4
        textView.layoutManager?.allowsNonContiguousLayout = true
        textView.isContinuousSpellCheckingEnabled = false
        textView.isGrammarCheckingEnabled = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticLinkDetectionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false

        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.scrollerKnobStyle = .light
        scrollView.usesPredominantAxisScrolling = true
        scrollView.drawsBackground = false
        scrollView.wantsLayer = true
        scrollView.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.13).cgColor
        scrollView.layer?.borderColor = NSColor.white.withAlphaComponent(0.07).cgColor
        scrollView.layer?.borderWidth = 1
        scrollView.layer?.cornerRadius = 16
        scrollView.layer?.cornerCurve = .continuous
        scrollView.layer?.masksToBounds = true
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.postsFrameChangedNotifications = true

        actionBar.wantsLayer = true
        actionBar.translatesAutoresizingMaskIntoConstraints = false
        primaryActionButton.onTap = { [weak self] in self?.handlePrimaryAction() }
        secondaryActionButton.onTap = { [weak self] in self?.handleSecondaryAction() }
        newActionButton.onTap = { [weak self] in self?.handleNewAction() }
        actionBar.addSubview(primaryActionButton)
        actionBar.addSubview(secondaryActionButton)
        actionBar.addSubview(newActionButton)

        chipTarget.onTap = { [weak self] in self?.handleChipTap() }
        let chipClick = NSClickGestureRecognizer(target: chipTarget, action: #selector(ButtonTarget.tap))
        modeChip.addGestureRecognizer(chipClick)

        content.addSubview(glassTint)
        content.addSubview(headerView)
        headerView.addSubview(iconBadge)
        iconBadge.addSubview(actionIcon)
        headerView.addSubview(statusDot)
        headerView.addSubview(closeButton)
        headerView.addSubview(kickerLabel)
        headerView.addSubview(titleLabel)
        headerView.addSubview(modeChip)
        modeChip.addSubview(modeLabel)
        headerView.addSubview(sessionActionChip)
        content.addSubview(hairline)
        content.addSubview(accentLine)
        content.addSubview(scrollView)
        content.addSubview(actionBar)
        content.addSubview(glassBorder)
        content.addSubview(confirmOverlay)
        confirmOverlay.translatesAutoresizingMaskIntoConstraints = false
        confirmOverlay.isHidden = true

        let headerBottom = headerView.bottomAnchor.constraint(equalTo: content.bottomAnchor)
        let scrollBottom = scrollView.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -14)
        let actionBarHeight = actionBar.heightAnchor.constraint(equalToConstant: 0)
        let actionBarBottom = actionBar.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -12)
        let scrollToActionBar = scrollView.bottomAnchor.constraint(equalTo: actionBar.topAnchor, constant: -8)
        headerBottomConstraint = headerBottom
        scrollBottomConstraint = scrollBottom
        actionBarHeightConstraint = actionBarHeight
        actionBarBottomConstraint = actionBarBottom
        scrollToActionBarConstraint = scrollToActionBar

        NSLayoutConstraint.activate([
            shadowHost.topAnchor.constraint(equalTo: root.topAnchor, constant: chromeInset),
            shadowHost.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: chromeInset),
            shadowHost.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -chromeInset),
            shadowHost.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -chromeInset),

            content.topAnchor.constraint(equalTo: shadowHost.topAnchor),
            content.leadingAnchor.constraint(equalTo: shadowHost.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: shadowHost.trailingAnchor),
            content.bottomAnchor.constraint(equalTo: shadowHost.bottomAnchor),

            glassTint.topAnchor.constraint(equalTo: content.topAnchor),
            glassTint.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            glassTint.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            glassTint.bottomAnchor.constraint(equalTo: content.bottomAnchor),

            glassBorder.topAnchor.constraint(equalTo: content.topAnchor),
            glassBorder.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            glassBorder.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            glassBorder.bottomAnchor.constraint(equalTo: content.bottomAnchor),

            headerView.topAnchor.constraint(equalTo: content.topAnchor),
            headerView.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            headerView.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            headerView.heightAnchor.constraint(equalToConstant: collapsedHeight),
            headerBottom,

            iconBadge.centerYAnchor.constraint(equalTo: headerView.centerYAnchor),
            iconBadge.leadingAnchor.constraint(equalTo: headerView.leadingAnchor, constant: 16),
            iconBadge.widthAnchor.constraint(equalToConstant: 38),
            iconBadge.heightAnchor.constraint(equalToConstant: 38),

            statusDot.trailingAnchor.constraint(equalTo: iconBadge.trailingAnchor, constant: 2),
            statusDot.bottomAnchor.constraint(equalTo: iconBadge.bottomAnchor, constant: 2),
            statusDot.widthAnchor.constraint(equalToConstant: 7),
            statusDot.heightAnchor.constraint(equalToConstant: 7),

            closeButton.centerYAnchor.constraint(equalTo: headerView.centerYAnchor),
            closeButton.trailingAnchor.constraint(equalTo: headerView.trailingAnchor, constant: -14),
            closeButton.widthAnchor.constraint(equalToConstant: 28),
            closeButton.heightAnchor.constraint(equalToConstant: 28),

            kickerLabel.topAnchor.constraint(equalTo: headerView.topAnchor, constant: 16),
            kickerLabel.leadingAnchor.constraint(equalTo: iconBadge.trailingAnchor, constant: 12),
            kickerLabel.trailingAnchor.constraint(lessThanOrEqualTo: sessionActionChip.leadingAnchor, constant: -12),

            titleLabel.topAnchor.constraint(equalTo: kickerLabel.bottomAnchor, constant: 2),
            titleLabel.leadingAnchor.constraint(equalTo: kickerLabel.leadingAnchor),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: sessionActionChip.leadingAnchor, constant: -12),
            titleLabel.bottomAnchor.constraint(lessThanOrEqualTo: headerView.bottomAnchor, constant: -10),

            modeChip.centerYAnchor.constraint(equalTo: headerView.centerYAnchor),
            modeChip.heightAnchor.constraint(equalToConstant: 24),

            modeLabel.leadingAnchor.constraint(equalTo: modeChip.leadingAnchor, constant: 10),
            modeLabel.trailingAnchor.constraint(equalTo: modeChip.trailingAnchor, constant: -10),
            modeLabel.centerYAnchor.constraint(equalTo: modeChip.centerYAnchor),

            sessionActionChip.centerYAnchor.constraint(equalTo: headerView.centerYAnchor),
            sessionActionChip.trailingAnchor.constraint(equalTo: closeButton.leadingAnchor, constant: -9),
            sessionActionChip.heightAnchor.constraint(equalToConstant: 24),

            hairline.topAnchor.constraint(equalTo: headerView.bottomAnchor),
            hairline.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 16),
            hairline.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -16),
            hairline.heightAnchor.constraint(equalToConstant: 1),

            accentLine.topAnchor.constraint(equalTo: content.topAnchor),
            accentLine.centerXAnchor.constraint(equalTo: content.centerXAnchor),
            accentLine.widthAnchor.constraint(equalToConstant: 72),
            accentLine.heightAnchor.constraint(equalToConstant: 2),

            scrollView.topAnchor.constraint(equalTo: hairline.bottomAnchor, constant: 12),
            scrollView.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 14),
            scrollView.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -14),

            actionBar.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 18),
            actionBar.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -18),
            actionBarHeight,

            primaryActionButton.leadingAnchor.constraint(equalTo: actionBar.leadingAnchor),
            primaryActionButton.centerYAnchor.constraint(equalTo: actionBar.centerYAnchor),
            primaryActionButton.heightAnchor.constraint(equalToConstant: HUDPillButton.height),

            secondaryActionButton.leadingAnchor.constraint(equalTo: primaryActionButton.trailingAnchor, constant: 8),
            secondaryActionButton.centerYAnchor.constraint(equalTo: actionBar.centerYAnchor),
            secondaryActionButton.heightAnchor.constraint(equalToConstant: HUDPillButton.height),

            newActionButton.centerYAnchor.constraint(equalTo: actionBar.centerYAnchor),
            newActionButton.heightAnchor.constraint(equalToConstant: HUDPillButton.height),
            newActionButton.trailingAnchor.constraint(lessThanOrEqualTo: actionBar.trailingAnchor),

            confirmOverlay.topAnchor.constraint(equalTo: content.topAnchor),
            confirmOverlay.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            confirmOverlay.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            confirmOverlay.bottomAnchor.constraint(equalTo: content.bottomAnchor)
        ])

        modeChipToSessionConstraint = modeChip.trailingAnchor.constraint(equalTo: sessionActionChip.leadingAnchor, constant: -8)
        modeChipToCloseConstraint = modeChip.trailingAnchor.constraint(equalTo: closeButton.leadingAnchor, constant: -9)
        sessionChipWidthConstraint = sessionActionChip.widthAnchor.constraint(equalToConstant: 0)
        newLeadingAfterPrimary = newActionButton.leadingAnchor.constraint(equalTo: primaryActionButton.trailingAnchor, constant: 8)
        newLeadingAfterSecondary = newActionButton.leadingAnchor.constraint(equalTo: secondaryActionButton.trailingAnchor, constant: 8)
        newLeadingAfterSecondary?.isActive = true
        modeChipToSessionConstraint?.isActive = true

        actionIconFillConstraints = [
            actionIcon.leadingAnchor.constraint(equalTo: iconBadge.leadingAnchor),
            actionIcon.trailingAnchor.constraint(equalTo: iconBadge.trailingAnchor),
            actionIcon.topAnchor.constraint(equalTo: iconBadge.topAnchor),
            actionIcon.bottomAnchor.constraint(equalTo: iconBadge.bottomAnchor)
        ]
        actionIconSymbolConstraints = [
            actionIcon.centerXAnchor.constraint(equalTo: iconBadge.centerXAnchor),
            actionIcon.centerYAnchor.constraint(equalTo: iconBadge.centerYAnchor),
            actionIcon.widthAnchor.constraint(equalToConstant: 20),
            actionIcon.heightAnchor.constraint(equalToConstant: 20)
        ]
        NSLayoutConstraint.activate(actionIconFillConstraints)

        frameObserver = NotificationCenter.default.addObserver(
            forName: NSView.frameDidChangeNotification,
            object: scrollView,
            queue: .main
        ) { [weak self] _ in
            self?.updateTextViewWidth()
        }

        self.panel = panel
    }

    private func configureActionBar(kind: String) {
        primaryActionButton.isHidden = true
        secondaryActionButton.isHidden = true
        newActionButton.isHidden = true
        actionBarHeightConstraint?.constant = 0

        switch kind {
        case "summary":
            primaryActionButton.apply(title: "Review Note", style: .primary)
            secondaryActionButton.apply(title: "Save", style: .save)
            newActionButton.apply(title: "New", style: .accent)
            primaryActionButton.isHidden = false
            secondaryActionButton.isHidden = false
            newActionButton.isHidden = false
            actionBarHeightConstraint?.constant = 48
        case "session" where sessionSnapshot?.phase == .ended:
            primaryActionButton.apply(title: "Summary", style: .primary)
            newActionButton.apply(title: "New", style: .accent)
            primaryActionButton.isHidden = false
            newActionButton.isHidden = false
            actionBarHeightConstraint?.constant = 48
        default:
            break
        }
        newLeadingAfterSecondary?.isActive = !secondaryActionButton.isHidden
        newLeadingAfterPrimary?.isActive = secondaryActionButton.isHidden
        actionBar.isHidden = actionBarHeightConstraint?.constant == 0
    }

    private func updateSessionActionButton() {
        let phase = sessionSnapshot?.phase
        let showStart = phase == .idle && currentKind == "session"
        let showEnd = phase == .running
        let showSummary = phase == .ended
        let showRecord = phase == .summaryReady || phase == .saved || currentKind == "summary"
        let visible = showStart || showEnd || showSummary || showRecord

        sessionActionChip.isHidden = !visible
        modeChip.isHidden = showStart
        sessionChipWidthConstraint?.isActive = !visible
        modeChipToSessionConstraint?.isActive = visible && !showStart
        modeChipToCloseConstraint?.isActive = !visible

        guard visible else { return }

        if showEnd {
            sessionActionChip.apply(title: "End", accent: NSColor(calibratedRed: 1.0, green: 0.45, blue: 0.42, alpha: 1))
        } else if showSummary || showRecord {
            sessionActionChip.apply(
                title: showRecord ? "Save" : "Summary",
                accent: NSColor(calibratedRed: 0.95, green: 0.78, blue: 0.38, alpha: 1)
            )
        } else {
            sessionActionChip.apply(title: "Start", accent: NSColor(calibratedRed: 0.42, green: 0.86, blue: 0.68, alpha: 1))
        }
    }

    private func handleSessionActionTap() {
        let phase = sessionSnapshot?.phase
        if phase == .running {
            onEndClass?()
        } else if phase == .idle {
            onStartClass?()
        } else if phase == .ended {
            onSummarizeClass?()
        } else if phase == .summaryReady || phase == .saved || currentKind == "summary" {
            onSaveNote?()
        }
    }

    private func handleChipTap() {
        // Mode chip is informational. Start / End live on the header session button.
    }

    private func handlePrimaryAction() {
        if currentKind == "summary" {
            onReviewNote?()
        } else if sessionSnapshot?.phase == .ended {
            onSummarizeClass?()
        }
    }

    private func handleSecondaryAction() {
        if currentKind == "summary" {
            onSaveNote?()
        }
    }

    private func handleNewAction() {
        if currentKind == "summary" || sessionSnapshot?.phase == .ended {
            onNewClass?()
        }
    }

    private func sessionKind(_ snapshot: ClassHUDSnapshot) -> String {
        switch snapshot.phase {
        case .idle, .running, .ended:
            return "session"
        case .summarizing:
            return "summary-loading"
        case .summaryReady, .saved:
            return "summary"
        }
    }

    private func sessionTitle(_ snapshot: ClassHUDSnapshot) -> String {
        switch snapshot.phase {
        case .idle:
            return "Start Class"
        case .running:
            return ClassHUDSnapshot.durationText(snapshot.elapsed)
        case .ended:
            return "Class Ended"
        case .summarizing:
            return "Summarizing"
        case .summaryReady:
            return "Class Summary"
        case .saved:
            return "Saved"
        }
    }

    private func sessionChipTitle(_ snapshot: ClassHUDSnapshot) -> String {
        switch snapshot.phase {
        case .idle:
            return "Start"
        case .running:
            return "End Class"
        case .ended:
            return "Summary"
        case .summarizing:
            return "Wait"
        case .summaryReady:
            return "Ready"
        case .saved:
            return "Saved"
        }
    }

    private func noteChipTitle(_ count: Int) -> String {
        count == 1 ? "1 Note" : "\(count) Notes"
    }

    private func sessionBody(_ snapshot: ClassHUDSnapshot) -> String {
        switch snapshot.phase {
        case .idle:
            return "开始上课后，Explain / Direct Answer / Say in Class 会自动记进这节课。\n\nTranslate 默认不记，可在菜单里打开。"
        case .running:
            return """
            \(snapshot.title)
            Start: \(snapshot.startClock)
            Duration: \(ClassHUDSnapshot.durationText(snapshot.elapsed))

            \(snapshot.interactionCount) interactions saved
            """
        case .ended:
            return """
            这节课已结束。

            点 Summary 才发给豆包做总结。
            不想总结就点 New 开新课。
            """
        case .summarizing:
            return "正在把这节课的记录发给豆包做总结。生成完成后会显示在这里。"
        case .summaryReady:
            return "Class summary ready"
        case .saved:
            return "笔记已保存。"
        }
    }

    private func accentColor(kind: String, action: CopilotAction?) -> NSColor {
        if kind == "loading" || kind == "summary-loading" {
            return NSColor(calibratedRed: 1.0, green: 0.68, blue: 0.32, alpha: 1)
        }
        if kind == "session" {
            return NSColor(calibratedRed: 0.52, green: 0.72, blue: 1.0, alpha: 1)
        }
        switch action {
        case .translate:
            return NSColor(calibratedRed: 0.42, green: 0.86, blue: 0.68, alpha: 1)
        case .explain:
            return NSColor(calibratedRed: 0.52, green: 0.72, blue: 1.0, alpha: 1)
        case .directAnswer:
            return NSColor(calibratedRed: 1.0, green: 0.62, blue: 0.32, alpha: 1)
        case .sayInClass:
            return NSColor(calibratedRed: 0.78, green: 0.62, blue: 1.0, alpha: 1)
        case .classSummary:
            return NSColor(calibratedRed: 0.95, green: 0.78, blue: 0.38, alpha: 1)
        default:
            return NSColor(calibratedRed: 0.42, green: 0.86, blue: 0.68, alpha: 1)
        }
    }

    private func setDotPulsing(_ pulsing: Bool) {
        statusDot.layer?.removeAnimation(forKey: "pulse")
        guard pulsing else {
            statusDot.layer?.opacity = 1
            return
        }
        let animation = CABasicAnimation(keyPath: "opacity")
        animation.fromValue = 1
        animation.toValue = 0.28
        animation.duration = 0.85
        animation.autoreverses = true
        animation.repeatCount = .infinity
        animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        statusDot.layer?.add(animation, forKey: "pulse")
    }

    private func handleHover(_ hovering: Bool) {
        if pinsExpanded {
            return
        }
        if hovering {
            wantsHoverCollapse = false
            collapseWork?.cancel()
            applyExpanded(true, animated: true)
            return
        }

        wantsHoverCollapse = true
        scheduleCollapseIfNeeded()
    }

    private func scheduleCollapseIfNeeded() {
        if pinsExpanded { return }
        collapseWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            if self.pinsExpanded { return }
            if NSEvent.pressedMouseButtons != 0 {
                self.scheduleCollapseIfNeeded()
                return
            }
            if self.isMouseOverHUD() {
                self.wantsHoverCollapse = false
                if !self.isExpanded {
                    self.applyExpanded(true, animated: true)
                }
                return
            }
            guard self.wantsHoverCollapse, self.isExpanded else { return }
            self.wantsHoverCollapse = false
            self.applyExpanded(false, animated: true)
        }
        collapseWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12, execute: work)
    }

    private func reconcileHoverState() {
        if pinsExpanded { return }
        if isMouseOverHUD() {
            wantsHoverCollapse = false
            collapseWork?.cancel()
            if !isExpanded {
                applyExpanded(true, animated: true)
            }
            return
        }
        if wantsHoverCollapse, isExpanded {
            scheduleCollapseIfNeeded()
        }
    }

    private func isMouseOverHUD() -> Bool {
        guard let panel, panel.isVisible else { return false }
        return panel.frame.insetBy(dx: -8, dy: -8).contains(NSEvent.mouseLocation)
    }

    private func collapsedCardWidth() -> CGFloat {
        let textWidth = max(
            kickerLabel.intrinsicContentSize.width,
            titleLabel.intrinsicContentSize.width
        )
        let modeWidth = modeChip.isHidden
            ? 0
            : modeLabel.intrinsicContentSize.width + 20 + 8
        let sessionWidth: CGFloat = {
            guard !sessionActionChip.isHidden else { return 0 }
            let labelWidth = max(sessionActionChip.intrinsicContentSize.width, 48)
            return labelWidth + 20 + 9
        }()
        let fitted = 16 + 38 + 12 + textWidth + 12 + modeWidth + sessionWidth + 28 + 14 + 16
        return min(max(ceil(fitted), collapsedMinWidth), expandedSize.width)
    }

    private func applyExpanded(_ expanded: Bool, animated: Bool) {
        guard let panel else { return }
        if pinsExpanded, !expanded {
            return
        }
        if expanded, isExpanded {
            return
        }

        isExpanded = expanded
        hoverGeneration += 1
        let generation = hoverGeneration
        isApplyingHoverLayout = true

        let showActions = expanded && actionBarHeightConstraint?.constant ?? 0 > 0
        headerBottomConstraint?.isActive = !expanded
        scrollBottomConstraint?.isActive = expanded && !showActions
        scrollToActionBarConstraint?.isActive = showActions
        actionBarBottomConstraint?.isActive = showActions

        if expanded {
            hairline.isHidden = false
            scrollView.isHidden = false
            actionBar.isHidden = !showActions
        }

        let cardWidth = expanded ? expandedSize.width : collapsedCardWidth()
        let cardHeight = expanded ? max(expandedSize.height, expandedMinHeight) : collapsedHeight
        let nextSize = windowSize(cardWidth: cardWidth, cardHeight: cardHeight)

        if expanded {
            panel.minSize = windowSize(cardWidth: 320, cardHeight: expandedMinHeight)
            panel.maxSize = NSSize(width: 10_000, height: 10_000)
        } else {
            panel.minSize = NSSize(width: 120, height: 60)
            panel.maxSize = NSSize(width: 10_000, height: 10_000)
        }

        let current = panel.frame
        var next = current
        next.size = nextSize
        next.origin.x = current.maxX - nextSize.width
        next.origin.y = current.maxY - nextSize.height
        next = keepOnScreenPreservingCorner(next)

        let targetBodyAlpha: CGFloat = expanded ? 1 : 0
        if !animated, expanded {
            scrollView.alphaValue = 1
            actionBar.alphaValue = 1
            hairline.alphaValue = 1
        } else if expanded, scrollView.alphaValue < 0.05 {
            scrollView.alphaValue = 0
            actionBar.alphaValue = 0
            hairline.alphaValue = 0
        }

        let finish = {
            guard generation == self.hoverGeneration else { return }
            panel.contentView?.layoutSubtreeIfNeeded()
            self.updateTextViewWidth()
            if expanded {
                self.textView.scrollToBeginningOfDocument(nil)
                self.scrollView.alphaValue = 1
                self.actionBar.alphaValue = 1
                self.hairline.alphaValue = 1
            } else {
                self.hairline.isHidden = true
                self.scrollView.isHidden = true
                self.actionBar.isHidden = true
                self.panel?.minSize = nextSize
                self.panel?.maxSize = nextSize
            }
            self.isApplyingHoverLayout = false
            self.reconcileHoverState()
        }

        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = expanded ? 0.28 : 0.22
                context.timingFunction = CAMediaTimingFunction(controlPoints: 0.16, 1, 0.3, 1)
                context.allowsImplicitAnimation = true
                panel.animator().setFrame(next, display: true)
                self.scrollView.animator().alphaValue = targetBodyAlpha
                self.actionBar.animator().alphaValue = targetBodyAlpha
                self.hairline.animator().alphaValue = targetBodyAlpha
            } completionHandler: {
                finish()
            }
        } else {
            panel.setFrame(next, display: true)
            scrollView.alphaValue = targetBodyAlpha
            actionBar.alphaValue = targetBodyAlpha
            hairline.alphaValue = targetBodyAlpha
            finish()
        }
    }

    private func keepOnScreenPreservingCorner(_ frame: NSRect) -> NSRect {
        guard let visible = (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame else {
            return frame
        }

        var next = frame
        if next.origin.x < visible.minX + 8 {
            next.origin.x = visible.minX + 8
        }
        if next.origin.y < visible.minY + 8 {
            next.origin.y = visible.minY + 8
        }
        if next.maxX > visible.maxX {
            next.origin.x = visible.maxX - next.width
        }
        if next.maxY > visible.maxY {
            next.origin.y = visible.maxY - next.height
        }
        return next
    }

    private func position(_ panel: NSPanel) {
        let screen = NSScreen.main ?? NSScreen.screens.first
        guard let visibleFrame = screen?.visibleFrame else { return }

        let size = windowSize(cardWidth: collapsedCardWidth(), cardHeight: collapsedHeight)
        let origin = NSPoint(
            x: visibleFrame.maxX - size.width - 8,
            y: visibleFrame.maxY - size.height - 8
        )
        panel.setFrame(NSRect(origin: origin, size: size), display: true)
        hasPositioned = true
    }
}

private enum GlassPalette {
    static let title = NSColor(calibratedWhite: 0.96, alpha: 1)
    static let body = NSColor(calibratedWhite: 0.93, alpha: 1)
    static let muted = NSColor(calibratedWhite: 0.78, alpha: 1)
    static let dim = NSColor(calibratedWhite: 0.58, alpha: 1)
    static let kicker = NSColor(calibratedWhite: 0.62, alpha: 1)
}

private final class ClearRootView: NSView {
    var cardView: NSView?
    var cornerRadius: CGFloat = 22

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let cardView else {
            return super.hitTest(point)
        }
        let local = cardView.convert(point, from: superview)
        let path = NSBezierPath(roundedRect: cardView.bounds, xRadius: cornerRadius, yRadius: cornerRadius)
        guard path.contains(local) else {
            return nil
        }
        return super.hitTest(point)
    }
}

private final class ShadowHostView: NSView {
    var cornerRadius: CGFloat = 22

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        layer?.masksToBounds = false
        layer?.shadowColor = NSColor.black.cgColor
        layer?.shadowOpacity = 0.46
        layer?.shadowRadius = 16
        layer?.shadowOffset = CGSize(width: 0, height: -3)
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func layout() {
        super.layout()
        layer?.shadowPath = CGPath(
            roundedRect: bounds,
            cornerWidth: cornerRadius,
            cornerHeight: cornerRadius,
            transform: nil
        )
    }
}

private final class HUDConfirmOverlay: NSView {
    private let dim = HUDClickRegion()
    private let card = HUDClickRegion()
    private let titleLabel = NSTextField(labelWithString: "")
    private let messageLabel = NSTextField(labelWithString: "")
    private let cancelButton = HUDPillButton()
    private let confirmButton = HUDPillButton()
    private var confirmHandler: (() -> Void)?
    private var cancelHandler: (() -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        translatesAutoresizingMaskIntoConstraints = false

        dim.wantsLayer = true
        dim.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.46).cgColor
        dim.translatesAutoresizingMaskIntoConstraints = false
        dim.onMouseUp = { [weak self] in self?.cancelHandler?() }

        card.wantsLayer = true
        card.layer?.backgroundColor = NSColor(calibratedWhite: 0.12, alpha: 0.96).cgColor
        card.layer?.cornerRadius = 16
        card.layer?.cornerCurve = .continuous
        card.layer?.borderWidth = 1
        card.layer?.borderColor = NSColor.white.withAlphaComponent(0.14).cgColor
        card.translatesAutoresizingMaskIntoConstraints = false

        titleLabel.font = .systemFont(ofSize: 16, weight: .semibold)
        titleLabel.textColor = GlassPalette.title
        titleLabel.alignment = .center
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        messageLabel.font = .systemFont(ofSize: 13)
        messageLabel.textColor = GlassPalette.muted
        messageLabel.alignment = .center
        messageLabel.maximumNumberOfLines = 4
        messageLabel.lineBreakMode = .byWordWrapping
        messageLabel.translatesAutoresizingMaskIntoConstraints = false

        cancelButton.apply(title: "Cancel", style: .quiet)
        cancelButton.onTap = { [weak self] in self?.cancelHandler?() }
        confirmButton.onTap = { [weak self] in self?.confirmHandler?() }

        addSubview(dim)
        addSubview(card)
        card.addSubview(titleLabel)
        card.addSubview(messageLabel)
        card.addSubview(cancelButton)
        card.addSubview(confirmButton)

        NSLayoutConstraint.activate([
            dim.topAnchor.constraint(equalTo: topAnchor),
            dim.leadingAnchor.constraint(equalTo: leadingAnchor),
            dim.trailingAnchor.constraint(equalTo: trailingAnchor),
            dim.bottomAnchor.constraint(equalTo: bottomAnchor),

            card.centerXAnchor.constraint(equalTo: centerXAnchor),
            card.centerYAnchor.constraint(equalTo: centerYAnchor, constant: 8),
            card.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 22),
            card.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -22),
            card.widthAnchor.constraint(lessThanOrEqualToConstant: 340),

            titleLabel.topAnchor.constraint(equalTo: card.topAnchor, constant: 18),
            titleLabel.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 18),
            titleLabel.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -18),

            messageLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 8),
            messageLabel.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 18),
            messageLabel.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -18),
            messageLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 240),

            cancelButton.topAnchor.constraint(equalTo: messageLabel.bottomAnchor, constant: 16),
            cancelButton.trailingAnchor.constraint(equalTo: card.centerXAnchor, constant: -6),
            cancelButton.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -16),
            cancelButton.heightAnchor.constraint(equalToConstant: HUDPillButton.height),

            confirmButton.topAnchor.constraint(equalTo: cancelButton.topAnchor),
            confirmButton.leadingAnchor.constraint(equalTo: card.centerXAnchor, constant: 6),
            confirmButton.heightAnchor.constraint(equalToConstant: HUDPillButton.height)
        ])
    }

    required init?(coder: NSCoder) { nil }

    override var mouseDownCanMoveWindow: Bool { false }

    override func hitTest(_ point: NSPoint) -> NSView? {
        isHidden ? nil : super.hitTest(point)
    }

    func present(
        title: String,
        message: String,
        confirmTitle: String,
        style: HUDActionStyle,
        onConfirm: @escaping () -> Void,
        onCancel: @escaping () -> Void
    ) {
        titleLabel.stringValue = title
        messageLabel.stringValue = message
        confirmButton.apply(title: confirmTitle, style: style)
        confirmHandler = onConfirm
        cancelHandler = onCancel
        alphaValue = 0
        isHidden = false
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.16
            animator().alphaValue = 1
        }
    }

    func dismiss() {
        confirmHandler = nil
        cancelHandler = nil
        isHidden = true
        alphaValue = 1
    }
}

private final class HUDDragRegion: NSView {
    override var mouseDownCanMoveWindow: Bool { true }
}

private final class HUDClickRegion: NSView {
    var onMouseUp: (() -> Void)?

    override var mouseDownCanMoveWindow: Bool { false }

    override func mouseUp(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if bounds.contains(point) {
            onMouseUp?()
        }
    }
}

private final class HUDPassthroughView: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override var mouseDownCanMoveWindow: Bool { true }
}

private final class HUDPassthroughImageView: NSImageView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override var mouseDownCanMoveWindow: Bool { true }
}

private final class HUDPassthroughLabel: NSTextField {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        isBezeled = false
        isEditable = false
        isSelectable = false
        drawsBackground = false
        backgroundColor = .clear
    }

    required init?(coder: NSCoder) { nil }

    convenience init(text: String) {
        self.init(frame: .zero)
        stringValue = text
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override var mouseDownCanMoveWindow: Bool { true }
}

private final class HoverView: NSVisualEffectView {
    var onHoverChange: ((Bool) -> Void)?
    var cornerRadius: CGFloat = 22
    private var trackingArea: NSTrackingArea?

    override var mouseDownCanMoveWindow: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        commonInit()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }

    private func commonInit() {
        wantsLayer = true
        layer?.cornerRadius = cornerRadius
        layer?.cornerCurve = .continuous
        layer?.masksToBounds = true
        updateMask()
    }

    override func layout() {
        super.layout()
        layer?.cornerRadius = cornerRadius
        layer?.cornerCurve = .continuous
        updateMask()
    }

    private func updateMask() {
        maskImage = Self.stretchableRoundedMask(cornerRadius: cornerRadius)
    }

    private static func stretchableRoundedMask(cornerRadius: CGFloat) -> NSImage {
        let radius = max(cornerRadius, 1)
        let edge = radius * 2 + 1
        let image = NSImage(size: NSSize(width: edge, height: edge), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            return true
        }
        image.resizingMode = .stretch
        image.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
        return image
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea {
            removeTrackingArea(trackingArea)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect, .enabledDuringMouseDrag],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        onHoverChange?(true)
    }

    override func mouseExited(with event: NSEvent) {
        let mouseInView = convert(event.locationInWindow, from: nil)
        if bounds.insetBy(dx: -6, dy: -6).contains(mouseInView) {
            return
        }
        onHoverChange?(false)
    }
}

private final class PassthroughOverlay: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }
}

private final class HUDHeaderChip: NSView {
    var onTap: (() -> Void)?

    private let titleLabel = NSTextField(labelWithString: "")
    private var accent = NSColor.white
    private var isPressed = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 11
        layer?.cornerCurve = .continuous
        layer?.borderWidth = 1
        translatesAutoresizingMaskIntoConstraints = false
        setContentCompressionResistancePriority(.required, for: .horizontal)
        setContentHuggingPriority(.required, for: .horizontal)

        titleLabel.font = .systemFont(ofSize: 10.5, weight: .semibold)
        titleLabel.alignment = .center
        titleLabel.drawsBackground = false
        titleLabel.isBezeled = false
        titleLabel.isEditable = false
        titleLabel.isSelectable = false
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(titleLabel)
        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            titleLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }

    required init?(coder: NSCoder) {
        nil
    }

    override var mouseDownCanMoveWindow: Bool { false }

    override var intrinsicContentSize: NSSize {
        let textWidth = ceil(titleLabel.intrinsicContentSize.width)
        return NSSize(width: max(48, textWidth + 20), height: 24)
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        isHidden ? nil : (frame.contains(point) ? self : nil)
    }

    func apply(title: String, accent: NSColor) {
        self.accent = accent
        titleLabel.stringValue = title
        titleLabel.textColor = accent.blended(withFraction: 0.22, of: .white) ?? accent
        paint()
        invalidateIntrinsicContentSize()
    }

    override func mouseDown(with event: NSEvent) {
        isPressed = true
        paint()
    }

    override func mouseUp(with event: NSEvent) {
        let inside = bounds.contains(convert(event.locationInWindow, from: nil))
        isPressed = false
        paint()
        if inside {
            onTap?()
        }
    }

    private func paint() {
        let alpha: CGFloat = isPressed ? 0.32 : 0.18
        layer?.backgroundColor = accent.withAlphaComponent(alpha).cgColor
        layer?.borderColor = accent.withAlphaComponent(0.55).cgColor
    }
}

private enum HUDActionStyle {
    case primary
    case save
    case accent
    case quiet
}

private final class HUDPillButton: NSView {
    static let height: CGFloat = 30

    var onTap: (() -> Void)?

    private let titleLabel = NSTextField(labelWithString: "")
    private var fillColor = NSColor.systemBlue
    private var trackingArea: NSTrackingArea?
    private var isPressed = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 8
        layer?.cornerCurve = .continuous
        layer?.borderWidth = 1
        layer?.masksToBounds = true
        translatesAutoresizingMaskIntoConstraints = false
        setContentHuggingPriority(.required, for: .horizontal)
        setContentCompressionResistancePriority(.required, for: .horizontal)

        titleLabel.font = .systemFont(ofSize: 12.5, weight: .semibold)
        titleLabel.textColor = .white
        titleLabel.alignment = .center
        titleLabel.drawsBackground = false
        titleLabel.isBezeled = false
        titleLabel.isEditable = false
        titleLabel.isSelectable = false
        titleLabel.lineBreakMode = .byClipping
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(titleLabel)

        NSLayoutConstraint.activate([
            titleLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor, constant: 0.5),
            titleLabel.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 14),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -14)
        ])
    }

    required init?(coder: NSCoder) {
        nil
    }

    override var intrinsicContentSize: NSSize {
        let textWidth = ceil(titleLabel.attributedStringValue.size().width)
        return NSSize(width: max(84, textWidth + 28), height: Self.height)
    }

    override var mouseDownCanMoveWindow: Bool { false }

    override func hitTest(_ point: NSPoint) -> NSView? {
        isHidden ? nil : (frame.contains(point) ? self : nil)
    }

    func apply(title: String, style: HUDActionStyle) {
        titleLabel.stringValue = title
        switch style {
        case .primary:
            fillColor = NSColor(calibratedRed: 0.33, green: 0.60, blue: 0.96, alpha: 1)
        case .save:
            fillColor = NSColor(calibratedRed: 0.20, green: 0.70, blue: 0.60, alpha: 1)
        case .accent:
            fillColor = NSColor(calibratedRed: 0.94, green: 0.56, blue: 0.28, alpha: 1)
        case .quiet:
            fillColor = NSColor.white.withAlphaComponent(0.18)
        }
        paint()
        invalidateIntrinsicContentSize()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea {
            removeTrackingArea(trackingArea)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        paint(hovered: true)
    }

    override func mouseExited(with event: NSEvent) {
        isPressed = false
        paint()
    }

    override func mouseDown(with event: NSEvent) {
        isPressed = true
        paint(hovered: true)
    }

    override func mouseUp(with event: NSEvent) {
        let inside = bounds.contains(convert(event.locationInWindow, from: nil))
        isPressed = false
        paint(hovered: inside)
        if inside {
            onTap?()
        }
    }

    private func paint(hovered: Bool = false) {
        let color = isPressed
            ? fillColor.shadow(withLevel: 0.12) ?? fillColor
            : hovered
                ? fillColor.highlight(withLevel: 0.08) ?? fillColor
                : fillColor
        layer?.backgroundColor = color.cgColor
        layer?.borderColor = NSColor.white.withAlphaComponent(hovered ? 0.32 : 0.18).cgColor
    }
}

private final class ButtonTarget: NSObject {
    var onTap: (() -> Void)?

    @objc func tap() {
        onTap?()
    }
}
