import XCTest
@testable import DailyReportKit

final class FirstRunGateTests: XCTestCase {
    func test_shows_only_on_very_first_launch_and_not_yet_connected() {
        // Fresh install, nothing set up → show the onboarding window.
        XCTAssertTrue(FirstRunGate.shouldShowOnboarding(hasLaunchedBefore: false, isConnected: false))
        // Already launched once → never auto-show again (menu-bar CTA takes over).
        XCTAssertFalse(FirstRunGate.shouldShowOnboarding(hasLaunchedBefore: true, isConnected: false))
        // Upgraded user who is already connected → don't surprise them with onboarding.
        XCTAssertFalse(FirstRunGate.shouldShowOnboarding(hasLaunchedBefore: false, isConnected: true))
        XCTAssertFalse(FirstRunGate.shouldShowOnboarding(hasLaunchedBefore: true, isConnected: true))
    }
}
