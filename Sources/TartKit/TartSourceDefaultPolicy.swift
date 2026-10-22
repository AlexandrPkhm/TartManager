/// Chooses the tart source when no preference is stored.
///
/// | Bundled tart     | Installed tart | Decision          |
/// | ---------------- | -------------- | ----------------- |
/// | absent           | any            | store `installed` |
/// | `ok`             | `ok`           | ask once          |
/// | present          | not `ok`       | store `bundled`   |
/// | present, not ok  | `ok`           | store `installed` |
///
/// A stored preference always wins (`.keep`). When both sources fail, the
/// bundled tart is stored, so the banner tells the user to reinstall.
public enum TartSourceDefaultPolicy {
    public enum Decision: Equatable, Sendable {
        case keep
        case store(TartSource)
        case ask
    }

    public static func decide(_ report: TartRuntimeReport) -> Decision {
        guard report.storedPreference == nil else { return .keep }
        guard let bundled = report.bundled else { return .store(.installed) }
        switch (bundled.isSatisfied, report.installed.isSatisfied) {
        case (true, true): return .ask
        case (false, true): return .store(.installed)
        case (_, false): return .store(.bundled)
        }
    }
}
