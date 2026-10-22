import AppKit
import ErstModel
import SwiftUI

extension View {
    /// Routes arrow keys, Return, and Escape to search while the panel is open.
    func searchKeyboard(
        model: SearchModel,
        onOpen: @escaping (SearchHit) -> Void,
        onClose: @escaping () -> Void
    ) -> some View {
        modifier(SearchKeyboardModifier(model: model, onOpen: onOpen, onClose: onClose))
    }
}

private struct SearchKeyboardModifier: ViewModifier {
    let model: SearchModel
    let onOpen: (SearchHit) -> Void
    let onClose: () -> Void
    func body(content: Content) -> some View {
        content
            .background(SearchKeyboardWindow(monitor: model.keyboard))
            .onAppear {
                model.keyboard.start(model: model, onOpen: onOpen, onClose: onClose)
            }
            .onDisappear {
                model.keyboard.stop()
            }
    }
}

private struct SearchKeyboardWindow: NSViewRepresentable {
    let monitor: SearchKeyMonitor

    func makeNSView(context: Context) -> SearchKeyboardWindowView {
        SearchKeyboardWindowView(monitor: monitor)
    }

    func updateNSView(_ nsView: SearchKeyboardWindowView, context: Context) {
        monitor.window = nsView.window
    }
}

private final class SearchKeyboardWindowView: NSView {
    private weak var monitor: SearchKeyMonitor?

    init(monitor: SearchKeyMonitor) {
        self.monitor = monitor
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) { nil }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        monitor?.window = window
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

@MainActor
final class SearchKeyMonitor {
    weak var window: NSWindow?
    private var monitor: Any?
    private weak var model: SearchModel?
    private var onOpen: ((SearchHit) -> Void)?
    private var onClose: (() -> Void)?

    private let escapeKeyCode: UInt16 = 53
    private let returnKeyCode: UInt16 = 36
    private let keypadEnterKeyCode: UInt16 = 76
    private let leftArrowKeyCode: UInt16 = 123
    private let rightArrowKeyCode: UInt16 = 124
    private let downArrowKeyCode: UInt16 = 125
    private let upArrowKeyCode: UInt16 = 126
    private let singleColumnStepCount = 1

    func start(
        model: SearchModel,
        onOpen: @escaping (SearchHit) -> Void,
        onClose: @escaping () -> Void
    ) {
        self.model = model
        self.onOpen = onOpen
        self.onClose = onClose
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            return handle(event)
        }
    }

    func stop() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
        model = nil
        onOpen = nil
        onClose = nil
    }

    private func handle(_ event: NSEvent) -> NSEvent? {
        guard let window, event.window === window, window.isKeyWindow, let model else { return event }
        guard event.modifierFlags.intersection([.command, .control, .option]).isEmpty else {
            return event
        }
        switch event.keyCode {
        case escapeKeyCode:
            if model.query.isEmpty {
                onClose?()
            } else {
                model.clearQuery()
            }
            return nil
        case returnKeyCode, keypadEnterKeyCode:
            if let hit = model.selectedHit {
                onOpen?(hit)
            }
            return nil
        case leftArrowKeyCode:
            model.moveSelection(by: -singleColumnStepCount)
            return nil
        case rightArrowKeyCode:
            model.moveSelection(by: singleColumnStepCount)
            return nil
        case downArrowKeyCode:
            model.moveSelection(by: SearchModel.resultColumnCount)
            return nil
        case upArrowKeyCode:
            model.moveSelection(by: -SearchModel.resultColumnCount)
            return nil
        default:
            return event
        }
    }
}
