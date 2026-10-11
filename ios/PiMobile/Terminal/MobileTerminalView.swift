import Foundation
import SwiftUI
import UIKit
import SwiftTerm
import PiMobileCore

/// Mobile terminal renders connection-local cumulative ANSI history; input control is always an explicit parent decision.
@MainActor
public struct MobileTerminalView: UIViewRepresentable {
    public typealias UIViewType = SwiftTerm.TerminalView
    private let frame: TerminalFrame?
    private let onInput: (Data) -> Void
    private let onResize: (Int, Int) -> Void
    private let interactive: Bool

    /// Pass SSHBridgeConnection.terminalFrame, not incremental wire events, so repeated SwiftUI updates stay idempotent.
    public init(frame: TerminalFrame?, onInput: @escaping (Data) -> Void,
                onResize: @escaping (Int, Int) -> Void, interactive: Bool) {
        self.frame = frame; self.onInput = onInput; self.onResize = onResize; self.interactive = interactive
    }

    /// Creates a SwiftTerm renderer only; no local process or SSH PTY is started.
    public func makeUIView(context: Context) -> SwiftTerm.TerminalView {
        let view = MobileTerminalHostView(frame: .zero, font: .monospacedSystemFont(ofSize: 12, weight: .regular))
        view.terminalDelegate = context.coordinator
        view.allowMouseReporting = false
        view.inputEnabled = interactive
        context.coordinator.update(parent: self, view: view)
        return view
    }

    /// Updates callback ownership without feeding the same history twice.
    public func updateUIView(_ uiView: SwiftTerm.TerminalView, context: Context) {
        (uiView as? MobileTerminalHostView)?.inputEnabled = interactive
        if !interactive { _ = uiView.resignFirstResponder() }
        context.coordinator.update(parent: self, view: uiView)
    }

    /// Coordinator implements the pinned SwiftTerm delegate, including explicit clipboard and link denial.
    public func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    /// Teardown follows SwiftTerm's GPU-idle close requirement instead of detaching a busy renderer.
    public static func dismantleUIView(_ uiView: SwiftTerm.TerminalView, coordinator: Coordinator) {
        coordinator.interactive = false
        uiView.terminalDelegate = nil
        _ = uiView.resignFirstResponder()
        closeWhenMetalIsIdle(uiView)
    }

    private static func closeWhenMetalIsIdle(_ view: SwiftTerm.TerminalView) {
        guard !view.updateUiClosed() else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { closeWhenMetalIsIdle(view) }
    }

    /// SwiftTerm delegate forwards bytes and measured columns/rows only while input control is enabled.
    @MainActor
    public final class Coordinator: NSObject, TerminalViewDelegate {
        fileprivate var interactive: Bool
        private var onInput: (Data) -> Void
        private var onResize: (Int, Int) -> Void
        private var terminalID: String?
        private var encodedHistory: String?
        private var consumed = Data()
        private var lastResize: (cols: Int, rows: Int)?

        fileprivate init(parent: MobileTerminalView) {
            interactive = parent.interactive; onInput = parent.onInput; onResize = parent.onResize
        }

        fileprivate func update(parent: MobileTerminalView, view: SwiftTerm.TerminalView) {
            let gainedControl = !interactive && parent.interactive
            interactive = parent.interactive
            onInput = parent.onInput
            onResize = parent.onResize
            if gainedControl { lastResize = nil }
            guard let frame = parent.frame else {
                if terminalID != nil { view.resetToInitialState() }
                terminalID = nil; encodedHistory = nil; consumed.removeAll()
                return
            }
            guard (1...4096).contains(frame.cols), (1...4096).contains(frame.rows) else { return }
            let dimensions = view.terminalDimensions
            if !interactive, dimensions.cols != frame.cols || dimensions.rows != frame.rows {
                view.resize(cols: frame.cols, rows: frame.rows)
            }
            if terminalID != frame.terminalId || encodedHistory != frame.data {
                guard let bytes = frame.bytes else { return }
                if terminalID != frame.terminalId || !bytes.starts(with: consumed) {
                    view.resetToInitialState()
                    consumed.removeAll()
                }
                let fresh = Array(bytes.dropFirst(consumed.count))
                terminalID = frame.terminalId
                encodedHistory = frame.data
                consumed = bytes
                if !fresh.isEmpty { view.feed(byteArray: fresh[...]) }
            }
            // A control transition can occur without a fresh layout/delegate callback.
            if gainedControl {
                let size = view.terminalDimensions
                sizeChanged(source: view, newCols: size.cols, newRows: size.rows)
            }
        }

        /// Resize callbacks report character cells and are deduplicated; observe mode never changes the host size.
        public func sizeChanged(source: SwiftTerm.TerminalView, newCols: Int, newRows: Int) {
            guard interactive, (1...4096).contains(newCols), (1...4096).contains(newRows),
                  lastResize?.cols != newCols || lastResize?.rows != newRows else { return }
            lastResize = (newCols, newRows)
            let callback = onResize
            Task { @MainActor [weak self] in
                guard let self, self.interactive,
                      self.lastResize?.cols == newCols, self.lastResize?.rows == newRows else { return }
                callback(newCols, newRows)
            }
        }

        /// Keyboard input and terminal query replies are gated by the parent's explicit control state.
        public func send(source: SwiftTerm.TerminalView, data: ArraySlice<UInt8>) {
            guard interactive else { return }
            let bytes = Data(data)
            let callback = onInput
            Task { @MainActor [weak self] in
                guard self?.interactive == true else { return }
                callback(bytes)
            }
        }

        /// Remote terminal titles do not change native navigation.
        public func setTerminalTitle(source: SwiftTerm.TerminalView, title: String) {}
        /// Remote working-directory OSC messages do not override authoritative topology.
        public func hostCurrentDirectoryUpdate(source: SwiftTerm.TerminalView, directory: String?) {}
        /// Scroll updates remain local to the renderer.
        public func scrolled(source: SwiftTerm.TerminalView, position: Double) {}
        /// Terminal escape sequences cannot open external links automatically.
        public func requestOpenLink(source: SwiftTerm.TerminalView, link: String, params: [String: String]) {}
        /// Remote bells do not generate notifications or background work.
        public func bell(source: SwiftTerm.TerminalView) {}
        /// Remote clipboard writes are denied, including OSC 52.
        public func clipboardCopy(source: SwiftTerm.TerminalView, content: Data) {}
        /// Remote clipboard reads never expose the phone's pasteboard.
        public func clipboardRead(source: SwiftTerm.TerminalView) -> Data? { nil }
        /// Unknown iTerm payloads are ignored rather than executed.
        public func iTermContent(source: SwiftTerm.TerminalView, content: ArraySlice<UInt8>) {}
        /// Rendering changes do not create transport traffic.
        public func rangeChanged(source: SwiftTerm.TerminalView, startY: Int, endY: Int) {}
    }
}

/// Observe mode preserves scrolling/selection but cannot summon an input keyboard.
private final class MobileTerminalHostView: SwiftTerm.TerminalView {
    var inputEnabled = false
    override var canBecomeFirstResponder: Bool { inputEnabled && super.canBecomeFirstResponder }
}

/// Phone keys let parent UI offer useful controls without reaching into the SwiftTerm renderer.
public enum MobileTerminalKey: String, CaseIterable, Identifiable {
    case escape, tab, enter, backspace, up, down, left, right, controlC, controlD
    /// Stable key identity is suitable for a native phone-key toolbar.
    public var id: String { rawValue }
    /// Key bytes use standard ANSI cursor mode; parent must still require writable terminal attachment.
    public var bytes: Data {
        let sequence: String
        switch self {
        case .escape: sequence = "\u{1B}"
        case .tab: sequence = "\t"
        case .enter: sequence = "\r"
        case .backspace: sequence = "\u{7F}"
        case .up: sequence = "\u{1B}[A"
        case .down: sequence = "\u{1B}[B"
        case .right: sequence = "\u{1B}[C"
        case .left: sequence = "\u{1B}[D"
        case .controlC: sequence = "\u{03}"
        case .controlD: sequence = "\u{04}"
        }
        return Data(sequence.utf8)
    }
}
