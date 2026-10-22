import ErstModel
import SwiftUI

/// Recording cadence and compression.
public struct GeneralSettingsView: View {
    let model: SettingsModel

    public var body: some View {
        Form {
            Toggle("Launch at login", isOn: model.binding(\.launchAtLogin))
                .tint(Color.erstButter)
            Toggle("Record the screen", isOn: model.binding(\.isRecording))
                .tint(Color.erstButter)
            Picker("Capture every", selection: model.binding(\.captureIntervalSeconds)) {
                ForEach(ErstSettings.captureIntervalChoices, id: \.self) { seconds in
                    Text(intervalTitle(seconds)).tag(seconds)
                }
            }
            Picker("Compression", selection: model.binding(\.compression)) {
                ForEach(ErstSettings.Compression.allCases, id: \.self) { compression in
                    Text(compression.title).tag(compression)
                }
            }
            .pickerStyle(.segmented)
        }
        .formStyle(.grouped)
    }

    private func intervalTitle(_ seconds: Int) -> String {
        seconds == 1 ? "1 second" : "\(seconds) seconds"
    }
}
