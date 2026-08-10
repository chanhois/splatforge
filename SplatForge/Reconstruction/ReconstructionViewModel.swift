import Combine
import Foundation

nonisolated enum ReconstructionPipelineError: LocalizedError, Sendable {
    case insufficientKeyframes(minimum: Int, actual: Int)
    case noReconstructedPoints

    var errorDescription: String? {
        switch self {
        case let .insufficientKeyframes(minimum, actual):
            return "재구성에는 최소 \(minimum)개의 키프레임이 필요합니다. 현재 \(actual)개입니다."
        case .noReconstructedPoints:
            return "재구성할 수 있는 3D 포인트를 찾지 못했습니다. 이미지를 확인하고 다시 촬영해 주세요."
        }
    }
}

@MainActor
final class ReconstructionViewModel: ObservableObject {
    typealias Worker = @Sendable ([PosedFrame], URL) async throws -> Int

    @Published var isProcessing = false
    @Published var pointCount: Int?
    @Published var exportedFileURL: URL?
    @Published var errorMessage: String?

    private let worker: Worker
    private let exportDirectoryFactory: @Sendable () -> URL
    private var activeRunID: UUID?
    private var activeTask: Task<Void, Never>?

    init(
        worker: @escaping Worker = ReconstructionViewModel.reconstructAndExport,
        exportDirectoryFactory: @escaping @Sendable () -> URL = ReconstructionViewModel.makeExportDirectory
    ) {
        self.worker = worker
        self.exportDirectoryFactory = exportDirectoryFactory
    }

    func reconstruct(keyframes: [PosedFrame]) {
        activeTask?.cancel()

        let runID = UUID()
        let outputURL = exportDirectoryFactory()
            .appendingPathComponent("sparse-\(runID.uuidString).ply")
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
                let didPublish = await self?.finishSuccess(
                    runID: runID,
                    pointCount: pointCount,
                    outputURL: outputURL
                )
                if didPublish != true {
                    Self.removeOutputFile(at: outputURL)
                }
            } catch {
                Self.removeOutputFile(at: outputURL)
                guard !Task.isCancelled else { return }
                await self?.finishFailure(
                    runID: runID,
                    message: error.localizedDescription
                )
            }
        }
    }

    private func finishSuccess(runID: UUID, pointCount: Int, outputURL: URL) -> Bool {
        guard activeRunID == runID else { return false }

        self.pointCount = pointCount
        exportedFileURL = outputURL
        errorMessage = nil
        isProcessing = false
        activeRunID = nil
        activeTask = nil
        return true
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
        guard keyframes.count >= SparseReconstructor.minimumKeyframeCount else {
            throw ReconstructionPipelineError.insufficientKeyframes(
                minimum: SparseReconstructor.minimumKeyframeCount,
                actual: keyframes.count
            )
        }
        let points = SparseReconstructor.reconstruct(keyframes: keyframes)
        try Task.checkCancellation()
        guard !points.isEmpty else {
            throw ReconstructionPipelineError.noReconstructedPoints
        }
        try PLYExporter.write(points: points, to: outputURL)
        try Task.checkCancellation()
        return points.count
    }

    nonisolated private static func makeExportDirectory() -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SplatForge-Exports", isDirectory: true)
        try? FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        return directory
    }

    nonisolated private static func removeOutputFile(at outputURL: URL) {
        try? FileManager.default.removeItem(at: outputURL)
    }
}
