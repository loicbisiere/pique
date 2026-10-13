import AppKit

/// Tells the user when a newer release exists on GitHub. Never downloads or runs anything itself:
/// the user updates with Homebrew or from the release page (auto-install would need Sparkle + notarization).
final class UpdateChecker: ObservableObject {
    struct Release: Equatable {
        let version: String
        let page: URL
    }

    static let enabledKey = "checkForUpdates"
    private static let latestRelease = URL(string: "https://api.github.com/repos/loicbisiere/toothpeek/releases/latest")!

    @Published private(set) var available: Release?
    @Published private(set) var lastCheck: Date?
    @Published private(set) var checking = false
    /// Why the last check failed (offline, GitHub unreachable or rate-limited); nil after a successful check.
    @Published private(set) var error: String?
    var onNewVersion: ((Release) -> Void)?

    /// Nil when not running from a bundle (`swift run`) or for dev builds: nothing to compare.
    let currentVersion: String? = {
        guard let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
              !version.contains("-") else { return nil }
        return version
    }()

    /// Homebrew keeps a record of installed casks; such users update with `brew upgrade`.
    let installedWithHomebrew = ["/opt/homebrew/Caskroom/toothpeek", "/usr/local/Caskroom/toothpeek"]
        .contains { FileManager.default.fileExists(atPath: $0) }

    private var timer: Timer?

    func start() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in self?.checkIfEnabled() }
        timer = Timer.scheduledTimer(withTimeInterval: 24 * 3600, repeats: true) { [weak self] _ in self?.checkIfEnabled() }
    }

    private func checkIfEnabled() {
        if UserDefaults.standard.object(forKey: Self.enabledKey) as? Bool ?? true { check() }
    }

    func check() {
        guard let currentVersion, !checking else { return }
        checking = true
        let started = Date()
        URLSession.shared.dataTask(with: Self.latestRelease) { [weak self] data, _, _ in
            let json = data.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
            let tag = json?["tag_name"] as? String
            let page = (json?["html_url"] as? String).flatMap(URL.init(string:))
            // Keep "Checking…" up at least 0.6 s: GitHub often answers in 0.2 s, too fast to notice.
            DispatchQueue.main.asyncAfter(deadline: .now() + max(0, 0.6 - Date().timeIntervalSince(started))) {
                guard let self else { return }
                self.checking = false
                guard let tag, let page else {
                    self.error = String(localized: "Couldn't reach GitHub. Try again later.", bundle: AppLanguage.bundle)
                    return
                }
                let version = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
                self.error = nil
                self.lastCheck = Date()
                guard Self.isNewer(version, than: currentVersion) else { return self.available = nil }
                let release = Release(version: version, page: page)
                self.available = release
                // One notification per version, not one per daily check.
                if UserDefaults.standard.string(forKey: "notifiedUpdate") != version {
                    UserDefaults.standard.set(version, forKey: "notifiedUpdate")
                    self.onNewVersion?(release)
                }
            }
        }.resume()
    }

    /// Numeric comparison of "1.2.3" style versions; pre-releases ("1.2.0-beta") are never offered.
    static func isNewer(_ candidate: String, than current: String) -> Bool {
        guard !candidate.contains("-") else { return false }
        let a = candidate.split(separator: ".").map { Int($0) ?? 0 }
        let b = current.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(a.count, b.count) {
            let x = i < a.count ? a[i] : 0, y = i < b.count ? b[i] : 0
            if x != y { return x > y }
        }
        return false
    }
}
