import XCTest
import simd
@testable import SplatForge

@MainActor
final class ReconstructionViewModelTests: XCTestCase {
    func test_successfulCompletionPublishesExistingFileAndPointCount() async throws {
        let points = [
            SparsePoint3D(position: simd_float3(1, 2, 3), color: SIMD3<UInt8>(255, 0, 0)),
            SparsePoint3D(position: simd_float3(4, 5, 6), color: SIMD3<UInt8>(0, 255, 0))
        ]
        let outputURL = temporaryPLYURL()
        defer { try? FileManager.default.removeItem(at: outputURL) }
        let viewModel = ReconstructionViewModel(
            worker: { _, url in
                try PLYExporter.write(points: points, to: url)
                return points.count
            },
            exportURLFactory: { outputURL }
        )

        viewModel.reconstruct(keyframes: [])

        XCTAssertTrue(viewModel.isProcessing)
        XCTAssertNil(viewModel.pointCount)
        XCTAssertNil(viewModel.exportedFileURL)
        XCTAssertNil(viewModel.errorMessage)
        guard await waitUntil({ !viewModel.isProcessing }) else {
            XCTFail("Reconstruction did not finish")
            return
        }

        XCTAssertEqual(viewModel.pointCount, 2)
        XCTAssertEqual(viewModel.exportedFileURL, outputURL)
        XCTAssertNil(viewModel.errorMessage)
        XCTAssertTrue(FileManager.default.fileExists(atPath: outputURL.path))
    }

    func test_exportFailurePublishesErrorAndNeverPublishesFileURL() async {
        let staleURL = temporaryPLYURL()
        defer { try? FileManager.default.removeItem(at: staleURL) }
        let viewModel = ReconstructionViewModel(
            worker: { _, url in
                try Data("partial export".utf8).write(to: url)
                throw ExpectedFailure.export
            },
            exportURLFactory: { staleURL }
        )
        viewModel.pointCount = 99
        viewModel.exportedFileURL = staleURL
        viewModel.errorMessage = "이전 오류"

        viewModel.reconstruct(keyframes: [])

        XCTAssertTrue(viewModel.isProcessing)
        XCTAssertNil(viewModel.pointCount)
        XCTAssertNil(viewModel.exportedFileURL)
        XCTAssertNil(viewModel.errorMessage)
        guard await waitUntil({ !viewModel.isProcessing }) else {
            XCTFail("Failed reconstruction did not finish")
            return
        }

        XCTAssertNil(viewModel.pointCount)
        XCTAssertNil(viewModel.exportedFileURL)
        XCTAssertEqual(viewModel.errorMessage, ExpectedFailure.export.localizedDescription)
        XCTAssertFalse(FileManager.default.fileExists(atPath: staleURL.path))
    }

    func test_defaultWorkerRejectsInsufficientKeyframesWithoutCreatingPLY() async {
        let outputURL = temporaryPLYURL()
        defer { try? FileManager.default.removeItem(at: outputURL) }
        let viewModel = ReconstructionViewModel(exportURLFactory: { outputURL })

        viewModel.reconstruct(keyframes: (0..<3).map(makeFrame(identifier:)))
        guard await waitUntil({ !viewModel.isProcessing }) else {
            XCTFail("Insufficient-input reconstruction did not finish")
            return
        }

        XCTAssertNil(viewModel.pointCount)
        XCTAssertNil(viewModel.exportedFileURL)
        XCTAssertTrue(viewModel.errorMessage?.contains("최소 4") == true)
        XCTAssertFalse(FileManager.default.fileExists(atPath: outputURL.path))
    }

    func test_defaultWorkerRejectsMissingImagesWhenNoPointsAreReconstructed() async {
        let outputURL = temporaryPLYURL()
        defer { try? FileManager.default.removeItem(at: outputURL) }
        let viewModel = ReconstructionViewModel(exportURLFactory: { outputURL })

        viewModel.reconstruct(keyframes: (0..<4).map(makeFrame(identifier:)))
        guard await waitUntil({ !viewModel.isProcessing }) else {
            XCTFail("Empty reconstruction did not finish")
            return
        }

        XCTAssertNil(viewModel.pointCount)
        XCTAssertNil(viewModel.exportedFileURL)
        XCTAssertTrue(viewModel.errorMessage?.contains("3D 포인트") == true)
        XCTAssertFalse(FileManager.default.fileExists(atPath: outputURL.path))
    }

    func test_olderRunCannotOverwriteNewerCompletion() async throws {
        let worker = ControlledWorker()
        let viewModel = ReconstructionViewModel(
            worker: { keyframes, url in
                let identifier = Int(keyframes[0].timestamp)
                return try await worker.run(identifier: identifier, outputURL: url)
            }
        )

        viewModel.reconstruct(keyframes: [makeFrame(identifier: 1)])
        guard await waitUntil({ await worker.hasStarted(identifier: 1) }) else {
            XCTFail("First reconstruction did not start")
            return
        }

        viewModel.reconstruct(keyframes: [makeFrame(identifier: 2)])
        guard await waitUntil({ await worker.hasStarted(identifier: 2) }) else {
            XCTFail("Second reconstruction did not start")
            return
        }

        await worker.succeed(identifier: 2, pointCount: 22)
        guard await waitUntil({ !viewModel.isProcessing }) else {
            XCTFail("Second reconstruction did not finish")
            return
        }
        XCTAssertEqual(viewModel.pointCount, 22)
        let newestURL = try XCTUnwrap(viewModel.exportedFileURL)
        defer { try? FileManager.default.removeItem(at: newestURL) }

        await worker.succeed(identifier: 1, pointCount: 11)
        guard await waitUntil({ await worker.hasReturned(identifier: 1) }) else {
            XCTFail("First reconstruction did not return")
            return
        }
        for _ in 0..<20 {
            await Task.yield()
        }

        XCTAssertFalse(viewModel.isProcessing)
        XCTAssertEqual(viewModel.pointCount, 22)
        XCTAssertEqual(viewModel.exportedFileURL, newestURL)
        XCTAssertNil(viewModel.errorMessage)

        if let staleURL = await worker.outputURL(identifier: 1) {
            guard await waitUntil({
                !FileManager.default.fileExists(atPath: staleURL.path)
            }) else {
                XCTFail("Canceled run output was not removed")
                return
            }
            XCTAssertFalse(FileManager.default.fileExists(atPath: staleURL.path))
        }
    }

    private func makeFrame(identifier: Int) -> PosedFrame {
        PosedFrame(
            imagePath: FileManager.default.temporaryDirectory
                .appendingPathComponent("missing-\(identifier).jpg"),
            pose: matrix_identity_float4x4,
            intrinsics: matrix_identity_float3x3,
            timestamp: TimeInterval(identifier)
        )
    }

    private func temporaryPLYURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("view-model-test-\(UUID().uuidString).ply")
    }

    private func waitUntil(
        _ condition: @escaping @MainActor () async -> Bool,
        timeout: Duration = .seconds(5)
    ) async -> Bool {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while clock.now < deadline {
            if await condition() {
                return true
            }
            await Task.yield()
        }
        return await condition()
    }
}

private enum ExpectedFailure: LocalizedError {
    case export

    var errorDescription: String? {
        "PLY 파일을 쓸 수 없습니다."
    }
}

private actor ControlledWorker {
    private var continuations: [Int: CheckedContinuation<Int, any Error>] = [:]
    private var startedIdentifiers: Set<Int> = []
    private var returnedIdentifiers: Set<Int> = []
    private var outputURLs: [Int: URL] = [:]

    func run(identifier: Int, outputURL: URL) async throws -> Int {
        startedIdentifiers.insert(identifier)
        outputURLs[identifier] = outputURL
        let pointCount = try await withCheckedThrowingContinuation { continuation in
            continuations[identifier] = continuation
        }
        // Deliberately bypass the cancellation-aware production exporter: this fake models an
        // injected worker that ignores cancellation and writes after a newer run has started.
        try Data("late output for run \(identifier)".utf8).write(to: outputURL)
        returnedIdentifiers.insert(identifier)
        return pointCount
    }

    func hasStarted(identifier: Int) -> Bool {
        startedIdentifiers.contains(identifier)
    }

    func hasReturned(identifier: Int) -> Bool {
        returnedIdentifiers.contains(identifier)
    }

    func outputURL(identifier: Int) -> URL? {
        outputURLs[identifier]
    }

    func succeed(identifier: Int, pointCount: Int) {
        continuations.removeValue(forKey: identifier)?.resume(returning: pointCount)
    }
}
