import ErstModel
import Foundation
import Observation
import SwiftUI

/// The updater as Settings and the menu bar see it. The app drives it from Sparkle; snapshots set a
/// phase and leave the actions empty.
@MainActor
@Observable
public final class SoftwareUpdateModel {
    /// What the update buttons do. The app fills these in when the updater starts.
    public struct Actions {
        public var check: @MainActor () -> Void
        public var install: @MainActor () -> Void
        public var cancel: @MainActor () -> Void
        public var setChecksAutomatically: @MainActor (Bool) -> Void
        public var setInstallsAutomatically: @MainActor (Bool) -> Void

        public init(
            check: @escaping @MainActor () -> Void,
            install: @escaping @MainActor () -> Void,
            cancel: @escaping @MainActor () -> Void,
            setChecksAutomatically: @escaping @MainActor (Bool) -> Void,
            setInstallsAutomatically: @escaping @MainActor (Bool) -> Void
        ) {
            self.check = check
            self.install = install
            self.cancel = cancel
            self.setChecksAutomatically = setChecksAutomatically
            self.setInstallsAutomatically = setInstallsAutomatically
        }

        public static var none: Actions {
            Actions(
                check: {}, install: {}, cancel: {}, setChecksAutomatically: { _ in },
                setInstallsAutomatically: { _ in })
        }
    }

    public var phase: SoftwareUpdatePhase
    public var checksAutomatically: Bool
    public var installsAutomatically: Bool
    /// Set when the menu bar or a notification asks Settings to open on the update.
    public var revealRequested = false
    @ObservationIgnored public var actions: Actions

    public init(
        phase: SoftwareUpdatePhase = .upToDate(lastChecked: nil),
        checksAutomatically: Bool = true,
        installsAutomatically: Bool = false,
        actions: Actions = .none
    ) {
        self.phase = phase
        self.checksAutomatically = checksAutomatically
        self.installsAutomatically = installsAutomatically
        self.actions = actions
    }

    /// The menu bar row while there is an update to act on, and nil otherwise.
    public var menuTitle: String? {
        switch phase {
        case .available(let offer): "Update to Erst \(offer.version)"
        case .downloading, .preparing, .installing: "Updating Erst\u{2026}"
        case .ready: "Relaunch to Update"
        case .upToDate, .checking, .failed: nil
        }
    }

    var checksBinding: Binding<Bool> {
        Binding(
            get: { self.checksAutomatically },
            set: {
                self.checksAutomatically = $0
                self.actions.setChecksAutomatically($0)
            })
    }

    var installsBinding: Binding<Bool> {
        Binding(
            get: { self.installsAutomatically },
            set: {
                self.installsAutomatically = $0
                self.actions.setInstallsAutomatically($0)
            })
    }
}
