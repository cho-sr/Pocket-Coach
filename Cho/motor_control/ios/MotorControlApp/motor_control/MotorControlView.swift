import SwiftUI

struct MotorControlView: View {
    @StateObject private var viewModel = MotorControlViewModel()

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.10, green: 0.16, blue: 0.30),
                    Color(red: 0.05, green: 0.08, blue: 0.16)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 24) {
                headerCard
                angleCard
                buttonRow
                footerText
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 28)
        }
        .onAppear {
            viewModel.refreshConnection()
        }
        .task {
            while !Task.isCancelled {
                await MainActor.run {
                    viewModel.refreshConnection()
                }
                try? await Task.sleep(nanoseconds: 1_500_000_000)
            }
        }
    }

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                Text("Leonardo USB MIDI 수동 제어")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)

                Spacer(minLength: 12)

                Button("다시 검색") {
                    viewModel.refreshConnection()
                }
                .buttonStyle(.borderedProminent)
                .tint(Color(red: 0.28, green: 0.58, blue: 0.95))
            }

            Text(viewModel.midiStatusText)
                .font(.system(size: 15, weight: .semibold, design: .monospaced))
                .foregroundStyle(Color(red: 0.74, green: 0.90, blue: 1.00))

            Text(viewModel.lastActionText)
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.92))

            if let lastErrorText = viewModel.lastErrorText {
                Text(lastErrorText)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(Color(red: 1.00, green: 0.72, blue: 0.72))
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("감지된 MIDI 목적지")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.72))

                ForEach(viewModel.midiDestinationLines, id: \.self) { line in
                    Text(line)
                        .font(.system(size: 12, weight: .regular, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.84))
                }
            }
            .padding(.top, 6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color.white.opacity(0.10))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.white.opacity(0.14), lineWidth: 1)
        )
    }

    private var angleCard: some View {
        VStack(spacing: 10) {
            Text("현재 각도")
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.84))

            Text("\(viewModel.currentAngle)°")
                .font(.system(size: 64, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)

            Text("표준 서보 각도 기준 · 1회 \(viewModel.tuning.stepDegrees)° 이동")
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.72))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .padding(.horizontal, 20)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(Color.black.opacity(0.22))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
    }

    private var buttonRow: some View {
        HStack(spacing: 16) {
            DirectionButton(
                title: "LEFT",
                subtitle: "-15°",
                systemImage: "arrow.left.circle.fill",
                tint: Color(red: 0.94, green: 0.55, blue: 0.30),
                isEnabled: viewModel.canMoveLeft,
                action: viewModel.moveLeft
            )

            DirectionButton(
                title: "RIGHT",
                subtitle: "+15°",
                systemImage: "arrow.right.circle.fill",
                tint: Color(red: 0.22, green: 0.72, blue: 0.58),
                isEnabled: viewModel.canMoveRight,
                action: viewModel.moveRight
            )
        }
    }

    private var footerText: some View {
        Text("버튼을 한 번 누를 때마다 Leonardo가 서보를 정확히 15도씩 이동시킵니다.")
            .font(.system(size: 14, weight: .medium, design: .rounded))
            .foregroundStyle(.white.opacity(0.74))
            .multilineTextAlignment(.center)
            .padding(.horizontal, 12)
    }
}

private struct DirectionButton: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let tint: Color
    let isEnabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 14) {
                Image(systemName: systemImage)
                    .font(.system(size: 34, weight: .bold))

                Text(title)
                    .font(.system(size: 26, weight: .heavy, design: .rounded))

                Text(subtitle)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .opacity(0.85)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 220)
            .foregroundStyle(.white)
            .background(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(tint.opacity(isEnabled ? 0.95 : 0.32))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .stroke(Color.white.opacity(isEnabled ? 0.20 : 0.08), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .scaleEffect(isEnabled ? 1.0 : 0.98)
        .opacity(isEnabled ? 1.0 : 0.72)
    }
}
