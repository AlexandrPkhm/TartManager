import SwiftUI
import TartKit

/// Settings → General → Tart: the source choice (Bundled / Path), the
/// read-only path with **Choose…** and **Reset**, and the active tart with
/// **Re-check**. All copy and control states come from `TartSettingsCopy`;
/// every change goes through `AppModel`, which gates and validates it.
struct TartSettingsPanel: View {
    @EnvironmentObject var model: AppModel
    /// Why the last **Choose…** was refused; cleared by the next change.
    @State private var chooseRejection: String?

    var body: some View {
        SettingsPanel(title: "Tart") {
            if let report = model.tartReport {
                content(TartSettingsCopy(
                    report: report,
                    customPath: model.settings.tartCustomPath,
                    runningJobs: model.tartJobsRunningCount))
            } else {
                LabeledContent("Active tart") {
                    Text("Checking for tart…").foregroundStyle(WorkspaceStyle.muted)
                }
            }
        }
    }

    @ViewBuilder
    private func content(_ copy: TartSettingsCopy) -> some View {
        LabeledContent("Source") {
            HStack(alignment: .top, spacing: 12) {
                Picker("Source", selection: Binding(
                    get: { model.tartReport?.selected ?? .installed },
                    set: { source in
                        chooseRejection = nil
                        model.setTartSource(source)
                    })) {
                    Text(TartSettingsCopy.sourceLabel(.bundled)).tag(TartSource.bundled)
                        .disabled(!copy.bundledEnabled)
                    Text(TartSettingsCopy.sourceLabel(.installed)).tag(TartSource.installed)
                }
                .pickerStyle(.radioGroup)
                .labelsHidden()
                .fixedSize()
                // Beside the Bundled choice, the first radio row.
                Text(verbatim: copy.bundledVersionText ?? copy.bundledCaption ?? "")
                    .font(.caption)
                    .foregroundStyle(WorkspaceStyle.muted)
                    .frame(minWidth: 160, alignment: .leading)
                    .padding(.top, 1)
            }
            .disabled(!copy.controlsEnabled)
        }
        if let jobsCaption = copy.jobsCaption {
            Text(jobsCaption)
                .font(.caption)
                .foregroundStyle(WorkspaceStyle.muted)
        }
        WorkspaceStyle.line.frame(height: 1)
        LabeledContent("Path") {
            VStack(alignment: .trailing, spacing: 4) {
                HStack(spacing: 8) {
                    Text(verbatim: copy.pathFieldValue)
                        .font(.system(.caption, design: .monospaced))
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                        .help(copy.pathFieldValue)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 4)
                        .frame(width: 260, alignment: .leading)
                        .background(WorkspaceStyle.background,
                                    in: RoundedRectangle(cornerRadius: 5))
                        .overlay(RoundedRectangle(cornerRadius: 5)
                            .stroke(WorkspaceStyle.line, lineWidth: 1))
                    Button("Choose…") { chooseTart() }
                    if copy.showsReset {
                        Button("Reset") {
                            chooseRejection = nil
                            model.resetCustomTart()
                        }
                    }
                }
                .disabled(!copy.pathControlsEnabled || !copy.controlsEnabled)
                Text(verbatim: copy.pathCaption)
                    .font(.caption)
                    .foregroundStyle(WorkspaceStyle.muted)
                if let chooseRejection {
                    Text(chooseRejection)
                        .font(.caption)
                        .foregroundStyle(WorkspaceStyle.warning)
                }
            }
            .opacity(copy.pathControlsEnabled ? 1 : 0.6)
        }
        WorkspaceStyle.line.frame(height: 1)
        LabeledContent("Active tart") {
            HStack(spacing: 8) {
                Text(verbatim: copy.activeLine)
                    .help(copy.activeHelp ?? "")
                    .textSelection(.enabled)
                Button(model.isCheckingPrerequisite ? "Checking…" : "Re-check") {
                    model.checkPrerequisite()
                }
                .disabled(model.isCheckingPrerequisite)
            }
        }
        if let warning = copy.versionWarning {
            Label {
                Text(warning).fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: "exclamationmark.triangle.fill")
            }
            .font(.caption)
            .foregroundStyle(WorkspaceStyle.warning)
        }
    }

    private func chooseTart() {
        guard let path = FilePicker.chooseExecutable(title: "Choose a tart executable") else { return }
        if case .invalid(_, let reason)? = model.chooseCustomTart(path: path) {
            chooseRejection = TartSettingsCopy.rejectionMessage(reason)
        } else {
            chooseRejection = nil
        }
    }
}
