import AppKit
import QuartzCore

final class FloatingAnswerWindow {
    private var panel: NSPanel?
    private let headerView = NSView()
    private let closeButton = NSButton()
    private let iconBadge = NSView()
    private let actionIcon = NSImageView()
    private let statusDot = NSView()
    private let kickerLabel = NSTextField(labelWithString: "LECTURE COPILOT")
    private let titleLabel = NSTextField(labelWithString: "Answer")
    private let modeChip = NSView()
    private let modeLabel = NSTextField(labelWithString: "")
    private let sessionActionChip = NSView()
    private let sessionActionLabel = NSTextField(labelWithString: "")
    private let hairline = NSView()
    private let accentLine = NSView()
    private let textView = NSTextView()
    private let scrollView = NSScrollView()
    private let closeTarget = ButtonTarget()
    private var hasPositioned = false
    private var frameObserver: NSObjectProtocol?
    private var isExpanded = false
    private var collapseWork: DispatchWorkItem?
    private var currentKind = "answer"
    private var currentAction: CopilotAction?
    private var sessionSnapshot: ClassHUDSnapshot?
    private var stayOnSessionAfterClose = false
    private let actionBar = NSView()
    private let primaryActionButton = NSButton(title: "", target: nil, action: nil)
    private let secondaryActionButton = NSButton(title: "", target: nil, action: nil)
    private let newActionButton = NSButton(title: "", target: nil, action: nil)
    private let primaryActionTarget = ButtonTarget()
    private let secondaryActionTarget = ButtonTarget()
    private let newActionTarget = ButtonTarget()
    private let chipTarget = ButtonTarget()
    private let sessionActionTarget = ButtonTarget()
    private var modeChipToSessionConstraint: NSLayoutConstraint?
    private var modeChipToCloseConstraint: NSLayoutConstraint?
    private var sessionChipWidthConstraint: NSLayoutConstraint?
    private var actionBarHeightConstraint: NSLayoutConstraint?
    private var actionBarBottomConstraint: NSLayoutConstraint?
    private var scrollToActionBarConstraint: NSLayoutConstraint?
    private var expandedSize = NSSize(width: 500, height: 590)

    var onStartClass: (() -> Void)?
    var onEndClass: (() -> Void)?
    var onReviewNote: (() -> Void)?
    var onSaveNote: (() -> Void)?
    var onNewClass: (() -> Void)?
    private var headerBottomConstraint: NSLayoutConstraint?
    private var scrollBottomConstraint: NSLayoutConstraint?

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
        stayOnSessionAfterClose = snapshot.phase == .running || snapshot.phase == .summarizing || snapshot.phase == .summaryReady
        let expand = snapshot.phase == .summaryReady || snapshot.phase == .summarizing || snapshot.phase == .saved
        let action: CopilotAction? = (snapshot.phase == .summaryReady || snapshot.phase == .summarizing || snapshot.phase == .saved) ? .classSummary : nil
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
        setDotPulsing(false)
        if stayOnSessionAfterClose,
           let sessionSnapshot,
           sessionSnapshot.phase == .running,
           currentKind == "answer" || currentKind == "loading" {
            showClassSession(sessionSnapshot)
            return
        }
        panel?.orderOut(nil)
        hasPositioned = false
        isExpanded = false
    }

    private func show(title: String, text: String, kind: String, action: CopilotAction?, expand: Bool) {
        if panel == nil {
            buildPanel()
        }

        currentKind = kind
        currentAction = action
        guard let panel else { return }
        panel.title = title
        configurePresentation(kind: kind, action: action)
        configureActionBar(kind: kind)
        updateSessionActionButton()
        render(text, kind: kind, action: action)

        if !panel.isVisible || !hasPositioned {
            position(panel)
        }
        applyExpanded(expand, animated: false)
        panel.orderFrontRegardless()
        textView.scrollToBeginningOfDocument(nil)
        LastOutputStore.save(kind: kind, action: action, title: title, text: text, panel: panel)
    }

    private func configurePresentation(kind: String, action: CopilotAction?) {
        let accent = accentColor(kind: kind, action: action)
        let isLoading = kind == "loading" || kind == "summary-loading"

        if kind == "session", let sessionSnapshot {
            kickerLabel.stringValue = sessionSnapshot.phase == .idle ? "LECTURE COPILOT" : "CLASS SESSION"
            titleLabel.stringValue = sessionTitle(sessionSnapshot)
            modeLabel.stringValue = sessionSnapshot.phase == .running
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
        actionIcon.image = NSImage(
            systemSymbolName: actionSymbol(kind: kind, action: action),
            accessibilityDescription: modeLabel.stringValue
        )
        actionIcon.contentTintColor = accent.blended(withFraction: 0.16, of: .white) ?? accent

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
        panel.isMovableByWindowBackground = true
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.appearance = darkAppearance
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
        iconBadge.translatesAutoresizingMaskIntoConstraints = false

        actionIcon.imageScaling = .scaleProportionallyDown
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

        sessionActionChip.wantsLayer = true
        sessionActionChip.layer?.cornerRadius = 11
        sessionActionChip.layer?.cornerCurve = .continuous
        sessionActionChip.layer?.borderWidth = 1
        sessionActionChip.setContentCompressionResistancePriority(.required, for: .horizontal)
        sessionActionChip.setContentHuggingPriority(.required, for: .horizontal)
        sessionActionChip.translatesAutoresizingMaskIntoConstraints = false

        sessionActionLabel.font = .systemFont(ofSize: 10.5, weight: .semibold)
        sessionActionLabel.alignment = .center
        sessionActionLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        sessionActionLabel.translatesAutoresizingMaskIntoConstraints = false

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

        actionBar.translatesAutoresizingMaskIntoConstraints = false
        styleActionButton(primaryActionButton)
        styleActionButton(secondaryActionButton)
        styleActionButton(newActionButton)
        primaryActionTarget.onTap = { [weak self] in self?.handlePrimaryAction() }
        secondaryActionTarget.onTap = { [weak self] in self?.handleSecondaryAction() }
        newActionTarget.onTap = { [weak self] in self?.handleNewAction() }
        primaryActionButton.target = primaryActionTarget
        primaryActionButton.action = #selector(ButtonTarget.tap)
        secondaryActionButton.target = secondaryActionTarget
        secondaryActionButton.action = #selector(ButtonTarget.tap)
        newActionButton.target = newActionTarget
        newActionButton.action = #selector(ButtonTarget.tap)
        actionBar.addSubview(primaryActionButton)
        actionBar.addSubview(secondaryActionButton)
        actionBar.addSubview(newActionButton)

        chipTarget.onTap = { [weak self] in self?.handleChipTap() }
        let chipClick = NSClickGestureRecognizer(target: chipTarget, action: #selector(ButtonTarget.tap))
        modeChip.addGestureRecognizer(chipClick)
        sessionActionTarget.onTap = { [weak self] in self?.handleSessionActionTap() }
        let sessionClick = NSClickGestureRecognizer(target: sessionActionTarget, action: #selector(ButtonTarget.tap))
        sessionActionChip.addGestureRecognizer(sessionClick)

        content.addSubview(glassTint)
        content.addSubview(headerView)
        headerView.addSubview(iconBadge)
        iconBadge.addSubview(actionIcon)
        iconBadge.addSubview(statusDot)
        headerView.addSubview(closeButton)
        headerView.addSubview(kickerLabel)
        headerView.addSubview(titleLabel)
        headerView.addSubview(modeChip)
        modeChip.addSubview(modeLabel)
        headerView.addSubview(sessionActionChip)
        sessionActionChip.addSubview(sessionActionLabel)
        content.addSubview(hairline)
        content.addSubview(accentLine)
        content.addSubview(scrollView)
        content.addSubview(actionBar)
        content.addSubview(glassBorder)

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

            actionIcon.centerXAnchor.constraint(equalTo: iconBadge.centerXAnchor),
            actionIcon.centerYAnchor.constraint(equalTo: iconBadge.centerYAnchor),
            actionIcon.widthAnchor.constraint(equalToConstant: 20),
            actionIcon.heightAnchor.constraint(equalToConstant: 20),

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

            sessionActionLabel.leadingAnchor.constraint(equalTo: sessionActionChip.leadingAnchor, constant: 10),
            sessionActionLabel.trailingAnchor.constraint(equalTo: sessionActionChip.trailingAnchor, constant: -10),
            sessionActionLabel.centerYAnchor.constraint(equalTo: sessionActionChip.centerYAnchor),

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

            secondaryActionButton.leadingAnchor.constraint(equalTo: primaryActionButton.trailingAnchor, constant: 10),
            secondaryActionButton.centerYAnchor.constraint(equalTo: actionBar.centerYAnchor),

            newActionButton.leadingAnchor.constraint(equalTo: secondaryActionButton.trailingAnchor, constant: 10),
            newActionButton.trailingAnchor.constraint(lessThanOrEqualTo: actionBar.trailingAnchor),
            newActionButton.centerYAnchor.constraint(equalTo: actionBar.centerYAnchor)
        ])

        modeChipToSessionConstraint = modeChip.trailingAnchor.constraint(equalTo: sessionActionChip.leadingAnchor, constant: -8)
        modeChipToCloseConstraint = modeChip.trailingAnchor.constraint(equalTo: closeButton.leadingAnchor, constant: -9)
        sessionChipWidthConstraint = sessionActionChip.widthAnchor.constraint(equalToConstant: 0)
        modeChipToSessionConstraint?.isActive = true

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
            primaryActionButton.title = "Review Note"
            secondaryActionButton.title = "Save"
            newActionButton.title = "New"
            primaryActionButton.isHidden = false
            secondaryActionButton.isHidden = false
            newActionButton.isHidden = false
            actionBarHeightConstraint?.constant = 44
        default:
            break
        }
        actionBar.isHidden = actionBarHeightConstraint?.constant == 0
    }

    private func styleActionButton(_ button: NSButton) {
        button.bezelStyle = .rounded
        button.controlSize = .regular
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setContentHuggingPriority(.required, for: .horizontal)
    }

    private func updateSessionActionButton() {
        let phase = sessionSnapshot?.phase
        let showStart = phase == .idle && currentKind == "session"
        let showEnd = phase == .running
        let showNew = phase == .summaryReady || phase == .saved || currentKind == "summary"
        let visible = showStart || showEnd || showNew

        sessionActionChip.isHidden = !visible
        modeChip.isHidden = showStart
        sessionChipWidthConstraint?.isActive = !visible
        modeChipToSessionConstraint?.isActive = visible && !showStart
        modeChipToCloseConstraint?.isActive = !visible

        guard visible else { return }

        let accent: NSColor
        if showEnd {
            sessionActionLabel.stringValue = "End"
            accent = NSColor(calibratedRed: 1.0, green: 0.45, blue: 0.42, alpha: 1)
        } else {
            sessionActionLabel.stringValue = showNew ? "New" : "Start"
            accent = NSColor(calibratedRed: 0.42, green: 0.86, blue: 0.68, alpha: 1)
        }
        sessionActionChip.layer?.backgroundColor = accent.withAlphaComponent(0.18).cgColor
        sessionActionChip.layer?.borderColor = accent.withAlphaComponent(0.55).cgColor
        sessionActionLabel.textColor = accent.blended(withFraction: 0.22, of: .white) ?? accent
        sessionActionChip.invalidateIntrinsicContentSize()
        sessionActionLabel.invalidateIntrinsicContentSize()
    }

    private func handleSessionActionTap() {
        let phase = sessionSnapshot?.phase
        if phase == .running {
            onEndClass?()
        } else if phase == .idle {
            onStartClass?()
        } else if phase == .summaryReady || phase == .saved || currentKind == "summary" {
            onNewClass?()
        }
    }

    private func handleChipTap() {
        // Mode chip is informational. Start / End live on the header session button.
    }

    private func handlePrimaryAction() {
        if currentKind == "summary" {
            onReviewNote?()
        }
    }

    private func handleSecondaryAction() {
        if currentKind == "summary" {
            onSaveNote?()
        }
    }

    private func handleNewAction() {
        if currentKind == "summary" {
            onNewClass?()
        }
    }

    private func sessionKind(_ snapshot: ClassHUDSnapshot) -> String {
        switch snapshot.phase {
        case .idle, .running:
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
        collapseWork?.cancel()
        if hovering {
            applyExpanded(true, animated: true)
            return
        }

        let work = DispatchWorkItem { [weak self] in
            self?.applyExpanded(false, animated: true)
        }
        collapseWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22, execute: work)
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
            let labelWidth = max(sessionActionLabel.intrinsicContentSize.width, 28)
            return labelWidth + 20 + 9
        }()
        let fitted = 16 + 38 + 12 + textWidth + 12 + modeWidth + sessionWidth + 28 + 14 + 16
        return min(max(ceil(fitted), collapsedMinWidth), expandedSize.width)
    }

    private func applyExpanded(_ expanded: Bool, animated: Bool) {
        guard let panel else { return }

        if expanded, isExpanded {
            return
        }
        isExpanded = expanded
        hairline.isHidden = !expanded
        scrollView.isHidden = !expanded
        let showActions = expanded && actionBarHeightConstraint?.constant ?? 0 > 0
        actionBar.isHidden = !showActions
        scrollBottomConstraint?.isActive = expanded && !showActions
        scrollToActionBarConstraint?.isActive = showActions
        actionBarBottomConstraint?.isActive = showActions
        headerBottomConstraint?.isActive = !expanded

        let cardWidth = expanded ? expandedSize.width : collapsedCardWidth()
        let cardHeight = expanded ? max(expandedSize.height, expandedMinHeight) : collapsedHeight
        let nextSize = windowSize(cardWidth: cardWidth, cardHeight: cardHeight)

        if expanded {
            panel.minSize = windowSize(cardWidth: 320, cardHeight: expandedMinHeight)
            panel.maxSize = NSSize(width: 10_000, height: 10_000)
        } else {
            panel.minSize = nextSize
            panel.maxSize = nextSize
        }

        let current = panel.frame
        var next = current
        next.size = nextSize
        next.origin.x = current.maxX - nextSize.width
        next.origin.y = current.maxY - nextSize.height
        next = pinnedToScreen(next)

        let finish = {
            panel.contentView?.layoutSubtreeIfNeeded()
            self.updateTextViewWidth()
            if expanded {
                self.textView.scrollToBeginningOfDocument(nil)
            }
        }

        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.22
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                panel.animator().setFrame(next, display: true)
            } completionHandler: {
                finish()
            }
        } else {
            panel.setFrame(next, display: true)
            finish()
        }
    }

    private func pinnedToScreen(_ frame: NSRect) -> NSRect {
        guard let visible = (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame else {
            return frame
        }

        var next = frame
        if next.maxX > visible.maxX - 12 {
            next.origin.x = visible.maxX - next.width - 24
        }
        if next.origin.x < visible.minX + 12 {
            next.origin.x = visible.minX + 24
        }
        if next.maxY > visible.maxY - 12 {
            next.origin.y = visible.maxY - next.height - 24
        }
        if next.origin.y < visible.minY + 12 {
            next.origin.y = visible.minY + 12
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
        let local = convert(point, to: cardView)
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

private final class HoverView: NSVisualEffectView {
    var onHoverChange: ((Bool) -> Void)?
    var cornerRadius: CGFloat = 22
    private var trackingArea: NSTrackingArea?

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
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
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
        onHoverChange?(false)
    }
}

private final class PassthroughOverlay: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }
}

private final class ButtonTarget: NSObject {
    var onTap: (() -> Void)?

    @objc func tap() {
        onTap?()
    }
}
