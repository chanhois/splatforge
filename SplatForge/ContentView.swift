//
//  ContentView.swift
//  SplatForge
//
//  Created by 서찬호 on 8/2/26.
//

import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel = ReconstructionViewModel()
    @State private var isShowingResult = false

    var body: some View {
        CaptureView { keyframes in
            isShowingResult = true
            viewModel.reconstruct(keyframes: keyframes)
        }
        .sheet(isPresented: $isShowingResult) {
            ResultView(viewModel: viewModel)
                .interactiveDismissDisabled(viewModel.isProcessing)
        }
    }
}

#Preview {
    ContentView()
}
