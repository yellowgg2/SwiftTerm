#if os(iOS)
import Foundation
import Testing
import UIKit
@testable import SwiftTerm

private final class TouchMouseCapturingDelegate: TerminalViewDelegate {
    var sentData: [[UInt8]] = []

    func sizeChanged(source: TerminalView, newCols: Int, newRows: Int) {}
    func setTerminalTitle(source: TerminalView, title: String) {}
    func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}
    func send(source: TerminalView, data: ArraySlice<UInt8>) { sentData.append(Array(data)) }
    func scrolled(source: TerminalView, position: Double) {}
    func requestOpenLink(source: TerminalView, link: String, params: [String: String]) {}
    func rangeChanged(source: TerminalView, startY: Int, endY: Int) {}
}

private final class EndedTapGestureRecognizer: UITapGestureRecognizer {
    private let testLocation: CGPoint

    init(location: CGPoint) {
        self.testLocation = location
        super.init(target: nil, action: nil)
    }

    override var state: UIGestureRecognizer.State {
        get { .ended }
        set {}
    }

    override func location(in view: UIView?) -> CGPoint {
        testLocation
    }
}

@MainActor
struct TouchMouseiOSTests {
    private let esc = "\u{1b}"

    private func makeSUT() -> (TerminalView, TouchMouseCapturingDelegate) {
        let view = TerminalView(frame: CGRect(x: 0, y: 0, width: 320, height: 160))
        let delegate = TouchMouseCapturingDelegate()
        view.terminalDelegate = delegate
        return (view, delegate)
    }

    /// 새 public API의 default는 automatic이고 remote availability callback은 DECSET/DECRST를 그대로 전달한다.
    @Test
    func automaticDefaultAndRemoteMouseCallbackTrackTerminalMode() {
        let (sut, _) = makeSUT()
        var changes: [Bool] = []
        sut.remoteMouseModeChangedHandler = { changes.append($0) }

        #expect(sut.touchMouseInteractionMode == .automatic)
        #expect(!sut.remoteMouseModeEnabled)

        sut.terminal.feed(text: "\(esc)[?1000h")
        #expect(sut.remoteMouseModeEnabled)
        sut.terminal.feed(text: "\(esc)[?1000l")

        #expect(!sut.remoteMouseModeEnabled)
        #expect(changes == [true, false])
    }

    /// local은 native scrollback owner를 남기고 scrollWheel은 direct one-finger recognizer만 설치한다.
    @Test
    func modeChangesUpdateTheMousePanRecognizerWithoutChangingAutomaticDefault() {
        let (sut, _) = makeSUT()
        sut.terminal.feed(text: "\(esc)[?1000h")
        #expect(sut.panMouseGesture != nil)

        sut.touchMouseInteractionMode = .local
        #expect(sut.panMouseGesture == nil)

        sut.touchMouseInteractionMode = .scrollWheel
        #expect(sut.panMouseGesture?.maximumNumberOfTouches == 1)

        sut.allowMouseReporting = false
        #expect(sut.panMouseGesture == nil)

        sut.touchMouseInteractionMode = .automatic
        #expect(sut.panMouseGesture != nil)
    }

    /// active selection은 touch-wheel recognizer 시작을 막아 selection handle pan을 보존한다.
    @Test
    func activeSelectionPreventsTouchWheelPanFromBeginning() throws {
        let (sut, _) = makeSUT()
        sut.touchMouseInteractionMode = .scrollWheel
        sut.terminal.feed(text: "\(esc)[?1000h")
        let pan = try #require(sut.panMouseGesture)

        sut.selection.active = true
        #expect(!sut.gestureRecognizerShouldBegin(pan))

        sut.selection.active = false
        #expect(sut.gestureRecognizerShouldBegin(pan))
    }

    /// ended/cancelled/failed는 touch 수가 0이어도 pending wheel state를 항상 정리한다.
    @Test
    func terminalPanStatesResetWithoutATouchCountGuard() {
        let (sut, _) = makeSUT()

        for state in [UIGestureRecognizer.State.ended, .cancelled, .failed] {
            #expect(
                sut.touchMouseWheelAccumulator.consume(
                    deltaY: 9,
                    cellHeight: 10,
                    timestamp: .zero
                ) == nil
            )
            sut.handleTouchMouseWheelPanChange(
                state: state,
                touchCount: 0,
                deltaY: 0,
                location: .zero,
                timestamp: .zero,
                reportingAllowed: false
            )
            #expect(
                sut.touchMouseWheelAccumulator.consume(
                    deltaY: 1,
                    cellHeight: 10,
                    timestamp: .zero
                ) == nil
            )
            sut.touchMouseWheelAccumulator.reset()
        }
    }

    /// mode change, remote off, view reset은 각각 pending wheel state를 폐기한다.
    @Test
    func policyAndAvailabilityChangesResetPendingWheelState() {
        let (sut, _) = makeSUT()

        #expect(sut.touchMouseWheelAccumulator.consume(deltaY: 9, cellHeight: 10, timestamp: .zero) == nil)
        sut.touchMouseInteractionMode = .local
        #expect(sut.touchMouseWheelAccumulator.consume(deltaY: 1, cellHeight: 10, timestamp: .zero) == nil)

        sut.touchMouseInteractionMode = .scrollWheel
        sut.terminal.feed(text: "\(esc)[?1000h")
        #expect(sut.touchMouseWheelAccumulator.consume(deltaY: 9, cellHeight: 10, timestamp: .zero) == nil)
        sut.terminal.feed(text: "\(esc)[?1000l")
        #expect(sut.touchMouseWheelAccumulator.consume(deltaY: 1, cellHeight: 10, timestamp: .zero) == nil)

        #expect(sut.touchMouseWheelAccumulator.consume(deltaY: 9, cellHeight: 10, timestamp: .zero) == .up)
        #expect(sut.touchMouseWheelAccumulator.consume(deltaY: 9, cellHeight: 10, timestamp: 1) == nil)
        sut.resetCmd(nil)
        #expect(sut.touchMouseWheelAccumulator.consume(deltaY: 1, cellHeight: 10, timestamp: .zero) == nil)
    }

    /// local tap은 byte를 보내지 않고 scrollWheel tap은 first responder가 아니어도 press/release를 보낸다.
    @Test
    func tapPolicyKeepsLocalModeLocalAndReportsInScrollWheelMode() {
        let (sut, delegate) = makeSUT()
        let tap = EndedTapGestureRecognizer(location: CGPoint(x: 10, y: 10))
        sut.addGestureRecognizer(tap)
        sut.terminal.feed(text: "\(esc)[?1000h\(esc)[?1006h")

        sut.touchMouseInteractionMode = .local
        sut.singleTap(tap)
        #expect(delegate.sentData.isEmpty)

        sut.touchMouseInteractionMode = .scrollWheel
        sut.singleTap(tap)
        #expect(delegate.sentData.count == 2)

        sut.allowMouseReporting = false
        sut.singleTap(tap)
        #expect(delegate.sentData.count == 2)
    }

    /// 수평-only 이동과 two-finger pinch arbitration은 wheel byte를 만들지 않는다.
    @Test
    func horizontalMovementAndPinchDoNotEmitWheelBytes() throws {
        let (sut, delegate) = makeSUT()
        sut.touchMouseInteractionMode = .scrollWheel
        sut.terminal.feed(text: "\(esc)[?1000h\(esc)[?1006h")
        let pan = try #require(sut.panMouseGesture)
        let pinch = UIPinchGestureRecognizer()

        #expect(sut.gestureRecognizer(pan, shouldRecognizeSimultaneouslyWith: pinch))
        sut.handleTouchMouseWheelPanChange(
            state: .changed,
            touchCount: 1,
            deltaY: 0,
            location: CGPoint(x: 10, y: 10),
            timestamp: .zero,
            reportingAllowed: true
        )
        sut.handleTouchMouseWheelPanChange(
            state: .changed,
            touchCount: 2,
            deltaY: 40,
            location: CGPoint(x: 10, y: 10),
            timestamp: 1,
            reportingAllowed: true
        )

        #expect(delegate.sentData.isEmpty)
    }

    /// automatic default는 기존 first-responder remote tap의 press/release byte를 그대로 유지한다.
    @Test
    func automaticModePreservesRemoteTapBytes() {
        let (sut, delegate) = makeSUT()
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 160))
        let rootViewController = UIViewController()
        window.rootViewController = rootViewController
        rootViewController.view.addSubview(sut)
        window.makeKeyAndVisible()
        let tap = EndedTapGestureRecognizer(location: CGPoint(x: 10, y: 10))
        sut.addGestureRecognizer(tap)
        sut.terminal.feed(text: "\(esc)[?1000h\(esc)[?1006h")

        #expect(sut.becomeFirstResponder())
        sut.singleTap(tap)

        #expect(delegate.sentData.count == 2)
        #expect(String(decoding: delegate.sentData[0], as: UTF8.self).hasPrefix("\(esc)[<0;"))
        #expect(String(decoding: delegate.sentData[1], as: UTF8.self).hasPrefix("\(esc)[<0;"))
    }

    /// host double-tap handler는 실제 recognizer callback에서 정확히 한 번 소비되고 remote byte를 만들지 않는다.
    @Test
    func hostDoubleTapHandlerConsumesTheRecognizerCallbackOnce() {
        let (sut, delegate) = makeSUT()
        let tap = EndedTapGestureRecognizer(location: CGPoint(x: 10, y: 10))
        sut.addGestureRecognizer(tap)
        sut.terminal.feed(text: "\(esc)[?1000h\(esc)[?1006h")
        var callCount = 0

        sut.doubleTapHandler = { callCount += 1 }
        sut.doubleTap(tap)
        #expect(callCount == 1)
        #expect(delegate.sentData.isEmpty)
    }

    /// wheel adapter는 기존 negotiated encoder를 사용해 natural swipe-up을 button 5로 전송한다.
    @Test
    func wheelEventUsesTheNegotiatedTerminalEncoder() throws {
        let (sut, delegate) = makeSUT()
        sut.terminal.feed(text: "\(esc)[?1000h\(esc)[?1006h")

        sut.sendTouchMouseWheelEvent(.down, at: CGPoint(x: 10, y: 10))

        let payload = try #require(delegate.sentData.first)
        #expect(String(decoding: payload, as: UTF8.self).hasPrefix("\(esc)[<65;"))
    }
}
#endif
