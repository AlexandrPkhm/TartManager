import TartKit

/// The Settings → General → Tart panel copy and control states, derived
/// from one check report so tests cover every caption without the view.
struct TartSettingsCopy: Equatable {
    static let bundledUnavailableCaption = "Not available in this build"
    static let notFoundCaption =
        "Not found. Install tart with `brew install cirruslabs/cli/tart` or choose a file."

    /// The Bundled choice can be selected (this build has a bundled tart).
    let bundledEnabled: Bool
    let bundledCaption: String?
    let bundledVersionText: String?
    /// The caption under the Source menu: the bundled tart's version or state
    /// while Bundled is selected; with Path selected, only why Bundled cannot
    /// be chosen, because the Path row shows its own version.
    let sourceDetail: String?
    /// The read-only path field: the custom path, else the detected path.
    let pathFieldValue: String
    let pathCaption: String
    let showsReset: Bool
    /// The Path row shows only while Path (the installed source) is selected.
    let showsPathRow: Bool
    /// `false` while a job runs: the source, Choose…, and Reset are refused.
    let controlsEnabled: Bool
    let jobsCaption: String?
    let activeLine: String
    /// The active tart's full path, for the help tag.
    let activeHelp: String?
    let versionWarning: String?

    init(report: TartRuntimeReport, customPath: String?, runningJobs: Int) {
        bundledEnabled = report.bundled != nil
        switch report.bundled {
        case nil:
            bundledCaption = Self.bundledUnavailableCaption
            bundledVersionText = nil
        case .damaged?, .missing?, .invalidCustomPath?:
            bundledCaption = "Damaged. Reinstall Tart Manager."
            bundledVersionText = nil
        case .ok(let version, _, _)?:
            bundledCaption = nil
            bundledVersionText = "tart \(version)"
        case .outdated(let found, _, _, _)?:
            bundledCaption = nil
            bundledVersionText = "tart \(found) (outdated)"
        }

        pathFieldValue = customPath ?? report.installed.binaryPath ?? ""
        let origin = customPath == nil ? "Detected automatically" : "Custom path"
        switch report.installed {
        case .ok(let version, _, _):
            pathCaption = "\(origin) · tart \(version)"
        case .outdated(let found, _, _, _):
            pathCaption = "\(origin) · tart \(found) (outdated)"
        case .invalidCustomPath, .damaged:
            pathCaption = "\(origin) · cannot run. Choose another file."
        case .missing:
            pathCaption = Self.notFoundCaption
        }
        showsReset = customPath != nil
        showsPathRow = report.selected == .installed
        switch report.selected {
        case .bundled:
            sourceDetail = bundledVersionText ?? bundledCaption
        case .installed:
            sourceDetail = report.bundled == nil ? Self.bundledUnavailableCaption : nil
        }

        controlsEnabled = runningJobs == 0
        jobsCaption = runningJobs == 0 ? nil : TartSourceSwitchGate.refusalMessage(jobCount: runningJobs)

        let active = report.active
        let sourceLabel = Self.sourceLabel(active.source)
        switch active {
        case .ok(let version, _, _):
            activeLine = "\(version) · \(sourceLabel)"
        case .outdated(let found, _, _, _):
            activeLine = "\(found) (outdated) · \(sourceLabel)"
        case .missing:
            activeLine = "Not found · \(sourceLabel)"
        case .damaged:
            activeLine = "Damaged · \(sourceLabel)"
        case .invalidCustomPath:
            activeLine = "Cannot run · \(sourceLabel)"
        }
        activeHelp = active.binaryPath
        versionWarning = Self.versionWarning(TartVersionSkewPolicy.evaluate(report))
    }

    /// The Source picker label: "Bundled" or "Path".
    static func sourceLabel(_ source: TartSource) -> String {
        switch source {
        case .bundled: return "Bundled"
        case .installed: return "Path"
        }
    }

    /// The Source menu icon, like the Appearance menu's icons.
    static func sourceSymbol(_ source: TartSource) -> String {
        switch source {
        case .bundled: return "shippingbox"
        case .installed: return "folder"
        }
    }

    /// Why **Choose…** refused a file; shown under the path row.
    static func rejectionMessage(_ reason: TartCustomPathValidation.Reason) -> String {
        switch reason {
        case .notAbsolute: return "Choose the file by its full path."
        case .missing: return "The chosen file no longer exists."
        case .notRegularFile: return "The chosen item is not a file."
        case .notExecutable: return "The chosen file is not executable."
        }
    }

    /// The version warning, shared with the one-time source sheet.
    static func versionWarning(_ skew: TartVersionSkewPolicy.Result) -> String? {
        guard case .selectedIsOlder(let selected, let other) = skew else { return nil }
        return "The selected tart (\(selected)) is older than the other tart (\(other)). "
            + "VMs that the newer tart changed can fail to open."
    }
}
