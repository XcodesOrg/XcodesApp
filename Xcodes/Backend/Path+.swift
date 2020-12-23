import Path

extension Path {
    static let xcodesApplicationSupport = Path.applicationSupport/"com.robotsandpencils.xcodes"
    static let cacheFile = xcodesApplicationSupport/"available-xcodes.json"
}
