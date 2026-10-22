/// Warns when the selected tart is older than the other source's tart.
///
/// A newer tart can change VM metadata that an older tart cannot read, so
/// the warning informs and blocks nothing. Both sources must check as `.ok`;
/// otherwise there is nothing to compare.
public enum TartVersionSkewPolicy {
    public enum Result: Equatable, Sendable {
        case none
        case selectedIsOlder(selected: TartVersion, other: TartVersion)
    }

    public static func evaluate(_ report: TartRuntimeReport) -> Result {
        guard case .ok(let selected, _, _) = report.active,
              case .ok(let other, _, _)? = report.other,
              selected < other else { return .none }
        return .selectedIsOlder(selected: selected, other: other)
    }
}
