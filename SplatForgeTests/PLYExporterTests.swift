import XCTest
import simd
@testable import SplatForge

final class PLYExporterTests: XCTestCase {
    func test_writesValidAsciiHeaderAndCompleteVertexRows() throws {
        let points = [
            SparsePoint3D(position: simd_float3(1, 2, 3), color: SIMD3<UInt8>(255, 0, 0)),
            SparsePoint3D(position: simd_float3(-1, 0.5, 2), color: SIMD3<UInt8>(0, 255, 0))
        ]
        let url = temporaryPLYURL()
        defer { try? FileManager.default.removeItem(at: url) }

        try PLYExporter.write(points: points, to: url)

        let content = try String(contentsOf: url, encoding: .utf8)
        XCTAssertEqual(
            content.split(whereSeparator: \Character.isNewline).map(String.init),
            [
                "ply",
                "format ascii 1.0",
                "element vertex 2",
                "property float x",
                "property float y",
                "property float z",
                "property uchar red",
                "property uchar green",
                "property uchar blue",
                "end_header",
                "1.0 2.0 3.0 255 0 0",
                "-1.0 0.5 2.0 0 255 0"
            ]
        )
    }

    func test_emptyCloudDeclaresZeroVerticesWithoutDataRows() throws {
        let url = temporaryPLYURL()
        defer { try? FileManager.default.removeItem(at: url) }

        try PLYExporter.write(points: [], to: url)

        let content = try String(contentsOf: url, encoding: .utf8)
        let lines = content.split(whereSeparator: \Character.isNewline).map(String.init)
        XCTAssertEqual(lines.count, 10)
        XCTAssertEqual(lines[2], "element vertex 0")
        XCTAssertEqual(lines.last, "end_header")
    }

    func test_writeFailureIsPropagated() {
        let missingParent = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let url = missingParent.appendingPathComponent("cloud.ply")

        XCTAssertThrowsError(try PLYExporter.write(points: [], to: url))
    }

    func test_preCancelledWriteThrowsCancellationWithoutCreatingFile() async {
        let url = temporaryPLYURL()
        defer { try? FileManager.default.removeItem(at: url) }
        let points = [
            SparsePoint3D(position: simd_float3(1, 2, 3), color: SIMD3<UInt8>(255, 0, 0))
        ]

        let threwCancellation = await Task.detached {
            withUnsafeCurrentTask { task in
                task?.cancel()
            }
            do {
                try PLYExporter.write(points: points, to: url)
                return false
            } catch is CancellationError {
                return true
            } catch {
                return false
            }
        }.value

        XCTAssertTrue(threwCancellation)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }

    private func temporaryPLYURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("test-\(UUID().uuidString).ply")
    }
}
