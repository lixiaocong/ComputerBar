import AppKit
import XCTest
@testable import ComputerBar

final class MenuBarStatusImageTests: XCTestCase {
    func testUnavailableMenuBarStatusImageMarksErrorAcrossStack() throws {
        let image = MenuBarStatusImage.make(
            bars: [
                MenuBarStatusImage.Bar(label: "ec2", isError: true),
            ]
        )

        let representation = try XCTUnwrap(image.tiffRepresentation)
        let bitmap = try XCTUnwrap(NSBitmapImageRep(data: representation))
        var strongRightSideRedPixels = 0

        for x in 35..<bitmap.pixelsWide {
            for y in 0..<bitmap.pixelsHigh {
                guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
                if color.alphaComponent > 0.55,
                   color.redComponent > 0.65,
                   color.greenComponent < 0.45,
                   color.blueComponent < 0.45 {
                    strongRightSideRedPixels += 1
                }
            }
        }

        XCTAssertGreaterThan(strongRightSideRedPixels, 0)
    }
}
