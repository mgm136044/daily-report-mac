import Foundation

public struct FSStats: Equatable {
    public var rootsScanned: Int
    public var files: Int
    public var filesDroppedOverCap: Int
    public init(rootsScanned: Int, files: Int, filesDroppedOverCap: Int) {
        self.rootsScanned = rootsScanned; self.files = files
        self.filesDroppedOverCap = filesDroppedOverCap
    }
}

public struct FSCollection: Equatable {
    public var roots: [String: [String]]
    public var stats: FSStats
    public init(roots: [String: [String]], stats: FSStats) {
        self.roots = roots; self.stats = stats
    }
}
