# Pool Intelligence Engine

_Last updated: July 2026_

## Purpose

The goal of the Pool Intelligence Engine is **not** to score a single water test.

Its purpose is to act as a knowledgeable pool assistant that learns how a specific pool behaves over time and provides recommendations based on:

- Current chemistry
- Historical chemistry
- Recent treatments
- Pool conditions
- Visual observations
- User behavior
- Confidence in available data

The engine intentionally avoids overreacting to individual readings while remaining conservative whenever safety may be affected.

---

# Design Philosophy

The engine follows several principles.

## 1. Safety First

Unsafe water should never receive an artificially high score.

Situations such as:

- Very low sanitizer
- Extremely high or low pH
- Algae
- Cloudy water
- High combined chlorine
- Scaling risk

always override convenience or historical trends.

---

## 2. Stable Pools Should Not Be Punished

Many pools operate safely for long periods while slightly outside textbook ranges.

Examples include:

- TA around 150–170
- CYA around 60–70
- Slightly elevated calcium
- Minor FC fluctuations

If the pool is:

- clear
- stable
- historically healthy
- producing consistent results

the engine reduces penalties and favors monitoring over unnecessary chemical additions.

---

## 3. History Matters

The latest test is only one piece of information.

Recommendations are influenced by:

- recent chemistry
- completed treatments
- historical chlorine performance
- dilution events
- repeated failures
- historical stability

The same chemistry values can produce different recommendations depending on recent history.

---

## 4. Context Matters

Pool chemistry cannot be interpreted correctly without understanding what happened since the previous test.

The engine incorporates pool conditions such as:

- swimmer load
- pet swimming
- rain
- cover usage
- debris
- skimming
- brushing
- cleaning
- water replacement

These explain why chemistry changed instead of assuming the chemistry itself is the entire story.

---

## 5. Confidence Matters

Recommendations are assigned a confidence level.

Confidence increases when:

- complete chemistry exists
- pool conditions were logged
- visual indicators were recorded
- historical data exists
- treatments are known

Confidence decreases when important information is missing.

Lower confidence should encourage confirmation rather than aggressive treatment.

---

# Pool Score

Pool Score estimates the overall health of the pool.

It is **not** intended to determine whether swimming is safe.

The score combines:

- chemistry
- visual indicators
- sanitizer
- historical behavior
- contextual penalties
- safety overrides

Scores are intentionally conservative.

Approximate interpretation:

| Score | Meaning |
|--------|---------|
| 90–100 | Excellent |
| 80–89 | Healthy |
| 70–79 | Good with minor improvements |
| 60–69 | Needs attention |
| Below 60 | Significant issues |

---

# Historical Intelligence

The engine uses recent history to recognize patterns.

Examples include:

- repeated chlorine loss
- repeated failed chlorine corrections
- stable chemistry
- improving trends
- declining trends
- treatment effectiveness

Historical information is rebuilt whenever tests are deleted.

Deleted tests should have zero influence on future recommendations.

---

# Pool Conditions

Pool Conditions describe what happened since the previous test.

Unknown means:

> The user did not provide information.

None means:

> The user confirmed nothing occurred.

This distinction is intentional.

Unknown lowers recommendation confidence.

None increases confidence.

Current Pool Conditions include:

- Swimming
- Pet Swimming
- Rain
- Cover Open Time
- Organic Debris
- Skimmed
- Water Added
- Vacuumed / Robot Cleaning
- Pool Brushed

---

# Chlorine Demand

Pool Conditions are converted into a Chlorine Demand score.

Rather than creating individual rules for every situation, the engine estimates overall sanitizer demand.

Factors increasing demand include:

- swimmers
- pets
- debris
- cover closed
- rain
- poor maintenance

Factors reducing demand include:

- skimming
- vacuuming
- brushing
- robot cleaning

Higher demand may:

- increase FC target
- increase urgency
- explain chlorine loss

High demand alone should never trigger shocking the pool.

---

# Water Dilution

Rain and water replacement contribute to a Water Dilution score.

Possible effects include:

- reduced CYA
- reduced calcium
- reduced alkalinity
- reduced salt

The engine prefers monitoring and confirmation before recommending chemical additions when dilution provides a likely explanation.

---

# Treatment Philosophy

Treatments should solve problems without creating new ones.

The engine prefers:

1. Safety
2. Minimal intervention
3. Confirmation before irreversible additions
4. Monitoring when appropriate

Examples:

- Elevated TA with stable pH usually becomes a watch item.
- Slightly low chlorine in a healthy pool often becomes an optional top-off.
- Low CYA measured with test strips becomes a confirmation recommendation before stabilizer.

---

# Why This Plan

Every treatment plan should be explainable.

The "Why This Plan" section summarizes:

- overall assessment
- recommendation confidence
- important contributing factors
- expected outcome
- recommended retest timing

The goal is transparency rather than simply presenting chemical doses.

---

# Insights

Insights are intended to help users understand **their pool**, not just today's test.

Current sections include:

- Pool Personality
- What's Changing
- Testing Rhythm
- Pool Score Trend
- Chemical Trends

Future versions will expand these into long-term behavioral coaching.

---

# Engine Principles

The engine should always favor:

- evidence over assumptions
- trends over isolated readings
- explanation over automation
- conservative recommendations over aggressive chemical additions
- teaching users instead of simply telling them what to add

If uncertainty exists, reduce confidence instead of pretending certainty.

---

# Future Direction

Planned evolution includes:

- Personalized pool behavior modeling
- Seasonal learning
- Weather integration
- Water temperature integration
- UV exposure estimation
- Automatic chlorine consumption modeling
- Predictive treatment recommendations
- Smart testing reminders
- Adaptive testing cadence
- Historical effectiveness scoring for treatments
- User-specific pool personality profiles

The long-term vision is for the app to evolve from a pool testing application into a trusted pool management assistant that continuously learns from each pool's unique behavior.