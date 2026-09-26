import SwiftUI
import StrengthTrackerShared
#if os(watchOS)
import WatchKit
#endif

struct WatchRestTimerView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel: WatchWorkoutViewModel
    @State private var crownPosition = 0
    @FocusState private var isCrownFocused: Bool

    init(viewModel: WatchWorkoutViewModel) {
        self._viewModel = State(initialValue: viewModel)
    }

    private let primaryYellow = Color(red: 0.949, green: 0.800, blue: 0.051)

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .bold))
                        .frame(width: 28, height: 28)
                        .background(Color.white.opacity(0.15))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                Spacer()
                if viewModel.isPaused {
                    Text("PAUSED")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(primaryYellow)
                }
            }

            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.1), lineWidth: 6)
                    .frame(width: 94, height: 94)

                Circle()
                    .trim(from: 0, to: viewModel.restProgress)
                    .stroke(
                        primaryYellow,
                        style: StrokeStyle(lineWidth: 6, lineCap: .round)
                    )
                    .frame(width: 94, height: 94)
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 1), value: viewModel.restProgress)

                VStack(spacing: 2) {
                    Image(systemName: "timer")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(primaryYellow)

                    Text(viewModel.restTimerText)
                        .font(.system(size: 24, weight: .bold))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                }
            }
            .focusable()
            .focused($isCrownFocused)
            .digitalCrownRotation(detent: $crownPosition, from: -4000, through: 4000,
                                  by: 1, sensitivity: .low)
            .onChange(of: crownPosition) { previous, position in
                viewModel.adjustRestTimer(by: (position - previous) * 15)
            }
            .onTapGesture { isCrownFocused = true }
            .accessibilityLabel("Timer \(viewModel.restTimerText). Turn the Crown to adjust by 15 seconds")

            ProgressView(value: viewModel.restProgress)
                .tint(primaryYellow)
                .accessibilityLabel("Timer progress")

            HStack(spacing: 8) {
                adjustmentButton("−15", seconds: -15)
                adjustmentButton("+15", seconds: 15)
            }

            Button {
                #if os(watchOS)
                WKInterfaceDevice.current().play(.click)
                #endif
                viewModel.skipRestTimer()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "forward.fill")
                        .font(.system(size: 12))
                    Text("SKIP")
                        .font(.system(size: 13, weight: .bold))
                        .tracking(1)
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(Color.white.opacity(0.15))
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .disabled(viewModel.isPaused)
        }
        .padding()
        .defaultFocus($isCrownFocused, true)
        .onAppear { isCrownFocused = true }
        // Haptic feedback on timer completion is handled by WatchWorkoutViewModel.restTimerCompleted()
    }

    private func adjustmentButton(_ title: String, seconds: Int) -> some View {
        Button {
            viewModel.adjustRestTimer(by: seconds)
            isCrownFocused = true
        } label: {
            Text(title)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(primaryYellow)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 7)
                .background(primaryYellow.opacity(0.15))
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(seconds < 0 ? "Subtract 15 seconds" : "Add 15 seconds")
    }
}
