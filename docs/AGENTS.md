# Pool Side — Agent Working Guide

This file tells coding agents how to work safely in the Pool Side repository. It is a navigation and guardrail document, not a replacement for the domain or architecture documentation.

## Read First

Before changing production behavior:

- Read `Docs/Architecture.md` for system ownership, data flow, persistence, workflow, and UI boundaries.
- Read `Docs/Pool Intelligence Engine.md` for pool-chemistry behavior, treatment philosophy, readiness, scoring, and domain rationale.
- When code and documentation appear to disagree, inspect the production tests and current implementation before changing behavior. Report the conflict rather than silently choosing one.

## Source-of-Truth Map

Use the existing authority for each question. Do not re-derive these rules in Views or convenience helpers.

| Question | Canonical authority |
|---|---|
| What chemistry state is this reading in? | `ChemistryPolicy` / `ParameterClassification` |
| How severe is the chemistry state? | `ChemistrySeverity` produced by `ChemistryPolicy` |
| What treatment urgency should the user see? | Canonical urgency derived from policy classification/severity |
| Can the user swim? | Swimability V2 only |
| What treatment should be generated? | `ChemistryEngine` / rule-based treatment generation consuming `ChemistryPolicy` |
| How much chemical is theoretically required? | `ChemicalDoseCalculator` |
| How much should be applied now? | `TreatmentApplicationPolicy` + treatment staging |
| How healthy is the pool overall? | Canonical Pool Score assessment API |
| What workflow step comes next? | `TreatmentWorkflowEngine` |
| When is targeted verification required? | Focused-Check workflow policy |
| When is the next full test due? | `NextTestRecommendationEngine` |
| What owns targeted reminders? | The relevant workflow step / Check notification lifecycle |
| What should External Review show? | `ExternalReviewExportBuilder` consuming canonical outputs |

## Core Architectural Rules

1. **ChemistryPolicy is the chemistry-classification authority.**
   - Do not duplicate ranges, thresholds, severity, or operating targets in SwiftUI or another service.
   - Parameter bands are resolvers where context matters (CYA, sanitizer, surface, configured salt range, measurement method, etc.).

2. **Swimability V2 is the only production swim-readiness authority.**
   - Pool Score is not a swim-safety score.
   - Treatment urgency is not a swim gate.
   - A parameter may need attention without being an emergency, and non-swim parameters may be urgent for pool/equipment protection without blocking swimming.

3. **Severity, urgency, and swim readiness are separate concepts.**
   - `Act Now`: significant risk or potentially damaging condition; immediate corrective action.
   - `Needs Attention`: below a safety/protection threshold or approaching unsafe conditions; correct before swimming/normal operation when applicable, but not an emergency.
   - `Recommended`: optimization/maintenance while the relevant safety goals are already met.
   - Views consume the canonical resolved urgency; they do not infer it from raw chemistry.

4. **Use the existing semantic status assets.**
   - Act Now → `StatusCritical`
   - Needs Attention → `StatusOffRange`
   - Recommended → `StatusSlight`
   - Ideal → `StatusIdeal`
   - Verification / Check → `StatusTesting`
   - Do not add a new color token unless the product design explicitly requires it.

5. **Treatment plans are ordered workflows/timelines.**
   - Render steps in the order the user is supposed to perform them.
   - Chemical actions, required waits, and required focused verification must respect dependency/timing rules.
   - Do not make the user mentally reorder the plan.

6. **Focused Checks are evidence collection, not chemical treatments.**
   - A purple Check is created only when new evidence is required for safety, before a required subsequent treatment, before repeating a staged correction, or for pool/equipment protection.
   - Do not create a Check merely because a treatment exists.
   - Recommended optimization on already-safe water should normally close into the next routine test rather than generate unnecessary verification work.

7. **A Focused Check cannot auto-complete.**
   - Completion is allowed only from saved valid focused measurements or qualifying full-test supersession.
   - Parent treatment completion, timers, notification delivery, notification opening, app relaunch, or merely opening the Check UI must never complete it.
   - Completed/superseded Checks cannot be skipped/restored.

8. **Check-owned notification rules must remain intact.**
   - Required Check reminders belong to the Check.
   - Completing a treatment with a wait but no required Check may schedule a neutral wait-complete reminder.
   - Skipping a treatment schedules no wait reminder.
   - Timer completion alone must never assert that swimming is safe; consult Swimability V2 and product-label requirements.

9. **Routine full testing and focused verification are separate.**
   - Do not ask the user to perform a focused retest and then immediately perform a redundant full test.
   - A qualifying full test may supersede an outstanding Check only under the established timing/evidence rules.

10. **Never carry a theoretical remainder forward.**
    - A staged treatment is followed by new evidence when required.
    - Any subsequent correction is freshly recalculated from the new measured value.
    - Never tell the user to “add the rest,” “finish the remaining dose,” or otherwise reuse an unmeasured theoretical remainder.

11. **Separate total calculated correction from safe current application.**
    - Preserve total demand for explanation/audit.
    - Apply the existing treatment/application policy for the current dose.
    - Do not invent a new staging cap without an approved domain or product-label basis.

12. **Product-label-first application guidance.**
    - Pool Side owns dose, sequencing, workflow timing, staging, and verification timing.
    - The product label owns PPE, mixing, physical application method, circulation/re-entry instructions, brushing, and manufacturer-specific warnings.
    - Do not universally prescribe pre-dissolving, broadcasting, pouring location, brushing, or similar handling unless grounded in the exact supported product label.

13. **Watchlist items are observations, not treatments.**
    - They must never enter repeat-treatment suppression/deferral logic.
    - Avoid redundant guidance already addressed by an active treatment.
    - Prioritize actionable/new information; de-prioritize or suppress stale repeated advice.
    - Contextual guidance should reflect reported behavior (for example, cover-open behavior).

14. **Pool Score is evidence-based and policy-aligned.**
    - Use the canonical score assessment entry point.
    - Score drivers should use canonical policy/severity wording.
    - Completing a treatment without new measured evidence must not improve the score.
    - Focused Checks update only the parameters actually measured.
    - Avoid `PoolConfiguration.current` or another hidden global when explicit configuration is available.

15. **Mixed-age evidence is intentional.**
    - Each parameter carries its own measurement timestamp/evidence age.
    - A focused FC/CC Check must not refresh pH, TA, CH, CYA, or salt evidence.
    - Preserve measurement-resolution behavior; do not imply precision the test method cannot observe.

16. **Deletion/edit/rebuild must use the safe orchestration path.**
    - Cancel obsolete treatment/Check/routine notifications.
    - Repair `checkResultTestID` and supersession links.
    - Rebuild affected later workflows from surviving chronological evidence.
    - Deleted tests should have zero influence on future recommendations.
    - Preserve valid unaffected completed/skipped history.

17. **Product preference changes may reprice unfinished generated work, not history.**
    - Never rewrite completed/skipped historical treatment products.
    - Preserve workflow IDs/dependencies where the existing repricing path expects them.

18. **External Review is a diagnostic mirror, not another authority.**
    - Separate treatment actions, focused Checks, Watchlist, V2 readiness, Pool Score, deferrals, and routine testing.
    - Do not model Checks as products/doses.
    - Do not re-derive chemistry or swim readiness inside export code.

## Current Chemistry/Policy Guardrails

Do not change these without explicit product/domain approval and corresponding tests:

- pH operating range: 7.2–7.6.
- pH swim-readiness range: 7.0–7.8 inclusive.
- pH urgency bands: <6.8 Act Now; 6.8–<7.0 Needs Attention; >7.8–8.0 Needs Attention; >8.0 Act Now.
- FC with CYA present uses a 2 ppm swim-readiness floor, 2–4 ppm operating band, 3 ppm treatment target, and 3–4 ppm no-action range. FC <1 ppm is Act Now; 1–<2 is Needs Attention; 2–<3 is Recommended; CYA is managed independently.
- FC high severity uses an explicit severe-high resolver, not `shockLevel`; current severe-high policy is `max(15 ppm, reentryCeiling)`.
- CC ≤0.5 is readiness-acceptable; >0.5–1.0 Needs Attention; >1.0 Act Now, subject to measurement resolution and visual/odor escalation.
- TA, CH, CYA, and salt do not directly block swimming; they may still become urgent for pool/surface/equipment protection.
- Readiness evidence freshness is 24 hours unless product policy is explicitly changed.

## Testing Discipline

For every production change:

1. Run the smallest focused test suite that exercises the change.
2. Add boundary and regression tests for the behavior, not only the reported dogfood value.
3. Run `ScenarioValidationTests/testCompleteScenarioCatalog()` when chemistry/workflow behavior changes.
4. Run the full `Pool SideTests` suite before declaring completion.
5. Do not weaken safety, chemistry, workflow, persistence, notification, or readiness assertions merely to get green.

In this Codex environment, run automated tests with the Xcode MCP test runner against Xcode’s currently selected iOS Simulator. Do not depend on the developer’s physical iPhone. Direct `xcodebuild` simulator targeting may fail from the Codex shell because `CoreSimulatorService` is not reliably available there; do not modify signing, provisioning, or project settings to work around that.

- Automated `Pool SideTests` must run via the Xcode MCP runner against an **iOS Simulator** by default.
- **Never run the full test suite on the developer’s dogfooding iPhone** — on-device tests share the app’s `UserDefaults.standard`.
- Tests that touch app preferences must use the isolated test defaults store (`PoolConfiguration.defaultsStore`, which auto-resolves to an isolated suite under XCTest) and must never read or mutate the production `UserDefaults.standard["poolConfiguration"]`.

Classify failures when behavior changes materially:

- **A** — implementation regression introduced by this change → fix production code.
- **B** — expectation legitimately superseded by an approved product/policy change → update with rationale.
- **C** — pre-existing defect exposed by the work → fix when safely in scope; otherwise report it.
- **D** — genuine unresolved product/domain decision → stop and ask rather than inventing policy.

## Agent Working Style

- Prefer narrow, independently testable changes over broad rewrites.
- Read only the subsystems relevant to the requested task before expanding scope.
- Reuse existing canonical helpers/types instead of introducing parallel models.
- Do not edit `project.pbxproj` while the Xcode project is open unless the user explicitly requests it and understands the risk.
- Do not add new production files when an existing appropriate target file is preferable solely to avoid target-membership problems; architectural cleanliness still matters, so report the tradeoff if relevant.
- Preserve user-visible completed history unless the approved rebuild/deletion rules require otherwise.
- If a requested change conflicts with these guardrails or the source-of-truth docs, stop and identify the conflict.
- Keep final reports concise: files changed, behavior before/after, tests added/updated, failures/classification, full-suite result, and any unresolved decision.

## Documentation Responsibilities

When an approved change alters a source-of-truth behavior, update the relevant documentation after production code and tests are green:

- `Docs/Architecture.md` for ownership/data-flow/lifecycle changes.
- `Docs/Pool Intelligence Engine.md` for chemistry, treatment, readiness, scoring, or domain-policy changes.
- Update this `AGENTS.md` only when the agent-working contract or source-of-truth map itself changes.

Do not let `AGENTS.md` become a duplicate copy of the domain documentation. It should remain a concise map and set of modification guardrails.
