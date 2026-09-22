import Foundation
import os

enum SemanticVersion {
    static func isNewer(_ candidate: String, than current: String) -> Bool {
        let a = components(candidate)
        let b = components(current)
        guard !a.isEmpty, !b.isEmpty else { return false }

        for index in 0 ..< max(a.count, b.count) {
            let left = index < a.count ? a[index] : 0
            let right = index < b.count ? b[index] : 0
            if left != right { return left > right }
        }
        return false
    }

    private static func components(_ version: String) -> [Int] {
        version
            .trimmingCharacters(in: CharacterSet(charactersIn: "vV "))
            .split(separator: ".")
            .map { Int($0.prefix(while: \.isNumber)) ?? 0 }
    }
}

protocol ReleaseFetching: AnyObject {
    func fetchLatestVersion(completion: @escaping (String?) -> Void)
}

final class GitHubReleaseFetcher: ReleaseFetching {
    private static let endpoint = URL(string: "https://api.github.com/repos/aksoyakin/lift/releases/latest")!
    private static let timeout: TimeInterval = 10

    func fetchLatestVersion(completion: @escaping (String?) -> Void) {
        var request = URLRequest(url: Self.endpoint, timeoutInterval: Self.timeout)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")

        URLSession.shared.dataTask(with: request) { data, _, _ in
            guard let data,
                  let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tag = payload["tag_name"] as? String else {
                completion(nil)
                return
            }
            completion(tag)
        }.resume()
    }
}

final class UpdateChecker {
    private let currentVersion: String
    private let fetcher: ReleaseFetching
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Lift", category: "UpdateChecker")

    private(set) var availableVersion: String?

    var onResult: ((String?) -> Void)?

    init(currentVersion: String = Bundle.main.shortVersion, fetcher: ReleaseFetching = GitHubReleaseFetcher()) {
        self.currentVersion = currentVersion
        self.fetcher = fetcher
    }

    func check() {
        fetcher.fetchLatestVersion { [weak self] tag in
            guard let self else { return }
            let newer = tag.flatMap { SemanticVersion.isNewer($0, than: self.currentVersion) ? $0 : nil }
            DispatchQueue.main.async {
                if let newer, newer != self.availableVersion {
                    self.logger.notice("Yeni sürüm bulundu: \(newer, privacy: .public)")
                }
                self.availableVersion = newer
                self.onResult?(newer)
            }
        }
    }
}

extension Bundle {
    var shortVersion: String {
        infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
    }
}
