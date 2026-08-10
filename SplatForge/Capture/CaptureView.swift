import SwiftUI
import ARKit

/// ARSCNView는 UIKit 뷰라서 SwiftUI에서 쓰려면 UIViewRepresentable로 감싸야 한다.
/// 세션을 스스로 만들지 않고 외부에서 주입받는다 — 세션의 생명주기는 CaptureSession이 소유한다.
struct ARContainerView: UIViewRepresentable {
    let session: ARSession

    func makeUIView(context: Context) -> ARSCNView {
        let view = ARSCNView()
        view.session = session
        return view
    }

    func updateUIView(_ uiView: ARSCNView, context: Context) {}
}

struct CaptureView: View {
    @StateObject private var captureSession = CaptureSession()
    @State private var isCapturing = false
    var onCaptureFinished: ([PosedFrame]) -> Void

    private let targetKeyframeCount = 50

    var body: some View {
        ZStack(alignment: .bottom) {
            ARContainerView(session: captureSession.session)
                .ignoresSafeArea()

            VStack(spacing: 16) {
                Text("\(captureSession.keyframeCount) / \(targetKeyframeCount) 키프레임")
                    .foregroundStyle(.white)
                    .padding(8)
                    .background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 8))

                Button(isCapturing ? "촬영 종료" : "촬영 시작") {
                    toggleCapture()
                }
                .buttonStyle(.borderedProminent)
                .padding(.bottom, 32)
            }
        }
        .onChange(of: captureSession.keyframeCount) { _, newCount in
            if isCapturing && newCount >= targetKeyframeCount {
                toggleCapture()
            }
        }
    }

    private func toggleCapture() {
        if isCapturing {
            captureSession.stop()
            onCaptureFinished(captureSession.keyframes)
        } else {
            captureSession.start()
        }
        isCapturing.toggle()
    }
}
