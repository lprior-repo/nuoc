# NUOC - All 186 Beads with TDD15 + Red Queen Self-Healing

## Mission
Implement ALL 186 beads using TDD15, then stress-test and evolve each using Red Queen adversarial QA. Create a self-healing system where code and tests coevolve.

## CRITICAL: Task Mode with Dynamic Replenishment

Ralph is running in **Tasks Mode**. Your task list in `.ralph/ralph-tasks.md` must ALWAYS have pending tasks until all 186 beads are complete.

### On First Iteration or Empty Task List

If `.ralph/ralph-tasks.md` is empty or has < 5 pending tasks:

```bash
# Populate initial tasks from bd ready
bd ready | head -20 | while read line; do
  BEAD_ID=$(echo "$line" | grep -oE 'nuoc-[a-z0-9]+')
  TITLE=$(echo "$line" | sed 's/.*\] //')
  echo "- [ ] $BEAD_ID - $TITLE"
done > .ralph/ralph-tasks.md
```

Then proceed with normal workflow.

### Task Replenishment (every iteration)

Before starting work, check task inventory:
- If tasks < 5: Add 10 more from `bd ready`
- Never let task list go empty until ALL beads complete

## Dual-Phase Workflow

### Phase 1: TDD15 Implementation (per bead)
### Phase 2: Red Queen Evolution (per bead)

---

## PHASE 1: TDD15 IMPLEMENTATION

### 1. Get Next Task from Task List
```bash
# Get first uncompleted task from .ralph/ralph-tasks.md
grep "^\- \[ \]" .ralph/ralph-tasks.md | head -1
```

### 2. Read Full Context
```bash
bd show <bead_id>
```

### 3. Claim Bead
```bash
bd update <bead_id> --status=in_progress
```

### 4. Execute TDD15 (15 Phases)

**Phase 0: Understanding** (1-2 iterations)
- Read all referenced files
- Map acceptance criteria to test cases
- Identify changes needed

**Phase 1-2: RED** (2-3 iterations)
- Write failing tests first
- Verify tests fail for right reasons
- Commit: `git add -A && git commit -m "RED: <bead_id> - failing tests"`

**Phase 3-7: GREEN** (3-5 iterations)
- Minimal implementation to pass tests
- No extras, no gold plating
- Commit: `git add -A && git commit -m "GREEN: <bead_id> - tests passing"`

**Phase 8-12: REFACTOR** (3-5 iterations)
- Clean code while keeping tests green
- Follow Nushell idioms
- Commit: `git add -A && git commit -m "REFACTOR: <bead_id> - clean code"`

**Phase 13-15: VERIFY** (2-3 iterations)
- Check all acceptance criteria
- Run full test suite
- Commit: `git add -A && git commit -m "VERIFY: <bead_id> - acceptance complete"`

### 5. Mark TDD15 Complete
```bash
git add -A && git commit -m "TDD15-COMPLETE: <bead_id> - ready for Red Queen"
git push
```

---

## PHASE 2: RED QUEEN ADVERSARIAL EVOLUTION

### What is Red Queen?
Adversarial evolutionary QA where:
- AI generates progressively harder test commands
- Code must defend against ALL previous generations
- Each generation tries to "dethrone" the current implementation
- Deterministic state machine tracks generations (liza-advanced.nu)
- Code and tests coevolve until battle-hardened

### Red Queen Workflow (per bead)

#### 1. Initialize Red Queen Session
```bash
# Red Queen will create adversarial tests for this bead's functionality
echo "Starting Red Queen evolution for <bead_id>"
```

#### 2. Generation Loop (5-10 generations recommended)

**Generation N** (each generation = 1 iteration):

1. **Generate Adversarial Test**
   - AI creates a test command that tries to break the implementation
   - Test targets edge cases, race conditions, boundary violations
   - Test is designed to exploit weaknesses
   - Example: `test-<bead_id>-gen<N>-attack.nu`

2. **Run Test Against Implementation**
   - Execute the adversarial test
   - Record: PASS or FAIL

3. **Battle Outcome**:
   - **If test PASSES**: Implementation defended successfully
     - Record test in "vanquished attacks" registry
     - Move to next generation (harder attack)

   - **If test FAILS**: Implementation has weakness
     - **REGRESSION**: This is a bug that must be fixed
     - Fix implementation to defend against attack
     - Re-run ALL previous generation tests (regression suite)
     - All previous tests must still pass (defend the throne)
     - Commit fix: `git add -A && git commit -m "RQ-FIX: <bead_id> gen<N> - defend against <attack>"`

4. **Regression Gate**
   - Before accepting any fix, run ALL previous tests
   - New fix must not break old defenses
   - This is the "defend against all previous generations" rule

5. **Generation Complete**
   - Record generation results in Red Queen state
   - Move to next generation

#### 3. Red Queen Completion (after 5-10 generations)

When code has successfully defended against 5-10 adversarial generations:

```bash
echo "Red Queen evolution complete for <bead_id>"
echo "  Generations survived: N"
echo "  Attacks defended: N"
echo "  Implementation hardened ✅"

git add -A && git commit -m "RQ-COMPLETE: <bead_id> - survived N generations"
git push
```

#### 4. Close Bead
```bash
bd close <bead_id> --reason="TDD15 + Red Queen complete - battle-hardened implementation"
bd sync
```

---

## TASKS MODE WORKFLOW - DYNAMIC BEAD SELECTION

Ralph is running in **Tasks Mode** with dynamic bead selection from `bd ready`.

### Task Replenishment Strategy

**CRITICAL**: Never let the task list become empty!

1. **Check task list**: Read `.ralph/ralph-tasks.md`
2. **If tasks < 5**: Replenish from `bd ready`
3. **Add next ready beads**: Get from `bd ready` and add to task list
4. **Keep working**: Continue with TDD15 + Red Queen workflow

### Task List Management

```bash
# At start of each iteration, check task inventory
TASK_COUNT=$(grep -c "^\- \[ \]" .ralph/ralph-tasks.md || echo 0)

if [ $TASK_COUNT -lt 5 ]; then
  # Get next 10 ready beads
  bd ready | head -10 | while read line; do
    # Parse bead ID and title
    BEAD_ID=$(echo $line | grep -oE 'nuoc-[a-z0-9]+')
    TITLE=$(echo $line | sed 's/.*\] //')
    # Add to task list
    echo "- [ ] $BEAD_ID - $TITLE" >> .ralph/ralph-tasks.md
  done
  echo "✅ Added new tasks from bd ready"
fi
```

### Complete Workflow Per Bead

```
1. Check task inventory (add from bd ready if < 5)
2. Get next task from .ralph/ralph-tasks.md
3. bd show <bead_id> → read context
4. bd update <bead_id> --status=in_progress

5. TDD15 (15 phases):
   Phase 0: Understanding
   Phase 1-2: RED
   Phase 3-7: GREEN
   Phase 8-12: REFACTOR
   Phase 13-15: VERIFY
   → Commit: "TDD15-COMPLETE: <bead_id>"
   → Output: <promise>READY_FOR_NEXT_TASK</promise>

6. Red Queen (5-10 generations):
   For each generation:
     - Generate adversarial test
     - Run test
     - If FAIL: Fix code, re-run ALL previous tests
     - If PASS: Record and next generation
   → Commit: "RQ-COMPLETE: <bead_id>"
   → Output: <promise>READY_FOR_NEXT_TASK</promise>

7. bd close <bead_id>
8. bd sync && git push
9. Mark task complete in .ralph/ralph-tasks.md
10. Output: <promise>READY_FOR_NEXT_TASK</promise>
11. Loop to step 1
```

## TASK COMPLETION SIGNALS

After completing each major milestone, output:

```
<promise>READY_FOR_NEXT_TASK</promise>
```

**When to signal**:
1. After TDD15 complete (before Red Queen)
2. After Red Queen complete (before closing bead)
3. After closing bead and marking task complete (ready for next bead)

## COMPLETION CRITERIA

Only output `<promise>COMPLETE</promise>` when:
- ALL tasks in .ralph/ralph-tasks.md are marked [x]
- AND `bd ready` returns 0 ready beads
- AND `bd stats` shows 186 closed beads

**Never complete early** - keep replenishing tasks from `bd ready`!

---

## RED QUEEN ADVERSARIAL STRATEGIES

### Generation Patterns
- **Gen 1-2**: Basic edge cases (null, empty, zero, negative)
- **Gen 3-4**: Boundary conditions (max int, overflow, underflow)
- **Gen 5-6**: Race conditions, concurrency, timing attacks
- **Gen 7-8**: Resource exhaustion, large inputs, DOS
- **Gen 9-10**: Creative exploits, assumption violations

### Test Command Examples

**SQL Injection Bead (nuoc-0zq)**:
```nu
# Gen 1: Basic SQL injection
test-sql-injection "'; DROP TABLE jobs;--"

# Gen 2: Unicode bypass
test-sql-injection "'; DROP TABLE jobs;—"  # em-dash instead of hyphen

# Gen 3: Encoding bypass
test-sql-injection (echo "'; DROP TABLE" | encode base64)

# Gen 4: Second-order injection
test-sql-injection-stored "safe" "'; DROP TABLE jobs;--"

# Gen 5: Time-based blind injection
test-sql-timing-attack "' OR SLEEP(10);--"
```

**Deterministic Replay (nuoc-577)**:
```nu
# Gen 1: Kill during operation
test-replay-crash-during-task

# Gen 2: Corrupt journal entry
test-replay-with-corrupted-journal

# Gen 3: Journal truncation
test-replay-with-partial-journal

# Gen 4: Non-determinism detection
test-replay-with-random-divergence

# Gen 5: Concurrent replay attempts
test-replay-concurrent-access
```

### Regression Suite
After each fix, run ALL previous generation tests:
```nu
# Regression gate
run-all-previous-tests <bead_id> <current_generation>
# Must pass ALL tests from gen 1..<current_generation>
# If any fail, this fix broke a previous defense
# Fix must be revised
```

---

## SELF-HEALING PROPERTIES

### How Red Queen Creates Self-Healing

1. **Continuous Stress Testing**
   - Each generation finds new weaknesses
   - No manual QA needed - AI generates adversarial tests

2. **Evolutionary Hardening**
   - Code improves through adversarial selection
   - Weak implementations don't survive

3. **Regression Prevention**
   - All previous tests must still pass
   - Prevents fixes from breaking existing defenses

4. **Comprehensive Coverage**
   - Adversarial tests explore edge cases humans miss
   - Better than random fuzzing - intelligent attacks

5. **Battle-Tested Quality**
   - After 10 generations, code is battle-hardened
   - High confidence in robustness

---

## ITERATION BUDGET

### Per Bead
- **TDD15**: ~15 iterations (phases 0-15)
- **Red Queen**: ~10 iterations (10 generations)
- **Fixes during RQ**: ~3 iterations average
- **Total per bead**: ~28 iterations

### Total Project
- **186 beads** × **28 iterations** = **~5,200 iterations**
- **Safety margin**: Set max to **6,000 iterations**

---

## QUALITY GATES

Before closing each bead, verify:

✅ All TDD15 phases complete (RED → GREEN → REFACTOR → VERIFY)
✅ All acceptance criteria met
✅ Red Queen evolution complete (5-10 generations)
✅ All adversarial tests defended
✅ No regressions (all previous tests still pass)
✅ Code follows Nushell best practices
✅ Git history shows clear phase progression
✅ Bead synced and pushed

---

## COMPLETION SIGNAL

When all 186 beads complete TDD15 + Red Queen:

```
<promise>COMPLETE</promise>

🎉 All 186 NUOC beads implemented and battle-hardened!

Implementation Phase (TDD15):
  ✅ RED phases: 186
  ✅ GREEN phases: 186
  ✅ REFACTOR phases: 186
  ✅ VERIFY phases: 186

Evolution Phase (Red Queen):
  ✅ Total generations: ~1,860 (186 beads × 10 gen avg)
  ✅ Adversarial tests created: ~1,860
  ✅ Attacks defended: ~1,860
  ✅ Implementation fixes: ~558 (30% attack success rate)
  ✅ Regression tests passed: 100%

Final State:
  📊 Total beads: 186
  ✅ Completed: 186
  ❌ Failed: 0
  🛡️ Battle-hardened: 186
  🧪 Total tests: ~3,720 (TDD + adversarial)
  ✅ All tests passing
  🔒 Security-audited: 186
  📈 Evolution complete: 186

Git Commits: ~1,116 (186 beads × 6 commits avg)
  - RED commits: 186
  - GREEN commits: 186
  - REFACTOR commits: 186
  - VERIFY commits: 186
  - RQ-FIX commits: ~186
  - RQ-COMPLETE commits: 186

System Status: PRODUCTION-READY 🚀
  All features implemented ✅
  All features battle-tested ✅
  All regressions prevented ✅
  Self-healing validated ✅
```

---

## STARTING POINT

Begin immediately with dual-phase workflow:

```bash
# Phase 1: Implementation
bd ready | head -1          # Get first bead
bd show <bead_id>           # Read context
# ... execute TDD15 ...

# Phase 2: Evolution
# ... execute Red Queen ...

# Complete
bd close <bead_id>
bd sync && git push

# Loop
bd ready | head -1          # Next bead
```

---

## ERROR RECOVERY

### If Stuck in TDD15
```bash
bd update <bead_id> --notes="TDD15 blocker: <issue>"
bd update <bead_id> --status=open
bd ready  # Get different bead
```

### If Stuck in Red Queen
```bash
# If >5 iterations on single generation
echo "Generation <N> too difficult, skip to next"
# Record in notes
bd update <bead_id> --notes="RQ Gen<N> skipped - needs manual review"
```

### If Regression Fails
```bash
# This is CRITICAL - new fix broke old defenses
# Must fix before proceeding
git diff HEAD~1  # See what changed
# Revise fix to defend both old and new attacks
# Re-run all previous tests
```

---

**START NOW**: Run `bd ready | head -1` and begin TDD15 + Red Queen on the first bead.

**Remember**: First build it right (TDD15), then make it unbreakable (Red Queen).
