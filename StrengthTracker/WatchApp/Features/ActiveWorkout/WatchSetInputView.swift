import SwiftUI
import StrengthTrackerShared

struct WatchSetInputView: View {
    @State private var viewModel: WatchWorkoutViewModel
    @State private var weightSteps: Int = 8
    @State private var reps: Int = 10
    @State private var weightCrownPosition = 0
    @State private var repsCrownPosition = 0
    @State private var weightCrownAnchor = 0
    @State private var repsCrownAnchor = 0
    @State private var separateSides = false
    @State private var selectedSide: BodySide = .left
    @State private var sideError: String?
    @FocusState private var focusedField: Field?

    enum Field {
        case weight, reps
    }

    private let weightUnit: WeightUnit
    private let poundsPerStep = 2.5
    // Five half-detents per value change gives an average of 2.5 Crown ticks.
    private let crownHalfDetentsPerStep = 5
    private let maximumWeightSteps = 440
    private var weightKg: Double { Double(weightSteps) * poundsPerStep / WeightUnit.lbsPerKg }
    private var weightText: String {
        let pounds = Double(weightSteps) * poundsPerStep
        return weightUnit == .lbs ? String(format: "%g", pounds) : String(format: "%.1f", weightUnit.fromKg(weightKg))
    }
    private var weightLabel: String { separateSides ? viewModel.currentExercise?.exercise.strengthRecording?.sideWeightLabel(weightUnit) ?? weightUnit.symbol : viewModel.currentExercise?.exercise.weightEntryLabel(weightUnit) ?? weightUnit.symbol }

    init(viewModel: WatchWorkoutViewModel, targetWeight: Double? = nil, targetReps: Int? = nil) {
        let prefs = UserPreferencesService()
        self._viewModel = State(initialValue: viewModel)
        // Keep the input on a 2.5 lb grid, including weights restored from storage.
        let startingPounds = targetWeight.map { $0 * WeightUnit.lbsPerKg }
            ?? (prefs.weightUnit == .lbs ? 20.0 : 20.0 * WeightUnit.lbsPerKg)
        self._weightSteps = State(initialValue: min(440, max(0, Int((startingPounds / 2.5).rounded()))))
        self._reps = State(initialValue: targetReps ?? prefs.defaultReps)
        self.weightUnit = prefs.weightUnit
    }

    private let primaryYellow = Color(red: 0.949, green: 0.800, blue: 0.051)
    private let cardBackground = Color.white.opacity(0.1)
    private let labelColor = Color.white.opacity(0.75)
    private let secondaryText = Color.white.opacity(0.6)

    var body: some View {
        VStack(spacing: 7) {
            if viewModel.isReviewingSet {
                Text(viewModel.reviewDetectedReps.map { "Detected \($0) reps" }
                     ?? "Review set")
                    .font(.caption2)
                    .foregroundStyle(secondaryText)
            }
            if let recording = viewModel.currentExercise?.exercise.strengthRecording {
                if recording.supportsSeparateSides {
                    if separateSides {
                        Picker("Side", selection: $selectedSide) { ForEach(BodySide.allCases, id: \.self) { Text($0.title).tag($0) } }
                            .onChange(of: selectedSide) { _, _ in loadSide() }
                    } else {
                        Button("Log left / right separately") { separateSides = true; loadSide() }.font(.caption2)
                        Text(recording.summary).font(.caption2).foregroundStyle(secondaryText)
                    }
                } else { Text(recording.summary).font(.caption2).foregroundStyle(secondaryText) }
            }
            if let sideError { Text(sideError).font(.caption2).foregroundStyle(.red) }
            // One large value per row, with controls that are easy to hit on Watch.
            VStack(spacing: 8) {
                inputCard(
                    label: separateSides ? "Reps/side" : viewModel.currentExercise?.exercise.repetitionsLabel ?? "Reps",
                    value: "\(reps)",
                    isFocused: focusedField == .reps,
                    onTap: { focusedField = .reps },
                    onDecrement: { reps = max(1, reps - 1) },
                    onIncrement: { reps = min(100, reps + 1) }
                )
                .focusable()
                .focused($focusedField, equals: .reps)
                .digitalCrownRotation(detent: $repsCrownPosition, from: -4000, through: 4000,
                                      by: 1, sensitivity: .low)
                .onChange(of: repsCrownPosition) { _, position in
                    let steps = (position * 2 - repsCrownAnchor) / crownHalfDetentsPerStep
                    guard steps != 0 else { return }
                    reps = min(100, max(1, reps + steps))
                    repsCrownAnchor += steps * crownHalfDetentsPerStep
                }

                inputCard(
                    label: weightLabel,
                    value: weightText,
                    isFocused: focusedField == .weight,
                    onTap: { focusedField = .weight },
                    onDecrement: { weightSteps = max(0, weightSteps - 1) },
                    onIncrement: { weightSteps = min(maximumWeightSteps, weightSteps + 1) }
                )
                .focusable()
                .focused($focusedField, equals: .weight)
                .digitalCrownRotation(detent: $weightCrownPosition, from: -4000, through: 4000,
                                      by: 1, sensitivity: .low)
                .onChange(of: weightCrownPosition) { _, position in
                    let steps = (position * 2 - weightCrownAnchor) / crownHalfDetentsPerStep
                    guard steps != 0 else { return }
                    weightSteps = min(maximumWeightSteps, max(0, weightSteps + steps))
                    weightCrownAnchor += steps * crownHalfDetentsPerStep
                }
            }

            // Rest timer indicator (shows when resting)
            if viewModel.isResting {
                HStack(spacing: 4) {
                    Image(systemName: "timer")
                        .font(.system(size: 11))
                        .foregroundStyle(primaryYellow)
                    Text("REST: \(viewModel.restTimerText)")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.8))
                        .tracking(2)
                        .textCase(.uppercase)
                }
                .padding(.vertical, 2)
            }

            Button {
                    // Convert the displayed value back to kg for storage.
                    if separateSides {
                        Task {
                            do {
                                try await viewModel.logSide(selectedSide, weight: weightKg, reps: reps)
                                sideError = nil
                                if let next = viewModel.visibleSet?.sideSets?.first(where: { !$0.effort.isCompleted }) { selectedSide = next.side; loadSide() }
                            } catch { sideError = error.localizedDescription }
                        }
                    } else if viewModel.isEditingCompletedSet {
                        Task { try? await viewModel.updateSet(weight: weightKg, reps: reps) }
                    } else {
                        Task {
                            try? await viewModel.logSet(weight: weightKg, reps: reps,
                                                        detectedReps: viewModel.reviewDetectedReps)
                        }
                    }
            } label: {
                    HStack(spacing: 4) {
                        Text(separateSides ? "LOG \(selectedSide.rawValue.uppercased())" : viewModel.isEditingCompletedSet ? "UPDATE" : "FINISH SET")
                            .font(.system(size: 12, weight: .black))
                            .tracking(-0.5)
                        Image(systemName: viewModel.isEditingCompletedSet ? "pencil.circle.fill" : "checkmark.circle.fill")
                            .font(.system(size: 12, weight: .bold))
                    }
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 7)
                    .background(primaryYellow)
                    .clipShape(Capsule())
                }
            .buttonStyle(.plain)
        }
        .onAppear {
            // Keep Crown scrolling the page until the user taps a field.
            focusedField = nil
            if let sides = viewModel.visibleSet?.sideSets {
                separateSides = true
                selectedSide = sides.first(where: { !$0.effort.isCompleted })?.side ?? .left
                loadSide()
            }
        }
    }

    private func loadSide() {
        if let effort = viewModel.visibleSet?.sideSets?.first(where: { $0.side == selectedSide })?.effort {
            weightSteps = min(maximumWeightSteps, max(0, Int(((effort.weight ?? 0) * WeightUnit.lbsPerKg / poundsPerStep).rounded())))
            reps = effort.reps ?? 8
        } else {
            let scale = viewModel.currentExercise?.exercise.strengthRecording?.sideWeightScale ?? 1
            weightSteps = min(maximumWeightSteps, max(0, Int(((viewModel.currentTargetWeight ?? 0) * scale * WeightUnit.lbsPerKg / poundsPerStep).rounded())))
            reps = viewModel.currentExercise?.exercise.strengthReps(viewModel.currentTargetReps ?? 8) ?? 8
        }
    }
    @ViewBuilder
    private func inputCard(
        label: String,
        value: String,
        isFocused: Bool,
        onTap: @escaping () -> Void,
        onDecrement: @escaping () -> Void,
        onIncrement: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 7) {
                // Minus button
                Button(action: onDecrement) {
                    Image(systemName: "minus")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(.white)
                        .frame(width: 38, height: 46)
                        .background(cardBackground)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)

                // Value display
                VStack(spacing: 0) {
                    Text(value)
                        .font(.system(size: 32, weight: .bold))
                        .monospacedDigit()
                        .foregroundStyle(isFocused ? primaryYellow : .white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                    Text(label.uppercased())
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(labelColor)
                }
                .frame(maxWidth: .infinity, minHeight: 49)
                .background(cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: 15))

                // Plus button
                Button(action: onIncrement) {
                    Image(systemName: "plus")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(.white)
                        .frame(width: 38, height: 46)
                        .background(cardBackground)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
        }
        .onTapGesture(perform: onTap)
    }
}
