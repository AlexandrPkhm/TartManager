import Foundation

/// Completion captions for prune jobs. tart prune emits nothing on the
/// success path (verified against tart 2.32.0 sources), so the caption is
/// derived from the measured free-space delta on the storage volume —
/// captured output is never consulted.
public enum PruneSummary {
    private static let gibibyte = 1_073_741_824.0

    public static func compose(freeBefore: Int64?, freeAfter: Int64?) -> String {
        guard let freeBefore, let freeAfter else { return "Prune complete." }
        let reclaimed = freeAfter - freeBefore
        guard reclaimed > 0 else { return "Nothing to prune." }
        let gigabytes = String(
            format: "%.1f", locale: Locale(identifier: "en_US_POSIX"),
            Double(reclaimed) / gibibyte)
        return "Prune complete — freed \(gigabytes) GB"
    }
}
