import Foundation

enum RecommendationV2FeatureFlags {
    /// Developer-only read-only comparison hook for the future Swimability v2 engine.
    /// Keep disabled for normal builds until the v2 gates are implemented and reviewed.
    static let swimabilityV2ComparisonEnabled = false
}
