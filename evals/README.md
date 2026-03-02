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
    clean-contract/     # Zero-vulnerability fixture for FPR testing
  scripts/
    match-finding.sh    # Jaccard similarity matcher for finding titles
    grade.sh            # Grade one audit output against a fixture
    score.sh            # Aggregate grade.json files into a summary table
    run-eval.sh         # Automated eval harness (runs skill, grades, reports)
  results/              # Grade outputs (git-ignored, .gitkeep present)
  baseline.json         # Reference scores for regression detection
  GRADING_SPEC.md       # Normative specification for all metrics and scoring
  README.md             # This file
  fixtures/README.md    # How to add new fixtures
```

## Usage Workflow

### Automated (recommended)

Use `run-eval.sh` for one-command evaluation:

```bash
# Single fixture, 1 trial
evals/scripts/run-eval.sh --fixture simple-reentrancy

# All fixtures, 3 trials each
evals/scripts/run-eval.sh --all --trials 3

# With budget cap
evals/scripts/run-eval.sh --all --trials 1 --max-budget-usd 5.0
```

`run-eval.sh` handles fixture isolation, forge-std installation, `claude -p` invocation with the eval plugin, grading, and score aggregation.

**Prerequisites**: `claude` CLI in PATH, `forge` installed. The eval plugin (`plugins/solidity-function-audit-eval`) must exist.

### Manual

#### 1. Run the skill against a fixture

```bash
cd evals/fixtures/simple-reentrancy
git init && forge install foundry-rs/forge-std --no-git   # one-time setup
claude --plugin-dir ../../plugins/solidity-function-audit
# > /solidity-function-audit .
```

Answer prompts normally. The skill writes output to `docs/audit/function-audit/` inside the fixture directory.

#### 2. Grade the output

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

Optional: `--duration-seconds N` adds timing data to grade.json.

#### 3. Aggregate results

```bash
evals/scripts/score.sh evals/results/
```

Prints a markdown table with per-fixture and overall scores.

#### 4. Compare against baseline

```bash
evals/scripts/score.sh evals/results/ --baseline evals/baseline.json
```

Adds Δ AYI and PASS/REGRESS verdict columns. REGRESS if AYI drops by > 0.1.

#### 5. Review the metrics

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

## CI Integration

The `eval-canary.yml` GitHub Actions workflow runs on pushes that modify SKILL.md or STAGE_PROMPTS.md. It runs 2 fixtures (simple-reentrancy + clean-contract) with 1 trial each and checks for AYI regression against `baseline.json`.

## Deferred (v2.0.0)

- More fixtures (expand to 20+ covering flash loans, governance, proxy patterns, cross-chain)
- LLM-as-judge fallback for semantically equivalent findings
- Docker isolation for full reproducibility
- Parallel trial execution
- Team variant eval plugin
