import Foundation

/// A validated change to a VM's resources; nil fields are not sent.
public struct VMResourceUpdate: Equatable, Sendable {
    public var cpuCount: Int?
    public var memoryMB: Int?
    /// Whole GBs — tart's `--disk-size` is a whole-GB option, and the editor
    /// edits/validates whole GBs (see `VMResourceValidator`).
    public var diskSizeGB: Int?
    public var display: String?
    /// Tri-state: nil = not sent; true/false → `--display-refit` /
    /// `--no-display-refit`. Nil is reachable, so `isEmpty` is meaningful
    /// and an untouched editor never rewrites unrelated settings.
    public var displayRefit: Bool?

    public init(cpuCount: Int?, memoryMB: Int?, diskSizeGB: Int?,
                display: String?, displayRefit: Bool?) {
        self.cpuCount = cpuCount
        self.memoryMB = memoryMB
        self.diskSizeGB = diskSizeGB
        self.display = display
        self.displayRefit = displayRefit
    }

    /// The argv fragment after `set <name>`; empty when nothing is set.
    public var arguments: [String] {
        var out: [String] = []
        if let cpuCount { out += ["--cpu", String(cpuCount)] }
        if let memoryMB { out += ["--memory", String(memoryMB)] }
        if let diskSizeGB { out += ["--disk-size", String(diskSizeGB)] }
        if let display { out += ["--display", display] }
        if let displayRefit {
            out += [displayRefit ? "--display-refit" : "--no-display-refit"]
        }
        return out
    }

    public var isEmpty: Bool { arguments.isEmpty }
}
