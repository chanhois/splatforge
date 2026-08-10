import Combine
import Foundation

@MainActor
final class ReconstructionViewModel: ObservableObject {
    typealias Worker = @Sendable ([PosedFrame], URL) async throws -> Int

    @Published var isProcessing = false
    @Published var pointCount: Int?
    @Published var exportedFileURL: URL?
    @Published var errorMessage: String?

    private let worker: Worker
    private let exportURLFactory: @Sendable () -> URL
    private var activeRunID: UUID?
    private var activeTask: Task<Void, Never>?

    init(
        worker: @escaping Worker = ReconstructionViewModel.reconstructAndExport,
        exportURLFactory: @escaping @Sendable () -> URL = ReconstructionViewModel.makeExportURL
    ) {
        self.worker = worker
        self.exportURLFactory = exportURLFactory
    }

    func reconstruct(keyframes: [PosedFrame]) {
        activeTask?.cancel()

        let runID = UUID()
        let outputURL = exportURLFactory()
        let worker = worker
        activeRunID = runID
        isProcessing = true
        pointCount = nil
        exportedFileURL = nil
        errorMessage = nil

        activeTask = Task.detached(priority: .userInitiated) { [weak self] in
            do {
                let pointCount = try await worker(keyframes, outputURL)
                try Task.checkCancellation()
                await self?.finishSuccess(
                    runID: runID,
                    pointCount: pointCount,
                    outputURL: outputURL
                )
            } catch {
                guard !Task.isCancelled else { return }
                await self?.finishFailure(
                    runID: runID,
                    message: error.localizedDescription
                )
            }
        }
    }

    private func finishSuccess(runID: UUID, pointCount: Int, outputURL: URL) {
        guard activeRunID == runID else { return }

        self.pointCount = pointCount
        exportedFileURL = outputURL
        errorMessage = nil
        isProcessing = false
        activeRunID = nil
        activeTask = nil
    }

    private func finishFailure(runID: UUID, message: String) {
        guard activeRunID == runID else { return }

        pointCount = nil
        exportedFileURL = nil
        errorMessage = message
        isProcessing = false
        activeRunID = nil
        activeTask = nil
    }

    nonisolated private static func reconstructAndExport(
        keyframes: [PosedFrame],
        outputURL: URL
    ) async throws -> Int {
        try Task.checkCancellation()
        let points = SparseReconstructor.reconstruct(keyframes: keyframes)
        try Task.checkCancellation()
        try PLYExporter.write(points: points, to: outputURL)
        try Task.checkCancellation()
        return points.count
    }

    nonisolated private static func makeExportURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("sparse-\(UUID().uuidString).ply")
    }
}
