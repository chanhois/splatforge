import SwiftUI

struct ResultView: View {
    @ObservedObject var viewModel: ReconstructionViewModel

    var body: some View {
        VStack(spacing: 16) {
            if viewModel.isProcessing {
                ProgressView("재구성 중...")
            } else if let errorMessage = viewModel.errorMessage {
                Label("재구성에 실패했습니다", systemImage: "exclamationmark.triangle")
                    .font(.headline)
                    .foregroundStyle(.red)
                Text(errorMessage)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
            } else if let count = viewModel.pointCount,
                      let url = viewModel.exportedFileURL {
                Text("\(count)개 포인트 재구성 완료")
                    .font(.headline)
                ShareLink(item: url) {
                    Label(".ply 내보내기", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
    }
}
