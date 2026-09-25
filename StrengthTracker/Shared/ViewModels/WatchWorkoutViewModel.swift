import Foundation
import Observation
import UserNotifications
#if os(watchOS)
import WatchKit
#endif

@MainActor
@Observable
public final class WatchWorkoutViewModel {
    public var activeWorkout: Workout? = nil
    public var currentExerciseIndex: Int = 0
    public var isActive = false
    public var isQuickStart: Bool = false
    public var plannedSessionId: UUID? = nil
    public var plannedPlanId: UUID? = nil

    // Template target data per exercise index
    public var plannedSetsPerExercise: [Int: Int] = [:]
    public var targetWeightPerExercise: [Int: Double?] = [:]
    public var targetRepsPerExercise: [Int: Int?] = [:]

    // Rest timer state
    public var isResting = false
    public var restTimeRemaining: TimeInterval = 0
    public var restDuration: TimeInterval = TimeInterval(UserPreferencesService.defaultRestSecondsValue)

    // Set navigation (nil = active/next set)
    public var viewingSetIndex: Int? = nil

    // Pending set type for quick-start (no sets exist yet)
    public var pendingSetType: SetType = .normal

    // Completion guard (prevents double-tap and provides loading state)
    public var isCompleting = false

    // Motion periods work for every selected exercise. Rep counting is per exercise.
    public var isCollectingSet = false
    public var isReviewingSet = false
    public var detectedRepCount = 0
    public var reviewDetectedReps: Int? { detector == nil ? nil : detectedRepCount }
    public var canDetectCurrentExercise: Bool { detector != nil && motionManager.isAvailable }

    // Notes
    public var workoutNotes: String = ""


    // HealthKit metrics (forwarded from WatchWorkoutSessionManager)
    public var heartRate: Double { watchSessionManager?.heartRate ?? 0 }
    public var activeCalories: Double { watchSessionManager?.activeCalories ?? 0 }
    public var healthKitElapsedTime: TimeInterval { watchSessionManager?.elapsedTime ?? 0 }

    private let workoutRepository: any WorkoutRepository
    private let healthKitService: any HealthKitServiceProtocol
    private let connectivityManager: ConnectivityManager
    private let userPreferencesService: UserPreferencesService?
    private let analyticsService: WorkoutAnalyticsService?
    private let bodyWeightProvider: BodyWeightProvider?
    private let exerciseRepository: (any ExerciseRepository)?
    private var bodyWeightKg: Double {
        bodyWeightProvider?.current ?? userPreferencesService?.bodyWeightKg ?? UserPreferencesService.defaultBodyWeightKg
    }
    private var restTimer: Timer?
    private var restStartDate: Date?
    private var restSetID: UUID?
    private var pendingPersistence: Task<Void, Never>?
    private let motionManager = MotionManager()
    private let motionRecording = MotionRecording()
    private var detector: (any RepDetector)?
    private var periodDetector = ExercisePeriodDetector()
    private var preRoll: [MotionSample] = []
    private var setInactivityTimer: Timer?
    private var lastSetActivityAt: Date?
    private var setAttemptStartedAt: Date?
    private var liveRevision: Int64 = 0
    private let sessionStateKey = "oneRep.watch.activeSessionState"

    private struct PersistedSessionState: Codable {
        struct ExercisePlan: Codable {
            let sets: Int
            let weight: Double?
            let reps: Int?
        }

        let workoutID: UUID
        let exerciseIndex: Int
        let plans: [Int: ExercisePlan]
    }

    // Watch workout session manager (nil on iOS)
    private var watchSessionManager: (any WatchWorkoutSessionManager)?

    public init(
        workoutRepository: any WorkoutRepository,
        healthKitService: any HealthKitServiceProtocol,
        connectivityManager: ConnectivityManager,
        userPreferencesService: UserPreferencesService? = nil,
        analyticsService: WorkoutAnalyticsService? = nil,
        bodyWeightProvider: BodyWeightProvider? = nil,
        exerciseRepository: (any ExerciseRepository)? = nil
    ) {
        self.workoutRepository = workoutRepository
        self.healthKitService = healthKitService
        self.connectivityManager = connectivityManager
        self.userPreferencesService = userPreferencesService
        self.analyticsService = analyticsService
        self.bodyWeightProvider = bodyWeightProvider
        self.exerciseRepository = exerciseRepository
        if let prefs = userPreferencesService {
            self.restDuration = TimeInterval(prefs.defaultRestSeconds)
        }
    }

    public func setWatchSessionManager(_ manager: any WatchWorkoutSessionManager) {
        self.watchSessionManager = manager
    }

    /// Serialize saves triggered by synchronous Watch controls so an older
    /// snapshot cannot overwrite a newer set or rest interval.
    private func enqueuePersistence(_ workout: Workout) {
        let previous = pendingPersistence
        pendingPersistence = Task { [workoutRepository] in
            await previous?.value
            do { _ = try await workoutRepository.save(workout) }
            catch { print("[WatchWorkoutVM] Save failed: \(error)") }
        }
    }

    private func persistNow(_ workout: Workout) async throws {
        await pendingPersistence?.value
        _ = try await workoutRepository.save(workout)
    }

    private func saveSessionState() {
        guard let workout = activeWorkout else { return }
        let persistedPlans = Dictionary(uniqueKeysWithValues: plannedSetsPerExercise.map { index, sets in
            (index, PersistedSessionState.ExercisePlan(
                sets: sets,
                weight: targetWeightPerExercise[index] ?? nil,
                reps: targetRepsPerExercise[index] ?? nil
            ))
        })
        let state = PersistedSessionState(
            workoutID: workout.id, exerciseIndex: currentExerciseIndex, plans: persistedPlans
        )
        if let data = try? JSONEncoder().encode(state) {
            UserDefaults.standard.set(data, forKey: sessionStateKey)
        }
    }

    private func clearSessionState() {
        UserDefaults.standard.removeObject(forKey: sessionStateKey)
    }

    public func restoreActiveWorkout() async {
        guard activeWorkout == nil else { return }
        do {
            guard var restored = try await workoutRepository.fetchActive() else { return }
            let fallbackIndex = restored.exercises.firstIndex {
                $0.sets.contains(where: { !$0.isFullyCompleted })
            } ?? 0
            let storedState = UserDefaults.standard.data(forKey: sessionStateKey)
                .flatMap { try? JSONDecoder().decode(PersistedSessionState.self, from: $0) }
            if let storedState, storedState.workoutID == restored.id {
                currentExerciseIndex = restored.exercises.indices.contains(storedState.exerciseIndex)
                    ? storedState.exerciseIndex : fallbackIndex
                plannedSetsPerExercise = storedState.plans.mapValues(\.sets)
                targetWeightPerExercise = storedState.plans.mapValues(\.weight)
                targetRepsPerExercise = storedState.plans.mapValues(\.reps)
            } else {
                currentExerciseIndex = fallbackIndex
                if restored.templateId != nil {
                    for (index, exercise) in restored.exercises.enumerated() {
                        plannedSetsPerExercise[index] = exercise.sets.count
                        targetWeightPerExercise[index] = exercise.sets.last?.weight
                        targetRepsPerExercise[index] = exercise.sets.last?.reps
                    }
                }
            }
            if let rest = WidgetDataService().readWatchRestTimerState() {
                if rest.workoutID == restored.id,
                   let setID = rest.setID,
                   let exerciseIndex = restored.exercises.firstIndex(where: { exercise in
                       exercise.sets.contains(where: { $0.id == setID })
                   }) {
                    if rest.endDate > Date() {
                        restStartDate = rest.startDate
                        restSetID = setID
                        restDuration = TimeInterval(rest.totalSeconds)
                        restTimeRemaining = rest.endDate.timeIntervalSinceNow
                        isResting = true
                        scheduleRestTicker()
                    } else if let setIndex = restored.exercises[exerciseIndex].sets.firstIndex(where: { $0.id == setID }) {
                        restored.exercises[exerciseIndex].sets[setIndex].restDurationSeconds = TimeInterval(rest.totalSeconds)
                        restored.exercises[exerciseIndex].sets[setIndex].restEndedAt = rest.endDate
                        try? await persistNow(restored)
                        WidgetDataService().updateWatchRestTimerState(nil)
                    }
                } else {
                    WidgetDataService().updateWatchRestTimerState(nil)
                }
            }
            activeWorkout = restored
            isQuickStart = restored.templateId == nil
            isActive = true
            saveSessionState()
            configureMotionForCurrentExercise()
            connectivityManager.sendWorkoutSnapshot(restored)
            publishLiveState()
        } catch {
            print("[WatchWorkoutVM] Recovery failed: \(error)")
        }
    }

    private func configureMotionForCurrentExercise() {
        motionManager.stop()
        motionManager.onSample = nil
        preRoll = []
        periodDetector.reset()
        guard isActive, !isResting, let exercise = currentExercise?.exercise else {
            detector = nil
            return
        }
        detector = RepDetectorFactory.make(exerciseName: exercise.name, wristSide: .left)
        motionManager.onSample = { [weak self] sample in self?.handleMotionSample(sample) }
        motionManager.start(exerciseID: exercise.id, wristSide: .left)
    }

    private func handleMotionSample(_ sample: MotionSample) {
        guard isActive, !isResting, !isReviewingSet,
              sample.exerciseID == currentExercise?.exercise.id else { return }
        preRoll.append(sample)
        if preRoll.count > 100 { preRoll.removeFirst(preRoll.count - 100) }
        if isCollectingSet { motionRecording.append(sample) }
        switch periodDetector.process(sample) {
        case .started:
            if !isCollectingSet { beginSetAttempt() }
            markSetActivity(at: sample.recordedAt)
        case .activity:
            if isCollectingSet, detector == nil { markSetActivity(at: sample.recordedAt) }
        case nil:
            break
        }
        guard var detector else { return }
        let repEvent = detector.process(sample)
        self.detector = detector
        switch repEvent {
        case .movementStarted:
            if !isCollectingSet { beginSetAttempt() }
            markSetActivity(at: sample.recordedAt)
        case .repCompleted:
            if !isCollectingSet { beginSetAttempt() }
            detectedRepCount += 1
            markSetActivity(at: sample.recordedAt)
        case nil:
            break
        }
    }

    private func markSetActivity(at date: Date) {
        lastSetActivityAt = date
        guard setInactivityTimer == nil else { return }
        setInactivityTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, let last = self.lastSetActivityAt else { return }
                if Date().timeIntervalSince(last) >= 5 { self.endSetAttempt() }
            }
        }
    }

    public func beginSetAttempt() {
        guard isActive, !isResting, !isCollectingSet, !isReviewingSet,
              let exercise = currentExercise?.exercise else { return }
        isCollectingSet = true
        setAttemptStartedAt = Date()
        detectedRepCount = 0
        lastSetActivityAt = nil
        setInactivityTimer?.invalidate()
        motionRecording.begin(exerciseID: exercise.id, exerciseName: exercise.name,
                              wristSide: .left, detectorVersion: detector?.version ?? "period-only-1",
                              preRoll: preRoll)
        publishLiveState()
    }

    public func endSetAttempt() {
        guard isCollectingSet else { return }
        setInactivityTimer?.invalidate()
        setInactivityTimer = nil
        lastSetActivityAt = nil
        isCollectingSet = false
        isReviewingSet = true
        motionManager.stop()
        publishLiveState()
    }

    private func resetSetAttempt(finalReps: Int) {
        _ = motionRecording.finish(detectedReps: detectedRepCount, finalReps: finalReps)
        setInactivityTimer?.invalidate()
        setInactivityTimer = nil
        lastSetActivityAt = nil
        isCollectingSet = false
        isReviewingSet = false
        detectedRepCount = 0
        setAttemptStartedAt = nil
        detector?.reset()
        periodDetector.reset()
    }

    private func publishLiveState(ended: Bool = false) {
        guard let workout = activeWorkout else { return }
        liveRevision = max(liveRevision + 1, Int64(Date().timeIntervalSince1970 * 1_000))
        let phase: WorkoutLivePhase = ended ? .ended
            : isResting ? .resting
            : isReviewingSet ? .review
            : isCollectingSet ? .lifting : .ready
        let state = WorkoutLiveState(
            sessionID: workout.id, revision: liveRevision,
            workout: ended ? nil : workout,
            currentExerciseIndex: currentExerciseIndex,
            phase: phase,
            detectedReps: detector == nil ? nil : detectedRepCount,
            restEndsAt: isResting ? restStartDate?.addingTimeInterval(restDuration) : nil
        )
        connectivityManager.publishWorkoutLiveState(state)
    }

    /// Reject commands aimed at a stale screen or a previous workout.
    public func applyControl(_ command: WorkoutLiveCommand) async -> WorkoutLiveCommandReply {
        guard let workout = activeWorkout, isActive,
              workout.id == command.sessionID,
              liveRevision == command.expectedRevision else {
            return WorkoutLiveCommandReply(accepted: false, reason: "Workout changed on Watch. Refresh and try again.")
        }
        let previousRevision = liveRevision
        switch command.action {
        case .startSet: beginSetAttempt()
        case .endSet: endSetAttempt()
        case .saveReviewedSet:
            guard isReviewingSet,
                  let reps = command.reviewedReps, (0...100).contains(reps),
                  let weight = command.reviewedWeightKg, weight.isFinite, weight >= 0 else {
                return WorkoutLiveCommandReply(accepted: false, reason: "Invalid set review")
            }
            do {
                try await logSet(weight: weight, reps: reps, detectedReps: reviewDetectedReps)
            } catch {
                return WorkoutLiveCommandReply(accepted: false, reason: "Watch could not save the set")
            }
        case .nextExercise: nextExercise()
        case .previousExercise: previousExercise()
        case .skipRest:
            if isResting { skipRestTimer() }
        }
        return liveRevision > previousRevision
            ? WorkoutLiveCommandReply(accepted: true)
            : WorkoutLiveCommandReply(accepted: false, reason: "Control unavailable in this set stage.")
    }

    // MARK: - Computed Properties

    public var currentExercise: WorkoutExercise? {
        guard let workout = activeWorkout,
              currentExerciseIndex < workout.exercises.count else {
            return nil
        }
        return workout.exercises[currentExerciseIndex]
    }

    public var currentSetNumber: Int {
        guard let exercise = currentExercise else { return 1 }
        let completedCount = exercise.sets.filter(\.isFullyCompleted).count
        return completedCount + 1
    }

    public var hasPlannedSets: Bool {
        plannedSetsPerExercise[currentExerciseIndex] != nil
    }

    public var plannedSets: Int {
        plannedSetsPerExercise[currentExerciseIndex] ?? (isQuickStart ? 1 : 4)
    }

    public var currentTargetWeight: Double? {
        // Prefer the next incomplete pre-populated set's weight (per-set targets from template)
        if let exercise = currentExercise,
           let nextIncomplete = exercise.sets.first(where: { !$0.isFullyCompleted }) {
            return nextIncomplete.weight
        }
        // Fall back to exercise-level target for extra sets
        return targetWeightPerExercise[currentExerciseIndex] ?? nil
    }

    public var currentTargetReps: Int? {
        // Prefer the next incomplete pre-populated set's reps (per-set targets from template)
        if let exercise = currentExercise,
           let nextIncomplete = exercise.sets.first(where: { !$0.isFullyCompleted }) {
            return nextIncomplete.reps
        }
        // Fall back to exercise-level target for extra sets
        return targetRepsPerExercise[currentExerciseIndex] ?? nil
    }

    public var isEditingCompletedSet: Bool {
        guard let idx = viewingSetIndex,
              let exercise = currentExercise else { return false }
        return idx < exercise.sets.count && exercise.sets[idx].isCompleted
    }

    public var viewingSetWeight: Double? {
        guard let idx = viewingSetIndex,
              let exercise = currentExercise,
              idx < exercise.sets.count else { return currentTargetWeight }
        return exercise.sets[idx].weight
    }

    public var viewingSetReps: Int? {
        guard let idx = viewingSetIndex,
              let exercise = currentExercise,
              idx < exercise.sets.count else { return currentTargetReps }
        return exercise.sets[idx].reps
    }

    public var canNavigateToPreviousSet: Bool {
        guard let exercise = currentExercise else { return false }
        let completedCount = exercise.sets.filter(\.isFullyCompleted).count
        if viewingSetIndex == nil {
            return completedCount > 0
        }
        return (viewingSetIndex ?? 0) > 0
    }

    public var canNavigateToNextSet: Bool {
        viewingSetIndex != nil
    }

    public var currentExercisePlannedSetsComplete: Bool {
        guard !isQuickStart,
              let planned = plannedSetsPerExercise[currentExerciseIndex],
              let exercise = currentExercise else { return false }
        return exercise.sets.filter(\.isFullyCompleted).count >= planned
    }

    public var isLastExercise: Bool {
        guard let workout = activeWorkout else { return false }
        return currentExerciseIndex >= workout.exercises.count - 1
    }

    public var currentExerciseVolume: Double {
        return currentExercise?.exerciseVolume(bodyWeightKg: bodyWeightKg) ?? 0
    }

    public var totalSetsCompleted: Int {
        guard let workout = activeWorkout else { return 0 }
        return workout.exercises.reduce(0) { $0 + $1.sets.filter(\.isFullyCompleted).count }
    }

    public var elapsedTime: TimeInterval {
        guard let workout = activeWorkout else { return 0 }
        return Date().timeIntervalSince(workout.startedAt)
    }

    public var restTimerText: String {
        let minutes = Int(restTimeRemaining) / 60
        let seconds = Int(restTimeRemaining) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    public var restProgress: Double {
        guard restDuration > 0 else { return 0 }
        return 1.0 - (restTimeRemaining / restDuration)
    }

    // MARK: - Workout Lifecycle

    /// Synchronous: builds workout, sets state, activates navigation immediately.
    /// Call from the same synchronous scope as sheet dismiss for batched rendering.
    public func prepareQuickStart(name: String, exercises: [Exercise]) {
        isQuickStart = true
        plannedSetsPerExercise = [:]
        targetWeightPerExercise = [:]
        targetRepsPerExercise = [:]
        viewingSetIndex = nil

        let workoutExercises = exercises.enumerated().map { index, exercise in
            WorkoutExercise(
                id: UUID(),
                exercise: exercise,
                order: index + 1,
                supersetGroup: nil,
                notes: nil,
                restTimerSeconds: nil,
                sets: []
            )
        }

        let workout = Workout(
            id: UUID(),
            name: name,
            startedAt: Date(),
            completedAt: nil,
            notes: nil,
            templateId: nil,
            healthKitWorkoutId: nil,
            exercises: workoutExercises
        )

        activeWorkout = workout
        currentExerciseIndex = 0
        isActive = true
        saveSessionState()
        configureMotionForCurrentExercise()
        publishLiveState()
    }

    /// Async: persists the current workout and starts HealthKit session.
    /// Call in a background Task after prepareQuickStart.
    public func persistAndStartSession() async {
        guard let workout = activeWorkout else { return }

        do {
            let saved = try await workoutRepository.save(workout)
            activeWorkout = saved
        } catch {
            print("[WatchWorkoutVM] Initial save failed: \(error)")
        }

        do {
            try await watchSessionManager?.requestAuthorization()
            try await watchSessionManager?.startWorkoutSession()
        } catch {
            print("[WatchWorkoutVM] HealthKit session start failed: \(error)")
        }

        connectivityManager.sendWorkoutStarted(activeWorkout ?? workout)
        publishLiveState()
    }

    public func startWorkout(name: String, from template: WorkoutTemplate, isDeload: Bool = false) async {
        let library: [Exercise]
        do { library = try await exerciseRepository?.fetchAll() ?? [] }
        catch { return }
        let template = template.resolvingBodyweight(from: library)
        isQuickStart = false
        plannedSetsPerExercise = [:]
        targetWeightPerExercise = [:]
        targetRepsPerExercise = [:]

        let workoutExercises = template.exercises.sorted { $0.order < $1.order }.enumerated().map { index, te in
            let sets = (0..<te.targetSets).map { setIndex in
                let target = te.setTargets.indices.contains(setIndex) ? te.setTargets[setIndex] : nil
                let resolvedSetType: SetType = {
                    if let t = target, t.setType != .normal { return t.setType }
                    return te.isWarmUp ? .warmup : .normal
                }()
                return ExerciseSet(
                    id: UUID(),
                    order: setIndex + 1,
                    setType: resolvedSetType,
                    weight: target?.targetWeight ?? te.targetWeight,
                    reps: target?.targetReps ?? te.targetReps,
                    durationSeconds: target?.targetDurationSeconds ?? te.targetDurationSeconds,
                    distanceMeters: target?.targetDistanceMeters ?? te.targetDistanceMeters,
                    rpe: nil,
                    isCompleted: false,
                    isPersonalRecord: false,
                    completedAt: nil
                )
            }
            return WorkoutExercise(
                id: UUID(),
                exercise: te.exercise,
                order: index + 1,
                supersetGroup: te.supersetGroup,
                notes: te.notes,
                restTimerSeconds: te.restTimerSeconds,
                sets: sets
            )
        }

        // Store per-exercise targets
        for (index, te) in template.exercises.sorted(by: { $0.order < $1.order }).enumerated() {
            plannedSetsPerExercise[index] = te.targetSets
            targetWeightPerExercise[index] = te.targetWeight
            targetRepsPerExercise[index] = te.targetReps
        }

        let workout = Workout(
            id: UUID(),
            name: name,
            startedAt: Date(),
            completedAt: nil,
            notes: nil,
            templateId: template.id,
            isDeload: isDeload,
            plannedSessionId: plannedSessionId,
            plannedPlanId: plannedPlanId,
            exercises: workoutExercises, deloadRestPercentage: template.deloadRestPercentage
        )

        // Set state immediately so navigation pushes without waiting for save
        activeWorkout = workout
        currentExerciseIndex = 0
        isActive = true
        saveSessionState()
        configureMotionForCurrentExercise()
        publishLiveState()

        // Persist and start HealthKit in background
        do {
            let saved = try await workoutRepository.save(workout)
            activeWorkout = saved
        } catch {
            print("[WatchWorkoutVM] Initial save failed: \(error)")
        }

        do {
            try await watchSessionManager?.requestAuthorization()
            try await watchSessionManager?.startWorkoutSession()
        } catch {
            print("[WatchWorkoutVM] HealthKit session start failed: \(error)")
        }

        connectivityManager.sendWorkoutStarted(workout)
        publishLiveState()
    }

    /// Start a workout from a planned session (progression plan sync from iPhone).
    public func startPlannedSession(_ session: PlannedSessionSync) async {
        plannedSessionId = session.id
        plannedPlanId = session.planId
        await startWorkout(name: session.sessionLabel, from: session.template, isDeload: session.isDeload)
    }

    public var visibleSet: ExerciseSet? {
        guard let exercise = currentExercise else { return nil }
        if let index = viewingSetIndex, exercise.sets.indices.contains(index) { return exercise.sets[index] }
        return exercise.sets.first { !$0.isFullyCompleted }
    }

    public func logSide(_ side: BodySide, weight: Double?, reps: Int?, rpe: Double? = nil) async throws {
        guard var workout = activeWorkout, workout.exercises.indices.contains(currentExerciseIndex),
              let recording = workout.exercises[currentExerciseIndex].exercise.strengthRecording,
              recording.supportsSeparateSides else { throw WorkoutError.exerciseNotFound }
        let exercise = workout.exercises[currentExerciseIndex]
        let index = viewingSetIndex ?? exercise.sets.firstIndex { !$0.isFullyCompleted } ?? exercise.sets.count
        if index == exercise.sets.count {
            workout.exercises[currentExerciseIndex].sets.append(ExerciseSet(id: UUID(), order: index + 1,
                setType: pendingSetType, weight: weight.map { $0 / recording.sideWeightScale }, reps: reps, durationSeconds: nil, distanceMeters: nil,
                rpe: nil, isCompleted: false, isPersonalRecord: false, completedAt: nil))
        }
        guard workout.exercises[currentExerciseIndex].sets.indices.contains(index) else { return }
        var set = workout.exercises[currentExerciseIndex].sets[index]
        let wasComplete = set.isFullyCompleted
        set.separateSides(recording: recording, onlySide: recording.repetitions == .oneSide ? side : nil)
        guard var sides = set.sideSets, let i = sides.firstIndex(where: { $0.side == side }), sides[i].effort.dropSets.isEmpty else { return }
        sides[i].effort.weight = weight
        sides[i].effort.reps = reps
        sides[i].effort.applyRPE(rpe)
        if sides[i].effort.isFailure { sides[i].effort.setFailureFlag(true) }
        sides[i].effort.setCompleted(true)
        set.applySideSets(sides)
        if set.startedAt == nil { set.startedAt = setAttemptStartedAt ?? Date() }
        workout.exercises[currentExerciseIndex].sets[index] = set
        activeWorkout = workout
        try await persistNow(workout)
        connectivityManager.sendWorkoutSnapshot(workout)
        if set.isFullyCompleted {
            resetSetAttempt(finalReps: reps ?? 0)
            viewingSetIndex = nil; pendingSetType = .normal
            if !wasComplete { startRestTimer(seconds: exercise.restTimerSeconds) }
            if !isResting {
                configureMotionForCurrentExercise()
                publishLiveState()
            }
        } else {
            publishLiveState()
        }
    }

    public func logSet(weight: Double?, reps: Int?, rpe: Double? = nil, detectedReps: Int? = nil) async throws {
        guard var workout = activeWorkout else {
            throw WorkoutError.noActiveWorkout
        }

        guard currentExerciseIndex < workout.exercises.count else {
            throw WorkoutError.exerciseNotFound
        }

        // Named sides must be edited independently; never replace their summary.
        guard visibleSet?.sideSets == nil else { return }
        // If there's an incomplete pre-populated set, update it instead of appending
        if let incompleteIndex = workout.exercises[currentExerciseIndex].sets.firstIndex(where: { !$0.isFullyCompleted }) {
            workout.exercises[currentExerciseIndex].sets[incompleteIndex].weight = weight
            workout.exercises[currentExerciseIndex].sets[incompleteIndex].reps = reps
            if workout.exercises[currentExerciseIndex].sets[incompleteIndex].startedAt == nil {
                workout.exercises[currentExerciseIndex].sets[incompleteIndex].startedAt = setAttemptStartedAt ?? Date()
            }
            workout.exercises[currentExerciseIndex].sets[incompleteIndex].detectedReps = detectedReps
            workout.exercises[currentExerciseIndex].sets[incompleteIndex].applyRPE(rpe)
            // Re-assert failure defaults in case a nil RPE cleared them just above.
            if workout.exercises[currentExerciseIndex].sets[incompleteIndex].isFailure {
                workout.exercises[currentExerciseIndex].sets[incompleteIndex].setFailureFlag(true)
            }
            workout.exercises[currentExerciseIndex].sets[incompleteIndex].isCompleted = true
            workout.exercises[currentExerciseIndex].sets[incompleteIndex].completedAt = Date()
        } else {
            // All pre-populated sets done (or none existed), append a new one
            let setOrder = workout.exercises[currentExerciseIndex].sets.count + 1
            var newSet = ExerciseSet(
                id: UUID(),
                order: setOrder,
                setType: pendingSetType,
                weight: weight,
                reps: reps,
                durationSeconds: nil,
                distanceMeters: nil,
                rpe: nil,
                isCompleted: true,
                isPersonalRecord: false,
                completedAt: Date(),
                detectedReps: detectedReps,
                startedAt: setAttemptStartedAt ?? Date()
            )
            newSet.applyRPE(rpe)
            // Watch still marks failure via the set-type cycle — carry the per-set flag
            // so analytics and the iPhone UI see it.
            if newSet.setType == .failure { newSet.setFailureFlag(true) }
            workout.exercises[currentExerciseIndex].sets.append(newSet)
        }

        activeWorkout = workout
        viewingSetIndex = nil
        pendingSetType = .normal

        try await persistNow(workout)
        resetSetAttempt(finalReps: reps ?? 0)

        // Send live snapshot to iPhone
        connectivityManager.sendWorkoutSnapshot(workout)

        // Auto-start rest timer after logging a set (uses per-exercise override if set)
        let exercise = workout.exercises[currentExerciseIndex]
        print("[WatchVM] logSet → startRestTimer (exercise=\(exercise.exercise.name), restOverride=\(String(describing: exercise.restTimerSeconds)))")
        startRestTimer(seconds: exercise.restTimerSeconds)
        if !isResting {
            configureMotionForCurrentExercise()
            publishLiveState()
        }
    }

    public func removeSet(at exerciseIndex: Int, setIndex: Int) {
        guard var workout = activeWorkout,
              exerciseIndex < workout.exercises.count,
              setIndex < workout.exercises[exerciseIndex].sets.count else {
            return
        }

        workout.exercises[exerciseIndex].sets.remove(at: setIndex)

        // Re-order remaining sets
        for i in 0..<workout.exercises[exerciseIndex].sets.count {
            workout.exercises[exerciseIndex].sets[i].order = i + 1
        }

        activeWorkout = workout
        enqueuePersistence(workout)
        connectivityManager.sendWorkoutSnapshot(workout)
        publishLiveState()
    }

    public func removeSetFromCurrentExercise(at setIndex: Int) {
        removeSet(at: currentExerciseIndex, setIndex: setIndex)
    }

    public func completeWorkout() async throws {
        guard !isCompleting else { return }
        isCompleting = true
        defer {
            isCompleting = false
            // Always pop navigation so user is never stuck
            isActive = false
        }

        guard var workout = activeWorkout else {
            throw WorkoutError.noActiveWorkout
        }

        motionManager.stop()
        setInactivityTimer?.invalidate()
        motionRecording.discard()
        isCollectingSet = false
        isReviewingSet = false

        stopRestTimer()
        await pendingPersistence?.value
        workout = activeWorkout ?? workout
        workout.completedAt = Date()
        if !workoutNotes.isEmpty {
            workout.notes = workoutNotes
        }
        var saved = try await workoutRepository.save(workout)

        // End HealthKit workout session BEFORE setting isActive = false.
        do {
            try await watchSessionManager?.endWorkoutSession()
        } catch {
            print("[WatchWorkoutVM] HealthKit session end failed: \(error)")
        }

        // Attach the Watch's HKWorkout UUID so iPhone can add calorie data to it
        if let hkUUID = watchSessionManager?.finishedWorkoutUUID {
            saved.healthKitWorkoutId = hkUUID
            saved = (try? await workoutRepository.save(saved)) ?? saved
        }

        activeWorkout = saved
        publishLiveState(ended: true)
        clearSessionState()

        // Notify iPhone workout ended, then send full workout via transferUserInfo
        connectivityManager.sendWorkoutEnded()
        // Prefer IDs persisted on the workout — survives VM resets/app restarts.
        var metadata: [String: String]? = nil
        if let sid = saved.plannedSessionId ?? plannedSessionId,
           let pid = saved.plannedPlanId ?? plannedPlanId {
            metadata = [
                "plannedSessionId": sid.uuidString,
                "plannedPlanId": pid.uuidString
            ]
        }
        connectivityManager.sendWorkoutCompleted(saved, metadata: metadata)
        plannedSessionId = nil
        plannedPlanId = nil

        // Vectorize workout for analytics in background
        Task {
            try? await analyticsService?.vectorizeWorkout(saved)
        }
    }

    public func cancelWorkout() async {
        guard !isCompleting else { return }
        isCompleting = true
        defer {
            isCompleting = false
            isActive = false
        }

        motionManager.stop()
        setInactivityTimer?.invalidate()
        motionRecording.discard()
        isCollectingSet = false
        isReviewingSet = false
        stopRestTimer()

        await watchSessionManager?.discardWorkoutSession()

        if let workout = activeWorkout {
            try? await workoutRepository.delete(workout)
        }

        publishLiveState(ended: true)
        activeWorkout = nil
        currentExerciseIndex = 0
        workoutNotes = ""
        clearSessionState()

        connectivityManager.sendWorkoutEnded()
        plannedSessionId = nil
        plannedPlanId = nil
    }

    // MARK: - Navigation

    public func nextExercise() {
        guard let workout = activeWorkout, !isCollectingSet, !isReviewingSet else { return }
        if currentExerciseIndex < workout.exercises.count - 1 {
            viewingSetIndex = nil
            pendingSetType = .normal
            currentExerciseIndex += 1
            saveSessionState()
            configureMotionForCurrentExercise()
            publishLiveState()
        }
    }

    public func previousExercise() {
        if currentExerciseIndex > 0, !isCollectingSet, !isReviewingSet {
            viewingSetIndex = nil
            pendingSetType = .normal
            currentExerciseIndex -= 1
            saveSessionState()
            configureMotionForCurrentExercise()
            publishLiveState()
        }
    }

    // MARK: - Set Navigation

    public func navigateToPreviousSet() {
        guard let exercise = currentExercise else { return }
        let completedCount = exercise.sets.filter(\.isFullyCompleted).count
        if viewingSetIndex == nil {
            // From active set, go to last completed
            if completedCount > 0 {
                viewingSetIndex = completedCount - 1
            }
        } else if let idx = viewingSetIndex, idx > 0 {
            viewingSetIndex = idx - 1
        }
    }

    public func navigateToNextSet() {
        guard let idx = viewingSetIndex,
              let exercise = currentExercise else { return }
        let completedCount = exercise.sets.filter(\.isFullyCompleted).count
        if idx < completedCount - 1 {
            viewingSetIndex = idx + 1
        } else {
            viewingSetIndex = nil
        }
    }

    public var currentSetType: SetType {
        guard let exercise = currentExercise else { return pendingSetType }
        if let idx = viewingSetIndex, idx < exercise.sets.count {
            return exercise.sets[idx].setType
        }
        if let nextIncomplete = exercise.sets.first(where: { !$0.isFullyCompleted }) {
            return nextIncomplete.setType
        }
        return pendingSetType
    }

    public func updateSetType(setType: SetType) {
        guard var workout = activeWorkout,
              currentExerciseIndex < workout.exercises.count else { return }
        if let idx = viewingSetIndex,
           idx < workout.exercises[currentExerciseIndex].sets.count {
            workout.exercises[currentExerciseIndex].sets[idx].setType = setType
            // Watch still marks failure via the set-type cycle — carry the per-set flag.
            if setType == .failure {
                workout.exercises[currentExerciseIndex].sets[idx].setFailureFlag(true)
            }
            activeWorkout = workout
            enqueuePersistence(workout)
            connectivityManager.sendWorkoutSnapshot(workout)
        } else if let incompleteIdx = workout.exercises[currentExerciseIndex].sets.firstIndex(where: { !$0.isFullyCompleted }) {
            workout.exercises[currentExerciseIndex].sets[incompleteIdx].setType = setType
            if setType == .failure {
                workout.exercises[currentExerciseIndex].sets[incompleteIdx].setFailureFlag(true)
            }
            activeWorkout = workout
            enqueuePersistence(workout)
            connectivityManager.sendWorkoutSnapshot(workout)
        } else {
            // No set exists yet (quick-start) — store for next logSet()
            pendingSetType = setType
        }
        publishLiveState()
    }

    public func updateSet(weight: Double?, reps: Int?) async throws {
        guard let idx = viewingSetIndex,
              var workout = activeWorkout,
              currentExerciseIndex < workout.exercises.count,
              idx < workout.exercises[currentExerciseIndex].sets.count,
              workout.exercises[currentExerciseIndex].sets[idx].sideSets == nil else { return }
        workout.exercises[currentExerciseIndex].sets[idx].weight = weight
        workout.exercises[currentExerciseIndex].sets[idx].reps = reps
        activeWorkout = workout
        viewingSetIndex = nil

        try await persistNow(workout)

        // Send updated snapshot to iPhone
        connectivityManager.sendWorkoutSnapshot(workout)
        publishLiveState()
    }

    // MARK: - Rest Timer

    /// Start rest timer with optional per-exercise duration override
    public func startRestTimer(seconds: Int? = nil) {
        print("[WatchVM] startRestTimer(seconds: \(String(describing: seconds)))")
        // Respect autoStartRestTimer preference
        guard userPreferencesService?.autoStartRestTimer ?? true else {
            print("[WatchVM] startRestTimer SKIPPED — autoStartRestTimer is false")
            return
        }

        stopRestTimer()

        var duration = seconds
            ?? userPreferencesService?.defaultRestSeconds
            ?? UserPreferencesService.defaultRestSecondsValue
        if activeWorkout?.isDeload == true {
            duration = max(15, duration * (activeWorkout?.deloadRestPercentage ?? userPreferencesService?.deloadRestPercentage ?? 75) / 100)
        }
        restDuration = TimeInterval(duration)
        isResting = true
        restTimeRemaining = restDuration
        restStartDate = Date()
        restSetID = currentExercise?.sets.last(where: { $0.isFullyCompleted })?.id
        print("[WatchVM] rest started dur=\(restDuration) rem=\(restTimeRemaining)")

        // Write timer state for native watchOS widget (works without iPhone)
        if let name = currentExercise?.exercise.name {
            let widgetState = WatchRestTimerState(
                exerciseName: name,
                setNumber: currentSetNumber,
                startDate: Date(),
                endDate: Date().addingTimeInterval(TimeInterval(duration)),
                totalSeconds: duration,
                workoutID: activeWorkout?.id,
                setID: restSetID
            )
            WidgetDataService().updateWatchRestTimerState(widgetState)

        }

        // Schedule local notification for when timer completes (visible even when backgrounded)
        let notifContent = UNMutableNotificationContent()
        notifContent.title = "Rest Complete"
        notifContent.body = currentExercise.map { "Time for your next set of \($0.exercise.name)" }
            ?? "Time for your next set"
        notifContent.sound = .default
        notifContent.interruptionLevel = .timeSensitive
        notifContent.relevanceScore = 1.0
        let trigger = UNTimeIntervalNotificationTrigger(
            timeInterval: max(1, restDuration), repeats: false
        )
        let request = UNNotificationRequest(
            identifier: "watch-rest-timer", content: notifContent, trigger: trigger
        )
        UNUserNotificationCenter.current().add(request)

        scheduleRestTicker()
        publishLiveState()
    }

    private func scheduleRestTicker() {
        restTimer?.invalidate()
        restTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, let start = self.restStartDate else { return }
                let elapsed = Date().timeIntervalSince(start)
                let remaining = self.restDuration - elapsed
                if remaining > 0 {
                    self.restTimeRemaining = remaining
                } else {
                    self.restTimeRemaining = 0
                    self.restTimerCompleted()
                }
            }
        }
    }

    public func stopRestTimer() {
        print("[WatchVM] stopRestTimer")
        if let start = restStartDate,
           let setID = restSetID,
           var workout = activeWorkout,
           let exerciseIndex = workout.exercises.firstIndex(where: { exercise in
               exercise.sets.contains(where: { $0.id == setID })
           }),
           let setIndex = workout.exercises[exerciseIndex].sets.firstIndex(where: { $0.id == setID }) {
            let endedAt = Date()
            workout.exercises[exerciseIndex].sets[setIndex].restDurationSeconds = max(0, endedAt.timeIntervalSince(start))
            workout.exercises[exerciseIndex].sets[setIndex].restEndedAt = endedAt
            activeWorkout = workout
            enqueuePersistence(workout)
            connectivityManager.sendWorkoutSnapshot(workout)
        }
        restTimer?.invalidate()
        restTimer = nil
        restStartDate = nil
        restSetID = nil
        isResting = false
        restTimeRemaining = 0

        // Cancel pending notification
        UNUserNotificationCenter.current().removePendingNotificationRequests(
            withIdentifiers: ["watch-rest-timer"]
        )

        // Clear watchOS widget timer state
        WidgetDataService().updateWatchRestTimerState(nil)
    }

    /// Called when timer naturally expires — plays strong haptic twice then stops
    private func restTimerCompleted() {
        #if os(watchOS)
        let device = WKInterfaceDevice.current()
        device.play(.notification)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            device.play(.notification)
        }
        #endif
        stopRestTimer()
        configureMotionForCurrentExercise()
        publishLiveState()
    }

    public func skipRestTimer() {
        stopRestTimer()
        configureMotionForCurrentExercise()
        publishLiveState()
    }
}
