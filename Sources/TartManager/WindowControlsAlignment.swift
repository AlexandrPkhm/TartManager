import SwiftUI
import AppKit

/// Aligns the existing native window controls with the custom top row.
/// AppKit keeps ownership of their actions, hover states, and accessibility.
struct WindowControlsAlignment: NSViewRepresentable {
    func makeNSView(context: Context) -> AttachmentView {
        AttachmentView()
    }

    func updateNSView(_ view: AttachmentView, context: Context) {
        view.needsLayout = true
    }

    final class AttachmentView: NSView {
        private var layoutScheduled = false

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            NotificationCenter.default.removeObserver(self)
            if let window {
                for notification in [NSWindow.didResizeNotification,
                                     NSWindow.didEndLiveResizeNotification,
                                     NSWindow.didBecomeKeyNotification,
                                     NSWindow.didExitFullScreenNotification] {
                    NotificationCenter.default.addObserver(self, selector: #selector(scheduleLayout),
                                                           name: notification, object: window)
                }
                let buttons = [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton]
                    .compactMap { window.standardWindowButton($0) }
                let views: [NSView] = buttons + [buttons.first?.superview].compactMap { $0 }
                for view in views {
                    view.postsFrameChangedNotifications = true
                    NotificationCenter.default.addObserver(self, selector: #selector(scheduleLayout),
                                                           name: NSView.frameDidChangeNotification,
                                                           object: view)
                }
            }
            scheduleLayout()
        }

        override func layout() {
            super.layout()
            scheduleLayout()
        }

        // Run after AppKit's own title-bar layout, which can reset the frames.
        @objc private func scheduleLayout() {
            guard !layoutScheduled else { return }
            layoutScheduled = true
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.layoutScheduled = false
                self.centerButtons()
            }
        }

        private func centerButtons() {
            guard let window, !window.styleMask.contains(.fullScreen), bounds.height > 0,
                  let close = window.standardWindowButton(.closeButton),
                  let container = close.superview,
                  let parent = container.superview else { return }
            let row = convert(bounds, to: parent)
            var frame = container.frame
            frame.origin.y = row.minY
            frame.size.height = row.height
            if container.frame != frame { container.frame = frame }
            for kind in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
                guard let button = window.standardWindowButton(kind) else { continue }
                var origin = button.frame.origin
                origin.y = (container.bounds.height - button.frame.height) / 2
                if button.frame.origin != origin { button.setFrameOrigin(origin) }
            }
        }
    }
}
