import Foundation
import TartKit

/// The About tab's acknowledgement of the bundled tart. It shows only when
/// the build carries a bundled tart, even a damaged one, because the license
/// duty follows the shipped files. The installed source carries none.
struct TartAcknowledgementCopy: Equatable {
    let isVisible: Bool
    let title = "Acknowledgements"
    let line: String
    /// The license file to open; `nil` hides **View License**.
    let licensePath: String?
    let viewLicenseButton = "View License"
    let gitHubLinkTitle = "Tart on GitHub"
    let gitHubURL = URL(string: "https://github.com/openai/tart")!

    var showsViewLicense: Bool { licensePath != nil }

    init(report: TartRuntimeReport?, licensePath: String?) {
        let bundled = report?.bundled
        isVisible = bundled != nil
        let tart = bundled?.version.map { "tart \($0)" } ?? "tart"
        line = "Tart Manager includes \(tart) by Cirrus Labs and OpenAI, under the FSL-1.1-ALv2 license."
        self.licensePath = licensePath
    }
}
