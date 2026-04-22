import SwiftUI
import UIKit

struct ModeSelectionView: View {
    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text("YOLO Check")
                    .font(.largeTitle.weight(.bold))
                Text("Pick a model test path.")
                    .font(.body)
                    .foregroundStyle(.secondary)

                VStack(spacing: 12) {
                    ForEach(DetectionMode.allCases) { mode in
                        NavigationLink {
                            DetectionModeHost(mode: mode)
                                .ignoresSafeArea()
                                .navigationBarTitleDisplayMode(.inline)
                        } label: {
                            ModeButton(mode: mode)
                        }
                        .buttonStyle(.plain)
                    }
                }

                Spacer()
            }
            .padding(20)
            .navigationTitle("Model Test")
        }
    }
}

private struct ModeButton: View {
    let mode: DetectionMode

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(mode.title)
                .font(.headline)
                .foregroundStyle(.primary)
            Text(mode.subtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color(uiColor: .secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

struct DetectionModeHost: UIViewControllerRepresentable {
    let mode: DetectionMode

    func makeUIViewController(context: Context) -> UIViewController {
        switch mode {
        case .detect, .testImage:
            return StillDetectionViewController(mode: mode)
        case .live:
            return LiveDetectionViewController()
        }
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {}
}
