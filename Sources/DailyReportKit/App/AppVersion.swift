/// Single source of truth for the app's version. `make-app.sh` reads this value
/// and injects it into the bundle's Info.plist (CFBundleShortVersionString), so the
/// running app and the update check compare the same number.
public enum AppVersion {
    public static let current = "1.4.0"
}
