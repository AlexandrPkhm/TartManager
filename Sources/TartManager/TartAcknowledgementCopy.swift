import Foundation
import TartKit

/// The About tab's acknowledgement of the bundled tart. It shows only when
/// the build carries a bundled tart, even a damaged one, because the license
/// duty follows the shipped files. The installed source carries none.
///
/// FSL-1.1-ALv2 accepts "a copy of or a link to" its terms, so **View
/// License** links to the license of the bundled release instead of a copy
/// in the app. Terms differ between tart releases, so the link names the
/// version; with no known version it falls back to the current license.
struct TartAcknowledgementCopy: Equatable {
    let isVisible: Bool
    let title = "Acknowledgements"
    let line: String
    let viewLicenseButton = "View License"
    let licenseURL: URL
    let gitHubLinkTitle = "Tart on GitHub"
    let gitHubURL = URL(string: "https://github.com/openai/tart")!

    /// `bundledVersion` is the version the bundled `tart.app` declares; the
    /// checked version from `report` stands in when it declares none.
    init(report: TartRuntimeReport?, bundledVersion: String?) {
        let bundled = report?.bundled
        isVisible = bundled != nil
        let version = bundledVersion ?? bundled?.version.map { "\($0)" }
        let tart = version.map { "tart \($0)" } ?? "tart"
        line = "Tart Manager includes \(tart) by Cirrus Labs and OpenAI, under the FSL-1.1-ALv2 license."
        licenseURL = URL(string: "https://github.com/openai/tart/blob/\(version ?? "main")/LICENSE")!
    }
}
