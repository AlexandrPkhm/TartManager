import SwiftUI
import AppKit

/// Gives the main window a native unified title bar, so AppKit places the
/// window controls (close, minimize, zoom) itself. The custom top row then
/// uses the native title-bar height, so the controls stay centered on it
/// and do not move during live resize (issue #2).
struct UnifiedTitlebar: NSViewRepresentable {
    /// Receives the native title-bar height in points.
    let onHeightChange: (CGFloat) -> Void

    func makeNSView(context: Context) -> AttachmentView {
        AttachmentView(onHeightChange: onHeightChange)
    }

    func updateNSView(_ view: AttachmentView, context: Context) {
        view.onHeightChange = onHeightChange
    }

    final class AttachmentView: NSView {
        var onHeightChange: (CGFloat) -> Void

        init(onHeightChange: @escaping (CGFloat) -> Void) {
            self.onHeightChange = onHeightChange
            super.init(frame: .zero)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window else { return }
            WindowTitlebarConfiguration.apply(to: window)
            reportHeight()
        }

        override func layout() {
            super.layout()
            reportHeight()
        }

        private func reportHeight() {
            guard let window else { return }
            let height = WindowTitlebarConfiguration.titlebarHeight(of: window)
            DispatchQueue.main.async { [weak self] in self?.onHeightChange(height) }
        }
    }
}

