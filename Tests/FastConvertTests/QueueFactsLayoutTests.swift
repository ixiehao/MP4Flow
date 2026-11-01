import AppKit
import SwiftUI
import XCTest
@testable import FastConvert

final class QueueFactsLayoutTests: XCTestCase {
    @MainActor
    func testExtraColumnWidthDoesNotSeparateDetailsFromResult() throws {
        // Render the real header: a height-only assertion cannot detect a
        // flexible spacer incorrectly inserted before the detail action.
        let width: CGFloat = 600
        let view = NSHostingView(rootView: QueueResultHeader(
            outputFileSize: 83_000_000,
            notice: MediaHandlingNotice(issues: [.chapters(10)]),
            showsDetails: .constant(false)
        ).frame(width: width, height: 32, alignment: .leading).background(Color.white))
        view.frame = CGRect(x: 0, y: 0, width: width, height: 32)
        view.layoutSubtreeIfNeeded()
        let bitmap = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: bitmap)
        var inkColumns = Set<Int>()
        for x in 0..<bitmap.pixelsWide {
            for y in 0..<bitmap.pixelsHigh {
                guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
                if color.alphaComponent > 0.5 && min(color.redComponent, color.greenComponent, color.blueComponent) < 0.8 {
                    inkColumns.insert(x)
                    break
                }
            }
        }
        XCTAssertGreaterThan(inkColumns.count, 30, "The renderer must capture actual text and icons")
        let rightEdge = CGFloat(try XCTUnwrap(inkColumns.max())) * width / CGFloat(bitmap.pixelsWide)
        XCTAssertLessThan(rightEdge, width * 0.6, "Details must remain next to the result when the column gets wider")
    }

    @MainActor
    func testIconOnlyDetailsDoNotMoveTheStatusBaseline() throws {
        var centers: [CGFloat] = []
        for notice in [nil, MediaHandlingNotice(issues: [.chapters(10)])] {
            let view = NSHostingView(rootView: QueueResultHeader(
                outputFileSize: 83_000_000, notice: notice, showsDetails: .constant(false)
            ).frame(width: 170, height: 32, alignment: .leading).background(Color.white))
            view.frame = CGRect(x: 0, y: 0, width: 170, height: 32)
            view.layoutSubtreeIfNeeded()
            let bitmap = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
            view.cacheDisplay(in: view.bounds, to: bitmap)
            var rows = Set<Int>()
            for x in 0..<bitmap.pixelsWide {
                for y in 0..<bitmap.pixelsHigh {
                    guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
                    if color.alphaComponent > 0.5 && color.greenComponent > color.redComponent * 1.5 && color.greenComponent > color.blueComponent * 1.2 {
                        rows.insert(y)
                    }
                }
            }
            let top = try XCTUnwrap(rows.min()), bottom = try XCTUnwrap(rows.max())
            centers.append(CGFloat(top + bottom) / 2 * 32 / CGFloat(bitmap.pixelsHigh))
        }
        XCTAssertEqual(centers[0], centers[1], accuracy: 0.5, "An image-only detail action must not change the status text's vertical position")
    }

    @MainActor
    func testCompletedStatusSizeAndDetailsKeepOneHeaderRowInEveryLanguage() {
        let defaults = UserDefaults.standard
        let original = defaults.volatileDomain(forName: "NSArgumentDomain")
        defer { defaults.setVolatileDomain(original, forName: "NSArgumentDomain") }
        for language in AppLanguage.allCases {
            var domain = original; domain["appLanguage"] = language.rawValue
            defaults.setVolatileDomain(domain, forName: "NSArgumentDomain")
            for notice in [nil, MediaHandlingNotice(issues: [.chapters(10)])] {
                let view = NSHostingView(rootView: QueueResultHeader(outputFileSize: 83_000_000, notice: notice, showsDetails: .constant(false)).frame(width: 230))
                view.layoutSubtreeIfNeeded()
                XCTAssertEqual(view.fittingSize.width, 230, accuracy: 0.5)
                XCTAssertEqual(view.fittingSize.height, 24, accuracy: 0.5, "Headers with and without details must keep the same line height: \(language)")
            }
        }
    }

    @MainActor
    func testNarrowFactsUseMoreLinesInsteadOfHidingSizeOrUnits() {
        let presentation = VideoPresentation(duration: 37_235, fileSize: 700_000_000_000, thumbnail: nil, width: 3840, height: 2160)
        let narrow = NSHostingView(rootView: QueueMediaFacts(presentation: presentation).frame(width: 140))
        let wide = NSHostingView(rootView: QueueMediaFacts(presentation: presentation).frame(width: 360))
        narrow.layoutSubtreeIfNeeded(); wide.layoutSubtreeIfNeeded()
        XCTAssertEqual(narrow.fittingSize.width, 140, accuracy: 0.5)
        XCTAssertEqual(wide.fittingSize.width, 360, accuracy: 0.5)
        XCTAssertGreaterThan(narrow.fittingSize.height, wide.fittingSize.height, "A narrow column must add lines rather than truncate the important facts")
        XCTAssertEqual(presentation.factFields.count, 3)
    }
}
