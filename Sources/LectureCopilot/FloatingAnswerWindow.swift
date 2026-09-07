import AppKit
import QuartzCore

final class FloatingAnswerWindow {
    private var panel: NSPanel?
    private let headerView = NSView()
    private let closeButton = NSButton()
    private let statusDot = NSView()
    private let kickerLabel = NSTextField(labelWithString: "LECTURE COPILOT")
    private let titleLabel = NSTextField(labelWithString: "Answer")
    private let modeChip = NSView()
    private let modeLabel = NSTextField(labelWithString: "")
    private let hairline = NSView()
    private let textView = NSTextView()
    private let scrollView = NSScrollView()
    private let closeTarget = ButtonTarget()
    private var hasPositioned = false
    private var frameObserver: NSObjectProtocol?
    private var isExpanded = false
    private var collapseWork: DispatchWorkItem?
    private var currentKind = "answer"
    private var currentAction: CopilotAction?
    private var expandedSize = NSSize(width: 460, height: 560)
    private var headerBottomConstraint: NSLayoutConstraint?
    private var scrollBottomConstraint: NSLayoutConstraint?

    private let collapsedHeight: CGFloat = 58
    private let expandedMinHeight: CGFloat = 430
    private let cornerRadius: CGFloat = 22

    deinit {
        collapseWork?.cancel()
        if let frameObserver {
            NotificationCenter.default.removeObserver(frameObserver)
        }
    }

    func showLoading(_ message: String, action: CopilotAction? = nil) {
        show(title: "Lecture Copilot", text: message, kind: "loading", action: action)
    }

    func showAnswer(_ text: String, action: CopilotAction? = nil) {
        show(title: "Answer", text: text, kind: "answer", action: action)
    }

    func close() {
        collapseWork?.cancel()
        setDotPulsing(false)
        panel?.orderOut(nil)
        hasPositioned = false
        isExpanded = false
    }

    private func show(title: String, text: String, kind: String, action: CopilotAction?) {
        if panel == nil {
            buildPanel()
        }

        currentKind = kind
        currentAction = action
        guard let panel else { return }
        panel.title = title
        configurePresentation(kind: kind, action: action)
        render(text, kind: kind, action: action)
        applyExpanded(false, animated: false)

        if !panel.isVisible || !hasPositioned {
            position(panel)
        }
        panel.orderFrontRegardless()
        textView.scrollToBeginningOfDocument(nil)
        LastOutputStore.save(kind: kind, action: action, title: title, text: text, panel: panel)
    }

    private func configurePresentation(kind: String, action: CopilotAction?) {
        let accent = accentColor(kind: kind, action: action)
        let isLoading = kind == "loading"

        kickerLabel.stringValue = "LECTURE COPILOT"
        titleLabel.stringValue = isLoading ? "Working" : "Answer"
        modeLabel.stringValue = action?.chipTitle ?? (isLoading ? "Sending" : "Ready")

        statusDot.layer?.backgroundColor = accent.cgColor
        statusDot.layer?.shadowColor = accent.cgColor
        statusDot.layer?.shadowRadius = 6
        statusDot.layer?.shadowOpacity = 0.85
        statusDot.layer?.shadowOffset = .zero

        modeChip.layer?.backgroundColor = accent.withAlphaComponent(0.16).cgColor
        modeChip.layer?.borderColor = accent.withAlphaComponent(0.28).cgColor
        modeLabel.textColor = accent.blended(withFraction: 0.18, of: .white) ?? accent
        hairline.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.08).cgColor

        setDotPulsing(isLoading)
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

        if kind == "loading" {
            result.append(lineString(text, font: .systemFont(ofSize: 15, weight: .regular), color: .secondaryLabelColor, spacing: 6, paragraphSpacing: 8))
            return result
        }

        for (index, raw) in lines.enumerated() {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty {
                result.append(NSAttributedString(string: "\n"))
                continue
            }

            let heading = isHeadingLine(line)
            let chinese = isMostlyChinese(line)
            let font: NSFont
            let color: NSColor
            let spacing: CGFloat
            let paragraphSpacing: CGFloat

            if heading {
                font = .systemFont(ofSize: 13, weight: .semibold)
                color = .tertiaryLabelColor
                spacing = 1
                paragraphSpacing = 6
            } else if action == .translate, chinese {
                font = .systemFont(ofSize: 14.5, weight: .regular)
                color = NSColor.labelColor.withAlphaComponent(0.78)
                spacing = 3
                paragraphSpacing = 14
            } else if action == .translate {
                font = .systemFont(ofSize: 15.5, weight: .medium)
                color = .labelColor
                spacing = 2
                paragraphSpacing = 4
            } else if action == .sayInClass, !chinese {
                font = .systemFont(ofSize: 16, weight: .medium)
                color = .labelColor
                spacing = 4
                paragraphSpacing = 10
            } else {
                font = .systemFont(ofSize: 15, weight: heading ? .semibold : .regular)
                color = chinese ? .secondaryLabelColor : .labelColor
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
        let compact = line.replacingOccurrences(of: " ", with: "")
        return [
            "核心", "结构", "关系", "最重要的一句话", "答案", "原因", "其他选项",
            "你可以很口语地回答", "这页真正意思"
        ].contains { compact.hasPrefix($0) }
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

    private func buildPanel() {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: expandedSize.width, height: collapsedHeight),
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
        panel.hasShadow = true
        panel.minSize = NSSize(width: 320, height: collapsedHeight)

        let content = HoverView(frame: NSRect(x: 0, y: 0, width: expandedSize.width, height: collapsedHeight))
        content.material = .hudWindow
        content.blendingMode = .behindWindow
        content.state = .active
        content.wantsLayer = true
        content.layer?.cornerRadius = cornerRadius
        content.layer?.cornerCurve = .continuous
        content.layer?.masksToBounds = true
        content.layer?.borderWidth = 1
        content.layer?.borderColor = NSColor.white.withAlphaComponent(0.14).cgColor
        content.onHoverChange = { [weak self] hovering in
            self?.handleHover(hovering)
        }
        panel.contentView = content

        headerView.wantsLayer = true
        headerView.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.04).cgColor
        headerView.translatesAutoresizingMaskIntoConstraints = false

        closeButton.bezelStyle = .inline
        closeButton.isBordered = false
        closeButton.image = NSImage(systemSymbolName: "xmark", accessibilityDescription: "Close")
        closeButton.imagePosition = .imageOnly
        closeButton.contentTintColor = .tertiaryLabelColor
        closeButton.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 10, weight: .bold)
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        closeTarget.onTap = { [weak self] in self?.close() }
        closeButton.target = closeTarget
        closeButton.action = #selector(ButtonTarget.tap)

        statusDot.wantsLayer = true
        statusDot.layer?.cornerRadius = 4.5
        statusDot.translatesAutoresizingMaskIntoConstraints = false

        kickerLabel.font = .systemFont(ofSize: 9, weight: .semibold)
        kickerLabel.textColor = .tertiaryLabelColor
        kickerLabel.translatesAutoresizingMaskIntoConstraints = false

        titleLabel.font = .systemFont(ofSize: 14, weight: .semibold)
        titleLabel.textColor = .labelColor
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        modeChip.wantsLayer = true
        modeChip.layer?.cornerRadius = 12
        modeChip.layer?.cornerCurve = .continuous
        modeChip.layer?.borderWidth = 1
        modeChip.translatesAutoresizingMaskIntoConstraints = false

        modeLabel.font = .systemFont(ofSize: 11, weight: .semibold)
        modeLabel.alignment = .center
        modeLabel.translatesAutoresizingMaskIntoConstraints = false

        hairline.wantsLayer = true
        hairline.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.08).cgColor
        hairline.translatesAutoresizingMaskIntoConstraints = false

        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.isRichText = true
        textView.font = .systemFont(ofSize: 15)
        textView.textColor = .labelColor
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
        scrollView.usesPredominantAxisScrolling = true
        scrollView.drawsBackground = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.postsFrameChangedNotifications = true

        content.addSubview(headerView)
        headerView.addSubview(closeButton)
        headerView.addSubview(statusDot)
        headerView.addSubview(kickerLabel)
        headerView.addSubview(titleLabel)
        headerView.addSubview(modeChip)
        modeChip.addSubview(modeLabel)
        content.addSubview(hairline)
        content.addSubview(scrollView)

        let headerBottom = headerView.bottomAnchor.constraint(equalTo: content.bottomAnchor)
        let scrollBottom = scrollView.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -14)
        headerBottomConstraint = headerBottom
        scrollBottomConstraint = scrollBottom

        NSLayoutConstraint.activate([
            headerView.topAnchor.constraint(equalTo: content.topAnchor),
            headerView.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            headerView.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            headerView.heightAnchor.constraint(equalToConstant: collapsedHeight),
            headerBottom,

            closeButton.centerYAnchor.constraint(equalTo: headerView.centerYAnchor),
            closeButton.leadingAnchor.constraint(equalTo: headerView.leadingAnchor, constant: 12),
            closeButton.widthAnchor.constraint(equalToConstant: 22),
            closeButton.heightAnchor.constraint(equalToConstant: 22),

            statusDot.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
            statusDot.leadingAnchor.constraint(equalTo: closeButton.trailingAnchor, constant: 8),
            statusDot.widthAnchor.constraint(equalToConstant: 9),
            statusDot.heightAnchor.constraint(equalToConstant: 9),

            kickerLabel.topAnchor.constraint(equalTo: headerView.topAnchor, constant: 11),
            kickerLabel.leadingAnchor.constraint(equalTo: statusDot.trailingAnchor, constant: 10),
            kickerLabel.trailingAnchor.constraint(lessThanOrEqualTo: modeChip.leadingAnchor, constant: -12),

            titleLabel.topAnchor.constraint(equalTo: kickerLabel.bottomAnchor, constant: 1),
            titleLabel.leadingAnchor.constraint(equalTo: kickerLabel.leadingAnchor),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: modeChip.leadingAnchor, constant: -12),
            titleLabel.bottomAnchor.constraint(lessThanOrEqualTo: headerView.bottomAnchor, constant: -10),

            modeChip.centerYAnchor.constraint(equalTo: headerView.centerYAnchor),
            modeChip.trailingAnchor.constraint(equalTo: headerView.trailingAnchor, constant: -14),
            modeChip.heightAnchor.constraint(equalToConstant: 26),

            modeLabel.leadingAnchor.constraint(equalTo: modeChip.leadingAnchor, constant: 11),
            modeLabel.trailingAnchor.constraint(equalTo: modeChip.trailingAnchor, constant: -11),
            modeLabel.centerYAnchor.constraint(equalTo: modeChip.centerYAnchor),

            hairline.topAnchor.constraint(equalTo: headerView.bottomAnchor),
            hairline.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 16),
            hairline.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -16),
            hairline.heightAnchor.constraint(equalToConstant: 1),

            scrollView.topAnchor.constraint(equalTo: hairline.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 8),
            scrollView.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -8)
        ])

        frameObserver = NotificationCenter.default.addObserver(
            forName: NSView.frameDidChangeNotification,
            object: scrollView,
            queue: .main
        ) { [weak self] _ in
            self?.updateTextViewWidth()
        }

        self.panel = panel
    }

    private func accentColor(kind: String, action: CopilotAction?) -> NSColor {
        if kind == "loading" {
            return NSColor(calibratedRed: 1.0, green: 0.68, blue: 0.32, alpha: 1)
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

    private func applyExpanded(_ expanded: Bool, animated: Bool) {
        guard let panel else { return }

        if expanded, isExpanded {
            return
        }
        if !expanded, !isExpanded, panel.frame.height <= collapsedHeight + 8 {
            panel.contentView?.layoutSubtreeIfNeeded()
            return
        }

        isExpanded = expanded
        hairline.isHidden = !expanded
        scrollView.isHidden = !expanded
        scrollBottomConstraint?.isActive = expanded
        headerBottomConstraint?.isActive = !expanded

        if expanded {
            panel.minSize = NSSize(width: 320, height: expandedMinHeight)
            panel.maxSize = NSSize(width: 10_000, height: 10_000)
        } else {
            panel.minSize = NSSize(width: 320, height: collapsedHeight)
            panel.maxSize = NSSize(width: 10_000, height: collapsedHeight)
        }

        let current = panel.frame
        let top = current.maxY
        let width = expanded ? max(current.width, expandedSize.width) : current.width
        let height = expanded ? max(expandedSize.height, expandedMinHeight) : collapsedHeight
        if expanded {
            expandedSize = NSSize(width: width, height: height)
        }

        var next = current
        next.size = NSSize(width: width, height: height)
        next.origin.y = top - height
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
                context.duration = 0.2
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

        let size = NSSize(width: expandedSize.width, height: collapsedHeight)
        let origin = NSPoint(
            x: visibleFrame.maxX - size.width - 24,
            y: visibleFrame.maxY - size.height - 24
        )
        panel.setFrame(NSRect(origin: origin, size: size), display: true)
        hasPositioned = true
    }
}

private final class HoverView: NSVisualEffectView {
    var onHoverChange: ((Bool) -> Void)?
    private var trackingArea: NSTrackingArea?

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

private final class ButtonTarget: NSObject {
    var onTap: (() -> Void)?

    @objc func tap() {
        onTap?()
    }
}
