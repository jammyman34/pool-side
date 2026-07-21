import Foundation

struct SwimabilityV2Engine {
    private let normalizer = PoolStateNormalizer()

    func assess(request: AIRecommendationRequest) -> SwimabilityV2Assessment {
        _ = normalizer.normalize(request: request)

        return SwimabilityV2Assessment(
            state: .moreInformationNeeded,
            evidenceType: .unknown,
            confidence: .insufficient,
            gateResults: [],
            invalidationReasons: [],
            testingRequired: false,
            summary: "Swimability v2 evaluation is not implemented yet. This placeholder confirms the parallel assessment boundary is wired without affecting production recommendations."
        )
    }
}
