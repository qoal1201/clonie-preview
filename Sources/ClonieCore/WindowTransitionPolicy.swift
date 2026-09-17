import Foundation
import CoreGraphics

public struct WindowModeRequest: Equatable {
    public let mode: String
    public let width: Double
    public let height: Double

    public init(mode: String, width: Double, height: Double) {
        self.mode = mode
        self.width = width
        self.height = height
    }
}

/// AppKit 전체화면 콜백 사이에서 최신 모드 요청과 숨김 우선순위를 결정한다.
/// 실제 창 조작은 효과를 받은 UI 계층이 수행한다.
public struct WindowTransitionPolicy {
    public enum Phase: Equatable {
        case idle
        case enteringUserFullScreen
        case exitingUserFullScreen
        case exitingForMode
        case enteringRestoredStack
        case exitingForHide
    }

    public enum Effect: Equatable {
        case none
        case apply(WindowModeRequest)
        case toggleFullScreen
        case hide
    }

    public private(set) var phase: Phase = .idle
    public private(set) var pendingRequest: WindowModeRequest?
    public private(set) var latestRequest: WindowModeRequest?
    public private(set) var restoresStackFullScreen = false
    public private(set) var hidePending = false

    public init() {}

    public var canPersistFrame: Bool { phase == .idle }

    public mutating func request(_ request: WindowModeRequest, isFullScreen: Bool,
                                 currentMode: String) -> Effect {
        latestRequest = request
        guard phase == .idle else {
            pendingRequest = request
            return .none
        }
        if request.mode != "stack", isFullScreen {
            if currentMode == "stack" { restoresStackFullScreen = true }
            pendingRequest = request
            phase = .exitingForMode
            return .toggleFullScreen
        }
        return .apply(request)
    }

    /// 숨김이 전환 대기를 취소했어도 화면이 마지막으로 요청한 native 모드를 다시 적용한다.
    public mutating func reapplyLatest(isFullScreen: Bool, currentMode: String) -> Effect {
        guard phase == .idle, let latestRequest else { return .none }
        pendingRequest = nil
        return request(latestRequest, isFullScreen: isFullScreen, currentMode: currentMode)
    }

    public mutating func didApply(_ request: WindowModeRequest, isFullScreen: Bool) -> Effect {
        guard request.mode == "stack", restoresStackFullScreen, !isFullScreen else { return .none }
        phase = .enteringRestoredStack
        return .toggleFullScreen
    }

    public mutating func willEnterFullScreen() {
        if phase == .idle { phase = .enteringUserFullScreen }
    }

    public mutating func willExitFullScreen() {
        if phase == .idle { phase = .exitingUserFullScreen }
    }

    public mutating func didEnterFullScreen(currentMode: String) -> Effect {
        if phase == .enteringRestoredStack { restoresStackFullScreen = false }
        phase = .idle
        if hidePending {
            if currentMode == "stack", let latestRequest, latestRequest.mode != "stack" {
                restoresStackFullScreen = true
            }
            phase = .exitingForHide
            return .toggleFullScreen
        }
        guard let pending = takePendingRequest() else { return .none }
        return request(pending, isFullScreen: true, currentMode: currentMode)
    }

    public mutating func didExitFullScreen(currentMode: String) -> Effect {
        phase = .idle
        if hidePending {
            hidePending = false
            // A deferred overlay request still owns the original stack full-screen state.
            // Keep it so returning to stack after reopening can restore that state.
            if currentMode == "stack", latestRequest?.mode == "stack" || latestRequest == nil {
                restoresStackFullScreen = false
            }
            return .hide
        }
        guard let pending = takePendingRequest() else { return .none }
        return request(pending, isFullScreen: false, currentMode: currentMode)
    }

    public mutating func requestHide(isFullScreen: Bool) -> Effect {
        hidePending = true
        pendingRequest = nil
        guard phase == .idle else { return .none }
        if isFullScreen {
            phase = .exitingForHide
            return .toggleFullScreen
        }
        hidePending = false
        return .hide
    }

    private mutating func takePendingRequest() -> WindowModeRequest? {
        defer { pendingRequest = nil }
        return pendingRequest
    }
}

public enum WindowFramePolicy {
    public static func frame(current: CGRect, remembered: CGRect?, defaultFrame: CGRect,
                             sameMode: Bool, keepsRememberedSize: Bool) -> CGRect {
        if sameMode, keepsRememberedSize { return current }
        if let remembered, remembered.origin.x.isFinite, remembered.origin.y.isFinite,
           remembered.width.isFinite, remembered.height.isFinite,
           remembered.width > 100, remembered.height > 100 {
            if keepsRememberedSize { return remembered }
            var frame = defaultFrame
            frame.origin = remembered.origin
            return frame
        }
        return defaultFrame
    }

    public static func frameOnScreen(_ frame: CGRect, visibleFrames: [CGRect],
                                     preferred: CGRect?) -> CGRect {
        guard !visibleFrames.isEmpty else { return frame }
        func visibleArea(on screen: CGRect) -> CGFloat {
            let intersection = screen.intersection(frame)
            return intersection.isNull || intersection.isEmpty
                ? 0 : intersection.width * intersection.height
        }
        let intersecting = visibleFrames.max { visibleArea(on: $0) < visibleArea(on: $1) }
        let screen = intersecting.flatMap { visibleArea(on: $0) > 0 ? $0 : nil }
            ?? preferred ?? visibleFrames[0]
        var result = frame
        result.size.width = min(result.width, screen.width)
        result.size.height = min(result.height, screen.height)
        result.origin.x = min(max(result.minX, screen.minX), screen.maxX - result.width)
        result.origin.y = min(max(result.minY, screen.minY), screen.maxY - result.height)
        return result
    }
}
