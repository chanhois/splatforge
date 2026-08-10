//
//  ContentView.swift
//  SplatForge
//
//  Created by 서찬호 on 8/2/26.
//

import SwiftUI

struct ContentView: View {
    var body: some View {
        CaptureView { keyframes in
            print("캡처 완료: \(keyframes.count)개 키프레임")
            // Task 11에서 여기를 재구성 파이프라인 호출로 교체한다.
        }
    }
}

#Preview {
    ContentView()
}
