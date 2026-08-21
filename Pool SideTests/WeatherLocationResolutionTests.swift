import XCTest
@testable import Pool_Side

/// Increment 5 — weather coordinate persistence/resolution. Guards the "Richmond, IN" regression where a
/// changed location kept the previous location's stored coordinates (and therefore its weather). The
/// decision is centralized in `LocationCoordinateResolver.canReuseCoordinates`, exercised here directly.
final class WeatherLocationResolutionTests: XCTestCase {

    // A. Coordinates resolved for the same typed location are reusable.
    func testFreshCoordinatesForSameLocationAreReused() {
        XCTAssertTrue(LocationCoordinateResolver.canReuseCoordinates(
            typedLocation: "Phoenix, AZ",
            coordinateSource: "Phoenix, AZ",
            latitude: 33.4484,
            longitude: -112.0740
        ))
    }

    // B. The regression: coordinates belong to a previously entered place; the user typed a new one.
    func testStaleCoordinatesFromPreviousLocationAreNotReused() {
        // Phoenix coordinates still stored, but the user has now entered Richmond, IN.
        XCTAssertFalse(LocationCoordinateResolver.canReuseCoordinates(
            typedLocation: "Richmond, IN",
            coordinateSource: "Phoenix, AZ",
            latitude: 33.4484,
            longitude: -112.0740
        ), "Coordinates from a different location must be re-resolved, not reused.")
    }

    // C. No coordinates yet → must resolve.
    func testMissingCoordinatesAreNotReused() {
        XCTAssertFalse(LocationCoordinateResolver.canReuseCoordinates(
            typedLocation: "Richmond, IN",
            coordinateSource: "Richmond, IN",
            latitude: nil,
            longitude: nil
        ))
    }

    // D. Coordinates present but of unknown provenance (source nil) → must resolve rather than trust them.
    func testCoordinatesWithUnknownSourceAreNotReused() {
        XCTAssertFalse(LocationCoordinateResolver.canReuseCoordinates(
            typedLocation: "Richmond, IN",
            coordinateSource: nil,
            latitude: 39.8289,
            longitude: -84.8902
        ))
    }

    // E. Only one coordinate present → treated as incomplete, must resolve.
    func testPartialCoordinatesAreNotReused() {
        XCTAssertFalse(LocationCoordinateResolver.canReuseCoordinates(
            typedLocation: "Richmond, IN",
            coordinateSource: "Richmond, IN",
            latitude: 39.8289,
            longitude: nil
        ))
    }

    // F. Empty typed location → nothing to resolve against, not reusable.
    func testEmptyTypedLocationIsNotReusable() {
        XCTAssertFalse(LocationCoordinateResolver.canReuseCoordinates(
            typedLocation: "",
            coordinateSource: "Phoenix, AZ",
            latitude: 33.4484,
            longitude: -112.0740
        ))
    }

    // G. Whitespace-only typed location is treated as empty.
    func testWhitespaceOnlyTypedLocationIsNotReusable() {
        XCTAssertFalse(LocationCoordinateResolver.canReuseCoordinates(
            typedLocation: "   \n",
            coordinateSource: "Phoenix, AZ",
            latitude: 33.4484,
            longitude: -112.0740
        ))
    }

    // H. Surrounding whitespace/newlines do not count as a location change.
    func testWhitespaceDifferencesStillCountAsSameLocation() {
        XCTAssertTrue(LocationCoordinateResolver.canReuseCoordinates(
            typedLocation: "  Richmond, IN\n",
            coordinateSource: "Richmond, IN",
            latitude: 39.8289,
            longitude: -84.8902
        ))
    }

    // I. Case differences do not count as a location change.
    func testCaseDifferencesStillCountAsSameLocation() {
        XCTAssertTrue(LocationCoordinateResolver.canReuseCoordinates(
            typedLocation: "richmond, in",
            coordinateSource: "Richmond, IN",
            latitude: 39.8289,
            longitude: -84.8902
        ))
    }

    // J. An empty-string source (never resolved) is not a valid match even if text is empty-vs-empty.
    func testEmptySourceIsNotReusable() {
        XCTAssertFalse(LocationCoordinateResolver.canReuseCoordinates(
            typedLocation: "Richmond, IN",
            coordinateSource: "",
            latitude: 39.8289,
            longitude: -84.8902
        ))
    }
}
