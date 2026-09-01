import Foundation
import Testing
@testable import SwiftTerm

struct TouchMouseWheelAccumulatorTests {
    private func makeSUT() -> TouchMouseWheelAccumulator {
        TouchMouseWheelAccumulator()
    }

    /// 한 cell을 채운 손가락 위쪽 이동은 natural 방향의 wheel-down 후보 한 개를 만든다.
    @Test
    func upwardFingerMovementEmitsWheelDownAtOneCell() {
        var sut = makeSUT()

        #expect(sut.consume(deltaY: -9, cellHeight: 10, timestamp: .zero) == nil)
        #expect(sut.consume(deltaY: -1, cellHeight: 10, timestamp: .zero) == .down)
    }

    /// 방향이 바뀌면 이전 remainder를 버리고 새 방향으로 한 cell을 다시 누적한다.
    @Test
    func reversalDropsThePreviousRemainder() {
        var sut = makeSUT()

        #expect(sut.consume(deltaY: 9, cellHeight: 10, timestamp: .zero) == nil)
        #expect(sut.consume(deltaY: -9, cellHeight: 10, timestamp: .zero) == nil)
        #expect(sut.consume(deltaY: -1, cellHeight: 10, timestamp: .zero) == .down)
    }

    /// pending distance가 여러 cell이어도 consume 한 번에는 한 event만 내고 30Hz 간격을 지킨다.
    @Test
    func cadenceAllowsOnlyOneEventPerThirtyHertzInterval() {
        var sut = makeSUT()

        #expect(sut.consume(deltaY: 60, cellHeight: 10, timestamp: .zero) == .up)
        #expect(sut.consume(deltaY: 0.1, cellHeight: 10, timestamp: 0.020) == nil)
        #expect(sut.consume(deltaY: 0.1, cellHeight: 10, timestamp: 0.034) == .up)
    }

    /// 긴 frame stall의 pending distance는 여섯 cell로 clamp되어 여섯 후보보다 많이 배출되지 않는다.
    @Test
    func pendingDistanceIsClampedToSixCells() {
        var sut = makeSUT()
        var emitted: [TouchMouseWheelDirection] = []

        if let direction = sut.consume(deltaY: 1_000, cellHeight: 10, timestamp: .zero) {
            emitted.append(direction)
        }
        for index in 1...6 {
            if let direction = sut.consume(
                deltaY: 0.1,
                cellHeight: 10,
                timestamp: Double(index) * 0.034
            ) {
                emitted.append(direction)
            }
        }

        #expect(emitted == Array(repeating: .up, count: 6))
    }

    /// zero와 non-finite delta 및 non-positive cell height는 상태를 오염시키지 않는다.
    @Test
    func invalidInputIsIgnoredWithoutChangingState() {
        var sut = makeSUT()

        #expect(sut.consume(deltaY: 0, cellHeight: 10, timestamp: .zero) == nil)
        #expect(sut.consume(deltaY: .nan, cellHeight: 10, timestamp: .zero) == nil)
        #expect(sut.consume(deltaY: .infinity, cellHeight: 10, timestamp: .zero) == nil)
        #expect(sut.consume(deltaY: 10, cellHeight: 0, timestamp: .zero) == nil)
        #expect(sut.consume(deltaY: 10, cellHeight: -1, timestamp: .zero) == nil)
        #expect(sut.consume(deltaY: 10, cellHeight: 10, timestamp: .zero) == .up)
    }

    /// reset은 pending remainder와 마지막 emission cadence를 모두 지운다.
    @Test
    func resetClearsPendingDistanceAndCadence() {
        var sut = makeSUT()

        #expect(sut.consume(deltaY: 9, cellHeight: 10, timestamp: .zero) == nil)
        sut.reset()
        #expect(sut.consume(deltaY: 1, cellHeight: 10, timestamp: .zero) == nil)
        #expect(sut.consume(deltaY: 9, cellHeight: 10, timestamp: .zero) == .up)
        sut.reset()
        #expect(sut.consume(deltaY: -10, cellHeight: 10, timestamp: .zero) == .down)
    }

    /// public policy constants는 30 event/s와 여섯 pending cell 계약을 고정한다.
    @Test
    func constantsMatchTheTouchMouseContract() {
        #expect(TouchMouseWheelAccumulator.maximumEventsPerSecond == 30)
        #expect(TouchMouseWheelAccumulator.maximumPendingCells == 6)
    }
}
