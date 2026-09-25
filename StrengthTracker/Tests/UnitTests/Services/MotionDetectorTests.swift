import Foundation
import Testing
@testable import StrengthTrackerShared

@Suite("OneRep motion detectors")
struct MotionDetectorTests {
    private let exerciseID = UUID()
    private let start = Date(timeIntervalSince1970: 1_700_000_000)

    private func sample(_ index: Int, moving: Bool,
                        gravity: MotionVector3 = MotionVector3(x: 0, y: -1, z: 0)) -> MotionSample {
        MotionSample(
            recordedAt: start.addingTimeInterval(Double(index) * 0.02),
            exerciseID: exerciseID, wristSide: .left,
            gravity: gravity,
            userAcceleration: MotionVector3(x: moving ? 0.2 : 0, y: 0, z: 0),
            rotationRate: MotionVector3(x: 0, y: 0, z: 0)
        )
    }

    @Test("A sustained motion period starts a set for any selected exercise")
    func genericPeriod() {
        var detector = ExercisePeriodDetector()
        for index in 0..<25 {
            #expect(detector.process(sample(index, moving: false)) == nil)
        }
        var started = false
        for index in 25..<50 {
            if case .started? = detector.process(sample(index, moving: true)) { started = true }
        }
        #expect(started)
        if case .activity? = detector.process(sample(50, moving: true)) {
            // A moving sample refreshes the set's inactivity clock.
        } else {
            Issue.record("Expected activity after the period started")
        }
        detector.reset()
        #expect(detector.process(sample(51, moving: false)) == nil)
    }

    @Test("The left wrist lateral raise detector emits a completed rep")
    func lateralRaiseRep() {
        var detector = LateralRaiseRepDetector()
        let lowered = MotionVector3(x: 0, y: -1, z: 0)
        let raised = MotionVector3(x: 0, y: 0, z: -1)
        #expect(detector.process(sample(0, moving: false, gravity: lowered)) == nil)
        if case .movementStarted? = detector.process(sample(50, moving: true, gravity: raised)) {
            // Raised phase entered.
        } else {
            Issue.record("Expected raised phase")
        }
        if case .repCompleted? = detector.process(sample(70, moving: true, gravity: lowered)) {
            // Return to the baseline completes the rep.
        } else {
            Issue.record("Expected a completed rep")
        }
    }
}
