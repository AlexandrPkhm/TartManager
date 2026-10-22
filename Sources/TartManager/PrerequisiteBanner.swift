import SwiftUI
import TartKit

/// Banner shown when the active tart is missing, damaged, outdated, or
/// cannot run. It offers the other source only when that source checks as
/// `.ok` (`info.switchTo`).
struct PrerequisiteBanner: View {
    let info: TartPrerequisiteGuidanceInfo
    let isChecking: Bool
    let onRecheck: () -> Void
    let onSwitch: (TartSource) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.yellow)
                .font(.title2)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 6) {
                Text(info.headline).font(.headline)
                Text(info.detail).font(.subheadline)
                    .foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    if let command = info.command {
                        Text(command)
                            .font(.system(.caption, design: .monospaced))
                            .padding(6)
                            .background(
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(.quaternary.opacity(0.5)))
                        CopyButton(value: command)
                            .buttonStyle(.borderless)
                    }
                    if let source = info.switchTo {
                        Button(TartPrerequisiteGuidance.switchLabel(for: source)) { onSwitch(source) }
                            .disabled(isChecking)
                    }
                    Button(isChecking ? "Checking…" : "Re-check") { onRecheck() }
                        .buttonStyle(.borderless)
                        .disabled(isChecking)
                }
            }
            Spacer()
        }
        .padding(12)
        .background(.orange.opacity(0.12))
        .overlay(alignment: .top) { Rectangle().fill(.orange).frame(height: 3) }
    }
}
