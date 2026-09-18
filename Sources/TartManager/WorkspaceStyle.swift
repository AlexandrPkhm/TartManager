import SwiftUI
import AppKit

/// The approved workspace palette, with explicit light and dark appearances.
enum WorkspaceStyle {
    static let background = color(0xfafafa, 0x202123)
    static let sidebar = color(0xeeeeef, 0x28292c)
    static let panel = color(0xffffff, 0x2b2c2f)
    static let line = color(0xdedee2, 0x3c3d41)
    static let text = color(0x202126, 0xf0f0f3)
    static let muted = color(0x64666f, 0xa7a9b1)
    static let accent = color(0x1762ce, 0x79acff)
    static let selected = color(0xdce9fb, 0x303f58)
    static let green = color(0x197345, 0x77d6a0)
    static let primary = color(0x246bdb, 0x246bdb)

    private static func color(_ light: UInt32, _ dark: UInt32) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let hex = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
            return NSColor(srgbRed: CGFloat((hex >> 16) & 255) / 255,
                           green: CGFloat((hex >> 8) & 255) / 255,
                           blue: CGFloat(hex & 255) / 255, alpha: 1)
        })
    }
}

struct WorkspaceButtonStyle: ButtonStyle {
    var primary = false
    var flat = false
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .medium))
            .padding(.horizontal, 13).padding(.vertical, 8)
            .foregroundStyle(primary ? Color.white : WorkspaceStyle.text)
            .background(primary ? WorkspaceStyle.primary : flat ? .clear : WorkspaceStyle.panel,
                        in: RoundedRectangle(cornerRadius: 7))
            .overlay(RoundedRectangle(cornerRadius: 7)
                .strokeBorder(primary || flat ? .clear : WorkspaceStyle.line, lineWidth: 1))
            .opacity(!isEnabled ? 0.4 : configuration.isPressed ? 0.7 : 1)
            .contentShape(RoundedRectangle(cornerRadius: 7))
    }
}

extension View {
    func workspacePanel() -> some View {
        background(WorkspaceStyle.panel, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(WorkspaceStyle.line, lineWidth: 1))
    }
}

struct WorkspaceEmptyState<Actions: View>: View {
    let symbol: String
    let title: String
    let message: String
    @ViewBuilder var actions: () -> Actions

    var body: some View {
        VStack(spacing: 0) {
            Image(systemName: symbol).font(.system(size: 24)).foregroundStyle(WorkspaceStyle.muted)
                .padding(.bottom, 13)
            Text(title).font(.system(size: 13, weight: .semibold)).padding(.bottom, 7)
            Text(message).font(.system(size: 12)).foregroundStyle(WorkspaceStyle.muted)
                .multilineTextAlignment(.center).padding(.bottom, 17)
            actions().buttonStyle(WorkspaceButtonStyle())
        }
        .frame(maxWidth: .infinity).padding(.vertical, 33)
    }
}

enum WorkspacePage { case machines, images }
