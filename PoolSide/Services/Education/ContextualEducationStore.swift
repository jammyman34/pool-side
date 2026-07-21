import Foundation
import Observation

@Observable
final class ContextualEducationStore {
    @MainActor static let shared = ContextualEducationStore()

    private static let seenTipsKey = "PoolSide.ContextualEducation.seenTips.v1"

    private let defaults: UserDefaults
    private(set) var seenTipIDs: Set<String>

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.seenTipIDs = Set(defaults.stringArray(forKey: Self.seenTipsKey) ?? [])
    }

    func hasSeen(_ tipID: ContextualTipID) -> Bool {
        seenTipIDs.contains(tipID.rawValue)
    }

    func hasSeen(_ walkthroughID: ContextualWalkthroughID) -> Bool {
        walkthroughID.tipIDs.allSatisfy { hasSeen($0) }
    }

    func markSeen(_ tipID: ContextualTipID) {
        seenTipIDs.insert(tipID.rawValue)
        persist()
    }

    func markSeen(_ walkthroughID: ContextualWalkthroughID) {
        walkthroughID.tipIDs.forEach { seenTipIDs.insert($0.rawValue) }
        persist()
    }

    func resetAll() {
        seenTipIDs.removeAll()
        persist()
    }

    private func persist() {
        defaults.set(Array(seenTipIDs).sorted(), forKey: Self.seenTipsKey)
    }
}
