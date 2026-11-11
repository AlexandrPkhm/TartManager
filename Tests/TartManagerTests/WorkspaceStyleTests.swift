import AppKit
import Foundation
import SwiftUI
import Testing
@testable import TartManager

@MainActor
@Suite struct WorkspaceStyleTests {
    // MARK: - Helpers

    /// Resolves a dynamic workspace color as 0xRRGGBB in one appearance.
    private func hex(_ color: Color, _ name: NSAppearance.Name) -> UInt32 {
        var value: UInt32 = 0
        NSAppearance(named: name)!.performAsCurrentDrawingAppearance {
            let rgb = NSColor(color).usingColorSpace(.sRGB)!
            let channel = { (component: CGFloat) in UInt32((component * 255).rounded()) }
            value = channel(rgb.redComponent) << 16 | channel(rgb.greenComponent) << 8
                | channel(rgb.blueComponent)
        }
        return value
    }

    /// WCAG 2 contrast ratio of two 0xRRGGBB values.
    private func contrast(_ first: UInt32, _ second: UInt32) -> Double {
        func luminance(_ hex: UInt32) -> Double {
            let channels = [hex >> 16 & 255, hex >> 8 & 255, hex & 255].map { channel -> Double in
                let value = Double(channel) / 255
                return value <= 0.03928 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
            }
            return 0.2126 * channels[0] + 0.7152 * channels[1] + 0.0722 * channels[2]
        }
        let (a, b) = (luminance(first), luminance(second))
        return (max(a, b) + 0.05) / (min(a, b) + 0.05)
    }

    private let appearances: [NSAppearance.Name] = [.aqua, .darkAqua]

    // MARK: - Tokens

    @Test func dangerHasExplicitLightAndDarkValues() {
        #expect(hex(WorkspaceStyle.danger, .aqua) == 0xc0281e)
        #expect(hex(WorkspaceStyle.danger, .darkAqua) == 0xff8b80)
    }

    @Test func onPrimaryIsWhiteInBothAppearances() {
        for appearance in appearances {
            #expect(hex(WorkspaceStyle.onPrimary, appearance) == 0xffffff)
        }
    }

    @Test func dangerTextReadsOnEveryWorkspaceGround() {
        let grounds = [WorkspaceStyle.background, WorkspaceStyle.sidebar,
                       WorkspaceStyle.panel, WorkspaceStyle.warningBackground]
        for appearance in appearances {
            for ground in grounds {
                let ratio = contrast(hex(WorkspaceStyle.danger, appearance), hex(ground, appearance))
                #expect(ratio >= 4.5, "danger on a ground in \(appearance.rawValue): \(ratio)")
            }
        }
    }

    @Test func onPrimaryReadsOnPrimary() {
        for appearance in appearances {
            let ratio = contrast(hex(WorkspaceStyle.onPrimary, appearance),
                                 hex(WorkspaceStyle.primary, appearance))
            #expect(ratio >= 4.5, "onPrimary on primary in \(appearance.rawValue): \(ratio)")
        }
    }

    @Test func mutedTextReadsOnTheWarningBanner() {
        for appearance in appearances {
            let ratio = contrast(hex(WorkspaceStyle.muted, appearance),
                                 hex(WorkspaceStyle.warningBackground, appearance))
            #expect(ratio >= 4.5, "muted on warningBackground in \(appearance.rawValue): \(ratio)")
        }
    }

    // MARK: - Source guard

    /// Every view color comes from WorkspaceStyle (AGENTS.md, Code Quality).
    /// `MenuBarIcon` draws a template image, whose mask must be black.
    @Test func viewsUseNoSystemColors() throws {
        let sources = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/TartManager")
        let banned = try Regex(
            #"(\(|: |\? )\.(red|orange|yellow|green|blue|secondary|tertiary|quaternary)\b|Color\.(red|orange|yellow|green|blue|white|black)\b"#)
        var offenders: [String] = []
        for file in try FileManager.default.contentsOfDirectory(atPath: sources.path)
        where file.hasSuffix(".swift") && file != "MenuBarIcon.swift" {
            let text = try String(contentsOf: sources.appendingPathComponent(file), encoding: .utf8)
            for (index, line) in text.components(separatedBy: "\n").enumerated()
            where line.contains(banned) {
                offenders.append("\(file):\(index + 1)")
            }
        }
        #expect(offenders.isEmpty, "System colors in views: \(offenders)")
    }
}
