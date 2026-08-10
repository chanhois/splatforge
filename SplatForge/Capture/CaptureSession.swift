import ARKit
import Combine

/// Owns an AR capture run and streams accepted keyframes to JPEG files instead of retaining pixels in memory.
final class CaptureSession: NSObject, ObservableObject, ARSessionDelegate {
    let session = ARSession()
    @Published private(set) var keyframeCount = 0

    /// A snapshot is synchronized with the capture queue, so callers may safely read it after `stop()`.
    var keyframes: [PosedFrame] {
        synchronizeCaptureQueue { storedKeyframes }
    }

    private static let captureQueueKey = DispatchSpecificKey<Void>()
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

    // Access only on the main thread. It prevents an older run's queued UI update from winning.
    private var publishedRunID: UUID?

    override init() {
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
        captureQueue.setSpecific(key: Self.captureQueueKey, value: ())
    }

    func start() {
        session.pause()
        setAcceptsFrames(false)

        synchronizeCaptureQueue {
            keyframeSelector.reset()
            storedKeyframes.removeAll()
        }

        let runID = UUID()
        intakeLock.lock()
        activeRunID = runID
        isProcessingFrame = false
        acceptsFrames = true
        intakeLock.unlock()
        beginPublishing(runID: runID)

        let configuration = ARWorldTrackingConfiguration()
        configuration.planeDetection = [.horizontal]
        session.delegate = self
        session.run(configuration)
    }

    /// Pauses ARKit and waits for the one in-flight candidate, making `keyframes` stable on return.
    func stop() {
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
        intakeLock.unlock()

        // This is a bounded hand-off: while one expensive candidate is converting, scoring, and saving,
        // newer AR frames are dropped rather than accumulating an unbounded queue.
        captureQueue.async { [weak self] in
            guard let self else { return }
            defer { self.finishProcessing(runID: runID) }
            self.process(frame, runID: runID)
        }
    }

    private func process(_ frame: ARFrame, runID: UUID) {
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

    private func setAcceptsFrames(_ accepts: Bool) {
        intakeLock.lock()
        acceptsFrames = accepts
        intakeLock.unlock()
    }

    private func synchronizeCaptureQueue<T>(_ work: () -> T) -> T {
        if DispatchQueue.getSpecific(key: Self.captureQueueKey) != nil {
            return work()
        }
        return captureQueue.sync(execute: work)
    }

    private func beginPublishing(runID: UUID) {
        let update = { [weak self] in
            guard let self else { return }
            self.publishedRunID = runID
            self.keyframeCount = 0
        }
        if Thread.isMainThread {
            update()
        } else {
            DispatchQueue.main.sync(execute: update)
        }
    }

    private func publishKeyframeCount(_ count: Int, for runID: UUID) {
        DispatchQueue.main.async { [weak self] in
            guard let self, self.publishedRunID == runID else { return }
            self.keyframeCount = count
        }
    }
}
