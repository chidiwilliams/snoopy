import AppKit
import UserNotifications

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    private let monitor = CaptureMonitor()
    private let logServer = LogServer(logger: .shared)
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private var stateItem = NSMenuItem(title: "Starting…", action: nil, keyEquivalent: "")
    private var diagnosticItem = NSMenuItem(title: "No capture yet", action: nil, keyEquivalent: "")
    private var toggleItem = NSMenuItem(title: "Stop Monitoring", action: #selector(toggleMonitoring), keyEquivalent: "")
    private var lastResult = "No notification has been sent to Codex yet."
    private var settingsController: SettingsWindowController?
    private var lastLoggedDiagnostic = ""
    private var testRequestIndex = Int.random(in: 0..<AppDelegate.testScenarios.count)

    private static let testScenarios: [(title: String, body: String)] = [
        ("Maya · seriously, where is this?", "I needed this yesterday. Research the latest AI coding-agent market shifts and the three biggest implications for a startup."),
        ("Marcus · still waiting", "How is this not done yet? Compare Sierra, Decagon, and Intercom Fin on positioning, customers, and differentiators."),
        ("Priya · this is overdue", "Please stop punting this. Find credible evidence on whether AI support automation actually improves resolution time and CSAT."),
        ("Jordan · I asked twice", "I can't keep chasing this. Research current EU AI Act obligations and deadlines for general-purpose AI providers."),
        ("Amara · come on", "Why do I still not have this? Research current voice-AI latency benchmarks and the vendors closest to real-time conversation."),
        ("Theo · what is taking so long?", "Get this together. Research best practices and practical metrics for evaluating production RAG quality."),
        ("Nina · we needed this already", "This delay is ridiculous. Research the security requirements enterprise buyers now expect from agentic AI vendors."),
        ("Devon · last reminder", "I'm out of patience. Research the most common reasons customer-support AI deployments fail and how teams mitigate them.")
    ]

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        SnoopyLog.shared.info("Snoopy launched")
        do {
            try logServer.start()
        } catch {
            SnoopyLog.shared.error("Could not start log dashboard: \(error.localizedDescription)")
        }
        configureStatusItem()
        configureNotifications()

        monitor.onStateChange = { [weak self] state in self?.update(state: state) }
        monitor.onDiagnosticChange = { [weak self] diagnostic in
            self?.diagnosticItem.title = diagnostic
            if self?.lastLoggedDiagnostic != diagnostic {
                self?.lastLoggedDiagnostic = diagnostic
                SnoopyLog.shared.info("Diagnostic: \(diagnostic)")
            }
        }
        monitor.onCodexResult = { [weak self] result in
            self?.lastResult = result.output
        }

        if AppSettings.monitoringEnabled { monitor.start() }
        else { update(state: .stopped) }
    }

    private func configureStatusItem() {
        statusItem.button?.image = NSImage(systemSymbolName: "bell.and.waves.left.and.right", accessibilityDescription: "Snoopy")

        let menu = NSMenu()
        stateItem.isEnabled = false
        diagnosticItem.isEnabled = false
        menu.addItem(stateItem)
        menu.addItem(diagnosticItem)
        menu.addItem(.separator())

        toggleItem.target = self
        menu.addItem(toggleItem)
        menu.addItem(withTitle: "Request Screen Recording Permission", action: #selector(requestPermission), keyEquivalent: "")
        menu.addItem(withTitle: "Send Test Notification", action: #selector(sendTestNotification), keyEquivalent: "t")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Settings…", action: #selector(showSettings), keyEquivalent: ",")
        menu.addItem(withTitle: "Open Logs Dashboard", action: #selector(openLogsDashboard), keyEquivalent: "l")
        menu.addItem(withTitle: "Show Last Codex Result…", action: #selector(showLastResult), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Snoopy", action: #selector(quit), keyEquivalent: "q")
        menu.items.forEach { if $0.action != nil { $0.target = self } }
        statusItem.menu = menu
    }

    private func configureNotifications() {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    private func update(state: CaptureMonitor.State) {
        stateItem.title = state.label
        toggleItem.title = state == .stopped ? "Start Monitoring" : "Stop Monitoring"
        statusItem.button?.image = NSImage(
            systemSymbolName: state == .processing ? "sparkles" : "bell.and.waves.left.and.right",
            accessibilityDescription: state.label
        )
    }

    @objc private func toggleMonitoring() {
        if monitor.state == .stopped {
            AppSettings.monitoringEnabled = true
            monitor.start()
        } else {
            AppSettings.monitoringEnabled = false
            monitor.stop()
        }
    }

    @objc private func requestPermission() {
        monitor.requestPermission()
    }

    @objc private func sendTestNotification() {
        let scenario = Self.testScenarios[testRequestIndex % Self.testScenarios.count]
        testRequestIndex = (testRequestIndex + 1) % Self.testScenarios.count
        let content = UNMutableNotificationContent()
        content.title = scenario.title
        content.body = scenario.body
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 2, repeats: false)
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request) { [weak self] error in
            DispatchQueue.main.async {
                if let error {
                    self?.diagnosticItem.title = "Test notification failed: \(error.localizedDescription)"
                    return
                }
                self?.diagnosticItem.title = "Test scheduled; capture in 3 seconds…"
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                    self?.monitor.processNextFrame()
                }
            }
        }
    }

    @objc private func showSettings() {
        if settingsController == nil { settingsController = SettingsWindowController() }
        settingsController?.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func showLastResult() {
        let alert = NSAlert()
        alert.messageText = "Last Codex Result"
        alert.informativeText = lastResult
        alert.addButton(withTitle: "OK")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    @objc private func openLogsDashboard() {
        NSWorkspace.shared.open(LogServer.dashboardURL)
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.run()
}
