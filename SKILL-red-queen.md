---
name: red-queen
description: "Adversarial evolutionary QA using the Digital Red Queen algorithm. Deterministic state machine (liza-advanced.nu) drives selection, regression, and gates. AI generates test commands only. Code and tests coevolve — each generation must defeat ALL previous generations. Use when you need aggressive QA, adversarial code review, CLI validation, regression hunting, or when the user says 'red queen', 'combative review', 'adversarial QA', 'stress test', or 'defend the throne'."
allowed-tools:
  - Read
  - Write
  - Edit
  - Glob
  - Grep
  - Bash
  - Task
  - TodoWrite
  - mcp__codanna__*
model: sonnet
user-invocable: true
argument-hint: [target path, CLI binary, or scope]
---

# The Red Queen: Deterministic Adversarial Evolution

## Liza Path

The deterministic state machine lives at:

```
~/.claude/skills/red-queen/liza-advanced.nu
```

All commands use this absolute path:

```bash
L="$HOME/.claude/skills/red-queen/liza-advanced.nu"
nu $L init
nu $L task-add drq-session --spec_ref README.md
# etc.
```

**Always set `L` at the start of every session.**

> *"It takes all the running you can do, to keep in the same place."* — The Red Queen

## Design Principle: Deterministic Over AI

The evolutionary loop has two kinds of operations:

| Operation | Who Does It | Why |
|-----------|------------|-----|
| **Generate test commands** | AI (creative) | Requires understanding of product semantics |
| **Execute tests** | Shell (deterministic) | `run-shell-cmd` — exit code is ground truth |
| **Select survivors** | Liza (deterministic) | exit_code != expect_exit → survivor. No AI judgment. |
| **Lock regressions** | Liza (deterministic) | `done_when` append — permanent, computed, no AI |
| **Gate transitions** | Liza (deterministic) | `assert-can-submit`, `assert-can-review`, `assert-can-merge` |
| **Track generations** | Liza `gen-start` (deterministic) | Increments generation counter on blackboard |
| **Record survivor** | Liza `gen-survivor` (deterministic) | Locks regression + updates landscape atomically |
| **Record discard** | Liza `gen-discard` (deterministic) | Updates landscape tests_run without adding regression |
| **Regression check** | Liza `validate` (deterministic) | Runs ALL `done_when` checks, all must pass |
| **Landscape scoring** | Liza `landscape` (deterministic) | Computes fitness, crown status from blackboard fields |

**AI generates test commands. Everything else is deterministic code.**

## The Algorithm

```
DRQ_DETERMINISTIC(target_binary, liza_script):

  # PHASE 0: Initialize deterministic state
  nu $Linit
  nu $Ltask-add drq-session --spec_ref README.md

  # AI: Read docs, generate initial done_when checks (the contract)
  for each promise discovered:
    nu $Ltask-add-check drq-session "<verification_cmd>" --expect_exit=0

  # Claim the session
  nu $Lclaim drq-session red-queen

  generation = 0
  landscape = {}  # dimension → {tests_run: 0, survivors: 0}

  loop:
    # INCREMENT: Deterministic
    nu $Lgen-start drq-session

    # EVOLVE: AI generates test commands for this generation
    # This is the ONLY step that uses AI creativity
    challengers = AI_generate_test_commands(landscape, generation)

    # EXECUTE + SELECT: Deterministic — run each, check exit code
    for cmd, dimension in challengers:
      result = shell(cmd)
      if result.exit_code != 0:  # BUG FOUND
        # Lock regression + update landscape atomically (DETERMINISTIC)
        nu $Lgen-survivor drq-session "<dimension>" "<cmd>" --severity <SEVERITY>
        # File bead IMMEDIATELY — not at session end
        bd create --title "[Red Queen] <SEVERITY>: <finding>" --type=bug --priority=<N>
      else:
        # No bug — update landscape tests_run only (DETERMINISTIC)
        nu $Lgen-discard drq-session "<dimension>"

    # ADAPT: Deterministic — computed by liza from blackboard fields
    nu $Llandscape drq-session

    # REGRESSION: Deterministic — Liza runs ALL done_when checks
    nu $Lcoder-submit drq-session red-queen
    nu $Lvalidate drq-session

    # LINEAGE REPLAY: Every predecessor must be defeated
    nu $Llineage-replay drq-session

    # CARNAGE: Track kill rate and lethality
    nu $Lcarnage drq-session

    # ESCALATION: Auto-promote severity for bleeding dimensions
    nu $Lescalate drq-session

    # EQUILIBRIUM: Requires 3 consecutive zero-survivor gens + all dims exhausted
    # Dormant dimensions reawaken every 5 gens — the Queen never rests

  # VERDICT: Computed from blackboard state
  nu $Llandscape drq-session
```

## What Liza Controls (Deterministic)

Every gate, transition, and regression check is enforced by `liza-advanced.nu`:

### State Machine

```
UNCLAIMED → claim → IN_PROGRESS → coder-submit → READY_FOR_REVIEW
  → validate (runs ALL done_when) → approve/reject
  → APPROVED → merge → MERGED
```

Each transition has a **deterministic gate**:

| Gate | What It Checks | Code |
|------|---------------|------|
| `assert-can-submit` | Status is IN_PROGRESS, agent_id set | Lines 132-139 |
| `assert-can-review` | Status is READY_FOR_REVIEW, commit SHA present, validation results exist | Lines 142-156 |
| `assert-can-merge` | Status is APPROVED, review decision is APPROVED | Lines 159-167 |
| `assert-no-test-weakening` | Changed files don't touch tests/ unless explicitly allowed | Lines 170-177 |

No AI judgment in any gate. Pure field checks.

### Validation (The Ratchet)

`cmd-supervisor-validate` (lines 356-414) is the ratchet mechanism:

```
for each done_when check:
  result = run-shell-cmd(check.cmd)
  pass = (result.exit_code == check.expect_exit)
  # DETERMINISTIC: exit code comparison, nothing else

all_ok = ALL checks pass
# If ANY check fails → validation fails → no approve possible
```

This is the core evolutionary mechanism: **every test that ever broke the code becomes a permanent `done_when` entry**. The validation command runs ALL of them. The code must pass ALL of them. There is no AI involved in this check — it's pure exit code comparison.

### Regression Locking

`cmd-regress` (lines 522-555) adds tests to the permanent bank:

```
# Without --force: deterministically verifies the test fails on champion, passes on candidate
champion_test = run-shell-cmd(cmd)  # must FAIL on current code
candidate_test = run-shell-cmd(cmd)  # must PASS after fix
# Only then: append to done_when
```

This prevents false positives from entering the lineage. Deterministic: two shell commands, two exit code checks.

## Execution Protocol

### Phase 0: Probe (AI + Deterministic)

**AI does**: Read README, --help, source code. Discover promises.
**Deterministic does**: Register each promise as a `done_when` check.

```bash
# Initialize state machine
nu $Linit
nu $Ltask-add drq-session --spec_ref README.md

# AI discovers promises, then registers each deterministically:
nu $Ltask-add-check drq-session "factory help" --expect_exit=0
nu $Ltask-add-check drq-session "factory version" --expect_exit=0
nu $Ltask-add-check drq-session "factory new -s test-slug 2>/dev/null; echo \$?" --expect_exit=0
# ... one per promise

# Claim
nu $Lclaim drq-session red-queen
```

### Generation N: Evolve → Execute → Select → Regress

**AI does**: Generate 3-10 test commands based on the landscape.
**Everything else is deterministic.**

```bash
L="$HOME/.claude/skills/red-queen/liza-advanced.nu"
DIM="error-handling"

# Start generation
nu $L gen-start drq-session

# AI generates test commands (the creative part)
# Execute each, let exit code decide survivor vs discard

# Challenger 1
factory bogus 2>/dev/null
if [ $? -eq 0 ]; then
  # BUG: should have failed — lock survivor + file bead
  nu $L gen-survivor drq-session "$DIM" "factory bogus 2>/dev/null; test \$? -ne 0" --severity CRITICAL
  bd create --title "[Red Queen] CRITICAL: bogus command exits 0" --type=bug --priority=0
else
  nu $L gen-discard drq-session "$DIM"
fi

# Challenger 2
factory new 2>/dev/null
if [ $? -eq 0 ]; then
  nu $L gen-survivor drq-session "$DIM" "factory new 2>/dev/null; test \$? -ne 0" --severity MAJOR
  bd create --title "[Red Queen] MAJOR: new without --slug exits 0" --type=bug --priority=1
else
  nu $L gen-discard drq-session "$DIM"
fi

# Show landscape (fitness computed from blackboard)
nu $L landscape drq-session

# REGRESS: Run full lineage (deterministic)
nu $L coder-submit drq-session red-queen
nu $L validate drq-session
```

### Landscape Scoring (Deterministic)

After each generation, compute fitness scores from raw counts:

```bash
# Landscape is a simple ratio: survivors / tests_run per dimension
# No AI judgment — pure arithmetic

# Example after generation 3:
# error-handling:    5 survivors / 8 tests = 0.625 (high fitness — keep probing)
# setup:             1 survivor  / 6 tests = 0.167 (low fitness — fewer tests next gen)
# edge-cases:        0 survivors / 4 tests = 0.000 (exhausted if 0 for 2 gens)
# state-management:  3 survivors / 3 tests = 1.000 (everything breaks — maximum pressure)
```

Allocation rule (deterministic, escalating):
- Dimensions with fitness > 0.7: allocate 6+ challengers (HEMORRHAGING)
- Dimensions with fitness > 0.5: allocate 5 challengers (HIGH PRESSURE)
- Dimensions with fitness > 0.3: allocate 4 challengers (CONTESTED)
- Dimensions with fitness > 0.1: allocate 3 challengers (PROBING)
- Dimensions with fitness 0: allocate 2 challengers (COOLING — double-tap, never single)
- Dimensions exhausted for 3+ gens: 0 challengers (but reawaken every 5 gens)
- ALL allocations multiplied by escalation factor: 1.0x + 0.5x per 2 generations
- Equilibrium requires 3 consecutive zero-survivor generations (not 2)

### Coevolution (Fix → Regress → Repeat)

When the DRQ loop is fixing code (not just reporting):

```bash
# 1. AI fixes the code (creative)
# 2. Liza validates ALL done_when (deterministic)
nu $Lcoder-submit drq-session red-queen
nu $Lvalidate drq-session

# If validate fails:
#   → The failing check is ALREADY in done_when (it was there before)
#   → The fix introduced a regression
#   → Fix the regression, re-validate
#   → Repeat until validate passes

# If validate passes:
#   → ALL historical tests pass
#   → Proceed to next generation
```

The ratchet is entirely in liza's `done_when` list and `validate` command. No AI decides if something regressed — the exit code does.

## What AI Does vs What Code Does

| Step | AI | Deterministic Code |
|------|----|--------------------|
| Discover promises | Reads docs, generates check commands | `task-add-check` stores them |
| Generate challengers | Creates test commands per dimension | — |
| Execute challengers | — | `run-shell-cmd` captures exit code |
| Classify survivor | — | `exit_code != expect_exit` → survivor |
| Lock regression | — | `task-add-check` appends to `done_when` |
| File bead | — | `bd create` at same moment as `task-add-check` — never deferred |
| Score landscape | — | `survivors / tests_run` per dimension |
| Allocate next gen | Uses landscape scores to decide dimensions | Scores are computed, allocation follows rules |
| Gate transitions | — | `assert-can-*` functions |
| Validate full lineage | — | `validate` runs all `done_when` checks |
| Fix code | Writes code changes | — |
| Detect regression | — | `validate` fails → regression exists |
| Track state | — | Blackboard YAML (atomic save) |

**AI touches**: test command generation, code fixes, promise discovery.
**Code handles**: selection, regression, gates, state, validation, scoring.

## Verdict Format

The verdict is **computed from blackboard state**, not AI narrative:

```bash
# Extract deterministic facts from blackboard
nu $Lshow --task=drq-session

# The verdict fields are all computable:
# - generations: count of generation loops executed
# - lineage_size: length of done_when list
# - survivors_by_dimension: group done_when entries by dimension tag
# - crown_status: if ALL done_when pass → DEFENDED
#                 if CRITICAL survivors exist → FORFEIT
#                 else → CONTESTED
```

```
THE RED QUEEN'S VERDICT
═══════════════════════════════════════════════════════════════

Champion:    [product name]
Generations: [N]
Lineage:     [M] survivors (done_when entries)
Final:       CROWN DEFENDED | CROWN CONTESTED | CROWN FORFEIT

FITNESS LANDSCAPE (computed from test results)
═══════════════════════════════════════════════════════════════

Dimension              Tests  Survivors  Fitness  Status
─────────────────────  ─────  ─────────  ───────  ──────────
[computed per dimension from raw counts]

PERMANENT LINEAGE (done_when entries)
═══════════════════════════════════════════════════════════════

[Each entry from done_when: cmd, expect_exit, generation added, dimension]

FULL VALIDATION
═══════════════════════════════════════════════════════════════

[Output of: nu $Lvalidate drq-session]
All checks pass: YES/NO
Failed checks: [list]
```

## Finding Report

Each finding maps to a `done_when` entry — the deterministic artifact:

```
[GEN-{gen}-{n}] {SEVERITY}: {title}
═══════════════════════════════════════════════
Generation:     {N}
Dimension:      {landscape dimension}
Command:        {exact command — this IS the done_when entry}
Expected Exit:  {expect_exit}
Actual Exit:    {what was observed}
Stdout:         {captured}
Stderr:         {captured}

done_when entry: { cmd: "<cmd>", expect_exit: <N> }
Locked by:      task-add-check (deterministic, permanent)
═══════════════════════════════════════════════
```

## Multi-Agent Orchestration

```
RED QUEEN (Orchestrator)
│
├─ SCOUT AGENT (Task: Explore)
│   └─ Phase 0: Read docs, generate initial done_when commands
│   └─ OUTPUT: List of "nu $Ltask-add-check" commands
│
├─ GENERATION AGENTS (Task: general-purpose)
│   └─ INPUT: Landscape scores, lineage (done_when list), generation N
│   └─ AI DOES: Generate test commands
│   └─ DETERMINISTIC: Execute, check exit codes, call task-add-check for survivors
│   └─ OUTPUT: Survivor list, updated landscape scores
│
├─ SOURCE AUDITOR (Task: code-reviewer)
│   └─ Identifies code patterns that inform landscape dimensions
│   └─ OUTPUT: Suggested dimensions to add to landscape
│
└─ ORCHESTRATOR computes:
    └─ Landscape fitness (arithmetic)
    └─ Equilibrium check (2 consecutive zero-survivor gens)
    └─ Crown status (validate pass/fail)
    └─ Verdict (from blackboard state)
```

## Rules of Engagement

1. **Deterministic over AI** — if it can be computed, compute it. AI generates test commands only.
2. **Exit codes are ground truth** — not AI interpretation of output
3. **done_when is the lineage** — every survivor is a permanent shell command with an expected exit code
4. **validate is the ratchet** — runs ALL done_when, deterministic pass/fail
5. **Gates are code** — `assert-can-*` functions, not AI judgment
6. **Landscape is arithmetic** — survivors / tests_run, not AI scoring
7. **State is YAML** — blackboard.yml, atomic save, auditable
8. **AI creativity is bounded** — generate test commands, fix code, read docs. Nothing else.
9. **No AI decides if something passes** — the shell exit code decides
10. **File beads at selection, not at session end** — `bd create` happens the same moment as `task-add-check`. Every survivor gets a bead immediately. Never defer.
11. **The Queen always returns** — today's done_when is tomorrow's regression gate
12. **Escalating pressure** — challenger counts increase with generation number (1.0x + 0.5x per 2 gens). The codebase faces ever-growing armies.
13. **Defeat ALL predecessors** — use `lineage-replay` to verify current code defeats every warrior from every generation. New code must beat the entire lineage.
14. **Anti-stagnation** — dormant dimensions reawaken every 5 generations. The Queen never truly rests.
15. **Severity escalation** — 3+ consecutive survivors in a dimension auto-promote severity. Persistent wounds become critical.
16. **Double-tap cooling dimensions** — never send just 1 challenger to a cooling dimension. Always 2+. Confirm the kill.
17. **Carnage tracking** — monitor kill rate and lethality per dimension. The codebase must constantly defend itself.

## Severity Classification

| Severity | Deterministic Criteria | Landscape Effect |
|----------|----------------------|-----------------|
| **CRITICAL** | Core workflow command returns wrong exit code (0 on error, non-0 on success) | dimension.fitness = 1.0 (maximum pressure) |
| **MAJOR** | Documented command fails or produces wrong output (verified by grep/diff, not AI) | dimension.fitness += 0.3 |
| **MINOR** | Output doesn't match documented format (verified by pattern match, not AI) | dimension.fitness += 0.1 |
| **OBSERVATION** | AI-only judgment (no deterministic check possible) | Not added to done_when |

Note: OBSERVATION is the only severity that relies on AI judgment. CRITICAL/MAJOR/MINOR all have deterministic verification commands in done_when.

## Anti-Patterns

| Anti-Pattern | Problem | Deterministic Way |
|--------------|---------|------------------|
| AI decides if test passed | Nondeterministic, unreproducible | Exit code comparison only |
| AI scores the landscape | Subjective, varies between runs | survivors / tests_run ratio |
| AI decides when to stop | No convergence guarantee | Equilibrium: 0 survivors for 2 consecutive gens |
| AI gates transitions | Bypassable, inconsistent | `assert-can-*` functions in liza |
| Tests not persisted | Lost between sessions | `done_when` in blackboard YAML |
| AI judges regression | Flaky, depends on prompt | `validate` runs all checks, exit code comparison |
| Narrative verdict | Different every run | Computed from blackboard fields |

## Quality Gates (All Deterministic)

- [ ] `nu $Lshow --task=drq-session` returns valid state
- [ ] At least 3 generations executed (check generation counter)
- [ ] Every survivor has a `done_when` entry (check done_when length >= survivor count)
- [ ] `nu $Lvalidate drq-session` passes (all done_when checks green)
- [ ] Landscape scores computed (survivors / tests_run for each dimension)
- [ ] Equilibrium checked (0-survivor generations counted)
- [ ] Crown status derived from validate result + survivor severities

## Session Completion

```bash
# 1. Beads already filed (filed at survivor selection, not here)
#    Verify: bd list --status=open | grep "Red Queen"

# 2. Verify lineage integrity (deterministic)
nu $Lvalidate drq-session

# 3. Show final state (deterministic)
nu $Lshow --task=drq-session

# 4. Push
git add . && git commit -m "test(red-queen): gen N — <verdict>"
git push
```

---

**Skill Version**: 6.0.0
**Last Updated**: January 2026
**Status**: Production-Ready
**Model**: Deterministic Adversarial Evolution — AI generates tests, code decides outcomes
