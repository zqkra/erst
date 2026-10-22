import ErstModel
import SwiftUI

/// The native grouped settings window.
public struct SettingsScreen: View {
    @StateObject private var model: SettingsModel
    @Environment(\.erstOpaquePanels) private var opaquePanels
    private let updates: SoftwareUpdateModel

    /// `showingEraseConfirmation` opens the erase alert immediately, which snapshots use.
    public init(
        service: any MemoryService,
        agents: any AgentClientService,
        updates: SoftwareUpdateModel = SoftwareUpdateModel(),
        initialSection: SettingsSection = .general,
        showingEraseConfirmation: Bool = false
    ) {
        self.updates = updates
        _model = StateObject(
            wrappedValue: SettingsModel(
                service: service,
                agents: agents,
                section: initialSection,
                eraseConfirmationPresented: showingEraseConfirmation
            )
        )
    }

    public var body: some View {
        NavigationSplitView {
            SettingsSidebar(model: model)
        } detail: {
            detail
                .navigationTitle(model.section.title)
        }
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: SettingsLayout.minimumWidth, minHeight: SettingsLayout.minimumHeight)
        .font(Typography.body.font)
        .tint(Color.erstButter)
        .preferredColorScheme(.dark)
        .overlay(alignment: .bottom) {
            if let error = model.error {
                Text(error)
                    .erstStyle(Typography.caption)
                    .foregroundStyle(Color.erstCoral)
                    .padding(Spacing.large)
                    .erstGlassSurface(cornerRadius: Radius.group)
            }
        }
        .task {
            Typography.registerFonts()
            await model.load()
        }
        .onDisappear {
            Task { await model.flush() }
        }
        // The menu bar and the update notification open Settings on the update.
        .onChange(of: updates.revealRequested, initial: true) { _, requested in
            guard requested else { return }
            model.section = .about
            updates.revealRequested = false
        }
        .overlay {
            if opaquePanels && model.showEraseConfirmation {
                SettingsEraseConfirmation(model: model)
            }
        }
        .alert(
            EraseConfirmationCopy.title,
            isPresented: Binding(
                get: { model.showEraseConfirmation && !opaquePanels },
                set: { model.showEraseConfirmation = $0 }
            )
        ) {
            Button("Erase", role: .destructive) {
                model.confirmErase()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(EraseConfirmationCopy.message)
        }
    }

    @ViewBuilder
    private var detail: some View {
        switch model.section {
        case .general:
            GeneralSettingsView(model: model)
        case .storage:
            StorageSettingsView(model: model)
        case .privacy:
            PrivacySettingsView(model: model)
        case .agents:
            AgentsSettingsView(model: model)
        case .shortcuts:
            ShortcutsSettingsView(model: model)
        case .about:
            AboutSettingsView(model: model, updates: updates)
        }
    }
}
