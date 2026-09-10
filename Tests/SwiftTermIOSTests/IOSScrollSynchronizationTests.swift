import Foundation
import Testing
@testable import SwiftTerm

#if os(iOS) || os(visionOS)
@MainActor
private final class ScrollStateTerminalView: TerminalView {
    var reportsTracking = false
    var reportsDecelerating = false

    override var isTracking: Bool { reportsTracking }
    override var isDecelerating: Bool { reportsDecelerating }
}

@MainActor
struct IOSScrollSynchronizationTests {
    /// Upward momentum keeps the terminal snapshot row aligned with UIScrollView after the finger lifts.
    @Test func upwardDecelerationSynchronizesDisplayRowAfterTrackingEnds() {
        let view = makeSUT()
        let bottomRow = view.withTerminal { $0.displayBuffer.yDisp }
        let dragRow = max(1, bottomRow - 2)
        let momentumRow = max(0, dragRow - 4)

        view.reportsTracking = true
        view.contentOffset.y = CGFloat(dragRow) * view.cellDimension.height
        #expect(view.withTerminal { $0.displayBuffer.yDisp } == dragRow)
        #expect(view.withTerminal { $0.userScrolling })

        view.reportsTracking = false
        view.reportsDecelerating = true
        view.contentOffset.y = CGFloat(momentumRow) * view.cellDimension.height

        #expect(view.withTerminal { $0.displayBuffer.yDisp } == momentumRow)
        #expect(view.withTerminal { $0.userScrolling })
    }

    /// Momentum reaching the bottom restores live-output following instead of freezing history.
    @Test func downwardDecelerationReachingBottomRestoresAutoFollow() {
        let view = makeSUT()
        let bottomRow = view.withTerminal { $0.displayBuffer.yDisp }
        let historyRow = max(1, bottomRow - 5)

        view.reportsTracking = true
        view.contentOffset.y = CGFloat(historyRow) * view.cellDimension.height
        #expect(view.withTerminal { $0.userScrolling })

        view.reportsTracking = false
        view.reportsDecelerating = true
        view.contentOffset.y = view.contentSize.height - view.bounds.height

        #expect(view.withTerminal { $0.displayBuffer.yDisp } == bottomRow)
        #expect(!view.withTerminal { $0.userScrolling })
    }

    private func makeSUT() -> ScrollStateTerminalView {
        let view = ScrollStateTerminalView(
            frame: CGRect(origin: .zero, size: .init(width: 320, height: 160))
        )
        for line in 0..<80 {
            view.feed(text: "line \(line)\r\n")
        }
        view.updateScroller()
        return view
    }
}
#endif
