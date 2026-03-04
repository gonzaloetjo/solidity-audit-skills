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
# Single fixture, 1 trial (uses CLI default model)
evals/scripts/run-eval.sh --fixture simple-reentrancy

# All fixtures, 1 trial each
evals/scripts/run-eval.sh --all

# All fixtures with a specific model
evals/scripts/run-eval.sh --all --model sonnet
evals/scripts/run-eval.sh --all --model opus

# Multi-trial for statistical robustness
evals/scripts/run-eval.sh --all --trials 3 --model sonnet

# Naive baseline — raw model prompt, no audit pipeline
# (answers: "does our pipeline actually help vs a plain model?")
evals/scripts/run-eval.sh --all --naive --model sonnet

# With custom budget cap
evals/scripts/run-eval.sh --all --trials 1 --max-budget-usd 8.0
```

**Options**:
- `--fixture NAME` — run a single fixture
- `--all` — run all fixtures
- `--model MODEL` — Claude model (`sonnet`, `opus`, `haiku`, or full ID like `claude-sonnet-4-20250514`)
- `--naive` — raw model baseline (no pipeline), results go to `results/naive-{model}/`
- `--trials N` — trials per fixture (default: 1)
- `--max-budget-usd N` — budget cap per trial (default: 12.0)
- `--max-turns N` — agent turn limit (default: 200)

`run-eval.sh` handles fixture isolation, forge-std installation, `claude -p` invocation with the eval plugin (or raw prompt in naive mode), grading, and score aggregation.

**Prerequisites**: `claude` CLI in PATH, `forge` installed. The eval plugin (`plugins/solidity-function-audit-eval`) must exist.

### Comparing pipeline vs raw model

The `--naive` flag runs the same fixtures through a plain Claude prompt (no pipeline, no stages, no verification). This answers whether the structured audit pipeline adds value over just asking the model to find bugs.

```bash
# Run pipeline with Sonnet
evals/scripts/run-eval.sh --all --model sonnet

# Run naive baseline with same model
evals/scripts/run-eval.sh --all --naive --model sonnet

# Compare results
evals/scripts/score.sh evals/results/                    # pipeline scores
evals/scripts/score.sh evals/results/naive-sonnet/       # naive scores
```

Naive results are stored separately under `results/naive-{model}/` so they don't mix with pipeline results.

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

## Fixture Design Principles

These principles address the four recommendations from [OpenZeppelin's EVMBench audit](https://www.openzeppelin.com/news/openai-evmbench-audit), adapted for our framework.

### Contamination awareness

Current fixtures (v1.x) use well-known vulnerability patterns by design — they serve as a functional baseline to ensure the pipeline works end-to-end. Each fixture's `GROUND_TRUTH.md` includes `contamination_notes` metadata with `pattern_risk` (how well-known the pattern is) and `reasoning_required` (whether detection requires genuine code reasoning vs pattern matching).

The `--naive` baseline comparison is the primary tool for detecting memorization. If a fixture shows high naive-vs-pipeline parity (both score equally well), that fixture likely tests memorization rather than reasoning. The `simple-reentrancy` fixture is expected to show this behavior; `state-divergence` should not.

### Exploit reproducibility

Each vulnerable fixture includes `test/Exploit.t.sol` — a Foundry test that validates every ground truth vulnerability is real and exploitable under the fixture's compiler version (^0.8.20). Run `forge test` in any fixture directory to verify. These tests serve as both a ground truth validation mechanism and a regression check if fixture source code is ever modified.

### Severity calibration

Severity definitions follow the 5-level scale documented in CLAUDE.md: CRITICAL (direct loss of funds, exploitable now), HIGH (conditional loss, requires specific conditions), MEDIUM (protocol deviation, limited financial impact), LOW (best practices, minor issues), INFO (observations, design choices). The grading algorithm uses a ±1 severity adjacency gate — a finding matched at an adjacent severity still counts as a TP but with a severity accuracy penalty.

### v2.0.0 design direction

Future fixtures will prioritize:
- **Novel composition**: vulnerabilities arising from the interaction of individually safe patterns, not standalone textbook issues
- **No inline annotations**: source code should read like real developer code with no `// BUG` or `// VULNERABILITY` comments
- **Protocol-context-dependent exploitability**: vulnerabilities that require understanding the protocol's trust assumptions, not just code patterns
- **Multi-hop dependency chains**: bugs that span 3+ contracts or require tracing through multiple state transitions
- **Non-standard naming**: avoid function names that signal vulnerability type (e.g., no `unsafeTransfer`)

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
