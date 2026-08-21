import Foundation

enum RecommendationV2FeatureFlags {
    /// Developer-only read-only comparison hook for the future Swimability v2 engine.
    /// Enabled automatically for DEBUG dogfooding and compiled disabled for release builds.
    #if DEBUG
    static let swimabilityV2ComparisonEnabled = true
    #else
    static let swimabilityV2ComparisonEnabled = false
    #endif
}
