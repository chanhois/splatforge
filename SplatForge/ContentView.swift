//
//  ContentView.swift
//  SplatForge
//
//  Created by 서찬호 on 8/2/26.
//

import SwiftUI
import ARKit

// ARSCNView는 UIKit 뷰라서 SwiftUI에서 쓰려면 UIViewRepresentable로 감싸야 한다.
// 지금은 동작 확인용 임시 세션만 돌린다 — 실제 캡처 로직은 Task 6/7에서 CaptureSession으로 교체한다.
struct ARCameraPreview: UIViewRepresentable {
    func makeUIView(context: Context) -> ARSCNView {
        let view = ARSCNView()
        let configuration = ARWorldTrackingConfiguration()
        view.session.run(configuration)
        return view
    }

    func updateUIView(_ uiView: ARSCNView, context: Context) {}
}

struct ContentView: View {
    var body: some View {
        ARCameraPreview()
            .ignoresSafeArea()
    }
}

#Preview {
    ContentView()
}
