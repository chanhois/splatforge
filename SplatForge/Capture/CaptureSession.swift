import ARKit
import Combine

/// Owns an AR capture run and streams accepted keyframes to JPEG files instead of retaining pixels in memory.
nonisolated final class CaptureSession: NSObject, ObservableObject, ARSessionDelegate, @unchecked Sendable {
    @MainActor let session = ARSession()
    @MainActor @Published private(set) var keyframeCount = 0

    /// A snapshot is synchronized with the capture queue, so callers may safely read it after `stop()`.
    var keyframes: [PosedFrame] {
        synchronizeCaptureQueue { storedKeyframes }
    }

    private let captureQueueKey = DispatchSpecificKey<Void>()
    private let captureQueue = DispatchQueue(label: "com.splatforge.capture.processing")
    private let intakeLock = NSLock()
    private let keyframeSelector = KeyframeSelector()
    private let storageDirectory: URL

    // Access only on captureQueue.
    private var storedKeyframes: [PosedFrame] = []

    // Access only while intakeLock is held.
    private var acceptsFrames = false
    private var isProcessingFrame = false
    private var activeRunID = UUID()

    // Access only on the main actor. It prevents an older run's queued UI update from winning.
    @MainActor private var publishedRunID: UUID?

    @MainActor override init() {
        storageDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("capture-\(UUID().uuidString)", isDirectory: true)

        do {
            try FileManager.default.createDirectory(
                at: storageDirectory,
                withIntermediateDirectories: true,
                attributes: nil
            )
        } catch {
            preconditionFailure("캡처 디렉터리를 만들 수 없습니다: \(error)")
        }

        super.init()
        captureQueue.setSpecific(key: captureQueueKey, value: ())
    }

    @MainActor func start() {
        session.pause()
        setAcceptsFrames(false)

        synchronizeCaptureQueue {
            keyframeSelector.reset()
            storedKeyframes.removeAll()
        }

        let runID = UUID()
        intakeLock.lock()
        activeRunID = runID
        acceptsFrames = true
        intakeLock.unlock()
        beginPublishing(runID: runID)

        let configuration = ARWorldTrackingConfiguration()
        configuration.planeDetection = [.horizontal]
        session.delegate = self
        session.run(configuration)
    }

    /// Pauses ARKit and waits for the one in-flight candidate, making `keyframes` stable on return.
    @MainActor func stop() {
        session.pause()
        setAcceptsFrames(false)
        synchronizeCaptureQueue {}
    }

    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        let runID: UUID
        intakeLock.lock()
        guard acceptsFrames, !isProcessingFrame else {
            intakeLock.unlock()
            return
        }
        isProcessingFrame = true
        runID = activeRunID

        // This is a bounded hand-off: while one expensive candidate is converting, scoring, and saving,
        // newer AR frames are dropped rather than accumulating an unbounded queue.
        captureQueue.async { [weak self] in
            guard let self else { return }
            defer { self.finishProcessing(runID: runID) }
            self.process(frame, runID: runID)
        }
        // Enqueue before releasing the reservation so stop/start's subsequent queue sync cannot miss it.
        intakeLock.unlock()
    }

    private func process(_ frame: ARFrame, runID: UUID) {
        guard isActiveRun(runID) else { return }
        let pose = frame.camera.transform
        guard keyframeSelector.passesGeometricFilter(pose: pose, trackingState: frame.camera.trackingState) else {
            return
        }

        let image = frame.capturedImage.toUIImage()
        guard keyframeSelector.passesBlurFilter(image: image) else {
            return
        }

        guard let jpegData = image.jpegData(compressionQuality: 0.9) else {
            print("키프레임 JPEG 인코딩 실패")
            return
        }

        let imageURL = storageDirectory.appendingPathComponent("frame-\(storedKeyframes.count).jpg")
        do {
            try jpegData.write(to: imageURL, options: .atomic)
        } catch {
            print("키프레임 저장 실패: \(error)")
            return
        }

        // Persist first: failed encoding/writes must not advance filtering state or the published count.
        keyframeSelector.commit(pose: pose)
        let posedFrame = PosedFrame(
            imagePath: imageURL,
            pose: pose,
            intrinsics: frame.camera.intrinsics,
            timestamp: frame.timestamp
        )
        storedKeyframes.append(posedFrame)
        let count = storedKeyframes.count
        publishKeyframeCount(count, for: runID)
        print("키프레임 #\(count) 저장: \(imageURL.path)")
    }

    private func finishProcessing(runID: UUID) {
        intakeLock.lock()
        if activeRunID == runID {
            isProcessingFrame = false
        }
        intakeLock.unlock()
    }

    private func isActiveRun(_ runID: UUID) -> Bool {
        intakeLock.lock()
        defer { intakeLock.unlock() }
        return activeRunID == runID
    }

    private func setAcceptsFrames(_ accepts: Bool) {
        intakeLock.lock()
        acceptsFrames = accepts
        intakeLock.unlock()
    }

    private func synchronizeCaptureQueue<T>(_ work: () -> T) -> T {
        if DispatchQueue.getSpecific(key: captureQueueKey) != nil {
            return work()
        }
        return captureQueue.sync(execute: work)
    }

    @MainActor private func beginPublishing(runID: UUID) {
        publishedRunID = runID
        keyframeCount = 0
    }

    private func publishKeyframeCount(_ count: Int, for runID: UUID) {
        DispatchQueue.main.async { @MainActor [weak self] in
            guard let self, self.publishedRunID == runID else { return }
            self.keyframeCount = count
        }
    }
}
