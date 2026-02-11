# solidity-audit-skills

Plugin marketplace for Solidity smart contract audit skills. Audience: developers building new skills or maintaining existing ones.
Pure markdown repo — no build step, no dependencies.

## STATIC — Architecture and Standards

### Directory Layout

```
.claude-plugin/marketplace.json            # Marketplace manifest
plugins/
  {plugin-name}/
    .claude-plugin/plugin.json             # Plugin manifest
    hooks/                                 # Plugin hooks (optional)
      hooks.json                           #   Hook event configuration
      validate-output.sh                   #   Output validation script
    skills/
      {skill-name}/
        SKILL.md                           # Skill entrypoint (required)
        resources/                         # Supporting files
          STAGE_PROMPTS.md                 #   Agent prompt templates
          REVIEW_PROMPTS.md                #   Stage 0/4/5 prompt templates
          FUNCTION_TEMPLATE.md             #   Per-function analysis template
          EXAMPLE_OUTPUT.md                #   Quality/format reference
README.md
CHANGELOG.md
LICENSE
```

Plugin name, skill directory name, and SKILL.md `name` field must all match.
Variants append a suffix to the base name (e.g. `-team`).

### Skill File Format

SKILL.md has YAML frontmatter followed by the full execution prompt.

**Frontmatter fields used here**: `name` (kebab-case slug, becomes `/name` command), `description` (multi-sentence, used for discovery), `disable-model-invocation: true` (user-only invocation).

**Other available fields**: `argument-hint`, `user-invocable`, `allowed-tools`, `model`, `context` (`fork` for subagent isolation), `agent` (subagent type when forked), `hooks`.

**String substitutions**: `$ARGUMENTS` (all args; falls back to CWD), `$0`/`$1`/`$ARGUMENTS[N]` (positional), `${CLAUDE_SESSION_ID}`, `` !`command` `` (dynamic shell injection).

**Body structure**: The markdown body IS the agent prompt. Keep SKILL.md between 200-400 lines. Move detailed reference material (prompt templates, output examples, analysis templates) into `resources/` files that agents read at runtime.

### Plugin and Marketplace Manifests

**marketplace.json** (repo root `.claude-plugin/`): `name`, `version`, `description`, `owner` (object with required `name` string), `plugins` (array of objects with `name` + `source`).

**plugin.json** (per-plugin `.claude-plugin/`): `name` (must match directory), `version`, `description`, `skills` (array of relative paths to skill directories).

Both use semver (MAJOR.MINOR.PATCH). Optional fields available in the spec: `author` (object), `homepage`, `repository`, `license`, `keywords`.

### Skill Design Patterns

**File-based agent output** — Agents write all analysis to markdown files via the Write tool. They never return analysis content in responses; instead they return a one-line confirmation: `"Written to {path} -- {N} items analyzed."`.

**Stage pipeline** — Skills define 6 sequential stages: Stage 0 (design decisions, interactive + optional Slither), Stages 1-3 (foundation, domain audit, cross-cutting — agents in parallel), Stage 4 (human review, interactive), Stage 5 (re-evaluation, conditional agent). Later stages depend on earlier stage outputs.

**Slither integration** — If Slither is installed, the orchestrator runs it between Stage 0 and Stage 1. Findings go to `stage0/slither-findings.md`. Stage 2 and Stage 3 agents cross-reference with Slither via the `{slither_file}` placeholder.

**Template-driven analysis** — `FUNCTION_TEMPLATE.md` defines the exact per-function output format (rationale, state mutations, dependencies, findings with severity, verdict). Agents read this template at runtime to ensure consistent output.

**Example-driven quality** — `EXAMPLE_OUTPUT.md` provides a complete domain analysis example. Agents read it to calibrate depth, tone, and formatting.

**Progressive disclosure** — SKILL.md contains orchestration logic. Detailed prompt templates live in `resources/STAGE_PROMPTS.md`, read by the orchestrator and injected into agent prompts at spawn time.

**Guardrails** — Each SKILL.md ends with a list of anti-patterns and required corrective actions, serving as embedded guardrails the orchestrator must follow.

**Agent turn limits** — All agent spawns include `max_turns` to prevent stuck agents from burning context until timeout. Stage 1/5: 15 turns, Stage 2/3: 25 turns.

**Output validation hooks** — Plugin hooks validate agent output files on completion. Solo uses `SubagentStop`, team uses `TaskCompleted`. Checks: non-empty, has `## ` headings, Stage 2 has required sections, Stage 2/3 have severity tags. Exit code 2 blocks completion and feeds the error back to the agent.

**Compaction guidance** — Each SKILL.md includes a "Context Compaction Guidance" section listing critical values the compactor must preserve (paths, domain groupings, placeholders, stage status).

**Post-completion verification** — After each stage's file existence check, the orchestrator reads the first/last 5 lines of each output file to verify structure. Malformed files are noted as INCOMPLETE in synthesis.

**Domain-scoped source files** — Stage 2 agents receive only domain-relevant files (contracts containing domain functions, externally called contracts from Stage 1c, inherited contracts/libraries) instead of all project source files.

**Domain grouping heuristic** — Pre-flight discovery groups contract functions into 4-10 domains of 3-15 functions each, confirmed with the user before launching agents.

**Severity definitions**: CRITICAL (direct loss of funds, unauthorized access, broken core invariants — exploitable now), HIGH (conditional loss of funds, significant access control bypass — requires specific conditions), MEDIUM (protocol behavior deviation, incorrect state under edge conditions — limited financial impact), LOW (best practices, gas optimizations with security implications, minor unlikely issues), INFO (observations, design choices, confirmations). **Verdicts**: SOUND (only INFO or no findings), NEEDS_REVIEW (MEDIUM or LOW findings, no CRITICAL/HIGH), ISSUE_FOUND (CRITICAL or HIGH finding). **Review statuses**: BUG, DESIGN, DISPUTED, DISCUSS. **Re-evaluation outcomes**: UPHELD, WITHDRAWN, DOWNGRADED, NEEDS_TESTING.

**Output directory**: `docs/audit/function-audit/{stage0,stage1,stage2,stage3,review}/` with `INDEX.md` and `SUMMARY.md` at the root. Stage 2 files use `domain-{slug}.md` naming.

### Development Workflow

**Adding a new skill**: Create `plugins/{name}/.claude-plugin/plugin.json` + `plugins/{name}/skills/{name}/SKILL.md` + `resources/`. Add the plugin name to `marketplace.json` `plugins` array. Update CHANGELOG.md.

**Adding a variant**: Copy an existing plugin directory, append a suffix (e.g. `-team`), modify the SKILL.md orchestration logic and STAGE_PROMPTS.md. Shared templates (FUNCTION_TEMPLATE.md, EXAMPLE_OUTPUT.md) can be duplicated as-is.

**Testing locally**: `claude --plugin-dir ./plugins/{name}` loads a single plugin for testing. Validate structure with `claude plugin validate .`.

### Conventions

- File naming: manifests lowercase (`plugin.json`), skill entrypoint UPPERCASE (`SKILL.md`), resources SCREAMING_SNAKE_CASE (`STAGE_PROMPTS.md`)
- All agent prompts use absolute paths to output files
- All agents use `subagent_type: "general-purpose"`
- Timeouts: Stage 1 = 5 min (300000ms), Stage 2 & 3 = 10 min (600000ms)
- Turn limits: Stage 1/5 = 15 `max_turns`, Stage 2/3 = 25 `max_turns`
- `{design_decisions_file}` is only substituted into Stage 2 and Stage 3 prompts (Stage 1 does not use it)
- Re-running a skill checks for existing output; offers archive, overwrite, or cancel options

---

## DYNAMIC — Current State and Evolution

<!-- Last reviewed: 2026-02-11 -->

### Current Inventory

| Plugin | Variant | Key Difference |
|--------|---------|---------------|
| solidity-function-audit | Solo (background agents) | `Task` + `run_in_background` + `TaskOutput` polling |
| solidity-function-audit-team | Agent team | `TeamCreate` + `SendMessage` + shared task list with `blockedBy` dependencies |

Both variants run the same 6-stage pipeline (Stage 0 → Slither → 1 → 2 → 3 → 4 → 5). Stages 0, 4, 5 are orchestrator-interactive and identical across variants. Slither integration is identical. Only Stages 1-3 differ (solo uses background agents, team uses agent teams).

FUNCTION_TEMPLATE.md, EXAMPLE_OUTPUT.md, and REVIEW_PROMPTS.md are byte-identical across both plugins. STAGE_PROMPTS.md differs only by Communication Guidelines sections in the team variant. Both hooks directories contain `hooks.json` + `validate-output.sh` (different hook events but same validation logic).

### Claude Code Features In Use

**Background agents** (stable) — Solo skill spawns agents via `Task(run_in_background: true)` and waits with `TaskOutput(block: true, timeout: N)`.
Docs: https://code.claude.com/docs/en/sub-agents
Search: `"Claude Code subagents"`, `"Claude Code Task tool"`

**Agent teams** (experimental) — Team skill uses `TeamCreate`, `TaskCreate`/`TaskUpdate`/`TaskList`, `SendMessage`, `TeamDelete`. Requires `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1`.
Docs: https://code.claude.com/docs/en/agent-teams
Search: `"Claude Code agent teams"`, `"CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS"`

**Permission modes** — Team skill uses `mode: "bypassPermissions"` for all stages (read/write without prompts). Stage 2 teammates use prompt-based planning (design plan → message lead → execute) instead of `mode: "plan"` to avoid deadlocks with the plan approval protocol.
Docs: https://code.claude.com/docs/en/sub-agents#permission-modes

**Hooks** (stable) — Both plugins define `hooks/hooks.json` for output validation. Solo uses `SubagentStop` (matched to `general-purpose` agent type). Team uses `TaskCompleted`. Exit code 2 blocks completion and feeds validation errors back to the agent. Scripts use `${CLAUDE_PLUGIN_ROOT}` for path resolution.
Docs: https://code.claude.com/docs/en/hooks

### Reference Links

**Official docs**:
- Skills: https://code.claude.com/docs/en/skills
- Plugins: https://code.claude.com/docs/en/plugins
- Plugin reference: https://code.claude.com/docs/en/plugins-reference
- Marketplaces: https://code.claude.com/docs/en/plugin-marketplaces
- Subagents: https://code.claude.com/docs/en/sub-agents
- Agent teams: https://code.claude.com/docs/en/agent-teams
- Memory: https://code.claude.com/docs/en/memory
- Hooks: https://code.claude.com/docs/en/hooks
- Best practices: https://code.claude.com/docs/en/best-practices

**Community**:
- Agent Skills standard: https://agentskills.io — cross-platform SKILL.md spec
- Official skills repo: https://github.com/anthropics/skills
- Official plugin directory: https://github.com/anthropics/claude-plugins-official
- Awesome Claude Code: https://github.com/hesreallyhim/awesome-claude-code
- Awesome Claude Skills: https://github.com/travisvn/awesome-claude-skills

**Search terms for updates**: `claude code skills marketplace`, `agent skills SKILL.md specification`, `topic:claude-code-skills` on GitHub, `".claude-plugin" marketplace.json`.

### Known Limitations

- **Agent teams is experimental**: no session resumption with in-process teammates, shutdown can be slow, one team per session, uses significantly more tokens
- **Context compaction destroys team state**: long sessions may trigger auto-compaction that drops task IDs, domain groupings, or file paths. Mitigated by compaction guidance in SKILL.md but not eliminated. See [#23620](https://github.com/anthropics/claude-code/issues/23620)
- **Resource file duplication**: FUNCTION_TEMPLATE.md and EXAMPLE_OUTPUT.md are copied identically across plugins; plugins cannot reference files outside their directory (by design — plugins are cached on install)
- **Timeout tuning**: Stage 2 timeout (10 min) may be insufficient for large projects with many domains; max allowed is 600000ms
- **Manual domain grouping**: the 4-10 domain / 3-15 function heuristic requires user confirmation and may need adjustment per project

**Monitoring tools**: For team variant sessions, [claude-code-kanban](https://github.com/L1AD/claude-task-viewer) (`npx claude-code-kanban`) provides a zero-config Kanban board watching `~/.claude/tasks/` with real-time task cards.
