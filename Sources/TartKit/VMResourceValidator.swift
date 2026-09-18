import Foundation

/// Result of validating a resource draft: hard errors block Apply, warnings
/// advise. The validator is total and accumulates every applicable error.
public struct VMResourceValidation: Equatable, Sendable {
    public let errors: [String]
    public let warnings: [String]

    public var isValid: Bool { errors.isEmpty }

    public init(errors: [String], warnings: [String]) {
        self.errors = errors
        self.warnings = warnings
    }
}

public enum VMResourceValidator {
    /// Modern macOS guests are the primary tart use case on this host.
    public static let guestMemoryMinimumMB = 8192

    /// Validates the raw editor fields. Every error is accumulated (no early
    /// return), so the inline "hard errors" rendering is total.
    public static func validate(fields: ResourceEditorFields,
                                currentDiskGB: Double,
                                host: HostFacts) -> VMResourceValidation {
        var errors: [String] = []
        var warnings: [String] = []

        if let cpuText = nonEmptyTrimmed(fields.cpuText) {
            if let cpu = Int(cpuText) {
                if cpu < 1 {
                    errors.append("CPU count must be at least 1.")
                } else if cpu > host.coreCount {
                    warnings.append("CPU count \(cpu) exceeds this Mac's \(host.coreCount) cores.")
                }
            } else {
                errors.append("CPUs must be a whole number.")
            }
        }

        if let memoryText = nonEmptyTrimmed(fields.memoryText) {
            if let memory = Int(memoryText) {
                if memory <= 0 {
                    errors.append("Memory must be a positive number of MB.")
                } else {
                    if memory < guestMemoryMinimumMB {
                        warnings.append("Memory \(memory) MB is below the \(guestMemoryMinimumMB / 1024) GB modern macOS guests need.")
                    }
                    let hostMB = Double(host.hostMemoryMB)
                    if Double(memory) > hostMB {
                        warnings.append("Memory exceeds this Mac's physical RAM (\(Int(hostMB)) MB).")
                    } else if Double(memory) > hostMB * HostMemoryWarnings.warningFraction {
                        warnings.append("Memory is within 10% of this Mac's physical RAM (\(Int(hostMB)) MB); other apps may swap.")
                    }
                }
            } else {
                errors.append("Memory must be a whole number of MB.")
            }
        }

        if let diskText = nonEmptyTrimmed(fields.diskText) {
            if let disk = Int(diskText) {
                if disk <= 0 {
                    errors.append("Disk size must be a positive number of GB.")
                } else if Double(disk) < currentDiskGB.rounded() {
                    // Compare against the same rounding the editor displays
                    // (Int(diskSize.rounded())), so the shown value is always
                    // re-applyable — no spurious grow-only errors (finding 8).
                    errors.append("Disks can only grow: the current size is \(Int(currentDiskGB.rounded())) GB.")
                }
            } else {
                errors.append("Disk size must be a whole number of GB.")
            }
        }

        if let displayText = nonEmptyTrimmed(fields.displayText) {
            // Extended delimiters: the package builds in Swift 5 language
            // mode, where bare `/…/` regex literals are not enabled.
            if let match = displayText.firstMatch(of: #/^(\d+)x(\d+)(pt|px)?$/#),
               let width = Int(match.1), let height = Int(match.2),
               width > 0, height > 0 {
                // valid — nothing to append
            } else {
                errors.append("Display must look like 1200x800.")
            }
            // NOTE: deliberately no early return — later errors still land.
        }

        return VMResourceValidation(errors: errors, warnings: warnings)
    }

    private static func nonEmptyTrimmed(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? nil : trimmed
    }
}
