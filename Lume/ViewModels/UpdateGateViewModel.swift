import Combine
import Foundation
import SwiftUI

@MainActor
final class UpdateGateViewModel: ObservableObject {
    @Published private(set) var forceUpdate: ForceUpdateState?

    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func refresh() async {
        guard let url = AppConfig.remoteAppConfigURL else {
            forceUpdate = nil
            return
        }

        do {
            let (data, response) = try await session.data(from: url)
            guard let httpResponse = response as? HTTPURLResponse else {
                forceUpdate = nil
                return
            }

            guard httpResponse.statusCode == 200 else {
                forceUpdate = nil
                return
            }

            let config = try JSONDecoder().decode(RemoteAppConfig.self, from: data)
            forceUpdate = config.forceUpdateStateIfNeeded(currentVersion: appVersion)
        } catch {
            forceUpdate = nil
        }
    }

    func openUpdatePage() {
        guard let url = forceUpdate?.updateURL else { return }
        UIApplication.shared.open(url)
    }

    private var appVersion: String {
        let info = Bundle.main.infoDictionary
        return (info?["CFBundleShortVersionString"] as? String)
            ?? (info?["CFBundleVersion"] as? String)
            ?? "0"
    }
}

struct ForceUpdateState: Equatable {
    let title: String
    let message: String
    let buttonTitle: String
    let updateURL: URL
}

private struct RemoteAppConfig: Decodable {
    let forceUpdate: Bool?
    let latestVersion: String?
    let minSupportedVersion: String?
    let updateURLString: String?
    let message: String?
    let title: String?
    let buttonTitle: String?

    enum CodingKeys: String, CodingKey {
        case forceUpdate = "force_update"
        case latestVersion = "latest_version"
        case minSupportedVersion = "min_supported_version"
        case updateURLString = "update_url"
        case message
        case title
        case buttonTitle = "button_title"
    }

    func forceUpdateStateIfNeeded(currentVersion: String) -> ForceUpdateState? {
        guard let updateURLString, let updateURL = URL(string: updateURLString) else { return nil }

        let requiresByMinVersion = minSupportedVersion.map {
            VersionComparator.compare(currentVersion, $0) == .orderedAscending
        } ?? false

        let requiresByForcedLatest = (forceUpdate == true) && {
            guard let latestVersion else { return false }
            return VersionComparator.compare(currentVersion, latestVersion) == .orderedAscending
        }()

        guard requiresByMinVersion || requiresByForcedLatest else { return nil }

        return ForceUpdateState(
            title: title?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ? title! : "Update Required",
            message: message?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ? message! : "A new version of Lume is required to continue.",
            buttonTitle: buttonTitle?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ? buttonTitle! : "Update Now",
            updateURL: updateURL
        )
    }
}

private enum VersionComparator {
    static func compare(_ lhs: String, _ rhs: String) -> ComparisonResult {
        let left = normalizedComponents(lhs)
        let right = normalizedComponents(rhs)
        let count = max(left.count, right.count)

        for index in 0..<count {
            let leftValue = index < left.count ? left[index] : 0
            let rightValue = index < right.count ? right[index] : 0
            if leftValue < rightValue { return .orderedAscending }
            if leftValue > rightValue { return .orderedDescending }
        }

        return .orderedSame
    }

    private static func normalizedComponents(_ version: String) -> [Int] {
        version
            .split(separator: ".")
            .map { Int($0) ?? 0 }
    }
}
