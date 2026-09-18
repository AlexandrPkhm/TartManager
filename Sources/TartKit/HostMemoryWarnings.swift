/// The shared host-RAM warning budget for every soft memory guardrail:
/// the per-VM memory-settings warning and the run-time over-commitment
/// warning must agree on one fraction, or the two copies drift as
/// thresholds are tuned. One copy, both consumers.
public enum HostMemoryWarnings {
    /// Fraction of physical RAM at/above which the soft warnings fire.
    public static let warningFraction: Double = 0.9
}
