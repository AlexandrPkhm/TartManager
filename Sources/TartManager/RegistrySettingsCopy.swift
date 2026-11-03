import TartKit

/// The Settings → Storage → Registries panel text, kept apart from the view
/// so that tests can cover it.
enum RegistrySettingsCopy {
    static let hostError = "Enter a host or an https URL with no path, such as ghcr.io."
    static let pullCaption = "Pulls from ghcr.io/cirruslabs. Progress shows in Jobs in the main window. "
        + "The image then appears on the Images page, where you can clone it to a VM."
    static let signInCaption = "Signing in stores the credentials in tart's macOS Keychain, not in "
        + "Tart Manager. tart can't list logged-in hosts, so sessions aren't shown here — sign in "
        + "or out per host."
    static let signInUnavailableCaption =
        "Registry sign-in is disabled while tart or the storage configuration is unavailable."
    static let lowSpaceMessage = "Free space is nearly exhausted; the pull may fail part-way."

    static func modeLabel(_ mode: RegistryMode) -> String {
        switch mode {
        case .standard: return "Default"
        case .custom: return "Custom"
        }
    }
}
