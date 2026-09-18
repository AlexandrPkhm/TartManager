import Foundation

/// The raw-text draft the editor holds field-by-field. Parsing is total and
/// side-effect free: empty (trimmed) text means "not sent", non-empty numeric
/// text parses to a value, and unparseable text maps to nil — but only after
/// `VMResourceValidator` has rejected the draft. `AppModel.apply` enforces
/// that ordering, so a malformed value can never reach the CLI.
public struct ResourceEditorFields: Equatable, Sendable {
    public var cpuText: String
    public var memoryText: String
    public var diskText: String
    public var displayText: String
    /// nil = leave as configured (nothing sent); true/false = send the flag.
    public var displayRefit: Bool?

    public init(cpuText: String = "", memoryText: String = "", diskText: String = "",
                displayText: String = "", displayRefit: Bool? = nil) {
        self.cpuText = cpuText
        self.memoryText = memoryText
        self.diskText = diskText
        self.displayText = displayText
        self.displayRefit = displayRefit
    }

    /// The argv model for this draft. Call only after validation passed.
    public var update: VMResourceUpdate {
        VMResourceUpdate(
            cpuCount: Self.wholeNumber(cpuText),
            memoryMB: Self.wholeNumber(memoryText),
            diskSizeGB: Self.wholeNumber(diskText),
            display: Self.nonEmptyTrimmed(displayText),
            displayRefit: displayRefit)
    }

    public var isEmpty: Bool { update.isEmpty }

    private static func wholeNumber(_ text: String) -> Int? {
        guard let trimmed = nonEmptyTrimmed(text) else { return nil }
        return Int(trimmed)
    }

    private static func nonEmptyTrimmed(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? nil : trimmed
    }
}
