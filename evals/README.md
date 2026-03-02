# Evals — Solidity Audit Skill Evaluation Framework

Evaluation framework for measuring the detection quality of `solidity-function-audit` skills against known-vulnerability fixtures.

## Directory Structure

```
evals/
  fixtures/             # Minimal Foundry projects with known vulnerabilities
    simple-reentrancy/
    erc4626-rounding/
    state-divergence/
    access-control-bypass/
    oracle-manipulation/
  scripts/
    match-finding.sh    # Jaccard similarity matcher for finding titles
    grade.sh            # Grade one audit output against a fixture
    score.sh            # Aggregate grade.json files into a summary table
  results/              # Grade outputs (git-ignored, .gitkeep present)
  GRADING_SPEC.md       # Normative specification for all metrics and scoring
  README.md             # This file
  fixtures/README.md    # How to add new fixtures
```

## Usage Workflow

### 1. Run the skill against a fixture

```bash
cd evals/fixtures/simple-reentrancy
git init && forge install foundry-rs/forge-std --no-git   # one-time setup
claude --plugin-dir ../../plugins/solidity-function-audit
# > /solidity-function-audit .
```

Answer prompts normally. The skill writes output to `docs/audit/function-audit/` inside the fixture directory.

### 2. Grade the output

```bash
evals/scripts/grade.sh \
  evals/fixtures/simple-reentrancy/docs/audit/function-audit \
  evals/fixtures/simple-reentrancy
```

`grade.sh` reads `GROUND_TRUTH.md` from the fixture, matches findings against `INDEX.md` using `match-finding.sh`, and emits `grade.json` to stdout. Redirect to save:

```bash
evals/scripts/grade.sh \
  evals/fixtures/simple-reentrancy/docs/audit/function-audit \
  evals/fixtures/simple-reentrancy > evals/results/simple-reentrancy/grade.json
```

### 3. Aggregate results

```bash
evals/scripts/score.sh evals/results/
```

Prints a markdown table with per-fixture and overall scores.

### 4. Review the metrics

See `evals/GRADING_SPEC.md` for the full definition of each metric.

## Metrics (brief)

| Metric | Description |
|--------|-------------|
| DR | Detection Rate — fraction of known vulnerabilities found |
| FPR | False Positive Rate — fraction of reported findings not in ground truth |
| SA | Severity Accuracy — fraction of found vulnerabilities at correct severity |
| VA | Verdict Accuracy — fraction of CONFIRMED findings correctly verified |
| AYI | Audit Youden Index — DR minus FPR (discriminative power, range -1.0 to 1.0) |

Full definitions, matching rules, and edge-case handling: see `GRADING_SPEC.md`.

## Multi-Trial Usage

To measure variance across runs, grade each trial into a per-trial subdirectory:

```bash
mkdir -p evals/results/simple-reentrancy/trial-{1,2,3}

for i in 1 2 3; do
  evals/scripts/grade.sh \
    path/to/run${i}/docs/audit/function-audit \
    evals/fixtures/simple-reentrancy > evals/results/simple-reentrancy/trial-${i}/grade.json
done

evals/scripts/score.sh evals/results/ --trials 3
```

`score.sh --trials N` reports best@k, median@k AYI across trials.

## Adding New Fixtures

See `evals/fixtures/README.md`.

## Deferred (v1.9.0)

- Eval-mode skill variant (non-interactive, no prompts)
- Automated harness (`run-all-fixtures.sh`) for one-command batch evaluation
- CI integration (GitHub Actions workflow)
