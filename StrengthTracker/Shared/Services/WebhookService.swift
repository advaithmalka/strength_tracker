import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Observation

@Observable
public final class WebhookService: @unchecked Sendable {
    private let preferencesService: UserPreferencesService
    private let session: URLSession

    @MainActor
    public init(preferencesService: UserPreferencesService) {
        self.preferencesService = preferencesService
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        self.session = URLSession(configuration: config)
    }

    @MainActor
    public func send(_ workout: Workout) async {
        // OneRep V1 never transmits workout data to a webhook.
        _ = workout
    }
}
