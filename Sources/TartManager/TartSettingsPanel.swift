import SwiftUI
import TartKit

/// Settings → General → Tart: the source menu (Bundled / Path, the same
/// control as Appearance), the read-only path with **Choose…** and **Reset**
/// (shown only for Path), and the active tart with **Re-check**. All copy and control states come from `TartSettingsCopy`;
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
            VStack(alignment: .trailing, spacing: 4) {
                // The same menu control as the Appearance picker.
                Picker("Source", selection: Binding(
                    get: { model.tartReport?.selected ?? .installed },
                    set: { source in
                        chooseRejection = nil
                        model.setTartSource(source)
                    })) {
                    ForEach([TartSource.bundled, .installed], id: \.self) { source in
                        Label(TartSettingsCopy.sourceLabel(source),
                              systemImage: TartSettingsCopy.sourceSymbol(source))
                            .tag(source)
                            .disabled(source == .bundled && !copy.bundledEnabled)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .fixedSize()
                .disabled(!copy.controlsEnabled)
                if let detail = copy.sourceDetail {
                    Text(verbatim: detail)
                        .font(.caption)
                        .foregroundStyle(WorkspaceStyle.muted)
                }
            }
        }
        if let jobsCaption = copy.jobsCaption {
            Text(jobsCaption)
                .font(.caption)
                .foregroundStyle(WorkspaceStyle.muted)
        }
        if copy.showsPathRow {
            WorkspaceStyle.line.frame(height: 1)
            pathRow(copy)
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

    private func pathRow(_ copy: TartSettingsCopy) -> some View {
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
                .disabled(!copy.controlsEnabled)
                Text(verbatim: copy.pathCaption)
                    .font(.caption)
                    .foregroundStyle(WorkspaceStyle.muted)
                if let chooseRejection {
                    Text(chooseRejection)
                        .font(.caption)
                        .foregroundStyle(WorkspaceStyle.warning)
                }
            }
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
