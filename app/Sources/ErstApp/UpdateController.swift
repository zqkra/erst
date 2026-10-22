import AppKit
import ErstModel
import ErstUI
import Sparkle
import UserNotifications
import os

private let updateLog = Logger(subsystem: "app.erst.Erst", category: "Updates")

/// Runs Sparkle behind Erst's own interface. Settings, About shows the update, the menu bar offers
/// it, and a check in the background that finds one posts a single notification. No window opens
/// over the user's work. Sparkle downloads the release, checks its EdDSA signature and its code
/// signature, replaces the app, and relaunches it.
@MainActor
final class UpdateController: NSObject {
    /// Notifications for an update use this prefix and the version after it.
    nonisolated static let notificationPrefix = "erst.update."
    /// Points the updater at another feed, for testing a release before it is published.
    nonisolated static let feedOverrideKey = "ERST_UPDATE_FEED_URL"
    private static let notifiedVersionKey = "UpdateNotifiedVersion"

    let model: SoftwareUpdateModel
    /// Opens Settings on About. The app sets it once SwiftUI hands over its settings action.
    var revealInSettings: (() -> Void)?

    private var updater: SPUUpdater?
    private var offer: SoftwareUpdateOffer?
    /// Sparkle waits on these until the user acts.
    private var pendingChoice: ((SPUUserUpdateChoice) -> Void)?
    private var pendingRelaunch: ((SPUUserUpdateChoice) -> Void)?
    private var cancelDownload: (() -> Void)?
    private var received: Int64 = 0
    private var expected: Int64?
    /// The user asked for this update, so Sparkle relaunches as soon as it is ready.
    private var installRequested = false
    private var userInitiatedCheck = false

    init(model: SoftwareUpdateModel) {
        self.model = model
    }

    /// Starts scheduled checks. A build without a release key, such as one run from source, has
    /// no updates.
    func start() {
        guard Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") != nil else {
            updateLog.notice("No release key in this build; updates are off")
            return
        }
        let updater = SPUUpdater(
            hostBundle: .main, applicationBundle: .main, userDriver: self, delegate: self)
        do {
            try updater.start()
        } catch {
            updateLog.error("Updater did not start: \(error.localizedDescription, privacy: .public)")
            return
        }
        self.updater = updater
        model.checksAutomatically = updater.automaticallyChecksForUpdates
        model.installsAutomatically = updater.automaticallyDownloadsUpdates
        model.phase = .upToDate(lastChecked: updater.lastUpdateCheckDate)
        model.actions = SoftwareUpdateModel.Actions(
            check: { [weak self] in self?.check() },
            install: { [weak self] in self?.install() },
            cancel: { [weak self] in self?.cancel() },
            setChecksAutomatically: { [weak updater] in updater?.automaticallyChecksForUpdates = $0 },
            setInstallsAutomatically: { [weak updater] in updater?.automaticallyDownloadsUpdates = $0 }
        )
        updateLog.notice(
            "Updater started; feed \(updater.feedURL?.absoluteString ?? "none", privacy: .public)")
    }

    private func check() {
        // An update Sparkle already offered stays on screen; asking again only reveals it.
        guard pendingChoice == nil, pendingRelaunch == nil else { return }
        updater?.checkForUpdates()
    }

    private func install() {
        installRequested = true
        if let relaunch = pendingRelaunch {
            pendingRelaunch = nil
            relaunch(.install)
        } else if let choice = pendingChoice {
            pendingChoice = nil
            choice(.install)
        }
    }

    private func cancel() {
        cancelDownload?()
        cancelDownload = nil
    }

    private func showDownload() {
        guard let offer else { return }
        model.phase = .downloading(offer, received: received, expected: expected)
    }

    /// One notification per version, and only when Erst may already post them.
    private func notifyOnce(_ offer: SoftwareUpdateOffer) {
        let defaults = UserDefaults.standard
        guard defaults.string(forKey: Self.notifiedVersionKey) != offer.version else { return }
        defaults.set(offer.version, forKey: Self.notifiedVersionKey)
        Task {
            let center = UNUserNotificationCenter.current()
            let settings = await center.notificationSettings()
            guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional
            else { return }
            let content = UNMutableNotificationContent()
            content.title = "Erst \(offer.version) is available"
            content.body = "See what changed and update from Settings."
            let request = UNNotificationRequest(
                identifier: Self.notificationPrefix + offer.version, content: content, trigger: nil)
            try? await center.add(request)
        }
    }
}

extension UpdateController: SPUUserDriver {
    func show(_ request: SPUUpdatePermissionRequest, reply: @escaping (SUUpdatePermissionResponse) -> Void) {
        // Info.plist turns checks on, so Sparkle should not ask; if it does, keep checking.
        reply(SUUpdatePermissionResponse(automaticUpdateChecks: true, sendSystemProfile: false))
    }

    func showUserInitiatedUpdateCheck(cancellation: @escaping () -> Void) {
        userInitiatedCheck = true
        model.phase = .checking
    }

    func showUpdateFound(
        with appcastItem: SUAppcastItem, state: SPUUserUpdateState,
        reply: @escaping (SPUUserUpdateChoice) -> Void
    ) {
        let offer = UpdateOfferReader.offer(from: appcastItem)
        self.offer = offer
        pendingChoice = reply
        model.phase = state.stage == .notDownloaded ? .available(offer) : .ready(offer)
        updateLog.notice("Update \(offer.version, privacy: .public) found, stage \(state.stage.rawValue)")
        if !state.userInitiated { notifyOnce(offer) }
    }

    func showUpdateReleaseNotes(with downloadData: SPUDownloadData) {}

    func showUpdateReleaseNotesFailedToDownloadWithError(_ error: any Error) {}

    func showUpdateNotFoundWithError(_ error: any Error, acknowledgement: @escaping () -> Void) {
        model.phase = .upToDate(lastChecked: Date())
        acknowledgement()
    }

    func showUpdaterError(_ error: any Error, acknowledgement: @escaping () -> Void) {
        updateLog.error("Update failed: \(error.localizedDescription, privacy: .public)")
        let lastChecked = updater?.lastUpdateCheckDate
        // A quiet check in the background that fails says nothing; one the user asked for explains.
        if userInitiatedCheck || installRequested {
            model.phase = .failed(message: error.localizedDescription, lastChecked: lastChecked)
        } else {
            model.phase = .upToDate(lastChecked: lastChecked)
        }
        acknowledgement()
    }

    func showDownloadInitiated(cancellation: @escaping () -> Void) {
        cancelDownload = cancellation
        received = 0
        expected = nil
        showDownload()
    }

    func showDownloadDidReceiveExpectedContentLength(_ expectedContentLength: UInt64) {
        expected = Int64(expectedContentLength)
        showDownload()
    }

    func showDownloadDidReceiveData(ofLength length: UInt64) {
        received += Int64(length)
        showDownload()
    }

    func showDownloadDidStartExtractingUpdate() {
        cancelDownload = nil
        if let offer { model.phase = .preparing(offer) }
    }

    func showExtractionReceivedProgress(_ progress: Double) {}

    func showReady(toInstallAndRelaunch reply: @escaping (SPUUserUpdateChoice) -> Void) {
        if installRequested {
            reply(.install)
            return
        }
        pendingRelaunch = reply
        if let offer { model.phase = .ready(offer) }
    }

    func showInstallingUpdate(
        withApplicationTerminated applicationTerminated: Bool,
        retryTerminatingApplication: @escaping () -> Void
    ) {
        if let offer { model.phase = .installing(offer) }
        updateLog.notice("Installing the update; app terminated: \(applicationTerminated)")
    }

    func showUpdateInstalledAndRelaunched(_ relaunched: Bool, acknowledgement: @escaping () -> Void) {
        model.phase = .upToDate(lastChecked: Date())
        acknowledgement()
    }

    func showUpdateInFocus() {
        revealInSettings?()
    }

    func dismissUpdateInstallation() {
        pendingChoice = nil
        pendingRelaunch = nil
        cancelDownload = nil
        installRequested = false
        userInitiatedCheck = false
        offer = nil
        if case .failed = model.phase { return }
        model.phase = .upToDate(lastChecked: updater?.lastUpdateCheckDate)
    }
}

extension UpdateController: SPUUpdaterDelegate {
    nonisolated func feedURLString(for updater: SPUUpdater) -> String? {
        ProcessInfo.processInfo.environment[Self.feedOverrideKey].flatMap { $0.isEmpty ? nil : $0 }
    }
}

/// Turns a release in the feed into what Settings shows.
enum UpdateOfferReader {
    static func offer(from item: SUAppcastItem) -> SoftwareUpdateOffer {
        SoftwareUpdateOffer(
            version: item.displayVersionString,
            notes: notes(item.itemDescription ?? "", isHTML: item.itemDescriptionFormat != "plain-text"),
            size: item.contentLength > 0 ? Int64(item.contentLength) : nil,
            releasedAt: item.date
        )
    }

    /// One note per line, without list markers. HTML notes lose their tags, and list items and
    /// paragraphs become lines.
    static func notes(_ description: String, isHTML: Bool) -> [String] {
        var text = description
        if isHTML {
            text = text.replacingOccurrences(
                of: "<(li|p|br)[^>]*>", with: "\n", options: [.regularExpression, .caseInsensitive])
            text = text.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        }
        return text.split(whereSeparator: \.isNewline).compactMap { line in
            var note = line.trimmingCharacters(in: .whitespaces)
            if note.hasPrefix("- ") || note.hasPrefix("* ") { note.removeFirst(2) }
            return note.isEmpty ? nil : note
        }
    }
}
