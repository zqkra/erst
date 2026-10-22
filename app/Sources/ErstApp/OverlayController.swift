import AppKit
import ErstKit
import ErstModel
import ErstUI
import SwiftUI

/// Shows Search, Timeline, and a Moment in floating panels over the user's apps.
///
/// The panel covers the screen under the pointer, the content sits centered in the visible
/// frame at the preset size, and the panel around it is a light dim. Escape and a click on
/// the dim close the top surface, and the Moment surface returns to the one below it.
@MainActor
final class OverlayController {
    /// SwiftUI's offscreen helper window, which the reference analysis excludes from its scan.
    private static let hiddenWindowIdentifier = "hidden-window"

    private let service: LiveMemoryService
    private let panel = OverlayPanel()
    private let backdrop = OverlayBackdrop()
    private var routes: [Route] = []
    /// Bumped on every show and hide, so a fade that ends late never hides a newer overlay.
    private var fadeGeneration = 0
    /// The app the user was in when the overlay opened. It gets focus back the moment the overlay
    /// closes, so a key typed during the fade lands there and not in Erst.
    private var previousApp: NSRunningApplication?

    /// The dim fades in under the arriving surface and out quicker than it came, because closing
    /// is the system answering, not the user deciding. Reduce Motion shows and hides at once.
    private static let fadeInSeconds: TimeInterval = 0.16
    private static let fadeOutSeconds: TimeInterval = 0.14

    /// Called with each surface the user opens, so onboarding can teach the shortcuts by doing.
    var onShow: ((OverlaySurface) -> Void)?
    /// Called when the overlay closes, so the onboarding window can come back.
    var onDismiss: (() -> Void)?

    private struct Route {
        let surface: OverlaySurface
        let view: OverlaySurfaceView
        /// Search inside a timeline route, so the search shortcut opens it there.
        var search: TimelineSearchPresentation?
    }

    init(service: LiveMemoryService) {
        self.service = service
        panel.contentView = backdrop
        backdrop.onOutsideClick = { [weak self] in self?.back() }
        panel.onEscape = { [weak self] in self?.back() }
    }

    /// Over the timeline, search grows out of the timeline's capsule instead of replacing it.
    func toggleSearch() {
        if panel.isVisible, let top = routes.last {
            if top.surface.isSearch {
                close()
                return
            }
            if let search = top.search {
                search.toggle()
                if search.isPresented { onShow?(.search) }
                return
            }
        }
        showSearch()
    }

    func toggleTimeline() {
        if panel.isVisible, routes.last?.surface.isTimeline == true {
            close()
        } else {
            showTimeline()
        }
    }

    func showSearch() {
        present([route(for: .search)])
    }

    func showTimeline(at date: Date = Date()) {
        present([route(for: .timeline(at: date))])
    }

    func showMoment(_ moment: Moment, terms: [String] = []) {
        var chain = routes
        if chain.last?.surface.isMoment == true { chain.removeLast() }
        chain.append(route(for: .moment(moment, terms: terms)))
        present(chain)
    }

    /// Closes the top surface: a Moment reveals the screen it came from, anything else closes.
    func back() {
        guard routes.count > 1 else {
            close()
            return
        }
        routes.removeLast()
        showTop()
        focusContent()
    }

    func close() {
        dismiss(restoringFocus: true)
    }

    /// Closes the chain. Deactivation passes `restoringFocus: false`, and termination also passes
    /// `animated: false` so nothing outlives the app.
    func dismiss(restoringFocus: Bool, animated: Bool = true) {
        // Handing focus back deactivates Erst, which asks again; the fade already running wins.
        if animated, routes.isEmpty, panel.isVisible, panel.ignoresMouseEvents { return }
        closeChain(restoringFocus: restoringFocus, animated: animated)
    }

    private func closeChain(restoringFocus: Bool, animated: Bool) {
        let wasOpen = !routes.isEmpty
        routes.removeAll()
        if wasOpen { onDismiss?() }
        fadeGeneration += 1
        let generation = fadeGeneration
        let handsFocusBack = restoringFocus && NSApp.isActive && !hasOtherVisibleWindow
        if handsFocusBack, let previousApp, !previousApp.isTerminated {
            NSApp.yieldActivation(to: previousApp)
            previousApp.activate()
        }
        guard animated, panel.isVisible, !reducesMotion else {
            finishDismiss(generation: generation, handsFocusBack: handsFocusBack)
            return
        }
        panel.ignoresMouseEvents = true
        NSAnimationContext.runAnimationGroup { context in
            context.duration = Self.fadeOutSeconds
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 0
        } completionHandler: { [weak self] in
            Task { @MainActor in
                self?.finishDismiss(generation: generation, handsFocusBack: handsFocusBack)
            }
        }
    }

    /// Takes the faded panel away, unless the overlay opened again during the fade. Hiding the app
    /// hands focus back when no previous app took it.
    private func finishDismiss(generation: Int, handsFocusBack: Bool) {
        guard fadeGeneration == generation else { return }
        backdrop.subviews.forEach { $0.removeFromSuperview() }
        panel.orderOut(nil)
        panel.alphaValue = 1
        panel.ignoresMouseEvents = false
        if handsFocusBack { restoreFocus() }
        Task { [service] in await service.releaseImageMemory() }
    }

    private func present(_ chain: [Route]) {
        guard let screen = screenForOverlay() else { return }
        fadeGeneration += 1
        let appearing = !panel.isVisible || panel.ignoresMouseEvents
        if appearing, !panel.isVisible {
            previousApp = NSWorkspace.shared.frontmostApplication.flatMap {
                $0 == NSRunningApplication.current ? nil : $0
            }
            panel.alphaValue = reducesMotion ? 1 : 0
        }
        panel.ignoresMouseEvents = false
        if panel.frame != screen.frame {
            panel.setFrame(screen.frame, display: false)
        }
        routes = chain
        showTop()
        WindowPlacement.bringToFront(panel)
        if appearing, panel.alphaValue < 1 {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = Self.fadeInSeconds
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                panel.animator().alphaValue = 1
            }
        }
        focusContent()
        if let surface = chain.last?.surface { onShow?(surface) }
    }

    private var reducesMotion: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    /// Places the top surface at its preset size and removes the other routes from the view tree.
    /// Their hosting views stay alive so returning to a Moment's origin keeps its state.
    private func showTop() {
        backdrop.subviews.forEach { $0.removeFromSuperview() }
        guard let top = routes.last, let screen = screenForOverlay() else { return }
        let size = OverlayLayout.contentSize(for: top.surface, in: screen.visibleFrame)
        top.view.frame = OverlayLayout.contentFrame(
            for: size, in: screen.visibleFrame, panelFrame: panel.frame)
        top.view.autoresizingMask = []
        backdrop.addSubview(top.view)
    }

    private func focusContent() {
        guard let top = routes.last else { return }
        panel.makeFirstResponder(top.view.hosting)
    }

    /// The panel's own screen while it is open, the screen under the pointer otherwise.
    private func screenForOverlay() -> NSScreen? {
        if panel.isVisible {
            if let screen = NSScreen.screens.first(where: { $0.frame == panel.frame }) { return screen }
        }
        return WindowPlacement.screenWithPointer()
    }

    /// Hands focus back to the app the user was in, as the reference analysis does when the
    /// chain closes and no other Erst window is visible.
    private func restoreFocus() {
        guard NSApp.isActive, !hasOtherVisibleWindow else { return }
        NSApp.hide(nil)
    }

    private var hasOtherVisibleWindow: Bool {
        NSApp.windows.contains { window in
            guard window !== panel, window.canBecomeKey else { return false }
            guard window.identifier?.rawValue != Self.hiddenWindowIdentifier else { return false }
            guard window.frame.width > 0, window.frame.height > 0 else { return false }
            return window.isVisible || window.isMiniaturized
        }
    }

    private func route(for surface: OverlaySurface) -> Route {
        switch surface {
        case .search:
            let screen = SearchScreen(
                service: service,
                onOpenMoment: { [weak self] moment, terms in self?.showMoment(moment, terms: terms) },
                onClose: { [weak self] in self?.back() })
            return Route(surface: surface, view: Self.surface(screen))
        case .timeline(let date):
            // Search keeps the size it has on its own; the timeline anchors it to the capsule.
            let search = TimelineSearchPresentation(
                panelSize: screenForOverlay().map {
                    OverlayLayout.contentSize(for: .search, in: $0.visibleFrame)
                })
            let screen = TimelineScreen(
                service: service, now: date, search: search,
                onClose: { [weak self] in self?.back() },
                onOpenMoment: { [weak self] in self?.showMoment($0) },
                onOpenSearchResult: { [weak self] moment, terms in self?.showMoment(moment, terms: terms) })
            return Route(surface: surface, view: Self.surface(screen), search: search)
        case .moment(let moment, let terms):
            let screen = MomentScreen(
                service: service, moment: moment, highlightedTerms: terms,
                onOpenTimeline: { [weak self] in self?.showTimeline(at: $0) },
                onClose: { [weak self] in self?.back() })
            return Route(surface: surface, view: Self.surface(screen))
        }
    }

    private static func surface<Screen: View>(_ screen: Screen) -> OverlaySurfaceView {
        OverlaySurfaceView(NSHostingView(rootView: AnyView(screen)))
    }
}
