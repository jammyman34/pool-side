import Foundation

struct SwimReadinessGateEvaluator {
    /// Chemistry swim gates consume ChemistryPolicy so there is one authority for chemistry thresholds:
    /// - pH swim range: ChemistryPolicy.PHPolicy (7.0–7.8 inclusive; operating range 7.2–7.6 is separate).
    /// - FC low: ChemistryPolicy.FreeChlorinePolicy.readinessMinimum(CYA); FC high: reentryCeiling(CYA).
    /// - CC: ChemistryPolicy.CombinedChlorinePolicy.readinessThreshold.
    private let combinedChlorineReadinessMaximum = CombinedChlorinePolicy.readinessThreshold

    /// Approved user-facing swim-readiness freshness window: readiness stays valid for 24 hours since the
    /// most recent supporting evidence, then re-testing is required. This is a product decision (not a
    /// chemistry fact); it balances daily re-testing against not expiring a same-day test by evening.
    private let readinessFreshnessThresholdMinutes = 24 * 60

    func evaluate(state: NormalizedPoolState, treatmentContext: V2TreatmentAwareContext? = nil) -> [SwimReadinessGateResult] {
        [
            sanitizerAdequacyGate(for: state),
            pHGate(for: state),
            combinedChlorineGate(for: state),
            waterClarityGate(for: state),
            visibleAlgaeGate(for: state),
            testFreshnessGate(for: state),
            treatmentCompletionGate(for: state, treatmentContext: treatmentContext),
            circulationGate(for: state, treatmentContext: treatmentContext),
            productReentryGate(for: state, treatmentContext: treatmentContext)
        ]
    }

    private func sanitizerAdequacyGate(for state: NormalizedPoolState) -> SwimReadinessGateResult {
        guard let freeChlorine = state.freeChlorine else {
            return result(
                .sanitizerAdequacy,
                .unknown,
                "Free chlorine was not recorded, so sanitizer adequacy cannot be evaluated.",
                blocksSwimming: true,
                requiresTesting: true
            )
        }

        guard let cyanuricAcid = state.cyanuricAcid else {
            return result(
                .sanitizerAdequacy,
                .unknown,
                "CYA was not recorded, so the FC minimum cannot be interpreted for this pool.",
                blocksSwimming: true,
                requiresTesting: true
            )
        }

        let minimum = FreeChlorinePolicy.readinessMinimum(cyanuricAcid: cyanuricAcid)
        if freeChlorine < minimum {
            return result(
                .sanitizerAdequacy,
                .fail,
                "FC \(format(freeChlorine)) ppm is below the CYA-adjusted observed-readiness minimum of \(format(minimum)) ppm.",
                blocksSwimming: true,
                requiresTesting: true
            )
        }

        // High-FC re-entry: above the CYA-resolved re-entry ceiling, hold swimming until FC decays.
        // Uses the ChemistryPolicy resolver rather than a hard-coded number.
        let ceiling = FreeChlorinePolicy.reentryCeiling(cyanuricAcid: cyanuricAcid)
        if freeChlorine > ceiling {
            return result(
                .sanitizerAdequacy,
                .fail,
                "FC \(format(freeChlorine)) ppm is above the CYA-adjusted re-entry ceiling of \(format(ceiling)) ppm; let it decay before swimming.",
                blocksSwimming: true,
                requiresTesting: false
            )
        }

        return result(
            .sanitizerAdequacy,
            .pass,
            "FC \(format(freeChlorine)) ppm meets the CYA-adjusted observed-readiness minimum of \(format(minimum)) ppm.",
            blocksSwimming: false,
            requiresTesting: false
        )
    }

    private func pHGate(for state: NormalizedPoolState) -> SwimReadinessGateResult {
        guard let pH = state.pH else {
            return result(.pH, .unknown, "pH was not recorded.", blocksSwimming: true, requiresTesting: true)
        }

        // ChemistryPolicy owns the pH SWIM range (7.0–7.8 inclusive), which is wider than the 7.2–7.6
        // operating range. A pH in the swim range does not block even when it is a Recommended correction.
        if ChemistryPolicy.classify(.pH, value: pH, context: ChemistryPolicyContext()).blocksSwimming {
            return result(.pH, .fail, "pH \(format(pH)) is outside the Pool Side swim-readiness range (7.0–7.8).", blocksSwimming: true, requiresTesting: true)
        }

        return result(.pH, .pass, "pH \(format(pH)) is within the Pool Side swim-readiness range (7.0–7.8).", blocksSwimming: false, requiresTesting: false)
    }

    private func combinedChlorineGate(for state: NormalizedPoolState) -> SwimReadinessGateResult {
        guard let combinedChlorine = state.combinedChlorine else {
            return result(.combinedChlorine, .unknown, "Combined chlorine could not be evaluated from the available readings.", blocksSwimming: true, requiresTesting: true)
        }

        if state.odorReported == .reportedPresent {
            return result(.combinedChlorine, .fail, "Strong chlorine odor was reported, so the chloramine/problem-water context requires verification.", blocksSwimming: true, requiresTesting: true)
        }

        if combinedChlorine > combinedChlorineReadinessMaximum {
            return result(.combinedChlorine, .fail, "CC \(format(combinedChlorine)) ppm is above the current observed-readiness threshold of \(format(combinedChlorineReadinessMaximum)) ppm.", blocksSwimming: true, requiresTesting: true)
        }

        return result(.combinedChlorine, .pass, "CC \(format(combinedChlorine)) ppm is within the current observed-readiness threshold.", blocksSwimming: false, requiresTesting: false)
    }

    private func waterClarityGate(for state: NormalizedPoolState) -> SwimReadinessGateResult {
        switch state.normalizedWaterClarity {
        case .clear:
            return result(.waterClarity, .pass, "Water clarity was explicitly clear.", blocksSwimming: false, requiresTesting: false)
        case .cloudy:
            return result(.waterClarity, .fail, "Water was reported cloudy.", blocksSwimming: true, requiresTesting: false)
        case .cannotTell:
            return result(.waterClarity, .unknown, "The user could not determine water clarity.", blocksSwimming: true, requiresTesting: false)
        case .notRecorded, .unknown:
            return result(.waterClarity, .unknown, "Water clarity was not recorded.", blocksSwimming: true, requiresTesting: false)
        }
    }

    private func visibleAlgaeGate(for state: NormalizedPoolState) -> SwimReadinessGateResult {
        switch state.normalizedVisibleAlgae {
        case .absent:
            return result(.visibleAlgae, .pass, "Visible algae was explicitly reported absent.", blocksSwimming: false, requiresTesting: false)
        case .present:
            return result(.visibleAlgae, .fail, "Visible algae was reported present.", blocksSwimming: true, requiresTesting: false)
        case .cannotTell:
            return result(.visibleAlgae, .unknown, "The user could not determine whether algae was visible.", blocksSwimming: true, requiresTesting: false)
        case .notRecorded, .unknown:
            return result(.visibleAlgae, .unknown, "Visible algae was not recorded.", blocksSwimming: true, requiresTesting: false)
        }
    }

    private func testFreshnessGate(for state: NormalizedPoolState) -> SwimReadinessGateResult {
        if state.ageInMinutes > readinessFreshnessThresholdMinutes {
            return result(
                .testFreshness,
                .fail,
                "The latest test is \(state.ageInMinutes) minutes old, beyond the provisional observed-readiness freshness policy.",
                blocksSwimming: true,
                requiresTesting: true
            )
        }

        return result(.testFreshness, .pass, "The latest test is fresh enough for observed readiness evaluation.", blocksSwimming: false, requiresTesting: false)
    }

    private func treatmentCompletionGate(
        for state: NormalizedPoolState,
        treatmentContext: V2TreatmentAwareContext?
    ) -> SwimReadinessGateResult {
        if let treatmentContext {
            if treatmentContext.hasUnknownReentryRequirement {
                return result(
                    .treatmentCompletion,
                    .unknown,
                    "A pending swim-blocking treatment has unknown completion or re-entry requirements.",
                    blocksSwimming: true,
                    requiresTesting: false
                )
            }

            if treatmentContext.hasSwimBlockingActiveTreatment {
                return result(
                    .treatmentCompletion,
                    .fail,
                    "A v2 swim-blocking treatment is planned but not completed.",
                    blocksSwimming: true,
                    requiresTesting: false
                )
            }

            if treatmentContext.hasCompletedWaitingTreatment {
                return result(
                    .treatmentCompletion,
                    .fail,
                    "A completed treatment is still inside its known circulation/re-entry window.",
                    blocksSwimming: true,
                    requiresTesting: false
                )
            }

            if treatmentContext.hasCompletedVerificationRequiredTreatment {
                return result(
                    .treatmentCompletion,
                    .fail,
                    "A completed treatment requires verification before swimming.",
                    blocksSwimming: true,
                    requiresTesting: true
                )
            }

            return result(
                .treatmentCompletion,
                .pass,
                "No v2 swim-blocking treatment completion hold is active.",
                blocksSwimming: false,
                requiresTesting: false
            )
        }

        guard state.activeTreatmentCount > 0 else {
            return result(.treatmentCompletion, .pass, "No active treatment steps are recorded for the current test.", blocksSwimming: false, requiresTesting: false)
        }

        return result(
            .treatmentCompletion,
            .unknown,
            "There are \(state.activeTreatmentCount) active treatment step(s), and v2 treatment swim-blocking classification is not implemented yet.",
            blocksSwimming: true,
            requiresTesting: false
        )
    }

    private func circulationGate(
        for state: NormalizedPoolState,
        treatmentContext: V2TreatmentAwareContext?
    ) -> SwimReadinessGateResult {
        if let treatmentContext {
            if treatmentContext.hasCompletedWaitingTreatment {
                return result(
                    .circulation,
                    .unknown,
                    "A treatment wait is active; elapsed time is predictive because pump/circulation confirmation is not persisted.",
                    blocksSwimming: false,
                    requiresTesting: false
                )
            }

            if treatmentContext.hasUnknownReentryRequirement {
                return result(
                    .circulation,
                    .unknown,
                    "Circulation requirements are unknown for a pending swim-blocking treatment.",
                    blocksSwimming: true,
                    requiresTesting: false
                )
            }

            if treatmentContext.hasSwimBlockingActiveTreatment {
                return result(
                    .circulation,
                    .notApplicable,
                    "Circulation timing has not started because the swim-blocking treatment is not completed.",
                    blocksSwimming: false,
                    requiresTesting: false
                )
            }

            return result(.circulation, .notApplicable, "No current v2 treatment context requires circulation evaluation.", blocksSwimming: false, requiresTesting: false)
        }

        guard state.activeTreatmentCount > 0 else {
            return result(.circulation, .notApplicable, "No active treatment currently requires circulation evaluation in observed v2.", blocksSwimming: false, requiresTesting: false)
        }

        switch state.circulationStatus {
        case .running:
            return result(.circulation, .pass, "Circulation was reported running for an active treatment context.", blocksSwimming: false, requiresTesting: false)
        case .stopped:
            return result(.circulation, .fail, "Circulation was reported stopped while active treatment work remains.", blocksSwimming: true, requiresTesting: false)
        case .unknown, .notRecorded:
            return result(.circulation, .unknown, "Circulation status is unavailable while active treatment work remains.", blocksSwimming: true, requiresTesting: false)
        }
    }

    private func productReentryGate(
        for state: NormalizedPoolState,
        treatmentContext: V2TreatmentAwareContext?
    ) -> SwimReadinessGateResult {
        if let treatmentContext {
            if treatmentContext.hasUnknownReentryRequirement {
                return result(
                    .productReentry,
                    .unknown,
                    "A swim-blocking treatment has no known v2 re-entry/wait metadata.",
                    blocksSwimming: true,
                    requiresTesting: false
                )
            }

            if treatmentContext.hasCompletedWaitingTreatment {
                return result(
                    .productReentry,
                    .fail,
                    "A known treatment re-entry/circulation window is still active.",
                    blocksSwimming: true,
                    requiresTesting: false
                )
            }

            return result(.productReentry, .notApplicable, "No current product re-entry restriction is active in v2 treatment context.", blocksSwimming: false, requiresTesting: false)
        }

        guard state.activeTreatmentCount > 0 else {
            return result(.productReentry, .notApplicable, "No active treatment currently creates a known product re-entry restriction in observed v2.", blocksSwimming: false, requiresTesting: false)
        }

        return result(
            .productReentry,
            .unknown,
            "Product-label re-entry requirements are not available for active treatment work in this v2 slice.",
            blocksSwimming: true,
            requiresTesting: false
        )
    }

    private func result(
        _ identifier: SwimReadinessGateIdentifier,
        _ state: SwimReadinessGateState,
        _ reason: String,
        blocksSwimming: Bool,
        requiresTesting: Bool
    ) -> SwimReadinessGateResult {
        SwimReadinessGateResult(
            identifier: identifier,
            state: state,
            reason: reason,
            blocksSwimming: blocksSwimming,
            requiresTesting: requiresTesting
        )
    }

    private func format(_ value: Double) -> String {
        value == value.rounded()
            ? "\(Int(value))"
            : String(format: "%.1f", value)
    }
}
