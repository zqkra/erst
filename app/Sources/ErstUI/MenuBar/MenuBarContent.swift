import ErstModel
import SwiftUI

/// The window shown from the menu bar.
public struct MenuBarContent: View {
    @StateObject private var model: MenuBarModel
    @FocusState private var isFocused: Bool
    private let onSearch: () -> Void
    private let onOpenTimeline: () -> Void
    private let onOpenActivity: () -> Void
    private let onPause: () -> Void
    private let onResume: () -> Void
    private let onOpenSettings: () -> Void
    private let onFixPermission: () -> Void
    private let onQuit: () -> Void

    public init(
        service: any MemoryService,
        onSearch: @escaping () -> Void = {},
        onOpenTimeline: @escaping () -> Void = {},
        onOpenActivity: @escaping () -> Void = {},
        onPause: @escaping () -> Void = {},
        onResume: @escaping () -> Void = {},
        onOpenSettings: @escaping () -> Void = {},
        onFixPermission: @escaping () -> Void = {},
        onQuit: @escaping () -> Void = {}
    ) {
        _model = StateObject(wrappedValue: MenuBarModel(service: service))
        self.onSearch = onSearch
        self.onOpenTimeline = onOpenTimeline
        self.onOpenActivity = onOpenActivity
        self.onPause = onPause
        self.onResume = onResume
        self.onOpenSettings = onOpenSettings
        self.onFixPermission = onFixPermission
        self.onQuit = onQuit
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            today
            if let apps = model.summary?.topApps, !apps.isEmpty {
                separator
                MenuBarSectionTitle(title: "Most used today")
                MenuBarTopApps(apps: apps)
            }
            separator
            rows(MenuBarAction.commands(isPaused: model.isPaused))
            separator
            rows(MenuBarAction.application)
        }
        .padding(.bottom, MenuBarLayout.rowInset)
        .frame(width: MenuBarLayout.width)
        .focusable()
        .focusEffectDisabled()
        .focused($isFocused)
        .onKeyPress(.downArrow) {
            model.moveHighlight(by: 1)
            return .handled
        }
        .onKeyPress(.upArrow) {
            model.moveHighlight(by: -1)
            return .handled
        }
        .onKeyPress(.return) {
            guard let highlighted = model.highlighted else { return .ignored }
            perform(highlighted)
            return .handled
        }
        .darkWindowAppearance()
        .task {
            Typography.registerFonts()
            isFocused = true
            await model.load()
        }
    }

    /// No title: the menu bar icon already says this is Erst. The recorder state shows above the
    /// numbers only when recording is not normal.
    private var today: some View {
        VStack(alignment: .leading, spacing: 0) {
            if model.showsStatus {
                MenuBarStatus(status: model.status, onFixPermission: onFixPermission)
                    .padding(.bottom, Spacing.medium)
            }
            MenuBarStats(summary: model.summary)
            MenuBarHeatStrip(heat: model.summary?.heat ?? [], range: model.summary?.range)
                .padding(.top, Spacing.large)
        }
        .padding(.horizontal, MenuBarLayout.contentInset)
        .padding(.top, MenuBarLayout.contentInset)
        .padding(.bottom, Spacing.small)
    }

    private var separator: some View {
        Rectangle()
            .fill(Color.erstHairline)
            .frame(height: ControlMetrics.hairlinePoints)
            .padding(.horizontal, MenuBarLayout.contentInset)
            .padding(.vertical, MenuBarLayout.separatorGap)
    }

    private func rows(_ actions: [MenuBarAction]) -> some View {
        VStack(spacing: 0) {
            ForEach(actions, id: \.self) { action in
                MenuBarRow(
                    action: action,
                    isHighlighted: model.highlighted == action,
                    onHover: { model.hover(action, inside: $0) },
                    perform: { perform(action) }
                )
            }
        }
    }

    private func perform(_ action: MenuBarAction) {
        switch action {
        case .openTimeline: onOpenTimeline()
        case .search: onSearch()
        case .activity: onOpenActivity()
        case .pause: onPause()
        case .resume: onResume()
        case .settings: onOpenSettings()
        case .quit: onQuit()
        }
    }
}
