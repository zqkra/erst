import ErstModel
import SwiftUI

/// Which agents can read memory, and how much they may see.
public struct AgentsSettingsView: View {
    let model: SettingsModel

    public var body: some View {
        Form {
            Section {
                ForEach(model.clients) { client in
                    clientRow(client)
                }
            }
            Section {
                Picker("How far back", selection: model.binding(\.agentHistoryDays)) {
                    ForEach(ErstSettings.agentHistoryChoices, id: \.self) { days in
                        Text(historyTitle(days)).tag(days)
                    }
                }
            }
            CommandLineSection(model: model)
            Section("Other agents") {
                HStack(spacing: Spacing.medium) {
                    Text("Copy MCP config")
                        .erstStyle(Typography.body)
                        .foregroundStyle(Color.erstText)
                    Spacer(minLength: Spacing.small)
                    Button(model.configCopied ? "Copied" : "Copy") {
                        model.copyManualConfiguration()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
        }
        .formStyle(.grouped)
    }

    private func clientRow(_ client: AgentClient) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xSmall) {
            HStack(spacing: Spacing.medium) {
                Text(client.name)
                    .erstStyle(Typography.body)
                    .foregroundStyle(Color.erstText)
                Text(statusTitle(client))
                    .erstStyle(Typography.caption)
                    .foregroundStyle(Color.erstSecondary)
                Spacer(minLength: Spacing.small)
                if client.isInstalled {
                    Button(client.isConnected ? "Disconnect" : "Connect") {
                        model.toggleConnection(for: client)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(model.pendingClients.contains(client.id))
                }
            }
            if let error = model.agentErrors[client.id] {
                Text(error)
                    .erstStyle(Typography.caption)
                    .foregroundStyle(Color.erstCoral)
            }
        }
    }

    private func statusTitle(_ client: AgentClient) -> String {
        if !client.isInstalled { return "Not installed" }
        return client.isConnected ? "Connected" : "Not connected"
    }

    private func historyTitle(_ days: Int?) -> String {
        guard let days else { return "All history" }
        return days == 1 ? "1 day" : "\(days) days"
    }
}
