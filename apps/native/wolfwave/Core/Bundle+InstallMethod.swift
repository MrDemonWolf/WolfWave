import Foundation

extension Bundle {
    /// Whether this bundle was installed via Homebrew (cask or formula).
    var isHomebrewInstall: Bool {
        Bundle.isHomebrewPath(bundlePath)
    }

    /// Path-matching helper exposed for testing.
    static func isHomebrewPath(_ path: String) -> Bool {
        let homebrewMarkers = [
            "/opt/homebrew/",
            "/usr/local/Caskroom/",
            "/usr/local/Cellar/",
            "/Homebrew/"
        ]
        return homebrewMarkers.contains { path.contains($0) }
    }
}
