/// The app's version ("Version 1.0"), shown at the bottom of the help window. The Build IPA
/// workflow rewrites this file from the version in the Info.plist before building; local
/// builds say "Development build".
enum BuildInfo {
    static let label = "Development build"
}
