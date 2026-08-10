import XCTest

@testable import OpenSuperWhisper

/// What the bubble shows while a clip is transcribing.
///
/// It follows the layout the user chose, or stopping a recording would resize the window under
/// them: someone who picked the meter alone would see it swapped for a wide label. One element
/// in, one element out, same footprint.
final class DecodingLayoutTests: XCTestCase {

    private func layout(hiding hidden: [IndicatorElement]) -> IndicatorLayout {
        var layout = IndicatorLayout.default
        for element in hidden { layout.setVisible(false, for: element) }
        return layout
    }

    func testMeterOnlyStaysMeterOnly() {
        let elements = layout(hiding: [.label, .stopButton, .cancelButton]).decoding

        XCTAssertTrue(elements.contains(.waveform))
        XCTAssertFalse(elements.contains(.label), "a label would widen a bubble that had none")
    }

    func testLabelOnlyStaysLabelOnly() {
        let elements = layout(hiding: [.waveform, .stopButton, .cancelButton]).decoding

        XCTAssertTrue(elements.contains(.label))
        XCTAssertFalse(elements.contains(.waveform))
    }

    func testBothStayBoth() {
        let elements = layout(hiding: [.stopButton, .cancelButton]).decoding

        XCTAssertTrue(elements.contains(.waveform))
        XCTAssertTrue(elements.contains(.label))
    }

    /// Nothing left to stop once the clip is queued, and a dead button invites a click that
    /// does nothing.
    func testControlsAreDropped() {
        let elements = layout(hiding: []).decoding

        XCTAssertFalse(elements.contains(.stopButton))
        XCTAssertFalse(elements.contains(.cancelButton))
    }

    /// A lone dot cannot say "still working": it looks the same either way. The meter is
    /// borrowed to carry the spinner rather than leaving no signal at all.
    func testALayoutThatCannotShowProgressGetsTheSpinner() {
        // The dot is hidden by default, so it has to be asked for to be the only thing left.
        var dotOnly = layout(hiding: [.waveform, .label, .stopButton, .cancelButton])
        dotOnly.setVisible(true, for: .dot)

        let elements = dotOnly.decoding

        XCTAssertTrue(elements.contains(.waveform), "nothing else could show progress")
        XCTAssertTrue(elements.contains(.dot), "the dot the user chose is still theirs")
    }

    /// Order is the user's, not ours: the spinner appears where their meter was.
    func testOrderMatchesTheRecordingLayout() {
        let chosen = layout(hiding: [.stopButton, .cancelButton])

        XCTAssertEqual(chosen.decoding, chosen.leading)
    }

    /// Hiding everything is a layout someone can actually save.
    func testAnEmptyLayoutStillShowsSomething() {
        let elements = layout(hiding: IndicatorElement.allCases).decoding

        XCTAssertEqual(elements, [.waveform])
    }
}
