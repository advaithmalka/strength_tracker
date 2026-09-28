import SwiftUI
import StrengthTrackerShared
#if os(watchOS)
import WatchKit
#endif

struct WatchActiveWorkoutView: View {
    @State private var viewModel: WatchWorkoutViewModel
    @State private var exerciseListViewModel: ExerciseListViewModel
    @State private var selectedPage = 1
    @State private var showSetEditor = false
    @State private var showRestTimer = false
    @State private var showSummary = false
    @State private var showExercisePicker = false
    @State private var isAddingExtraSet = false
    @State private var actionError: String?

    init(viewModel: WatchWorkoutViewModel, exerciseListViewModel: ExerciseListViewModel) {
        self._viewModel = State(initialValue: viewModel)
        self._exerciseListViewModel = State(initialValue: exerciseListViewModel)
    }

    private let primaryBlue = Color(red: 0.149, green: 0.475, blue: 1.000)
    private let restTimerYellow = Color(red: 0.949, green: 0.800, blue: 0.051)
    private let secondaryText = Color.white.opacity(0.6)
    private let weightUnit = UserPreferencesService().weightUnit

    var body: some View {
        if let workout = viewModel.activeWorkout {
            VStack(spacing: 0) {
                if viewModel.isResting { restBanner }
                TabView(selection: $selectedPage) {
                    actionsPage.tag(0)
                    activePage(workout).tag(1)
                    exerciseListPage(workout).tag(2)
                }
                .tabViewStyle(.page(indexDisplayMode: .automatic))
            }
            .navigationBarBackButtonHidden()
            .toolbar(.hidden, for: .navigationBar)
            .onAppear {
                if viewModel.isReviewingSet { showSetEditor = true }
            }
            .onChange(of: viewModel.isReviewingSet) { _, reviewing in
                if reviewing { selectedPage = 1; showSetEditor = true }
                else if !viewModel.isEditingCompletedSet { showSetEditor = false }
            }
            .onChange(of: viewModel.isEditingCompletedSet) { _, editing in
                if !editing && !viewModel.isReviewingSet { showSetEditor = false }
            }
            .onChange(of: showSetEditor) { _, editing in
                if !editing {
                    if !viewModel.isReviewingSet { viewModel.viewingSetIndex = nil }
                }
            }
            .onChange(of: viewModel.currentExerciseIndex) { _, _ in
                isAddingExtraSet = false
            }
            .onChange(of: viewModel.isResting) { _, resting in
                if !resting { showRestTimer = false }
            }
            .sheet(isPresented: $showSetEditor) {
                setEditor
            }
            .sheet(isPresented: $showRestTimer) {
                WatchRestTimerView(viewModel: viewModel)
            }
            .sheet(isPresented: $showSummary) {
                WorkoutSummaryView(workout: workout, viewModel: viewModel)
            }
            .sheet(isPresented: $showExercisePicker) {
                WatchExercisePickerView(exerciseListViewModel: exerciseListViewModel, actionTitle: "ADD") { exercises in
                    Task {
                        do {
                            try await viewModel.addExercises(exercises)
                            actionError = nil
                            showExercisePicker = false
                            selectedPage = 2
                        } catch {
                            actionError = error.localizedDescription
                        }
                    }
                }
            }
            .alert("Could not add exercises", isPresented: Binding(
                get: { actionError != nil },
                set: { if !$0 { actionError = nil } }
            )) {
                Button("OK") { actionError = nil }
            } message: {
                Text(actionError ?? "Please try again.")
            }
        }
    }

    private var actionsPage: some View {
        VStack(spacing: 8) {
            Text(viewModel.isPaused ? "Workout paused" : "Workout actions")
                .font(.system(size: 15, weight: .bold))
                .frame(maxWidth: .infinity, alignment: .leading)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                actionButton("Add", icon: "plus", color: primaryBlue, darkText: true) {
                    showExercisePicker = true
                }
                actionButton("Timer", icon: "timer", color: .white.opacity(0.17)) {
                    if !viewModel.isResting && !viewModel.isPaused {
                        viewModel.startRestTimer(force: true)
                    }
                    if viewModel.isResting { showRestTimer = true }
                }
                .disabled(viewModel.isPaused && !viewModel.isResting)
                actionButton("End", icon: "stop.fill", color: .red.opacity(0.32)) {
                    showSummary = true
                }
                actionButton(viewModel.isPaused ? "Resume" : "Pause",
                             icon: viewModel.isPaused ? "play.fill" : "pause.fill",
                             color: primaryBlue.opacity(0.28)) {
                    if viewModel.isPaused { viewModel.resumeWorkout() }
                    else { viewModel.pauseWorkout() }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .padding(.top, 4)
    }

    private func actionButton(_ title: String, icon: String, color: Color,
                              darkText: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 25, weight: .semibold))
                    .frame(maxWidth: .infinity, minHeight: 54)
                    .background(color)
                    .clipShape(RoundedRectangle(cornerRadius: 25))
                    .foregroundStyle(darkText ? .black : .white)
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
        .buttonStyle(.plain)
    }

    private var restBanner: some View {
        HStack(spacing: 8) {
            Button { showRestTimer = true } label: {
                HStack(spacing: 8) {
                    Image(systemName: "timer")
                        .font(.system(size: 13, weight: .semibold))
                    Spacer(minLength: 0)
                    Text(viewModel.restTimerText)
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .monospacedDigit()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Timer, \(viewModel.restTimerText). Double tap to adjust")
            Button {
                viewModel.skipRestTimer()
            } label: {
                Image(systemName: "forward.end.fill")
                    .font(.system(size: 12, weight: .bold))
                    .frame(width: 28, height: 28)
                    .background(Color.white.opacity(0.12))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .disabled(viewModel.isPaused)
            .accessibilityLabel("Skip rest")
        }
        .foregroundStyle(restTimerYellow)
        .padding(.leading, 10)
        .padding(.trailing, 5)
        .padding(.vertical, 4)
        .background(restTimerYellow.opacity(0.12))
        .clipShape(Capsule())
        .padding(.horizontal, 8)
    }

    private func activePage(_ workout: Workout) -> some View {
        ScrollView {
            VStack(spacing: 7) {
                #if canImport(HealthKit) && os(watchOS)
                TimelineView(.periodic(from: .now, by: 1)) { _ in
                    WatchMetricsView(heartRate: viewModel.heartRate,
                                     activeCalories: viewModel.activeCalories,
                                     elapsedTime: max(0, viewModel.elapsedTime))
                }
                #endif

                if let current = viewModel.currentExercise {
                    VStack(alignment: .leading, spacing: 4) {
                        Button { selectedPage = 2 } label: {
                            HStack(spacing: 4) {
                                Text(current.exercise.name)
                                    .fixedSize(horizontal: false, vertical: true)
                                Image(systemName: "chevron.down")
                                    .font(.system(size: 10, weight: .bold))
                            }
                            .font(.system(size: 17, weight: .bold))
                            .foregroundStyle(primaryBlue)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Choose exercise")
                        Text("EXERCISE \(viewModel.currentExerciseIndex + 1) OF \(workout.exercises.count)")
                            .font(.system(size: 10, weight: .bold))
                            .tracking(1)
                            .foregroundStyle(secondaryText)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    if viewModel.canRecordDeveloperMotion {
                        Button {
                            if viewModel.isDeveloperRecording { viewModel.stopDeveloperRecording() }
                            else { viewModel.startDeveloperRecording() }
                        } label: {
                            Label(viewModel.isDeveloperRecording ? "STOP RECORDING" : "RECORD EXERCISE",
                                  systemImage: viewModel.isDeveloperRecording ? "stop.circle.fill" : "record.circle")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(viewModel.isDeveloperRecording ? .red : primaryBlue)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 6)
                        }
                        .buttonStyle(.plain)
                        .disabled((viewModel.isPaused || viewModel.isResting) &&
                                  !viewModel.isDeveloperRecording)
                    }

                    setCard

                    if !current.sets.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 7) {
                                ForEach(Array(current.sets.enumerated()), id: \.element.id) { index, set in
                                    Button {
                                        if set.isCompleted {
                                            viewModel.viewingSetIndex = index
                                            showSetEditor = true
                                        }
                                    } label: {
                                        VStack(spacing: 2) {
                                            Text(set.setType == .normal ? "S\(set.order)" : String(set.setType.rawValue.prefix(1)).uppercased())
                                                .font(.system(size: 10, weight: .bold))
                                                .foregroundStyle(secondaryText)
                                            Text("\(weightUnit.formatValue(set.weight ?? 0)) × \(set.reps ?? 0)")
                                                .font(.system(size: 11, weight: .semibold))
                                                .foregroundStyle(.white)
                                        }
                                        .padding(7)
                                        .background(Color.white.opacity(0.1))
                                        .clipShape(RoundedRectangle(cornerRadius: 12))
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                    exerciseNavigation(workout)
                }
            }
            .padding(.horizontal, 8)
            .padding(.top, 4)
            // Page dots and the rounded watch edge cover the bottom of TabView.
            .padding(.bottom, 64)
        }
    }

    private var setCard: some View {
        VStack(spacing: 5) {
            HStack {
                Text(viewModel.isEditingCompletedSet ? "EDIT SET" : "SET \(viewModel.currentSetNumber)\(viewModel.hasPlannedSets ? "/\(viewModel.plannedSets)" : "")")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(secondaryText)
                Spacer()
                Button {
                    viewModel.updateSetType(setType: viewModel.currentSetType.nextType)
                } label: {
                    Text(viewModel.currentSetType == .normal ? "NORMAL" : viewModel.currentSetType.rawValue.uppercased())
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(primaryBlue)
                }
                .buttonStyle(.plain)
            }
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(viewModel.viewingSetReps.map { String($0) } ?? "—")
                    .font(.system(size: 28, weight: .bold))
                Text("REPS")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(secondaryText)
                Spacer()
                Text(viewModel.viewingSetWeight.map { weightUnit.format($0, decimals: 0) } ?? "—")
                    .font(.system(size: 22, weight: .semibold))
                    .minimumScaleFactor(0.65)
            }
            .monospacedDigit()

            if viewModel.isPaused {
                Text("Resume to continue this set")
                    .font(.system(size: 12))
                    .foregroundStyle(secondaryText)
            } else if viewModel.isReviewingSet || viewModel.isEditingCompletedSet {
                mainButton("REVIEW SET", icon: "pencil") { showSetEditor = true }
            } else if viewModel.isCollectingSet {
                Text(viewModel.canDetectCurrentExercise
                     ? "Lifting · \(viewModel.detectedRepCount) detected"
                     : "Lifting · enter reps after set")
                    .font(.system(size: 12))
                    .foregroundStyle(secondaryText)
                mainButton("END SET", icon: "checkmark") { viewModel.endSetAttempt() }
            } else if viewModel.currentExercisePlannedSetsComplete && !isAddingExtraSet {
                mainButton("ADD SET", icon: "plus") { isAddingExtraSet = true }
            } else {
                mainButton("START SET", icon: "chevron.right") { viewModel.beginSetAttempt() }
            }
        }
        .padding(8)
        .background(Color.white.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 22))
    }

    private func mainButton(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(.black)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 7)
                .background(primaryBlue)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private func exerciseNavigation(_ workout: Workout) -> some View {
        HStack {
            Button { viewModel.previousExercise() } label: {
                Image(systemName: "chevron.left.circle.fill")
            }
            .disabled(viewModel.currentExerciseIndex == 0)
            Spacer()
            Button { selectedPage = 2 } label: {
                Image(systemName: "list.bullet")
                Text("Exercises")
            }
            Spacer()
            Button { viewModel.nextExercise() } label: {
                Image(systemName: "chevron.right.circle.fill")
            }
            .disabled(viewModel.currentExerciseIndex >= workout.exercises.count - 1)
        }
        .font(.system(size: 14, weight: .semibold))
        .foregroundStyle(.white)
        .buttonStyle(.plain)
    }

    private func exerciseListPage(_ workout: Workout) -> some View {
        ScrollView {
            VStack(spacing: 9) {
                Text("Exercises")
                    .font(.system(size: 19, weight: .bold))
                    .frame(maxWidth: .infinity, alignment: .leading)
                ForEach(Array(workout.exercises.enumerated()), id: \.element.id) { index, item in
                    Button {
                        viewModel.selectExercise(at: index)
                        selectedPage = 1
                    } label: {
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(item.exercise.name)
                                    .font(.system(size: 17, weight: .semibold))
                                    .fixedSize(horizontal: false, vertical: true)
                                Text("\(item.sets.filter(\.isFullyCompleted).count) sets logged")
                                    .font(.system(size: 11))
                                    .foregroundStyle(secondaryText)
                            }
                            Spacer(minLength: 2)
                            if index == viewModel.currentExerciseIndex {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(primaryBlue)
                            }
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(13)
                        .background(Color.white.opacity(index == viewModel.currentExerciseIndex ? 0.17 : 0.09))
                        .clipShape(RoundedRectangle(cornerRadius: 20))
                    }
                    .buttonStyle(.plain)
                }
                Button { showExercisePicker = true } label: {
                    Label("Add Exercise", systemImage: "plus")
                        .font(.system(size: 16, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 15)
                        .background(Color.white.opacity(0.14))
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 8)
            .padding(.top, 5)
            .padding(.bottom, 64)
        }
    }

    private var setEditor: some View {
        ScrollView {
            VStack(spacing: 7) {
                if viewModel.isResting { restBanner }
                WatchSetInputView(
                    viewModel: viewModel,
                    targetWeight: viewModel.viewingSetWeight,
                    targetReps: viewModel.isReviewingSet && (viewModel.reviewDetectedReps ?? 0) > 0
                        ? viewModel.reviewDetectedReps : viewModel.viewingSetReps
                )
                .id(viewModel.isEditingCompletedSet ? "edit-\(viewModel.viewingSetIndex ?? 0)" : "review-\(viewModel.currentSetNumber)")
            }
            .padding(.horizontal, 8)
        }
    }
}
