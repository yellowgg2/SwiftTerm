import Foundation

enum TouchMouseWheelDirection: Sendable, Equatable {
    /// Scrolls remote content up using xterm wheel button 4.
    case up
    /// Scrolls remote content down using xterm wheel button 5.
    case down
}

struct TouchMouseWheelAccumulator: Sendable {
    static let maximumEventsPerSecond = 30
    static let maximumPendingCells = 6

    private static let minimumEmissionInterval: TimeInterval =
        1.0 / Double(maximumEventsPerSecond)

    private var pendingDistance = 0.0
    private var pendingSign: Int?
    private var lastEmissionTimestamp: TimeInterval?

    mutating func consume(
        deltaY: Double,
        cellHeight: Double,
        timestamp: TimeInterval
    ) -> TouchMouseWheelDirection? {
        guard deltaY.isFinite, deltaY != 0, cellHeight.isFinite, cellHeight > 0 else {
            return nil
        }

        let sign = deltaY > 0 ? 1 : -1
        if let pendingSign, pendingSign != sign {
            pendingDistance = 0
        }
        pendingSign = sign

        let maximumPendingDistance = Double(Self.maximumPendingCells) * cellHeight
        pendingDistance = min(
            max(pendingDistance + deltaY, -maximumPendingDistance),
            maximumPendingDistance
        )

        guard abs(pendingDistance) >= cellHeight else {
            return nil
        }
        if let lastEmissionTimestamp,
           timestamp - lastEmissionTimestamp < Self.minimumEmissionInterval {
            return nil
        }

        lastEmissionTimestamp = timestamp
        if pendingDistance > 0 {
            pendingDistance -= cellHeight
            return .up
        } else {
            pendingDistance += cellHeight
            return .down
        }
    }

    mutating func reset() {
        pendingDistance = 0
        pendingSign = nil
        lastEmissionTimestamp = nil
    }
}
