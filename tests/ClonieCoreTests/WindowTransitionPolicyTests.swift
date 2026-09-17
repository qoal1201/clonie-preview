import XCTest
@testable import ClonieCore

final class WindowTransitionPolicyTests: XCTestCase {
    private let live = WindowModeRequest(mode: "live", width: 560, height: 440)
    private let practice = WindowModeRequest(mode: "practice", width: 560, height: 440)
    private let stack = WindowModeRequest(mode: "stack", width: 1180, height: 760)

    func testModeRequestedDuringUserFullScreenEntryWaitsThenExitsOnce() {
        var policy = WindowTransitionPolicy()
        policy.willEnterFullScreen()
        XCTAssertEqual(policy.request(live, isFullScreen: false, currentMode: "stack"), .none)
        XCTAssertEqual(policy.phase, .enteringUserFullScreen)
        XCTAssertEqual(policy.didEnterFullScreen(currentMode: "stack"), .toggleFullScreen)
        XCTAssertEqual(policy.phase, .exitingForMode)
        XCTAssertEqual(policy.didExitFullScreen(currentMode: "stack"), .apply(live))
    }

    func testLatestModeRequestWinsWhileFullScreenIsExiting() {
        var policy = WindowTransitionPolicy()
        XCTAssertEqual(policy.request(live, isFullScreen: true, currentMode: "stack"), .toggleFullScreen)
        XCTAssertEqual(policy.request(practice, isFullScreen: true, currentMode: "stack"), .none)
        XCTAssertEqual(policy.didExitFullScreen(currentMode: "stack"), .apply(practice))
    }

    func testReturningToStackRestoresFullScreenAfterApplyingNormalFrame() {
        var policy = WindowTransitionPolicy()
        XCTAssertEqual(policy.request(live, isFullScreen: true, currentMode: "stack"), .toggleFullScreen)
        XCTAssertEqual(policy.didExitFullScreen(currentMode: "stack"), .apply(live))
        XCTAssertEqual(policy.didApply(live, isFullScreen: false), .none)
        XCTAssertEqual(policy.request(stack, isFullScreen: false, currentMode: "live"), .apply(stack))
        XCTAssertEqual(policy.didApply(stack, isFullScreen: false), .toggleFullScreen)
        XCTAssertEqual(policy.phase, .enteringRestoredStack)
        XCTAssertEqual(policy.didEnterFullScreen(currentMode: "stack"), .none)
        XCTAssertFalse(policy.restoresStackFullScreen)
    }

    func testHideOverridesPendingModeAndWaitsForFullScreenExit() {
        var policy = WindowTransitionPolicy()
        XCTAssertEqual(policy.request(live, isFullScreen: true, currentMode: "stack"), .toggleFullScreen)
        XCTAssertEqual(policy.requestHide(isFullScreen: true), .none)
        XCTAssertNil(policy.pendingRequest)
        XCTAssertEqual(policy.didExitFullScreen(currentMode: "stack"), .hide)
        XCTAssertTrue(policy.restoresStackFullScreen)
        XCTAssertEqual(policy.reapplyLatest(isFullScreen: false, currentMode: "stack"), .apply(live))
        XCTAssertEqual(policy.didApply(live, isFullScreen: false), .none)
        XCTAssertEqual(policy.request(stack, isFullScreen: false, currentMode: "live"), .apply(stack))
        XCTAssertEqual(policy.didApply(stack, isFullScreen: false), .toggleFullScreen)
    }

    func testHideDuringUserFullScreenEntryDoesNotReverseUntilEntryCompletes() {
        var policy = WindowTransitionPolicy()
        policy.willEnterFullScreen()
        XCTAssertEqual(policy.request(live, isFullScreen: false, currentMode: "stack"), .none)
        XCTAssertEqual(policy.requestHide(isFullScreen: false), .none)
        XCTAssertNil(policy.pendingRequest)
        XCTAssertEqual(policy.didEnterFullScreen(currentMode: "stack"), .toggleFullScreen)
        XCTAssertEqual(policy.phase, .exitingForHide)
        XCTAssertEqual(policy.didExitFullScreen(currentMode: "stack"), .hide)
        XCTAssertTrue(policy.restoresStackFullScreen)
        XCTAssertEqual(policy.reapplyLatest(isFullScreen: false, currentMode: "stack"), .apply(live))
    }

    func testNormalLiveHideReappliesLiveBeforeShowingAgain() {
        var policy = WindowTransitionPolicy()
        XCTAssertEqual(policy.request(live, isFullScreen: false, currentMode: "stack"), .apply(live))
        XCTAssertEqual(policy.didApply(live, isFullScreen: false), .none)
        XCTAssertEqual(policy.requestHide(isFullScreen: false), .hide)
        XCTAssertEqual(policy.reapplyLatest(isFullScreen: false, currentMode: "live"), .apply(live))
    }

    func testOverlayUsesRequestedSizeButRememberedPosition() {
        let result = WindowFramePolicy.frame(
            current: CGRect(x: 0, y: 0, width: 1180, height: 760),
            remembered: CGRect(x: 220, y: 180, width: 1180, height: 760),
            defaultFrame: CGRect(x: 50, y: 60, width: 560, height: 440),
            sameMode: false, keepsRememberedSize: false)
        XCTAssertEqual(result, CGRect(x: 220, y: 180, width: 560, height: 440))
    }

    func testFrameIsClampedToAvailableScreen() {
        let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let result = WindowFramePolicy.frameOnScreen(
            CGRect(x: 1800, y: -200, width: 1600, height: 1000),
            visibleFrames: [screen], preferred: screen)
        XCTAssertEqual(result, screen)
    }
}
