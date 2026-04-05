import Foundation

private final class FixtureMarker {}

func fixture(named name: String) throws -> String {
    let bundle = Bundle(for: FixtureMarker.self)
    let url = bundle.url(forResource: name, withExtension: "txt")!
    return try String(contentsOf: url)
}
