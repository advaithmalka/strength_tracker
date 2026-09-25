import SwiftUI
import UIKit
import StrengthTrackerShared

struct ActiveWorkoutView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var viewModel: WorkoutViewModel
    @State private var exerciseListViewModel: ExerciseListViewModel
    /// Owns the tap side effects (rest timer, Live Activity, widget) and the
    /// start/finish/cancel lifecycle, shared with the AI tools.
    let coordinator: WorkoutSessionCoordinator
    let restTimerService: RestTimerService
    let connectivityManager: ConnectivityManager?
    var analyticsViewModel: WorkoutAnalyticsViewModel?
    /// Assistant entry point; nil when the AI feature is not configured.
    var aiChat: AIChatEntry? = nil
    @State private var showAIChat = false
    @Environment(DataRevision.self) private var dataRevision: DataRevision?
    @State private var showingExercisePicker = false
    @State private var showingCancelConfirmation = false
    @State private var showingFinishError = false
    @State private var isFinishing = false
    @State private var finishErrorMessage = ""
    @State private var showingNotes = false
    @State private var showingRestTimer = false
    @State private var notesText = ""
    @State private var seededNotesText = ""
    @State private var watchReviewReps = 10
    @State private var watchReviewWeightLb = 20.0

    // Drag-to-reorder state, isolated so per-frame updates only invalidate the
    // ExerciseDragEffect modifiers — never this whole view's body.
    @State private var dragState = ExerciseDragState()

    init(
        viewModel: WorkoutViewModel,
        coordinator: WorkoutSessionCoordinator,
        exerciseListViewModel: ExerciseListViewModel,
        restTimerService: RestTimerService,
        analyticsViewModel: WorkoutAnalyticsViewModel? = nil,
        connectivityManager: ConnectivityManager? = nil,
        aiChat: AIChatEntry? = nil
    ) {
        self._viewModel = State(initialValue: viewModel)
        self._exerciseListViewModel = State(initialValue: exerciseListViewModel)
        self.coordinator = coordinator
        self.restTimerService = restTimerService
        self.connectivityManager = connectivityManager
        self.aiChat = aiChat
        self.analyticsViewModel = analyticsViewModel
    }

    var body: some View {
        NavigationStack {
            Group {
                if let workout = viewModel.currentWorkout, viewModel.isActive {
                    workoutContent(workout)
                } else if let state = viewModel.watchLiveState, let watchWorkout = state.workout {
                    watchWorkoutBanner(watchWorkout, state: state)
                } else if let watchWorkout = viewModel.watchActiveWorkout {
                    watchWorkoutBanner(watchWorkout, state: nil)
                } else {
                    startView
                }
            }
            .navigationTitle(viewModel.currentWorkout?.name ?? "Workout")
            .navigationBarTitleDisplayMode(.inline)
            .stNavigationBarStyle()
            .toolbar {
                if let aiChat, aiChat.isAvailable {
                    ToolbarItem(placement: .topBarTrailing) {
                        AIChatToolbarButton(isPresented: $showAIChat)
                    }
                }
            }
            .aiChatCover(aiChat, isPresented: $showAIChat)
            .onChange(of: viewModel.watchLiveState?.revision, initial: true) { _, _ in
                if let state = viewModel.watchLiveState { seedWatchReview(from: state) }
            }
            .sheet(isPresented: $showingExercisePicker) {
                ExercisePickerView(viewModel: exerciseListViewModel) { exercise in
                    viewModel.addExercise(exercise)
                }
            }
            .confirmationDialog(
                "Cancel Workout",
                isPresented: $showingCancelConfirmation,
                titleVisibility: .visible
            ) {
                Button("Cancel Workout", role: .destructive) {
                    Task { await coordinator.cancel() }
                }
                Button("Keep Going", role: .cancel) {}
            } message: {
                Text("Are you sure you want to cancel this workout? All progress will be lost.")
            }
            .alert("Error", isPresented: .init(
                get: { viewModel.errorMessage != nil },
                set: { if !$0 { viewModel.errorMessage = nil } }
            )) {
                if viewModel.lastSaveError != nil {
                    Button("Retry Save") { Task { await viewModel.retryPendingSave(); viewModel.errorMessage = viewModel.lastSaveError } }
                }
                Button("OK") { viewModel.errorMessage = nil }
            } message: {
                Text(viewModel.errorMessage ?? "")
            }
            .alert("Failed to Save Workout", isPresented: $showingFinishError) {
                if viewModel.lastSaveError != nil {
                    Button("Retry Save") { Task { await viewModel.retryPendingSave(); viewModel.errorMessage = viewModel.lastSaveError } }
                }
                Button("OK") {}
            } message: {
                Text(finishErrorMessage)
            }
        }
    }

    // MARK: - Watch Workout Banner

    private func seedWatchReview(from state: WorkoutLiveState) {
        guard state.phase == .review,
              let workout = state.workout,
              workout.exercises.indices.contains(state.currentExerciseIndex) else { return }
        let nextSet = workout.exercises[state.currentExerciseIndex].sets.first { !$0.isFullyCompleted }
        if let detected = state.detectedReps, detected > 0 {
            watchReviewReps = detected
        } else {
            watchReviewReps = nextSet?.reps ?? 10
        }
        watchReviewWeightLb = WeightUnit.lbs.fromKg(nextSet?.weight ?? WeightUnit.lbs.toKg(20))
    }

    private func watchWorkoutBanner(_ workout: Workout, state: WorkoutLiveState?) -> some View {
        ScrollView {
        VStack(spacing: 16) {
            Image(systemName: "applewatch")
                .font(.system(size: 48))
                .foregroundStyle(STColors.primary)

            Text("Workout In Progress on Watch")
                .font(.headline)
                .foregroundStyle(STColors.textPrimary)

            VStack(spacing: 8) {
                Text(workout.name)
                    .font(.title3.bold())
                    .foregroundStyle(STColors.textPrimary)

                if let currentExercise = state.flatMap({ workout.exercises.indices.contains($0.currentExerciseIndex)
                    ? workout.exercises[$0.currentExerciseIndex] : nil }) ?? workout.activeExercise(preferredId: nil) {
                    Text(currentExercise.exercise.name)
                        .font(.subheadline)
                        .foregroundStyle(STColors.textSecondary)

                    ForEach(currentExercise.sets.filter(\.isFullyCompleted)) { set in
                        Text("Set \(set.order): \(set.reps ?? 0) reps · \((viewModel.userPreferencesService?.weightUnit ?? .lbs).format(set.weight ?? 0, decimals: 1))")
                            .font(.caption)
                            .foregroundStyle(STColors.textSecondary)
                    }
                }

                if let state {
                    Text(state.phase == .review ? "Review this set"
                         : state.phase == .lifting ? "Set in progress"
                         : state.phase == .resting ? "Resting" : "Ready for next set")
                        .font(.subheadline.bold())
                        .foregroundStyle(STColors.primary)
                    if let end = state.restEndsAt, end > Date() {
                        Text(timerInterval: Date()...end, countsDown: true)
                            .font(.title3.monospacedDigit())
                    }
                }

                let totalSets = workout.exercises.reduce(0) { $0 + $1.sets.filter(\.isFullyCompleted).count }
                Text("\(totalSets) sets completed")
                    .font(.subheadline)
                    .foregroundStyle(STColors.textSecondary)

                let elapsed = Date().timeIntervalSince(workout.startedAt)
                let minutes = Int(elapsed) / 60
                Text("\(minutes) min elapsed")
                    .font(.caption)
                    .foregroundStyle(STColors.textTertiary)
            }
            .padding()
            .frame(maxWidth: .infinity)
            .background(STColors.surface)
            .clipShape(RoundedRectangle(cornerRadius: STRadius.card))
            .overlay(
                RoundedRectangle(cornerRadius: STRadius.card)
                    .stroke(STColors.border, lineWidth: 1)
            )

            if let state, let connectivityManager {
                Text(connectivityManager.isReachable ? "Watch connected" : "Watch offline · updates will sync later")
                    .font(.caption)
                    .foregroundStyle(STColors.textSecondary)
                if let error = connectivityManager.lastControlError {
                    Text(error).font(.caption).foregroundStyle(.red)
                }
                if connectivityManager.isReachable {
                    HStack {
                        Button("Previous") { connectivityManager.sendWorkoutControl(state: state, action: .previousExercise) }
                        Button("Next") { connectivityManager.sendWorkoutControl(state: state, action: .nextExercise) }
                    }
                    .disabled(state.phase == .lifting || state.phase == .review)
                    if state.phase == .ready {
                        Button("Start Set") { connectivityManager.sendWorkoutControl(state: state, action: .startSet) }
                    } else if state.phase == .lifting {
                        Button("End Set") { connectivityManager.sendWorkoutControl(state: state, action: .endSet) }
                    } else if state.phase == .review {
                        VStack(spacing: 10) {
                            Stepper("Reps: \(watchReviewReps)", value: $watchReviewReps, in: 0...100, step: 1)
                            Stepper("Weight: \(String(format: "%.1f", watchReviewWeightLb)) lb",
                                    value: $watchReviewWeightLb, in: 0...1000, step: 2.5)
                            Button("Save Set") {
                                connectivityManager.sendWorkoutControl(
                                    state: state, action: .saveReviewedSet,
                                    reviewedReps: watchReviewReps,
                                    reviewedWeightKg: WeightUnit.lbs.toKg(watchReviewWeightLb)
                                )
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    } else if state.phase == .resting {
                        Button("End Rest Early") { connectivityManager.sendWorkoutControl(state: state, action: .skipRest) }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
        .background(STColors.background)
        }
    }

    // MARK: - Start View

    private var startView: some View {
        ScrollView {
            VStack(spacing: 20) {
                Spacer()
                    .frame(height: 20)

                // Pre-workout context card (M4) when analytics loaded
                if let analytics = analyticsViewModel,
                   !analytics.insights.recoveryPatterns.isEmpty {
                    PreWorkoutContextCard(
                        recoveryPatterns: analytics.insights.recoveryPatterns,
                        trainingLoad: analytics.insights.trainingLoad,
                        adherence: analytics.adherenceAnalysis,
                        verdict: analytics.insights.verdict,
                        onStartWorkout: {
                            Task { await startQuickWorkout() }
                        },
                        onStartFromPlan: nil
                    )
                } else {
                    // Minimal start view for new users
                    Image(systemName: "figure.strengthtraining.traditional")
                        .font(.system(size: 60))
                        .foregroundStyle(STColors.textSecondary)
                    Text("No Active Workout")
                        .font(.title2)
                        .foregroundStyle(STColors.textPrimary)
                    Button {
                        Task { await startQuickWorkout() }
                    } label: {
                        Text("Start Workout")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(STColors.background)
                            .padding(.horizontal, 24)
                            .padding(.vertical, 12)
                            .background(STColors.primary)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)
                }

                Spacer()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(STColors.background)
        .task(id: dataRevision?.value ?? 0) {
            // Load analytics for pre-workout context
            await analyticsViewModel?.loadDashboardInsights()
        }
    }

    // MARK: - Workout Content

    private func workoutContent(_ workout: Workout) -> some View {
        ScrollViewReader { proxy in
            workoutScrollView(workout: workout, proxy: proxy).allowsHitTesting(!isFinishing)
        }
        .task {
            await viewModel.loadPreviousData()
            await viewModel.loadCoachingData()
        }
        .onAppear {
            if let notes = workout.notes, !notes.isEmpty {
                notesText = notes
                seededNotesText = notes
                showingNotes = true
            }
        }
        .safeAreaInset(edge: .bottom) {
            if restTimerService.isRunning || (restTimerService.remainingSeconds > 0 && !restTimerService.isCompleted) {
                stickyRestTimer
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                finishButton
            }
        }
        .sheet(isPresented: $showingRestTimer) {
            RestTimerView(service: restTimerService)
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                restTimerService.handleForegroundReturn()
            } else {
                STNumericTextField.commitActiveInput()
            }
        }
    }

    private func workoutScrollView(workout: Workout, proxy: ScrollViewProxy) -> some View {
        let canReorder = workout.exercises.count > 1
        return ScrollView {
            VStack(spacing: STSpacing.cardGap) {
                ForEach(Array(workout.exercises.enumerated()), id: \.element.id) { index, workoutExercise in
                    exerciseCard(for: workoutExercise, reorderable: canReorder)
                    .id(workoutExercise.id)
                    .onGeometryChange(for: CGFloat.self) { geometry in
                        geometry.size.height
                    } action: { height in
                        dragState.heights[workoutExercise.id] = height
                    }
                    .modifier(ActiveExerciseHighlight(
                        exerciseId: workoutExercise.id,
                        viewModel: viewModel
                    ))
                    .modifier(ExerciseDragEffect(
                        id: workoutExercise.id,
                        index: index,
                        dragState: dragState
                    ))
                    .simultaneousGesture(TapGesture().onEnded {
                        // Tapping anywhere on a card makes it the active exercise
                        guard viewModel.activeExerciseId != workoutExercise.id else { return }
                        coordinator.setActiveExercise(workoutExercise.id)
                    })
                }
                notesCard
                deloadToggle
                addExerciseButton
                cancelWorkoutButton
                Color.clear.frame(height: 20)
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
        }
        .scrollDisabled(dragState.isDragging)
        .onChange(of: workout.exercises.count) { oldCount, newCount in
            // Add/remove/watch-sync mid-drag would leave stale offsets — reset first
            dragState.reset()
            guard newCount > oldCount else { return }  // Only scroll on addition
            if let lastExercise = workout.exercises.last {
                withAnimation(.easeInOut(duration: 0.3)) {
                    proxy.scrollTo(lastExercise.id, anchor: .top)
                }
            }
        }
        .background(STColors.background)
        .scrollDismissesKeyboard(.interactively)
        .preferredColorScheme(.dark)
        .onDisappear { STNumericTextField.commitActiveInput() }
    }

    private func exerciseCard(for workoutExercise: WorkoutExercise, reorderable: Bool) -> some View {
        ExerciseCardView(
            workoutExercise: workoutExercise,
            previousSetData: previousDataForExercise(workoutExercise.id),
            onWeightChange: { setId, weight in
                enqueueEdit {
                    await viewModel.updateSetWeight(
                        exerciseId: workoutExercise.id,
                        setId: setId,
                        weight: weight
                    )
                }
            },
            onRepsChange: { setId, reps in
                enqueueEdit {
                    await viewModel.updateSetReps(
                        exerciseId: workoutExercise.id,
                        setId: setId,
                        reps: reps
                    )
                }
            },
            onIntensityChange: { setId, value in
                enqueueEdit {
                    await viewModel.updateSetIntensity(
                        exerciseId: workoutExercise.id,
                        setId: setId,
                        value: value,
                        metric: intensityMetric
                    )
                }
            },
            onToggleComplete: { setId in
                handleSetToggle(workoutExercise: workoutExercise, setId: setId)
            },
            onAddSet: {
                guard STNumericTextField.commitActiveInput() else { return }
                enqueueEdit {
                    await viewModel.addEmptySet(exerciseId: workoutExercise.id)
                }
            },
            onRemoveSet: { setId in
                guard STNumericTextField.commitActiveInput() else { return }
                enqueueEdit {
                    await viewModel.removeSet(
                        exerciseId: workoutExercise.id,
                        setId: setId
                    )
                }
            },
            onRemoveExercise: {
                guard STNumericTextField.commitActiveInput() else { return }
                enqueueEdit {
                    await viewModel.removeExercise(exerciseId: workoutExercise.id)
                }
            },
            onSetTypeChange: { setId, setType in
                guard STNumericTextField.commitActiveInput() else { return }
                enqueueEdit {
                    await viewModel.updateSetType(
                        exerciseId: workoutExercise.id,
                        setId: setId,
                        setType: setType
                    )
                }
            },
            onAddDropEntry: { setId in
                guard STNumericTextField.commitActiveInput() else { return }
                enqueueEdit {
                    await viewModel.addDropEntry(exerciseId: workoutExercise.id, setId: setId)
                }
            },
            onToggleFailure: { setId in
                guard STNumericTextField.commitActiveInput() else { return }
                enqueueEdit {
                    await viewModel.toggleSetFailure(exerciseId: workoutExercise.id, setId: setId)
                }
            },
            onDropEntryWeightChange: { setId, entryId, weight in
                enqueueEdit {
                    await viewModel.updateDropEntryWeight(
                        exerciseId: workoutExercise.id, setId: setId, entryId: entryId, weight: weight
                    )
                }
            },
            onDropEntryRepsChange: { setId, entryId, reps in
                enqueueEdit {
                    await viewModel.updateDropEntryReps(
                        exerciseId: workoutExercise.id, setId: setId, entryId: entryId, reps: reps
                    )
                }
            },
            onDropEntryIntensityChange: { setId, entryId, value in
                enqueueEdit {
                    await viewModel.updateDropEntryIntensity(
                        exerciseId: workoutExercise.id, setId: setId, entryId: entryId, value: value, metric: intensityMetric
                    )
                }
            },
            onDropEntryToggleFailure: { setId, entryId in
                enqueueEdit {
                    await viewModel.toggleDropEntryFailure(
                        exerciseId: workoutExercise.id, setId: setId, entryId: entryId
                    )
                }
            },
            onRemoveDropEntry: { setId, entryId in
                guard STNumericTextField.commitActiveInput() else { return }
                enqueueEdit {
                    await viewModel.removeDropEntry(
                        exerciseId: workoutExercise.id, setId: setId, entryId: entryId
                    )
                }
            },
            onNoteChange: { notes in
                enqueueEdit {
                    await viewModel.updateExerciseNotes(
                        exerciseId: workoutExercise.id,
                        notes: notes
                    )
                }
            },
            onMoveSet: { fromIndex, toIndex in
                guard STNumericTextField.commitActiveInput() else { return }
                enqueueEdit {
                    await viewModel.moveSets(
                        exerciseId: workoutExercise.id,
                        from: fromIndex,
                        to: toIndex
                    )
                }
            },
            onDragChanged: reorderable ? { translation in
                guard STNumericTextField.commitActiveInput(), let workout = viewModel.currentWorkout else { return }
                dragState.dragChanged(
                    id: workoutExercise.id,
                    translation: translation,
                    orderedIds: workout.exercises.map(\.id)
                )
            } : nil,
            onDragEnded: reorderable ? {
                if let (from, to) = dragState.dragEnded() {
                    enqueueEdit { await viewModel.moveExercise(from: from, to: to) }
                }
            } : nil,
            coachingData: viewModel.exerciseCoachingCache[workoutExercise.id],
            alwaysShowRPE: viewModel.userPreferencesService?.alwaysShowRPE ?? false,
            intensityMetric: intensityMetric,
            weightUnit: viewModel.userPreferencesService?.weightUnit ?? .kg,
            onWeightRecordingChange: { recording in enqueueEdit { await viewModel.updateWeightRecording(exerciseId: workoutExercise.id, recording: recording) } },
            onSideSetsChange: { setId, sides in enqueueEdit { await coordinator.updateSideSets(exerciseId: workoutExercise.id, setId: setId, entries: sides) } },
            onSideRest: { setId in coordinator.restBetweenSides(exerciseId: workoutExercise.id, setId: setId) },
            onSaveRecordingDefault: { recording in enqueueEdit { await viewModel.saveWeightRecordingDefault(exerciseId: workoutExercise.exercise.id, recording: recording) } }
        )
    }

    private var intensityMetric: IntensityMetric {
        viewModel.userPreferencesService?.intensityMetric ?? .rpe
    }

    private func enqueueEdit(_ operation: @escaping @MainActor () async -> Void) {
        viewModel.inputEdits.enqueue {
            await operation()
            if let error = viewModel.lastSaveError { viewModel.errorMessage = error }
        }
    }

    private func handleSetToggle(workoutExercise: WorkoutExercise, setId: UUID) {
        guard STNumericTextField.commitActiveInput() else { return }
        enqueueEdit {
            guard viewModel.lastSaveError == nil else { return }
            await coordinator.toggleSet(exerciseId: workoutExercise.id, setId: setId)
        }
    }

    private func startQuickWorkout() async {
        do {
            try await coordinator.start(.init(name: "Quick Workout"))
        } catch {
            viewModel.errorMessage = error.localizedDescription
        }
    }

    private var isDeload: Bool {
        viewModel.currentWorkout?.isDeload ?? false
    }

    private var deloadToggle: some View {
        Button {
            Task { await viewModel.toggleDeload() }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: isDeload ? "checkmark.circle.fill" : "arrow.down.circle")
                    .font(.system(size: 18))
                    .foregroundStyle(isDeload ? STColors.primary : STColors.textTertiary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(isDeload ? "Deload Workout" : "Mark as Deload")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(isDeload ? STColors.primary : STColors.textSecondary)
                    Text("Excludes from progression & PR tracking")
                        .font(.system(size: 11))
                        .foregroundStyle(STColors.textTertiary)
                }
                Spacer()
                if isDeload {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(STColors.textTertiary)
                }
            }
            .padding(STSpacing.cardPadding)
            .background(isDeload ? STColors.primary.opacity(0.1) : STColors.surface)
            .clipShape(RoundedRectangle(cornerRadius: STRadius.card))
            .overlay(
                RoundedRectangle(cornerRadius: STRadius.card)
                    .stroke(isDeload ? STColors.primary.opacity(0.3) : STColors.border, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private var finishButton: some View {
        Button {
            guard !isFinishing, STNumericTextField.commitActiveInput() else { return }
            isFinishing = true
            Task {
                defer { isFinishing = false }
                do {
                    try await coordinator.finish()
                } catch {
                    finishErrorMessage = error.localizedDescription
                    showingFinishError = true
                }
            }
        } label: {
            Text("Finish")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(STColors.background)
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
                .background(STColors.primary)
                .clipShape(Capsule())
        }
        .disabled(isFinishing)
    }

    // MARK: - Add Exercise Button

    private var addExerciseButton: some View {
        Button {
            guard STNumericTextField.commitActiveInput() else { return }
            showingExercisePicker = true
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 18))
                Text("Add Exercise")
                    .font(.system(size: 16, weight: .bold))
            }
            .foregroundStyle(STColors.textPrimary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(STColors.surface)
            .clipShape(RoundedRectangle(cornerRadius: STRadius.card))
            .overlay(
                RoundedRectangle(cornerRadius: STRadius.card)
                    .stroke(STColors.border, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Cancel Workout Button

    private var cancelWorkoutButton: some View {
        Button {
            showingCancelConfirmation = true
        } label: {
            Text("Cancel Workout")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(STColors.danger)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Notes Card

    private var notesCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            if showingNotes {
                HStack {
                    Text("NOTES")
                        .font(.system(size: 10, weight: .bold))
                        .tracking(1.5)
                        .foregroundStyle(STColors.textSecondary)
                    Spacer()
                    Button("Done") { STNumericTextField.commitActiveInput() }
                        .font(.subheadline.weight(.semibold)).frame(minHeight: 44).foregroundStyle(STColors.primary)
                    Button {
                        STNumericTextField.commitActiveInput()
                        showingNotes = false
                    } label: {
                        Image(systemName: "xmark")
                            .font(.caption)
                            .foregroundStyle(STColors.textTertiary)
                    }
                }
                TextField("Add workout notes...", text: $notesText, axis: .vertical)
                    .lineLimit(2...5)
                    .font(.system(size: 14))
                    .foregroundStyle(STColors.textPrimary)
                    .onChange(of: notesText) { _, newValue in
                        guard newValue != seededNotesText else { return }
                        enqueueEdit { await viewModel.updateNotes(newValue) }
                        seededNotesText = newValue
                    }
            } else {
                Button {
                    showingNotes = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "note.text")
                            .font(.system(size: 14))
                        Text(notesText.isEmpty ? "Add Notes" : "Edit Notes")
                            .font(.system(size: 14, weight: .medium))
                    }
                    .foregroundStyle(STColors.textSecondary)
                }
            }
        }
        .padding(STSpacing.cardPadding)
        .background(STColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: STRadius.card))
        .overlay(
            RoundedRectangle(cornerRadius: STRadius.card)
                .stroke(STColors.border, lineWidth: 1)
        )
        .onReceive(NotificationCenter.default.publisher(for: .commitWorkoutNotes)) { _ in
            guard notesText != seededNotesText else { return }
            let committedNotes = notesText
            enqueueEdit { await viewModel.updateNotes(committedNotes) }
            seededNotesText = notesText
        }
    }

    // MARK: - Sticky Rest Timer

    private var stickyRestTimer: some View {
        HStack {
            HStack(spacing: 12) {
                // Circular progress indicator
                ZStack {
                    Circle()
                        .stroke(Color.black.opacity(0.1), lineWidth: 3)
                        .frame(width: 40, height: 40)

                    Circle()
                        .trim(from: 0, to: restTimerService.progress)
                        .stroke(
                            Color.black,
                            style: StrokeStyle(lineWidth: 3, lineCap: .round)
                        )
                        .frame(width: 40, height: 40)
                        .rotationEffect(.degrees(-90))

                    Image(systemName: "timer")
                        .font(.system(size: 16))
                        .foregroundStyle(Color.black)
                }

                VStack(alignment: .leading, spacing: 1) {
                    Text("RESTING")
                        .font(.system(size: 10, weight: .bold))
                        .tracking(1.5)
                        .foregroundStyle(Color.black.opacity(0.7))

                    Text(restTimerService.formattedTime)
                        .font(.system(size: 20, weight: .bold, design: .default))
                        .monospacedDigit()
                        .foregroundStyle(Color.black)
                }
            }
            .onTapGesture {
                showingRestTimer = true
            }

            Spacer()

            HStack(spacing: 8) {
                Button {
                    restTimerService.addTime(seconds: 15)
                } label: {
                    Text("+15s")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Color.black)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color.black.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.black.opacity(0.1), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)

                Button {
                    coordinator.skipRest()
                } label: {
                    Text("Skip")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(STColors.primary)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Color.black)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
        .background(STColors.primary.opacity(0.95))
        .clipShape(RoundedRectangle(cornerRadius: STRadius.timer))
        .padding(.horizontal, 16)
        .padding(.bottom, 4)
    }

    // MARK: - Helpers

    private func previousDataForExercise(_ exerciseId: UUID) -> [Int: String] {
        var result: [Int: String] = [:]
        if let exercise = viewModel.currentWorkout?.exercises.first(where: { $0.id == exerciseId }) {
            for (index, set) in exercise.sets.enumerated() {
                let key = "\(exerciseId)-\(set.id)"
                if let data = viewModel.previousSetDataCache[key] {
                    result[index] = data
                }
            }
        }
        return result
    }
}
