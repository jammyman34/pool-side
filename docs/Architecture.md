# Architecture

_Last updated: July 2026_

## Overview

The app is organized into several independent systems, each with a single responsibility.

```
Pool Test
    │
    ▼
Chemistry Engine
    │
    ├── Pool Score
    ├── Treatment Generation
    ├── Recommendation Confidence
    ├── Watchlist
    └── Why This Plan
            │
            ▼
      Treatment Plan UI
            │
            ▼
        External Review
```

Historical data feeds the engine at every stage.

---

# Core Components

## PoolTest

Represents one complete snapshot of the pool.

Contains:

- chemistry readings
- visual indicators
- pool conditions
- treatments
- notes
- overall score
- timestamp

Every recommendation begins with a PoolTest.

---

## PoolConfiguration

Represents long-term pool settings.

Examples include:

- pool volume
- pool type
- surface type
- chlorine preference
- test method
- robotic cleaner
- pets
- pool cover

Configuration should rarely change.

PoolTests should change frequently.

---

## PoolConditions

PoolConditions capture what happened **since the previous test log**.

Unlike chemistry, these are behavioral inputs.

Current fields include:

- swimming
- pet swimming
- rain
- cover open time
- debris
- skimmed
- vacuumed / robot cleaning
- brushing
- water added

Every field supports:

- Unknown
- None
- One or more meaningful values

Unknown is intentionally different from None.

Unknown lowers confidence.

None increases confidence.

---

# ChemistryEngine

The ChemistryEngine is the heart of the application.

Its responsibilities include:

- chemical evaluation
- status calculation
- pool score
- treatment generation
- watchlists
- recommendation confidence inputs
- trend analysis
- historical analysis

The engine should never contain UI logic.

---

# Historical Processing

The engine receives historical PoolTests through recentHistory.

History is used for:

- repeated chlorine failures
- rapid chlorine loss
- treatment suppression
- recommendation confidence
- trend detection
- historical stability

History should always be rebuilt from existing tests.

Deleted tests should never influence calculations.

---

# Pool Score

Pool Score is generated entirely by the ChemistryEngine.

Inputs include:

- chemistry
- visual indicators
- history
- pool conditions
- safety overrides

Outputs include:

- score
- floor logic
- penalties
- explanations

The score should represent overall pool health.

It is not a swimming safety score.

---

# Treatment Generation

Treatments are generated in several stages.

```
Chemical Evaluation
        │
        ▼
Rule Treatments
        │
        ▼
Validation
        │
        ▼
Suppression
        │
        ▼
Watchlists
        │
        ▼
Treatment Plan
```

Validation may:

- suppress unnecessary chemicals
- delay repeat treatments
- recommend confirmation testing
- convert actions into advisories

---

# Recommendation Confidence

Recommendation confidence estimates how trustworthy the generated treatment plan is.

Inputs include:

- chemistry completeness
- pool conditions
- visual indicators
- historical data
- treatment history

Confidence should never affect safety rules.

Instead it influences:

- Why This Plan
- summaries
- AI export
- user expectations

---

# Why This Plan

The Why This Plan card explains engine decisions.

It is generated after treatment recommendations.

Sections include:

- Summary
- Recommendation Confidence
- Key Factors
- Expected Outcome
- Next Test Timing

Its purpose is to explain recommendations rather than simply display them.

---

# AIService

AIService is intentionally separate from ChemistryEngine.

Responsibilities:

- prepare structured summaries
- prepare external review payloads
- generate recommendation confidence input
- assist future AI integrations

The ChemistryEngine remains the source of truth.

AI should explain recommendations, not replace them.

---

# Insights

Insights interpret historical behavior.

Current responsibilities:

- Pool Personality
- What's Changing
- Testing Rhythm
- Pool Score Trend
- Chemical Trends

Insights should focus on helping users understand patterns rather than today's chemistry.

---

# Dashboard

Dashboard presents the current pool state.

Responsibilities include:

- latest score
- latest chemistry
- current treatment plan
- recent history

Dashboard should not perform engine calculations directly.

It should display engine output.

---

# Data Flow

```
Pool Configuration
        │
        │
Pool Test
        │
        ▼
Pool Conditions
        │
        ▼
Chemistry Engine
        │
        ├── Pool Score
        ├── Treatments
        ├── Watchlist
        ├── Confidence
        └── Why Inputs
                │
                ▼
        Treatment Plan UI
                │
                ├── Why This Plan
                ├── Clipboard Export
                └── AI Review
```

---

# Deletion Rules

Deleting a PoolTest should:

- remove the test
- remove attached treatments
- cancel pending notifications
- rebuild chronological history
- regenerate newer treatment plans
- refresh dashboard
- refresh insights
- refresh trends
- refresh recommendation confidence

Deleted tests should behave as though they never existed.

---

# Design Rules

When adding new features:

## Ask:

> Does this belong in configuration, a test log, or the engine?

Configuration describes the pool.

PoolTests describe a point in time.

The engine interprets both.

---

## Avoid

- UI decisions inside ChemistryEngine
- duplicated calculations
- cached history
- hidden state
- magic numbers without explanation

---

## Prefer

- deterministic calculations
- recomputation over caching
- explainable recommendations
- conservative treatment advice
- modular helper functions
- small single-purpose methods

---

# Long-Term Vision

The architecture is designed so the application can evolve from:

> "Analyze today's pool test."

to

> "Understand my pool."

Future additions should continue strengthening historical learning rather than increasing the complexity of single-test analysis.

The ChemistryEngine should increasingly model each pool's unique behavior over time while remaining transparent, explainable, and conservative in its recommendations.
