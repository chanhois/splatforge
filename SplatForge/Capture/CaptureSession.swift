import ARKit
import Combine

/// ARSession을 감싸는 클래스. 이 시점에서는 재구성 로직을 전혀 모르고,
/// ARKit이 주는 프레임을 받아서 콘솔에 찍어보는 것까지만 한다 —
/// 실시간 키프레임 필터링/저장은 Task 6에서 추가된다.
final class CaptureSession: NSObject, ObservableObject, ARSessionDelegate {
    let session = ARSession()
    @Published private(set) var keyframeCount = 0

    private var frameCounter = 0

    func start() {
        let configuration = ARWorldTrackingConfiguration()
        configuration.planeDetection = [.horizontal]
        session.delegate = self
        session.run(configuration)
    }

    func stop() {
        session.pause()
    }

    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        frameCounter += 1
        // 30프레임(약 0.5초)마다 한 번씩만 로그 — 매 프레임 찍으면 콘솔이 감당 안 됨
        if frameCounter % 30 == 0 {
            let t = frame.camera.transform.columns.3
            print("frame #\(frameCounter) tracking=\(frame.camera.trackingState) pos=(\(t.x), \(t.y), \(t.z))")
        }
    }
}
