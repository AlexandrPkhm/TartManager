import AppKit
import Testing
@testable import TartManager

@MainActor
@Suite struct WindowTitlebarConfigurationTests {
    private func makeWindow(styleMask: NSWindow.StyleMask = [.titled, .closable, .miniaturizable, .resizable])
        -> NSWindow {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 500),
                              styleMask: styleMask, backing: .buffered, defer: true)
        window.isReleasedWhenClosed = false
        return window
    }

    @Test func applyGivesTheWindowANativeUnifiedTitlebar() {
        let window = makeWindow()

        WindowTitlebarConfiguration.apply(to: window)

        #expect(window.toolbar != nil)
        #expect(window.toolbar?.showsBaselineSeparator == false)
        #expect(window.toolbarStyle == .unified)
        #expect(window.styleMask.contains(.fullSizeContentView))
        #expect(window.titlebarAppearsTransparent)
        #expect(window.titleVisibility == .hidden)
        #expect(window.standardWindowButton(.closeButton) != nil)
    }

    @Test func applyKeepsAnExistingToolbar() {
        let window = makeWindow()
        let existing = NSToolbar(identifier: "existing")
        window.toolbar = existing

        WindowTitlebarConfiguration.apply(to: window)
        WindowTitlebarConfiguration.apply(to: window)

        #expect(window.toolbar === existing)
        #expect(window.toolbarStyle == .unified)
    }

    @Test func titlebarHeightIsTheUnifiedHeightAfterApply() {
        let window = makeWindow()

        WindowTitlebarConfiguration.apply(to: window)

        #expect(WindowTitlebarConfiguration.titlebarHeight(of: window) >= 28)
    }

    @Test func windowWithoutTitlebarFallsBackToTheDefaultHeight() {
        let window = makeWindow(styleMask: [.borderless])

        #expect(WindowTitlebarConfiguration.titlebarHeight(of: window)
                == WindowTitlebarConfiguration.defaultHeight)
    }

    @Test func resolvedHeightRejectsMissingValues() {
        let fallback = WindowTitlebarConfiguration.defaultHeight
        #expect(WindowTitlebarConfiguration.resolvedHeight(0) == fallback)
        #expect(WindowTitlebarConfiguration.resolvedHeight(-4) == fallback)
        #expect(WindowTitlebarConfiguration.resolvedHeight(.nan) == fallback)
        #expect(WindowTitlebarConfiguration.resolvedHeight(.infinity) == fallback)
        #expect(WindowTitlebarConfiguration.resolvedHeight(60) == 60)
    }
}
