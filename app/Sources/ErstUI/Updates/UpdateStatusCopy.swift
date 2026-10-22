import ErstModel
import Foundation

/// The words for each update phase in Settings, About.
struct UpdateStatusCopy {
    let phase: SoftwareUpdatePhase
    var now = Date()
    var calendar = Calendar.current

    var title: String {
        switch phase {
        case .upToDate: "Erst is up to date"
        case .checking: "Checking for updates\u{2026}"
        case .available(let offer): "Erst \(offer.version) is available"
        case .downloading(let offer, _, _): "Downloading Erst \(offer.version)"
        case .preparing(let offer): "Preparing Erst \(offer.version)"
        case .ready(let offer): "Erst \(offer.version) is ready"
        case .installing(let offer): "Installing Erst \(offer.version)"
        case .failed: "Erst could not check for updates"
        }
    }

    var detail: String? {
        switch phase {
        case .upToDate(let lastChecked): lastChecked.map(checked)
        case .checking: nil
        case .available(let offer): released(offer)
        case .downloading(_, let received, let expected): downloaded(received, of: expected)
        case .preparing: "Checking its signature"
        case .ready: "Relaunch Erst to finish updating."
        case .installing: "Erst relaunches by itself."
        case .failed(let message, _): message
        }
    }

    /// The lines under the status while there is an update to talk about.
    var notes: [String] {
        switch phase {
        case .available, .downloading, .preparing, .ready: phase.offer?.notes ?? []
        case .upToDate, .checking, .installing, .failed: []
        }
    }

    /// The download's progress from 0 to 1, when its size is known.
    var progress: Double? {
        guard case .downloading(_, let received, let expected?) = phase, expected > 0 else { return nil }
        return min(1, Double(received) / Double(expected))
    }

    private func checked(_ date: Date) -> String {
        let time = date.formatted(date: .omitted, time: .shortened)
        if calendar.isDateInToday(date) { return "Checked today at \(time)" }
        if calendar.isDateInYesterday(date) { return "Checked yesterday at \(time)" }
        return "Checked \(date.formatted(.dateTime.day().month(.abbreviated))) at \(time)"
    }

    private func released(_ offer: SoftwareUpdateOffer) -> String? {
        let size = offer.size.map { ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) }
        let date = offer.releasedAt.map {
            "Released \($0.formatted(.relative(presentation: .named, unitsStyle: .wide)))."
        }
        let parts = [date, size].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " ")
    }

    private func downloaded(_ received: Int64, of expected: Int64?) -> String {
        let done = ByteCountFormatter.string(fromByteCount: received, countStyle: .file)
        guard let expected else { return done }
        return "\(done) of \(ByteCountFormatter.string(fromByteCount: expected, countStyle: .file))"
    }
}
