import Foundation

/// Decides whether the first-launch onboarding WINDOW should appear. The Claude app's
/// menu-bar-only nature makes first setup unfriendly (you have to discover the menu bar
/// item), so on the very first launch we pop a real window; afterward it's menu-bar only.
public enum FirstRunGate {
    /// UserDefaults key marking that the app has launched at least once.
    public static let hasLaunchedKey = "hasLaunchedBefore"

    /// Show onboarding only on the very first launch AND when not already connected —
    /// so a user upgrading from an older version (already set up) is never surprised by it.
    public static func shouldShowOnboarding(hasLaunchedBefore: Bool, isConnected: Bool) -> Bool {
        !hasLaunchedBefore && !isConnected
    }
}
