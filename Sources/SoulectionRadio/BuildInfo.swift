/// When this copy of the app was built. The Build IPA workflow rewrites this file with the
/// build's date and time (Los Angeles) before building; local builds say "Development build".
/// Shown at the bottom of the help window, so testers can say which build they have.
enum BuildInfo {
    static let label = "Development build"
}
