import Domain
import Foundation
import Observation
import Support

/// Settings › General › About (E7-S5): what to tell support, copied or sent as
/// a prefilled issue that holds the version, build, macOS version, and Mac model
/// only. The saved diagnostics report is attached by hand, never sent.
@MainActor
@Observable
public final class AboutModel {
    /// The GitHub issue form that Report a Problem opens.
    public static let issueForm = "beta-feedback.yml"
    public static let issueBase = "https://github.com/bkareti/LemmeTypeApp/issues/new"

    public let buildInfo: BuildInfo
    public let channel: DistributionChannel
    public let osVersion: String
    public let hardwareModel: String
    /// Set after Copy Support Info, for the pane to show and announce.
    public private(set) var message: String?

    private let copier: any TextCopying
    private let openPage: @MainActor (URL) -> Void

    public init(
        buildInfo: BuildInfo, channel: DistributionChannel, copier: any TextCopying,
        openPage: @escaping @MainActor (URL) -> Void,
        osVersion: String = SystemInfo.osVersion, hardwareModel: String = SystemInfo.hardwareModel
    ) {
        self.buildInfo = buildInfo
        self.channel = channel
        self.copier = copier
        self.openPage = openPage
        self.osVersion = osVersion
        self.hardwareModel = hardwareModel
    }

    /// Exactly the fields shown in the About section; nothing else.
    public var supportInfo: String {
        """
        LemmeType \(buildInfo.displayString)
        Channel: \(channel.rawValue)
        macOS: \(osVersion)
        Mac: \(hardwareModel)
        """
    }

    public func copySupportInfo() async {
        await copier.copy(supportInfo)
        message = String(localized: "Copied. Paste it into your message.", bundle: .module)
    }

    /// The prefilled issue address: the form name and four plain facts.
    public var problemReportURL: URL? {
        var components = URLComponents(string: Self.issueBase)
        components?.queryItems = [
            URLQueryItem(name: "template", value: Self.issueForm),
            URLQueryItem(name: "version", value: buildInfo.version),
            URLQueryItem(name: "build", value: buildInfo.build),
            URLQueryItem(name: "macos", value: osVersion),
            URLQueryItem(name: "mac", value: hardwareModel),
        ]
        return components?.url
    }

    public func reportProblem() {
        if let url = problemReportURL { openPage(url) }
    }
}
