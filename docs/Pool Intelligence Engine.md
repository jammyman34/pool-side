# Pool Intelligence Engine

_Last updated: August 2026_

## Purpose

The Pool Intelligence Engine is the decision system behind Pool Side.

Its purpose is not merely to score a single water test or calculate chemical doses.

Its purpose is to answer four related questions:

1. What condition is the pool currently in?
2. Is it currently safe to swim?
3. What, if anything, should the user do?
4. What evidence should be collected next?

The engine reasons from:

- current chemistry
- parameter-specific evidence age
- historical chemistry
- recent treatments
- treatment completion state
- focused verification results
- pool conditions
- visual observations
- pool configuration
- product preferences
- confidence in available evidence

The engine should avoid unnecessary intervention while remaining conservative whenever swimming safety or irreversible chemical additions are involved.

---

# Core Decision Model

Pool Side deliberately separates several concepts that should not be conflated.

## Pool Score

Represents overall pool health.

## Swimability

Represents whether available evidence supports swimming now.

## Treatment Plan

Represents actions recommended to improve or maintain the pool.

## Treatment Workflow

Represents the safe order in which treatments and verification should occur.

## Next Full Pool Test

Represents when the user should perform the next normal complete chemistry test.

These systems inform one another but answer different questions.

---

# Chemistry Classification

Underneath all of these systems is one shared classification authority.

A single reading — its operating band, its action state (from clearly-low through in-range to clearly-high), whether it blocks swimming, and what disposition it warrants — is classified in exactly one place. That classification is:

- sanitizer-aware (alkalinity is judged differently for hypochlorite versus acidic/stabilized chlorine)
- surface-aware (calcium is judged differently by pool surface)
- configuration-aware (salt ranges follow the pool's generator, not a universal assumption)

Every downstream system — Pool Score, Swimability, treatment generation, and the workflow — consumes this one classification rather than re-deriving its own ranges. This is what keeps the score, the swim gates, and the treatment plan from disagreeing about whether the same value is acceptable.

---

# Design Philosophy

## 1. Safety First

Swimming readiness is controlled by explicit safety gates rather than Pool Score.

Important concerns include:

- inadequate sanitizer
- unsafe pH
- elevated combined chlorine
- cloudy water
- visible algae
- stale safety evidence
- unfinished swim-blocking treatments
- treatment circulation requirements
- product re-entry restrictions
- required post-treatment verification

Historical stability cannot override a current failed safety gate.

---

## 2. Pool Score Is Not Swimability

A pool can have a reasonably good overall score while still failing a swimming-readiness requirement.

Conversely, a pool may be safe to swim while having maintenance issues that should eventually be corrected.

This distinction is intentional.

Pool Score communicates overall condition.

Swimability communicates readiness to swim.

---

## 3. Stable Pools Should Not Be Over-Treated

Not every deviation from an ideal textbook range requires chemical correction.

Examples may include:

- elevated TA with acceptable pH
- moderately elevated CYA
- somewhat elevated calcium without scaling evidence
- small sanitizer deviations that remain above the safety minimum

When appropriate, the engine should favor:

- monitoring
- optional maintenance
- future testing

over unnecessary treatment.

---

## 4. History Matters

The newest test is evidence, not the entire truth.

History may affect:

- chlorine-loss interpretation
- repeated correction failures
- pH trend interpretation
- treatment suppression
- confidence
- stability assessment
- treatment effectiveness

Example:

An isolated pH of 8.0 may be treated differently from pH 8.0 following a sustained rising trend.

The same current chemistry can therefore produce different recommendations when historical evidence differs.

---

## 5. Evidence Has Age

Not all chemistry values necessarily come from the same test time.

After a focused treatment verification, some parameters may be newly measured while others remain older.

The engine therefore tracks evidence freshness by parameter.

Example:

10:00 AM full test:
FC, CC, pH, TA, CH, CYA

11:00 AM focused chlorine verification:
FC, CC only

At 11:00 AM:

- FC and CC have 11:00 AM evidence
- pH, TA, CH, and CYA still have 10:00 AM evidence

The engine must never treat unmeasured chemistry as newly observed.

---

# Effective Chemistry State

Focused verification creates a mixed-age chemistry state.

The engine constructs an effective state from the newest valid evidence available for each parameter.

This allows treatment decisions to use newly verified chemistry without discarding still-useful prior measurements.

It also prevents focused checks from bypassing freshness rules.

The effective state should always preserve provenance:

- what was measured
- when it was measured
- what remained inherited from earlier evidence

---

# Context Matters

Chemistry changes for reasons.

Pool Conditions help explain those changes.

Relevant conditions include:

- swimmer load
- pet swimming
- rain
- cover usage
- organic debris
- skimming
- brushing
- robot cleaning
- water replacement
- backwashing

Context should influence interpretation without replacing measured chemistry.

---

# Unknown Is Different From None

Where supported:

Unknown means:

"The user did not provide this information."

None means:

"The user explicitly reported that this did not occur."

These are different evidence states.

Explicit absence can increase confidence.

Unknown information can reduce confidence.

Unknown visual safety evidence may also prevent the system from asserting Ready to Swim.

---

# Recommendation Confidence

Confidence describes how strongly the available evidence supports the recommendation.

Confidence may increase when:

- chemistry is complete
- relevant evidence is fresh
- visual observations are explicit
- pool conditions are known
- useful history exists
- treatment history is available

Confidence may decrease when:

- history is limited
- contextual information is unknown
- observations are uncertain
- evidence is old

Confidence should affect communication and aggressiveness where appropriate.

It must never weaken a safety requirement.

---

# Pool Score

Pool Score represents overall pool condition.

Inputs may include:

- chemistry
- visual observations
- sanitizer state
- historical behavior
- contextual penalties
- safety floors

The canonical user-facing grade bands are:

90–100: Great
75–89: Good
60–74: Alright
40–59: Not Great
Below 40: Real Bad

These grade labels come from a single source (`ChemistryEngine.scoreGrade`) shared by the Dashboard, completed rows, and export, so the same score always reads the same way everywhere.

Production reads the score as a structured assessment (score, grade, and canonical drivers) rather than a bare number. Whether an individual reading counts as "in range" for scoring is decided by ChemistryPolicy — the score does not carry its own separate ranges. Score drivers are named by their actual policy action state (for example "above operating range" vs "critically high") rather than raw-value guesses.

The score is intentionally separate from swimming readiness. It communicates maintenance/health, never permission to swim.

---

# Swimability V2

Swimability V2 evaluates whether the evidence currently supports swimming.

Core gates include:

## Sanitizer Adequacy

FC is evaluated relative to CYA rather than against a single universal FC number.

The engine distinguishes between:

- minimum observed-readiness sanitizer
- preferred operating target
- maintenance target

Being below the preferred target does not automatically mean the pool is unsafe.

Being below the readiness minimum does.

---

## pH

pH must remain inside the observed-readiness safety range.

A pH value may be safe enough for swimming while still producing a monitoring recommendation.

Treatment-generation thresholds and swimming-readiness thresholds are therefore not necessarily identical.

---

## Combined Chlorine

Elevated CC can indicate active sanitizer demand or contamination and may require correction and verification.

---

## Water Clarity

Cloudy water prevents Ready to Swim.

Clarity is treated as safety evidence, not merely cosmetic quality.

---

## Visible Algae

Visible algae prevents Ready to Swim.

---

## Evidence Freshness

Old chemistry cannot indefinitely support a Ready to Swim determination.

When critical evidence exceeds the freshness policy, new testing is required.

Focused verification refreshes only the parameters actually tested.

---

## Treatment Completion

Required swim-blocking treatment activity can prevent Ready to Swim until the required workflow has been completed.

---

## Circulation and Product Re-entry

Some treatments require circulation or waiting before swimming.

These requirements are independent of whether the original chemistry problem has theoretically been corrected.

---

## Verification

Some corrective treatments require measured confirmation.

In these cases, completing the chemical addition alone is insufficient.

The pool may move through states such as:

Do Not Swim
→ treatment completed
→ circulation / waiting
→ Test Before Swimming
→ focused verification
→ Ready to Swim

---

# Treatment Philosophy

Treatment recommendations follow this priority:

1. Swimming safety
2. Correct the underlying chemistry problem
3. Avoid conflicting treatments
4. Avoid unnecessary chemicals
5. Limit irreversible or aggressive additions
6. Verify before repeating treatment
7. Preserve understandable sequencing

The engine should recommend only actions that are justified by current evidence.

---

# Chlorine and CYA

FC requirements are interpreted in relation to CYA.

Higher CYA requires higher operating FC.

The engine distinguishes between:

- unsafe sanitizer deficiency
- maintenance-level deficiency
- acceptable FC
- recovery conditions

A maintenance top-off can therefore be optional while a lower FC value at the same CYA may require corrective treatment and post-treatment verification.

---

# Optional Chlorine Maintenance

When FC is above the readiness minimum but below the preferred operating target, the engine may generate an optional chlorine top-off.

An optional top-off:

- does not itself block swimming
- does not create mandatory verification
- may offer an optional FC/CC Check
- should not transform a healthy pool into a mandatory treatment workflow

Completing optional maintenance must not incorrectly extend the next routine testing interval.

The routine follow-up remains based on the active treatment-plan cadence rather than falling immediately to the stable-pool cadence.

---

# Corrective Chlorine

When FC is below the readiness requirement or CC requires correction, chlorine treatment may become swim-blocking.

Corrective chlorine generally requires:

- treatment
- circulation
- focused FC/CC verification

The verification uses new measured FC and CC evidence.

If the new result remains inadequate, the engine reassesses and may generate another corrective treatment.

---

# Recovery Chlorine

Recovery conditions such as algae, cloudy water, and significant sanitizer problems may require more aggressive chlorine correction.

The engine should avoid stabilized dry chlorine when doing so would unnecessarily increase CYA.

Nonchemical recovery actions, such as continued filtration, may appear alongside chemical treatment.

---

# pH Treatment

pH treatment should distinguish between:

- unsafe pH
- acceptable but nonideal pH
- historical pH trend
- alkalinity-driven drift
- scaling risk

The pH operating bands come from ChemistryPolicy: roughly 7.2–7.6 is in range, 7.7–7.8 is above the operating range but still swimmable, and 7.9 and above is treated as clearly high (and swim-blocking at the extreme). Corresponding low bands mirror this.

Clearly-high pH (the actNowHigh band) generates corrective acid on the current reading alone; it does not wait for a rising-history confirmation.

The nuance applies at the boundary. In the recommendedHigh band — above the operating range but not yet clearly high — the engine avoids reflexively adding acid at every isolated reading and instead weighs supporting evidence such as:

- rising pH history
- sustained high pH
- scaling evidence

This reduces unnecessary acid treatment for pools that are only slightly high, without deferring correction when pH is genuinely high.

---

# Acid Application Policy

Acid correction may be staged.

The engine distinguishes:

- total calculated acid demand
- safe current application

If total demand exceeds the conservative application amount, the engine recommends only the current dose.

After circulation, the user performs a focused pH Check.

The engine then reassesses from the new measured pH before recommending additional acid.

The original calculated total must not be interpreted as an instruction to add the entire amount at once.

---

# pH Increase

Unsafe low pH may generate a pH increaser such as:

- soda ash
- borax

Dose behavior may consider alkalinity.

The user should verify pH after the appropriate circulation period before additional adjustment.

---

# Total Alkalinity

TA should not be treated independently of pH.

Elevated TA with acceptable pH often becomes a watch condition rather than immediate acid treatment.

Low TA may generate alkalinity increaser.

When pH and TA problems coexist, treatment sequencing should avoid chemical conflict.

Examples:

- high pH + high TA may use one acid strategy
- high pH + low TA should avoid immediately fighting acid with baking soda
- low pH + low TA may permit compatible raising treatments

The engine should solve the highest-priority chemistry problem without creating an acid/base treatment loop.

---

# Cyanuric Acid

CYA affects both sanitizer requirements and treatment selection.

Low CYA may justify stabilizer.

High CYA should suppress additional stabilizer.

Very high CYA may justify partial water replacement.

High CYA plus low FC still requires sanitizer readiness to be addressed.

Stabilizer treatment should be verified after the appropriate delay before additional stabilizer is recommended.

---

# Calcium Hardness

Low calcium in applicable pool surfaces may generate calcium increaser.

High calcium alone does not automatically make the pool unsafe to swim.

When high calcium combines with high pH or other scaling evidence, the engine may produce scaling-risk guidance.

Calcium additions should be followed by delayed verification before repeating the dose.

---

# Salt Pools

Salt systems require separate interpretation.

The engine distinguishes between:

- adequate salt
- low salt requiring pool salt
- chlorine generation behavior
- urgent sanitizer deficiency

A salt chlorine generator action is treated as a nonchemical action rather than a conventional chemical dose.

Salt-system status must not override sanitizer safety.

---

# Chlorine Demand

Pool Conditions may contribute to a chlorine-demand model.

Demand factors can include:

- swimmers
- pets
- debris
- cover behavior
- rain
- maintenance activity

Demand can help explain chlorine consumption and influence recommendation context.

Demand alone should not trigger shock treatment.

Measured chemistry remains authoritative.

---

# Water Dilution

Rain and water replacement may help explain changes in:

- CYA
- calcium
- alkalinity
- salt

When dilution provides a plausible explanation, the engine should favor confirmation before making large additions where appropriate.

---

# Product Selection

User product preferences should be respected where chemically appropriate.

However, preference must not override treatment safety or application suitability.

Examples:

- liquid chlorine may be preferred for immediate correction even when a stabilized dry chlorine product is selected globally
- recovery treatment should avoid unnecessary stabilizer
- trichlor tablets should not be represented as a precise immediate ppm correction when their delivery characteristics do not support that model

Product preference is an input, not an unconditional command.

---

# Treatment Magnitude

Dose calculations must be protected against unit and magnitude errors.

Validation should guard against:

- 10× conversion errors
- gallons versus quarts confusion
- liquid versus weight units
- pounds versus ounces
- concentration mismatches
- unrealistic additions

Representative-volume tests should verify dose scaling.

---

# Treatment Workflow

Treatment recommendations are not merely a list.

They form an ordered workflow.

The workflow may contain:

Treatment
→ Check
→ Treatment
→ Check

Only the current actionable step should be active.

Future steps remain visible so the user understands what may happen next.

The sequence should reflect chemistry and safety dependencies.

---

# Focused Checks

A Check is treatment-specific verification.

Examples:

Chlorine:
Check FC & CC

Acid:
Check pH

pH increaser:
Check pH

Alkalinity:
Check TA

Stabilizer:
Check CYA

Calcium:
Check CH

Focused Checks are not equivalent to a full routine pool test.

Their purpose is to answer:

"Did this treatment produce enough evidence to decide what happens next?"

---

# Focused Check Reassessment

When focused results are saved, the engine reassesses the remaining treatment plan.

The rules are:

- completed prior steps remain
- skipped prior steps remain
- the completed Check becomes new evidence
- unfinished generated future steps are invalidated
- the effective chemistry state is rebuilt
- the production recommendation engine runs again
- future workflow steps are regenerated

This prevents the application from blindly following recommendations that were generated before newer chemistry evidence existed.

---

# Check Completion and Integrity

A Check reaches a completed state through only one path: the user enters its measured result and saves it. There is deliberately no automatic completion.

In particular, logging a later full pool test does not complete a pending Check, even if that test measures the Check's parameter after the Check is due. A full test does not prove the user actually performed the treatment's follow-up measurement, so the Check remains pending until the user checks it. The Check's reminder is a nudge to perform that measurement — it never completes the Check on its own.

Because a Check carries verification evidence, the engine defends its state:

- A generic "mark complete" does not complete a Check.
- The passage of the Check's due time does not complete it.
- A completed or inapplicable Check rejects skip, restore, and uncomplete. The rejection is typed so the interface and the underlying logic agree on why the action was refused.

The purpose is to ensure a Check is only ever completed by a measurement the user actually took.

---

# Skipped Treatments

Skipping means:

"I am not doing this instance of this recommendation."

It does not mean:

"Never recommend this treatment again."

If later evidence still supports the treatment, the engine may generate a new instance.

This is necessary because the treatment plan should represent what the pool currently needs.

---

# Next Full Pool Test

Focused treatment verification and routine testing are separate concepts.

The global Next Pool Test recommendation always refers to the next complete pool test.

Examples:

Stable pool:
Next full pool test in approximately the normal stable cadence.

Active maintenance plan:
Next full pool test may occur sooner to confirm overall response.

Focused treatment verification:
Appears as a Check step in the treatment workflow and does not replace the global routine test.

The user should never need to infer whether "Next Pool Test" means FC-only, pH-only, or a complete chemistry panel.

---

# Why This Plan

Every treatment plan should explain itself.

Why This Plan may summarize:

- overall assessment
- recommendation confidence
- important chemistry
- historical factors
- contextual factors
- expected outcome
- intentionally suppressed treatments
- reasons for monitoring instead of treatment

The explanation should make both action and restraint understandable.

"No treatment" can be an intentional engine decision.

---

# Watchlist

Watchlist items identify conditions worth monitoring that do not currently justify treatment.

Examples include:

- pH drift risk from elevated TA
- manageable elevated CYA
- scaling risk
- cover-management concerns
- sanitizer operating-target concerns

Watchlist items should not be confused with required workflow steps.

---

# Scenario Validation

The Pool Intelligence Engine is protected by a production-oriented scenario catalog.

Validation covers combinations and boundaries including:

- FC/CYA readiness
- combined chlorine
- pH
- acid products
- pH increasers
- alkalinity
- calcium
- CYA
- salt
- dry chlorine
- trichlor behavior
- conflicting chemistry
- multiple treatments
- freshness
- uncertainty
- history
- volume scaling
- magnitude sanity
- treatment application policy
- Next Full Pool Test
- treatment workflow and verification

Scenario validation should exercise production logic rather than duplicate it.

Fixtures must faithfully represent the state that the production application would save.

---

# Failure Classification

When a scenario fails, determine why before modifying production code.

A. Production defect

The fixture accurately reproduces production state and production behavior is incorrect.

B. Fixture problem

The fixture does not faithfully reproduce the conditions the application would provide.

C. Stale expectation

Production behavior is correct but the test expects obsolete or incorrect behavior.

Only category A automatically justifies a production-engine change.

Passing tests are evidence of consistency, not proof that the chemistry policy itself is correct.

Real-world dogfooding remains important.

---

# Engine Principles

The engine should favor:

- measured evidence over assumptions
- fresh evidence over stale evidence
- trends over isolated readings where appropriate
- safety gates over aggregate scores
- minimal effective intervention
- verification before repeating treatment
- conservative application limits
- chemistry-aware sequencing
- explanation over opaque automation
- recomputation after new evidence
- deterministic behavior
- explicit uncertainty

The engine should not manufacture certainty from missing information.

---

# Open Limitations

Stated plainly so they are not mistaken for solved problems:

- There is no maintained product-label database. Product suitability and staged dosing are encoded in engine logic rather than looked up from real product concentrations. Calcium in particular has a single product (Calcium Chloride); the engine raises calcium and does not shop between calcium alternatives.
- Salt classification follows the configured generator range. A wrong configuration yields wrong classification.
- Weather is not yet an engine input. It is anticipated future intelligence, not a current factor in recommendations.
- Passing scenario tests demonstrate internal consistency, not that the underlying chemistry policy is correct for every real pool. Real-world dogfooding remains the check on the policy itself.

---

# Future Intelligence

Long-term intelligence can build on the current evidence model.

Potential future inputs include:

- weather
- water temperature
- UV exposure
- seasonal behavior
- historical FC consumption
- cover patterns
- treatment effectiveness
- testing cadence
- user behavior

This can eventually support:

- personalized chlorine-loss models
- predicted FC demand
- adaptive testing schedules
- treatment-effectiveness learning
- seasonal baselines
- pool-specific pH drift modeling
- smarter anomaly detection
- personalized Pool Personality

Personalization must not weaken established safety requirements.

The goal is not for Pool Side to become more aggressive or complicated.

The goal is for it to need fewer assumptions.

Over time, the engine should increasingly be able to say:

"This is what pools generally do."

"This is what your pool usually does."

"This is what your pool is doing differently today."

"And this is the smallest safe action supported by the evidence."