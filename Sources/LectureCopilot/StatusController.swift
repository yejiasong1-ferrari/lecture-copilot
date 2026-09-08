import AppKit

protocol StatusControllerDelegate: AnyObject {
    func statusControllerDidToggleClassMode(_ statusController: StatusController)
    func statusControllerDidChooseAction(_ statusController: StatusController, action: CopilotAction)
    func statusControllerDidChooseOpenDoubao(_ statusController: StatusController)
    func statusControllerDidChoosePromptSettings(_ statusController: StatusController)
    func statusControllerDidChooseLastAnswer(_ statusController: StatusController)
    func statusControllerDidChooseInspectDoubao(_ statusController: StatusController)
    func statusControllerDidChooseTranslateLastCapture(_ statusController: StatusController)
    func statusControllerDidChooseShortcutSettings(_ statusController: StatusController)
    func statusControllerDidChooseStartClass(_ statusController: StatusController)
    func statusControllerDidChooseEndClass(_ statusController: StatusController)
    func statusControllerDidToggleRecordTranslate(_ statusController: StatusController)
    func statusControllerDidChooseNotesFolder(_ statusController: StatusController)
}

final class StatusController {
    weak var delegate: StatusControllerDelegate?

    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

    func render(
        classModeEnabled: Bool,
        sessionRunning: Bool = false,
        recordTranslate: Bool = false,
        noteCount: Int = 0
    ) {
        statusItem.length = NSStatusItem.squareLength
        statusItem.button?.title = ""
        statusItem.button?.imagePosition = .imageOnly
        statusItem.button?.image = statusImage(classModeEnabled: classModeEnabled)
        statusItem.button?.toolTip = classModeEnabled ? "Lecture Copilot · Class Mode ON" : "Lecture Copilot"

        let menu = NSMenu()
        menu.addItem(.sectionHeader(title: "Lecture Copilot"))

        let classModeItem = NSMenuItem(
            title: "Class Mode",
            action: #selector(toggleClassMode),
            keyEquivalent: ""
        )
        classModeItem.target = self
        classModeItem.state = classModeEnabled ? .on : .off
        menu.addItem(classModeItem)
        menu.addItem(.separator())

        menu.addItem(.sectionHeader(title: "Class Session"))
        if sessionRunning {
            menu.addItem(targetedItem("End Class", selector: #selector(endClass)))
            menu.addItem(disabledItem("\(noteCount) notes saved", shortcut: ""))
        } else {
            menu.addItem(targetedItem("Start Class", selector: #selector(startClass)))
        }
        let translateItem = NSMenuItem(
            title: "Record Translate",
            action: #selector(toggleRecordTranslate),
            keyEquivalent: ""
        )
        translateItem.target = self
        translateItem.state = recordTranslate ? .on : .off
        menu.addItem(translateItem)
        menu.addItem(targetedItem("Notes Folder", selector: #selector(openNotesFolder)))
        menu.addItem(.separator())

        menu.addItem(.sectionHeader(title: "Actions"))
        menu.addItem(actionItem("Translate", shortcut: "⇧←", action: .translate))
        menu.addItem(actionItem("Explain", shortcut: "⇧→", action: .explain))
        menu.addItem(actionItem("Direct Answer", shortcut: "⇧↑", action: .directAnswer))
        menu.addItem(actionItem("Say in Class", shortcut: "⇧↑↑", action: .sayInClass))
        menu.addItem(disabledItem("Read Doubao Answer", shortcut: "⇧↩"))
        menu.addItem(actionItem("Back to Class", shortcut: "⇧↓", action: .backToClass))
        menu.addItem(.separator())

        menu.addItem(.sectionHeader(title: "Settings"))
        menu.addItem(targetedItem("Doubao", selector: #selector(openDoubao)))
        menu.addItem(targetedItem("Prompts", selector: #selector(openPromptSettings)))
        menu.addItem(targetedItem("Shortcuts", selector: #selector(openShortcutSettings)))
        menu.addItem(targetedItem("Last Answer", selector: #selector(openLastAnswer)))
        menu.addItem(.separator())

        menu.addItem(.sectionHeader(title: "Tools"))
        menu.addItem(targetedItem("Translate Last Capture", selector: #selector(translateLastCapture)))
        menu.addItem(targetedItem("Inspect Doubao", selector: #selector(inspectDoubao)))
        menu.addItem(.separator())

        let quit = NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quit.target = NSApplication.shared
        menu.addItem(quit)

        statusItem.menu = menu
    }

    private func statusImage(classModeEnabled: Bool) -> NSImage? {
        if classModeEnabled {
            let image = NSImage(
                systemSymbolName: "graduationcap.fill",
                accessibilityDescription: "Lecture Copilot"
            )
            image?.isTemplate = true
            return image
        }

        let blank = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { _ in true }
        blank.isTemplate = true
        blank.accessibilityDescription = "Lecture Copilot"
        return blank
    }

    private func actionItem(_ title: String, shortcut: String, action: CopilotAction) -> NSMenuItem {
        let item = NSMenuItem(title: labeled(title, shortcut: shortcut), action: #selector(chooseAction(_:)), keyEquivalent: "")
        item.target = self
        item.representedObject = ActionBox(action)
        return item
    }

    private func targetedItem(_ title: String, selector: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: selector, keyEquivalent: "")
        item.target = self
        return item
    }

    private func disabledItem(_ title: String, shortcut: String) -> NSMenuItem {
        let item = NSMenuItem(title: labeled(title, shortcut: shortcut), action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    private func labeled(_ title: String, shortcut: String) -> String {
        shortcut.isEmpty ? title : "\(title)\t\(shortcut)"
    }

    @objc private func toggleClassMode() {
        delegate?.statusControllerDidToggleClassMode(self)
    }

    @objc private func chooseAction(_ sender: NSMenuItem) {
        guard let box = sender.representedObject as? ActionBox else { return }
        delegate?.statusControllerDidChooseAction(self, action: box.action)
    }

    @objc private func openDoubao() {
        delegate?.statusControllerDidChooseOpenDoubao(self)
    }

    @objc private func openPromptSettings() {
        delegate?.statusControllerDidChoosePromptSettings(self)
    }

    @objc private func openLastAnswer() {
        delegate?.statusControllerDidChooseLastAnswer(self)
    }

    @objc private func inspectDoubao() {
        delegate?.statusControllerDidChooseInspectDoubao(self)
    }

    @objc private func translateLastCapture() {
        delegate?.statusControllerDidChooseTranslateLastCapture(self)
    }

    @objc private func openShortcutSettings() {
        delegate?.statusControllerDidChooseShortcutSettings(self)
    }

    @objc private func startClass() {
        delegate?.statusControllerDidChooseStartClass(self)
    }

    @objc private func endClass() {
        delegate?.statusControllerDidChooseEndClass(self)
    }

    @objc private func toggleRecordTranslate() {
        delegate?.statusControllerDidToggleRecordTranslate(self)
    }

    @objc private func openNotesFolder() {
        delegate?.statusControllerDidChooseNotesFolder(self)
    }
}

private final class ActionBox {
    let action: CopilotAction

    init(_ action: CopilotAction) {
        self.action = action
    }
}
