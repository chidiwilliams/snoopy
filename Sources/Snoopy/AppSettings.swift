import Foundation

struct AppSettings {
    private enum Key {
        static let instruction = "codexInstruction"
        static let workingDirectory = "workingDirectory"
        static let monitoringEnabled = "monitoringEnabled"
    }

    static let defaultInstruction = """
    Focus only on completing useful research associated with the coworker's request. Prefer primary and recent sources, distinguish evidence from inference, and keep the Slack answer compact enough to read quickly.
    """

    static var instruction: String {
        get { UserDefaults.standard.string(forKey: Key.instruction) ?? defaultInstruction }
        set { UserDefaults.standard.set(newValue, forKey: Key.instruction) }
    }

    static var workingDirectory: String {
        get {
            UserDefaults.standard.string(forKey: Key.workingDirectory)
                ?? FileManager.default.homeDirectoryForCurrentUser.path
        }
        set { UserDefaults.standard.set(newValue, forKey: Key.workingDirectory) }
    }

    static var monitoringEnabled: Bool {
        get {
            if UserDefaults.standard.object(forKey: Key.monitoringEnabled) == nil { return true }
            return UserDefaults.standard.bool(forKey: Key.monitoringEnabled)
        }
        set { UserDefaults.standard.set(newValue, forKey: Key.monitoringEnabled) }
    }
}
