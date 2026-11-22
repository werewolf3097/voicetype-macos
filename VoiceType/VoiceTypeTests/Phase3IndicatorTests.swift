import XCTest
@testable import VoiceTypeTests

final class Phase3IndicatorTests: XCTestCase {
    func testNormalizeDecibelsMapsSilenceAndSpeechIntoUnitRange() {
        XCTAssertEqual(AudioRecorder.normalizeDecibels(-160), 0, accuracy: 0.001)
        XCTAssertEqual(AudioRecorder.normalizeDecibels(-52), 0, accuracy: 0.001)
        XCTAssertGreaterThan(AudioRecorder.normalizeDecibels(-20), 0.4)
        XCTAssertEqual(AudioRecorder.normalizeDecibels(0), 1, accuracy: 0.001)
    }

    func testIndicatorLayoutCalculatorOffReturnsNil() {
        let rect = IndicatorLayoutCalculator.frame(
            size: CGSize(width: 100, height: 26),
            screenFrame: NSRect(x: 0, y: 0, width: 1512, height: 982),
            visibleFrame: NSRect(x: 0, y: 60, width: 1512, height: 884),
            safeAreaTop: 38,
            auxTopLeft: NSRect(x: 0, y: 944, width: 650, height: 38),
            auxTopRight: NSRect(x: 862, y: 944, width: 650, height: 38),
            position: .off,
            placement: .fromNotch
        )
        XCTAssertNil(rect)
    }

    func testIndicatorLayoutCalculatorFromNotchWithAndWithoutNotch() throws {
        let size = CGSize(width: 100, height: 26)
        let screen = NSRect(x: 0, y: 0, width: 1512, height: 982)
        let visible = NSRect(x: 0, y: 60, width: 1512, height: 884)

        let notched = try XCTUnwrap(IndicatorLayoutCalculator.frame(
            size: size,
            screenFrame: screen,
            visibleFrame: visible,
            safeAreaTop: 38,
            auxTopLeft: NSRect(x: 0, y: 944, width: 650, height: 38),
            auxTopRight: NSRect(x: 862, y: 944, width: 650, height: 38),
            position: .top,
            placement: .fromNotch
        ))
        XCTAssertEqual(notched.midX, screen.midX, accuracy: 0.5)
        XCTAssertEqual(notched.maxY, screen.maxY - 38 - 4, accuracy: 0.5)

        let nonNotched = try XCTUnwrap(IndicatorLayoutCalculator.frame(
            size: size,
            screenFrame: screen,
            visibleFrame: NSRect(x: 0, y: 60, width: 1512, height: 897),
            safeAreaTop: 0,
            auxTopLeft: .zero,
            auxTopRight: .zero,
            position: .top,
            placement: .fromNotch
        ))
        XCTAssertEqual(nonNotched.maxY, 957 - 8, accuracy: 0.5)
    }

    func testIndicatorLayoutCalculatorInMenuBarAvoidsNotch() throws {
        let size = CGSize(width: 100, height: 26)
        let screen = NSRect(x: 0, y: 0, width: 1512, height: 982)
        let visible = NSRect(x: 0, y: 60, width: 1512, height: 884)
        let auxRight = NSRect(x: 862, y: 944, width: 650, height: 38)

        let frame = try XCTUnwrap(IndicatorLayoutCalculator.frame(
            size: size,
            screenFrame: screen,
            visibleFrame: visible,
            safeAreaTop: 38,
            auxTopLeft: NSRect(x: 0, y: 944, width: 650, height: 38),
            auxTopRight: auxRight,
            position: .top,
            placement: .inMenuBar
        ))
        XCTAssertGreaterThanOrEqual(frame.minX, auxRight.minX)
        XCTAssertGreaterThan(frame.minY, visible.maxY)
    }

    func testIndicatorLayoutCalculatorBottomPlacement() throws {
        let size = CGSize(width: 100, height: 26)
        let screen = NSRect(x: 0, y: 0, width: 1512, height: 982)
        let visible = NSRect(x: 0, y: 60, width: 1512, height: 884)

        let frame = try XCTUnwrap(IndicatorLayoutCalculator.frame(
            size: size,
            screenFrame: screen,
            visibleFrame: visible,
            safeAreaTop: 38,
            auxTopLeft: .zero,
            auxTopRight: .zero,
            position: .bottom,
            placement: .fromNotch
        ))
        XCTAssertEqual(frame.minY, visible.minY + 14, accuracy: 0.5)
        XCTAssertEqual(frame.midX, screen.midX, accuracy: 0.5)
    }
}
