import Foundation

/// Allocates immutable, per-run capture locations while their frame URLs may still be consumed.
nonisolated struct CaptureRunStorage: Sendable {
    let rootDirectory: URL

    init(
        rootDirectory: URL = FileManager.default.temporaryDirectory
            .appendingPathComponent("SplatForge-Captures", isDirectory: true)
    ) {
        self.rootDirectory = rootDirectory
    }

    func makeRunDirectory() throws -> URL {
        let runDirectory = rootDirectory
            .appendingPathComponent("capture-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: runDirectory,
            withIntermediateDirectories: true,
            attributes: nil
        )
        return runDirectory
    }

    func frameURL(index: Int, in runDirectory: URL) -> URL {
        runDirectory.appendingPathComponent("frame-\(index).jpg")
    }
}
