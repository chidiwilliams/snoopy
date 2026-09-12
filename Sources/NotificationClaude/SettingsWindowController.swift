import AppKit

final class SettingsWindowController: NSWindowController {
    private let directoryField = NSTextField()
    private let instructionView = NSTextView()

    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 590, height: 390),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        self.init(window: window)
        window.title = "Snoopy Settings"
        window.center()
        buildUI()
        loadValues()
    }

    private func buildUI() {
        guard let content = window?.contentView else { return }

        let directoryLabel = NSTextField(labelWithString: "Codex working directory")
        directoryLabel.font = .boldSystemFont(ofSize: NSFont.systemFontSize)

        let chooseButton = NSButton(title: "Choose…", target: self, action: #selector(chooseDirectory))
        let directoryRow = NSStackView(views: [directoryField, chooseButton])
        directoryRow.orientation = .horizontal
        directoryRow.spacing = 8
        directoryField.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let instructionLabel = NSTextField(labelWithString: "Additional instruction sent to Codex")
        instructionLabel.font = .boldSystemFont(ofSize: NSFont.systemFontSize)

        instructionView.isRichText = false
        instructionView.isAutomaticQuoteSubstitutionEnabled = false
        instructionView.font = .systemFont(ofSize: NSFont.systemFontSize)
        instructionView.textContainerInset = NSSize(width: 8, height: 8)
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .bezelBorder
        scrollView.documentView = instructionView

        let saveButton = NSButton(title: "Save", target: self, action: #selector(save))
        saveButton.keyEquivalent = "\r"
        let buttonRow = NSStackView(views: [NSView(), saveButton])
        buttonRow.orientation = .horizontal

        let stack = NSStackView(views: [directoryLabel, directoryRow, instructionLabel, scrollView, buttonRow])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -20),
            stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 20),
            stack.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -20),
            directoryRow.widthAnchor.constraint(equalTo: stack.widthAnchor),
            scrollView.widthAnchor.constraint(equalTo: stack.widthAnchor),
            scrollView.heightAnchor.constraint(greaterThanOrEqualToConstant: 210),
            buttonRow.widthAnchor.constraint(equalTo: stack.widthAnchor)
        ])
    }

    private func loadValues() {
        directoryField.stringValue = AppSettings.workingDirectory
        instructionView.string = AppSettings.instruction
    }

    @objc private func chooseDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            directoryField.stringValue = url.path
        }
    }

    @objc private func save() {
        AppSettings.workingDirectory = directoryField.stringValue
        let instruction = instructionView.string.trimmingCharacters(in: .whitespacesAndNewlines)
        AppSettings.instruction = instruction.isEmpty ? AppSettings.defaultInstruction : instruction
        window?.close()
    }
}
