import TartKit

/// The one-time source sheet's copy, derived from the check report that
/// asked (both sources check as `.ok`), so tests cover it without the view.
struct TartSourcePromptCopy: Equatable {
    let title = "Choose the tart that Tart Manager uses"
    let body = "Tart Manager now includes its own tart. You can also keep the tart that is "
        + "installed on this Mac. You can change this later in Settings."
    let bundledLabel = "Bundled with Tart Manager"
    let bundledDetail: String
    let installedLabel = "Installed on this Mac"
    let installedDetail: String
    let installedPath: String
    let warning: String?
    let keepInstalledButton = "Keep Installed"
    let useBundledButton = "Use Bundled"

    init(report: TartRuntimeReport) {
        bundledDetail = Self.versionText(report.bundled)
        installedDetail = Self.versionText(report.installed)
        installedPath = report.installed.binaryPath ?? ""
        warning = TartSettingsCopy.versionWarning(TartVersionSkewPolicy.evaluate(report))
    }

    private static func versionText(_ status: TartPrerequisiteStatus?) -> String {
        status?.version.map { "tart \($0)" } ?? ""
    }
}
