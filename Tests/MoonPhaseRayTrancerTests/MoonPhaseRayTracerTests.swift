import XCTest
import CoreLocation
@testable import MoonPhaseRayTracer

final class MoonPhaseRayTracerTests: XCTestCase {

    // MARK: - Utility

    private func isPNG(_ data: Data) -> Bool {
        // PNG signature: 89 50 4E 47 0D 0A 1A 0A
        let sig: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]
        guard data.count >= sig.count else { return false }
        return data.prefix(sig.count).elementsEqual(sig)
    }

    // MARK: - fractionalPhase tests

    func testFractionalPhaseRange() {
        // A few sample dates should always yield [0, 1)
        let dates: [Date] = [
            Date(timeIntervalSinceReferenceDate: 0),                // 2001-01-01
            Date(timeIntervalSinceReferenceDate: 10_000_000),       // arbitrary
            Date(timeIntervalSinceReferenceDate: -10_000_000),      // before reference
            Date()                                                  // now
        ]
        for d in dates {
            let phase = MoonPhaseRayTracer.fractionalPhase(for: d)
            XCTAssert(phase >= 0 && phase < 1, "Phase should be in [0,1), got \(phase)")
        }
    }

    func testFractionalPhaseWrapsDailyProgress() {
        // Move ~1 day and verify phase changes smoothly (not necessarily monotonic over long span)
        let base = Date(timeIntervalSinceReferenceDate: 0)
        let oneDay: TimeInterval = 86_400
        let p0 = MoonPhaseRayTracer.fractionalPhase(for: base)
        let p1 = MoonPhaseRayTracer.fractionalPhase(for: base.addingTimeInterval(oneDay))
        // Over a day, phase should change by roughly 1 / 29.53 ~= 0.0338
        let delta = abs(p1 - p0)
        XCTAssert(delta > 0.01 && delta < 0.1, "Unexpected daily phase delta: \(delta)")
    }

    // MARK: - Rendering tests (phase-based API)

    func testRenderMoonImageWithPhaseReturnsPNG() {
        let data = MoonPhaseRayTracer.renderMoonImage(phase: 0.25, size: CGSize(width: 128, height: 128))
        XCTAssertFalse(data.isEmpty, "PNG data should not be empty")
        XCTAssertTrue(isPNG(data), "Output should be PNG data")
    }

    func testRenderMoonImageClampsPhaseAndReturnsPNG() {
        // Phase outside [0,1] should be clamped without crashing
        let dataLow = MoonPhaseRayTracer.renderMoonImage(phase: -1.0, size: CGSize(width: 64, height: 64))
        let dataHigh = MoonPhaseRayTracer.renderMoonImage(phase: 2.0, size: CGSize(width: 64, height: 64))
        XCTAssertTrue(isPNG(dataLow))
        XCTAssertTrue(isPNG(dataHigh))
    }

    // MARK: - Rendering tests (date/location API)

    func testRenderMoonImageForDateLocationReturnsPNG() {
        let kyoto = CLLocationCoordinate2D(latitude: 35.0116, longitude: 135.7681)
        let data = MoonPhaseRayTracer.renderMoonImage(for: Date(), location: kyoto, size: CGSize(width: 64, height: 64))
        XCTAssertTrue(isPNG(data))
    }

    func testRenderMoonImageForDateWithNilLocationReturnsPNG() {
        let data = MoonPhaseRayTracer.renderMoonImage(for: Date(), location: nil, size: CGSize(width: 64, height: 64))
        XCTAssertTrue(isPNG(data))
    }

    // MARK: - SceneKit-specific behavior (only when available)

    #if canImport(SceneKit)
    func testRenderWithAntialiasingModes() {
        let sizes = [CGSize(width: 64, height: 64), CGSize(width: 128, height: 96)]
        let modes: [MoonPhaseRayTracer.RenderingOptions.Antialiasing] = [.none, .x2, .x4]
        for s in sizes {
            for m in modes {
                let options = MoonPhaseRayTracer.RenderingOptions(antialiasing: m, exposure: 1.0)
                let data = MoonPhaseRayTracer.renderMoonImage(phase: 0.6, size: s, options: options)
                XCTAssertTrue(isPNG(data))
            }
        }
    }

    func testRenderWithExposureValues() {
        // Extreme exposures should still produce valid PNG data
        let exposures: [CGFloat] = [0.0, 0.5, 1.0, 2.0, 4.0]
        for e in exposures {
            let options = MoonPhaseRayTracer.RenderingOptions(exposure: e)
            let data = MoonPhaseRayTracer.renderMoonImage(phase: 0.1, size: CGSize(width: 80, height: 80), options: options)
            XCTAssertTrue(isPNG(data))
        }
    }
    #endif
}
