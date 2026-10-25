import XCTest
@testable import FastConvert

final class CropGeometryTests: XCTestCase {
    func testFullFrameAndZeroOriginAreNotShiftedOrShrunk() throws {
        let full = CropRect(x: 0, y: 0, width: 1920, height: 1080)
        XCTAssertEqual(CropGeometry.normalized(full, sourceWidth: 1920, sourceHeight: 1080), full)
        let topLeft = CropRect(x: 0, y: 0, width: 640, height: 480)
        XCTAssertEqual(CropGeometry.normalized(topLeft, sourceWidth: 1920, sourceHeight: 1080), topLeft)
    }

    func testSquareAndMatchingAspectFitTheActualCanvas() throws {
        XCTAssertEqual(CropGeometry.centered(ratio: 1, sourceWidth: 1920, sourceHeight: 1080), CropRect(x: 420, y: 0, width: 1080, height: 1080))
        XCTAssertEqual(CropGeometry.centered(ratio: 1, sourceWidth: 1080, sourceHeight: 1920), CropRect(x: 0, y: 420, width: 1080, height: 1080))
        XCTAssertEqual(CropGeometry.centered(ratio: 16.0 / 9, sourceWidth: 1920, sourceHeight: 1080), CropRect(x: 0, y: 0, width: 1920, height: 1080))
    }

    func testInputsStayEvenAndWithinBoundsIncludingOddAndSmallCanvases() throws {
        let inputs = [
            CropRect(x: -10, y: -1, width: 2000, height: 2000),
            CropRect(x: 1919, y: 1079, width: 100, height: 100),
            CropRect(x: 3, y: 5, width: 17, height: 19),
            CropRect(x: Int.min, y: Int.max, width: -1, height: Int.max)
        ]
        for (width, height) in [(1920, 1080), (1919, 1079), (2, 2), (3, 3)] {
            for input in inputs {
                let crop = try XCTUnwrap(CropGeometry.normalized(input, sourceWidth: width, sourceHeight: height))
                XCTAssertGreaterThanOrEqual(crop.x, 0)
                XCTAssertGreaterThanOrEqual(crop.y, 0)
                XCTAssertGreaterThanOrEqual(crop.width, 2)
                XCTAssertGreaterThanOrEqual(crop.height, 2)
                XCTAssertLessThanOrEqual(crop.x + crop.width, width)
                XCTAssertLessThanOrEqual(crop.y + crop.height, height)
                for value in [crop.x, crop.y, crop.width, crop.height] { XCTAssertEqual(value % 2, 0) }
                XCTAssertEqual(CropGeometry.normalized(crop, sourceWidth: width, sourceHeight: height), crop)
            }
        }
    }

    func testUnsupportedCanvasesAndAspectValuesAreRejected() {
        let crop = CropRect(x: 0, y: 0, width: 10, height: 10)
        XCTAssertNil(CropGeometry.normalized(crop, sourceWidth: 1, sourceHeight: 10))
        XCTAssertNil(CropGeometry.normalized(crop, sourceWidth: 10, sourceHeight: 0))
        for ratio in [0.0, -1, .infinity, .nan] {
            XCTAssertNil(CropGeometry.centered(ratio: ratio, sourceWidth: 1920, sourceHeight: 1080))
        }
    }
}
