import SwiftUI
import TartKit

/// Banner shown when the tart prerequisite is missing or outdated.
struct PrerequisiteBanner: View {
    let info: TartPrerequisiteGuidanceInfo
    let isChecking: Bool
    let onRecheck: () -> Void

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
                    Text(info.command)
                        .font(.system(.caption, design: .monospaced))
                        .padding(6)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .fill(.quaternary.opacity(0.5)))
                    CopyButton(value: info.command)
                        .buttonStyle(.borderless)
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
