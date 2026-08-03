//
//  ContentView.swift
//  SplatForge
//
//  Created by 서찬호 on 8/2/26.
//

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

struct ContentView: View {
    @StateObject private var captureSession = CaptureSession()

    var body: some View {
        ARContainerView(session: captureSession.session)
            .ignoresSafeArea()
            .onAppear { captureSession.start() }
    }
}

#Preview {
    ContentView()
}
