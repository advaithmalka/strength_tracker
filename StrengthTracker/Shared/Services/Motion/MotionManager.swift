import Foundation
#if os(watchOS)
import CoreMotion
#endif

/// Owns Watch motion sampling. Detection runs in the ViewModel on the main actor.
@MainActor
public final class MotionManager {
    public var onSample: ((MotionSample) -> Void)?

    #if os(watchOS)
    private let manager = CMMotionManager()
    private let queue: OperationQueue = {
        let queue = OperationQueue()
        queue.name = "OneRep motion samples"
        queue.maxConcurrentOperationCount = 1
        queue.qualityOfService = .userInitiated
        return queue
    }()
    #endif

    public init() {}

    public var isAvailable: Bool {
        #if os(watchOS)
        manager.isDeviceMotionAvailable
        #else
        false
        #endif
    }

    public func start(exerciseID: UUID, wristSide: WristSide) {
        #if os(watchOS)
        guard manager.isDeviceMotionAvailable else { return }
        stop()
        manager.deviceMotionUpdateInterval = 1.0 / 50.0
        manager.startDeviceMotionUpdates(to: queue) { [weak self] motion, _ in
            guard let motion else { return }
            let sample = MotionSample(
                recordedAt: Date(), exerciseID: exerciseID, wristSide: wristSide,
                gravity: MotionVector3(x: motion.gravity.x, y: motion.gravity.y, z: motion.gravity.z),
                userAcceleration: MotionVector3(x: motion.userAcceleration.x, y: motion.userAcceleration.y, z: motion.userAcceleration.z),
                rotationRate: MotionVector3(x: motion.rotationRate.x, y: motion.rotationRate.y, z: motion.rotationRate.z)
            )
            Task { @MainActor [weak self] in self?.onSample?(sample) }
        }
        #endif
    }

    public func stop() {
        #if os(watchOS)
        manager.stopDeviceMotionUpdates()
        #endif
    }
}
