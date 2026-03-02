# Fixtures

Each fixture is a minimal, self-contained Foundry project with a known vulnerability (or vulnerabilities) documented in `GROUND_TRUTH.md`. The grading scripts use `GROUND_TRUTH.md` as the reference for evaluating skill output.

## Required Files

```
fixtures/{fixture-name}/
  foundry.toml        # Foundry project config (see template below)
  src/
    Contract.sol      # Contract(s) under test — at least one must have a vulnerability
  test/
    Contract.t.sol    # Basic functionality tests (NOT exploit tests)
  GROUND_TRUTH.md     # Ground truth specification (YAML frontmatter + markdown body)
```

### foundry.toml template

```toml
[profile.default]
src = "src"
test = "test"
out = "out"
libs = ["lib"]
solc = "0.8.20"
```

Tests import `forge-std/Test.sol`. Install forge-std once per fixture before running:
```bash
cd fixtures/{fixture-name} && git init && forge install foundry-rs/forge-std --no-git
```

## GROUND_TRUTH.md Format

```yaml
---
fixture: {fixture-name}           # Must match directory name
version: "1.0"
contracts:
  - src/Contract.sol              # List of all source contracts
known_vulnerabilities:
  - id: V001                      # Sequential, V001 V002 ...
    severity: HIGH                # CRITICAL | HIGH | MEDIUM | LOW | INFO
    title: "short descriptive title"
    contract: ContractName
    function: functionName
    location: "src/Contract.sol:{line}"   # Line number of function declaration
    verification_expected: CONFIRMED      # Optional — CONFIRMED | REFUTED | LIKELY-FP
    tags: [tag1, tag2]            # Optional semantic tags
known_safe:
  - contract: ContractName
    function: functionName        # Functions that must NOT be flagged as vulnerable
---
```

The markdown body (after the `---`) should explain the vulnerability in plain text. It is not parsed by grading scripts but is useful for understanding the fixture.

## Constraints

- **No external imports**: do not use OpenZeppelin or any other library. All code must be self-contained in `src/`.
- **Compiles**: `forge build` must succeed without errors.
- **Tests pass**: `forge test` must pass (after forge-std is installed). Tests are basic functionality tests — they do not demonstrate the exploit.
- **Pragma**: use `pragma solidity ^0.8.20;` for all contracts.
- **Size**: keep contracts concise. Target 50-100 LOC per contract.

## Naming

- Directory name must match the `fixture` field in `GROUND_TRUTH.md`.
- Use kebab-case for directory names (e.g., `state-divergence`, `access-control-bypass`).
- Vulnerability IDs are sequential per fixture: V001, V002, ...

## Checklist Before Committing

- [ ] `foundry.toml` uses the standard template above
- [ ] All contracts use `pragma solidity ^0.8.20;` and have no external imports
- [ ] `forge build` succeeds
- [ ] `forge test` passes (after `git init && forge install foundry-rs/forge-std --no-git`)
- [ ] `GROUND_TRUTH.md` has valid YAML frontmatter between `---` markers
- [ ] `fixture` field matches the directory name
- [ ] Line numbers in `location` fields match the actual source code
- [ ] `known_safe` lists all functions that should not be flagged
- [ ] Test file tests functionality only — no exploit demonstration
