# Grading Specification

Normative specification for grading solidity-function-audit skill output against ground truth.

---

## 1. Purpose

This document formally defines the algorithm used by `grade.sh` to score an audit run. It is the authoritative reference for interpreting grade.json output and for authoring GROUND_TRUTH.md fixtures.

---

## 2. Definitions

| Term | Definition |
|------|-----------|
| **TP** (True Positive) | A known vulnerability from GROUND_TRUTH.md that was matched to an INDEX.md finding |
| **FN** (False Negative) | A known vulnerability not matched to any INDEX.md finding |
| **FP** (False Positive) | An INDEX.md finding that matched a `known_safe` function and was not matched to any ground truth vulnerability |
| **Match** | A pairing between a ground truth vulnerability and an INDEX.md finding, established via location or fuzzy title (see §4) |
| **Severity Adjacency** | Two severities are adjacent if they differ by at most one level in the 5-level scale |

Severity levels (descending): CRITICAL(5) > HIGH(4) > MEDIUM(3) > LOW(2) > INFO(1).

Adjacent pairs: CRITICAL↔HIGH, HIGH↔MEDIUM, MEDIUM↔LOW, LOW↔INFO.
Non-adjacent (blocked): CRITICAL↔MEDIUM, HIGH↔LOW, etc.

---

## 3. Ground Truth Format

Each fixture contains a `GROUND_TRUTH.md` file with YAML frontmatter followed by a markdown description.

### Schema

```yaml
---
known_vulnerabilities:
  - id: V001                          # Unique identifier (V + zero-padded integer)
    severity: HIGH                    # CRITICAL | HIGH | MEDIUM | LOW | INFO
    title: "Reentrancy in withdraw"   # Human-readable title (used for fuzzy match)
    contract: Vault                   # Contract name (no .sol extension)
    function: withdraw                # Function name
    location: "Vault.sol:42"         # File:line (used for exact match)
    verification_expected: CONFIRMED  # CONFIRMED | REFUTED | LIKELY-FP | INCONCLUSIVE
known_safe:
  - contract: Vault
    function: deposit
---
```

### Field Reference

**known_vulnerabilities fields:**

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `id` | string | yes | Unique ID, format `V` + zero-padded integer (e.g. `V001`) |
| `severity` | enum | yes | Expected severity level |
| `title` | string | yes | Short vulnerability title for fuzzy matching |
| `contract` | string | yes | Contract name containing the vulnerability |
| `function` | string | yes | Function name containing the vulnerability |
| `location` | string | yes | Source location string (file:line); must appear in INDEX.md location column |
| `verification_expected` | enum | yes | Expected verification verdict |

**known_safe fields:**

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `contract` | string | yes | Contract name of a safe function |
| `function` | string | yes | Function known to be safe; findings here are scored as FP |

---

## 4. Finding Matching Algorithm

For each known vulnerability, `grade.sh` attempts to find a matching row in the INDEX.md "All Findings" table. Matching is greedy (each INDEX.md row used at most once, best match wins).

### Step 1: Exact Location Match

A finding matches if its INDEX.md `location` column contains **both** the ground truth `contract` name **and** `function` name as substrings.

If an exact location match is found, proceed to the **severity adjacency gate** (Step 3). If it passes, the match is accepted immediately (no title comparison needed).

### Step 2: Fuzzy Title Match

If no exact location match passes the gate, compute Jaccard similarity between the ground truth `title` and each unmatched INDEX.md finding title using `match-finding.sh`:

- Lowercase both strings
- Tokenize on `[^a-z0-9]+`
- Jaccard = |intersection| / |union| (token sets)
- Minimum threshold: Jaccard ≥ 0.4
- Among candidates passing the threshold, select the highest Jaccard score

Then proceed to Step 3 for the best candidate.

### Step 3: Severity Adjacency Gate

A match (from either Step 1 or Step 2) is valid only if the ground truth severity and finding severity are **adjacent** (within ±1 level). Non-adjacent matches are discarded.

### False Positive Classification

After all ground truth vulnerabilities are matched:
- Unmatched INDEX.md findings whose `location` contains a `known_safe` function name → **FP**
- Unmatched INDEX.md findings not matching any known_safe entry → ignored (not scored)

This follows the EVMbench approach: only penalize findings on functions known to be safe.

---

## 5. Metrics

| Metric | Formula | Description |
|--------|---------|-------------|
| **DR** | TP / (TP + FN) | Detection Rate — fraction of known vulns found |
| **FPR** | FP / (FP + TP) | False Positive Rate — FPs as fraction of all reported findings |
| **SA** | severity_matches / TP | Severity Accuracy — fraction of TPs with exact severity match |
| **VA** | correct_verdicts / total_verdicts | Verification Accuracy — fraction of verdicts matching expected |
| **AYI** | DR − FPR | Are You Improving? — composite score (higher is better, max 1.0) |

All metrics are in [0.0, 1.0]. AYI can be negative if FPR > DR.

---

## 6. Multi-Trial Aggregation

When a skill is run multiple times on the same fixture (k trials), `score.sh --trials N` computes:

| Statistic | Definition |
|-----------|-----------|
| **best@k** | Maximum AYI across k trials |
| **median@k** | Median AYI across k trials |
| **pass^k** | TP only if detected in ≥ ceil(k/2) trials (majority vote) |

Trial results are stored as `<results_dir>/<fixture>/trial-N/grade.json`.

---

## 7. Edge Cases

| Situation | Handling |
|-----------|---------|
| Division by zero (e.g. TP=0 and FN=0) | Result = 0.0 |
| Empty INDEX.md / no findings table | All known vulns → FN; FP = 0 |
| No verification files | VA = 0.0, V_CORRECT = 0, V_TOTAL = 0 |
| No known_safe entries | FP = 0 regardless of unmatched findings |
| Fixture with no known_vulnerabilities | DR = 0.0, SA = 0.0 |
| Jaccard tie between candidates | First candidate (by INDEX.md order) wins |
