import AppKit
import ErstModel
import Foundation
import Observation
import SwiftUI
import UniformTypeIdentifiers

/// The sections in the settings sidebar.
public enum SettingsSection: String, CaseIterable, Identifiable, Sendable {
    case general
    case storage
    case privacy
    case agents
    case shortcuts
    case about

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .general: "General"
        case .storage: "Storage"
        case .privacy: "Privacy"
        case .agents: "Agents"
        case .shortcuts: "Shortcuts"
        case .about: "About Erst"
        }
    }

    public var symbol: String {
        switch self {
        case .general: "gearshape"
        case .storage: "internaldrive"
        case .privacy: "hand.raised"
        case .agents: "terminal"
        case .shortcuts: "command"
        case .about: "info.circle"
        }
    }

    static let mainSections: [SettingsSection] = [
        .general, .storage, .privacy, .agents, .shortcuts,
    ]
}

/// State for the settings window.
@MainActor
@Observable
public final class SettingsModel: ObservableObject {
    // ObservableObject lets SwiftUI own this observable model through StateObject without Xcode macros.
    public var section: SettingsSection
    public var settings: ErstSettings = .default
    public var storage: StorageReport?
    public var clients: [AgentClient] = []
    public var agentErrors: [AgentClient.Kind: String] = [:]
    public var pendingClients: Set<AgentClient.Kind> = []
    public var error: String?
    public var configCopied = false
    public var commandLine: CommandLineToolState = .notInstalled
    public var isChangingCommandLine = false
    /// The example command just copied, which shows a check for two seconds.
    public var copiedCommand: String?
    public var showEraseConfirmation = false

    private let service: any MemoryService
    private let agents: any AgentClientService
    private var hasLoaded = false
    private var saveTask: Task<Void, Never>?
    private var copiedTask: Task<Void, Never>?

    private let saveDebounceMilliseconds = 300
    private let copiedResetSeconds: TimeInterval = 2
    private let eraseLastHourSeconds: TimeInterval = 3600
    private let applicationsPath = "/Applications"

    public init(
        service: any MemoryService,
        agents: any AgentClientService,
        section: SettingsSection = .general,
        eraseConfirmationPresented: Bool = false
    ) {
        self.service = service
        self.agents = agents
        self.section = section
        showEraseConfirmation = eraseConfirmationPresented
    }

    public var dataFolder: URL {
        service.dataDirectory
    }

    /// Running apps that are not already excluded, sorted by name for the Add app menu.
    public var addableApps: [AppRef] {
        let excluded = Set(settings.excludedApps.map(\.bundleID))
        var seen = Set<String>()
        return NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .filter { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }
            .compactMap { application -> AppRef? in
                guard let bundleID = application.bundleIdentifier,
                    let name = application.localizedName,
                    bundleID != Bundle.main.bundleIdentifier,
                    !excluded.contains(bundleID),
                    !seen.contains(bundleID)
                else { return nil }
                seen.insert(bundleID)
                return AppRef(bundleID: bundleID, name: name)
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    public func load() async {
        guard !hasLoaded else { return }
        hasLoaded = true
        do {
            settings = try await service.settings()
            storage = try await service.storage()
        } catch {
            self.error = error.localizedDescription
        }
        clients = await agents.clients()
        commandLine = await agents.commandLineState()
    }

    public var commandLinePath: String {
        agents.commandLinePath
    }

    /// Installs the command, points it back at this copy, or removes it.
    public func changeCommandLine() {
        guard !isChangingCommandLine else { return }
        isChangingCommandLine = true
        error = nil
        Task { [weak self, agents] in
            guard let self else { return }
            defer { isChangingCommandLine = false }
            do {
                if commandLine == .installed {
                    try await agents.uninstallCommandLine()
                } else {
                    try await agents.installCommandLine()
                }
            } catch {
                self.error = error.localizedDescription
            }
            commandLine = await agents.commandLineState()
        }
    }

    public func copyCommand(_ command: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(command, forType: .string)
        copiedCommand = command
        copiedTask?.cancel()
        copiedTask = Task { [weak self, copiedResetSeconds] in
            try? await Task.sleep(for: .seconds(copiedResetSeconds))
            guard !Task.isCancelled else { return }
            self?.copiedCommand = nil
        }
    }

    public func flush() async {
        guard hasLoaded else { return }
        saveTask?.cancel()
        saveTask = nil
        await save()
    }

    public func binding<T>(_ keyPath: WritableKeyPath<ErstSettings, T>) -> Binding<T> {
        Binding(
            get: { self.settings[keyPath: keyPath] },
            set: { value in
                self.settings[keyPath: keyPath] = value
                self.scheduleSave()
            }
        )
    }

    public func addExcludedApp(_ app: AppRef) {
        guard !settings.excludedApps.contains(where: { $0.bundleID == app.bundleID }) else { return }
        settings.excludedApps.append(app)
        scheduleSave()
    }

    public func removeExcludedApp(_ app: AppRef) {
        settings.excludedApps.removeAll { $0.bundleID == app.bundleID }
        scheduleSave()
    }

    public func addApplication(at url: URL) {
        guard let bundle = Bundle(url: url), let bundleID = bundle.bundleIdentifier else { return }
        let name =
            (bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
            ?? (bundle.object(forInfoDictionaryKey: "CFBundleName") as? String)
            ?? url.deletingPathExtension().lastPathComponent
        addExcludedApp(AppRef(bundleID: bundleID, name: name))
    }

    public func chooseApp() {
        let panel = NSOpenPanel()
        panel.directoryURL = URL(fileURLWithPath: applicationsPath, isDirectory: true)
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.prompt = "Choose"
        Task { [weak self] in
            let response = await withCheckedContinuation { continuation in
                panel.begin { continuation.resume(returning: $0) }
            }
            guard response == .OK, let url = panel.url else { return }
            self?.addApplication(at: url)
        }
    }

    public func toggleConnection(for client: AgentClient) {
        guard !pendingClients.contains(client.id) else { return }
        pendingClients.insert(client.id)
        agentErrors[client.id] = nil
        Task { [weak self, agents] in
            guard let self else { return }
            defer { pendingClients.remove(client.id) }
            do {
                if client.isConnected {
                    try await agents.disconnect(client.id)
                } else {
                    try await agents.connect(client.id)
                }
                clients = await agents.clients()
            } catch {
                agentErrors[client.id] = error.localizedDescription
            }
        }
    }

    public func copyManualConfiguration() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(agents.manualConfiguration, forType: .string)
        configCopied = true
        copiedTask?.cancel()
        copiedTask = Task { [weak self, copiedResetSeconds] in
            try? await Task.sleep(for: .seconds(copiedResetSeconds))
            guard !Task.isCancelled else { return }
            self?.configCopied = false
        }
    }

    public func showInFinder() {
        let folder = dataFolder
        if FileManager.default.fileExists(atPath: folder.path) {
            NSWorkspace.shared.activateFileViewerSelecting([folder])
        } else {
            NSWorkspace.shared.open(folder.deletingLastPathComponent())
        }
    }

    public func confirmErase() {
        showEraseConfirmation = false
        eraseLastHour()
    }

    private func eraseLastHour() {
        Task { [weak self, service, eraseLastHourSeconds] in
            let end = Date()
            let start = end.addingTimeInterval(-eraseLastHourSeconds)
            do {
                try await service.erase(start...end)
                self?.storage = try await service.storage()
            } catch {
                self?.error = error.localizedDescription
            }
        }
    }

    private func scheduleSave() {
        guard hasLoaded else { return }
        saveTask?.cancel()
        saveTask = Task { [weak self, saveDebounceMilliseconds] in
            try? await Task.sleep(for: .milliseconds(saveDebounceMilliseconds))
            guard !Task.isCancelled, let self else { return }
            await save()
        }
    }

    private func save() async {
        do {
            try await service.update(settings)
            error = nil
        } catch {
            self.error = error.localizedDescription
            return
        }
        await adoptLaunchAtLogin()
    }

    /// Launch at login can fail to register, so the service reports the real SMAppService
    /// state after its own update. Replace only that field to keep other in-flight edits.
    private func adoptLaunchAtLogin() async {
        guard let saved = try? await service.settings() else { return }
        guard settings.launchAtLogin != saved.launchAtLogin else { return }
        settings.launchAtLogin = saved.launchAtLogin
    }
}
