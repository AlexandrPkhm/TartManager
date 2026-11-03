/// How the Registries panel works: `.standard` pulls from the default
/// registry, `.custom` signs in to a host that the user enters.
public enum RegistryMode: String, CaseIterable, Sendable {
    case standard
    case custom
}
