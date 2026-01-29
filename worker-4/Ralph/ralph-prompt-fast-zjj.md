# NUOC - Fast TDD15 + Red Queen for zjj Parallel Workers

## Mission
Implement beads using **FAST MODE TDD15** + **streamlined Red Queen** for parallel zjj worker processing.

## FAST MODE Configuration

**Iteration Budgets (per bead)**:
- TDD15: **8 phases** (not 15) - skip review/documentation phases
- Red Queen: **3 generations** (not 10) - critical attacks only
- Total: **~12 iterations per bead** (down from 28)

**Speed**: **~2.3x faster** than standard Ralph

---

## COMPLETE WORKFLOW PER BEAD

### 1. Claim Bead
```bash
bd update <bead_id> --status=in_progress
```

### 2. Read Context
```bash
bd show <bead_id>
```

### 3. FAST TDD15 (8 Phases)

**Phase 0: Understanding** (1 iteration)
- Read all referenced files
- Map acceptance criteria
- Identify changes needed

**Phase 1-2: RED** (1 iteration)
- Write failing tests
- Verify they fail correctly
- Commit: `git add -A && git commit -m "RED: <bead_id>"`

**Phase 3-5: GREEN** (2 iterations)
- Minimal implementation
- Make tests pass
- Commit: `git add -A && git commit -m "GREEN: <bead_id>"`

**Phase 6-7: REFACTOR** (2 iterations)
- Clean code, keep tests green
- Follow Nushell idioms from https://www.nushell.sh/book/
- Use Moon for all commands: `moon run :test`
- Commit: `git add -A && git commit -m "REFACTOR: <bead_id>"`

**Phase 8: VERIFY** (2 iterations)
- Check acceptance criteria
- Run `moon run :ci`
- Commit: `git add -A && git commit -m "VERIFY: <bead_id>"`

### 4. FAST RED QUEEN (3 Generations)

**Generation 1: Basic Edge Cases**
- Generate test for null/empty/zero/negative inputs
- Run test
- If FAIL: Fix, re-run all previous tests, commit fix
- If PASS: Record and move on

**Generation 2: Boundary Conditions**
- Generate test for max/overflow/underflow
- Run test
- If FAIL: Fix, re-run all previous tests, commit fix
- If PASS: Record and move on

**Generation 3: One Critical Attack**
- Generate test for most important attack vector (SQL injection, race condition, etc.)
- Run test
- If FAIL: Fix, re-run all previous tests, commit fix
- If PASS: Record complete

### 5. Close and Sync
```bash
git add -A && git commit -m "COMPLETE: <bead_id> - TDD15 + RQ fast mode"
bd close <bead_id> --reason="Complete - TDD15 + Red Queen fast mode"
bd sync
git push
```

### 6. Request Next Task
```bash
# Get next ready bead
bd ready | head -1
# Loop back to step 1
```

---

## CRITICAL RULES

1. **Use Moon ONLY** - Never use cargo/nu directly
2. **Consult Nushell docs** - https://www.nushell.sh/book/ for idioms
3. **Commit every phase** - Git history must show progression
4. **Defend all previous RQ tests** - Regression gate is mandatory
5. **Never skip quality** - Fast mode cuts iterations, not quality

---

## QUALITY GATES

Before closing bead:
- ✅ All TDD15 phases complete (RED → GREEN → REFACTOR → VERIFY)
- ✅ All acceptance criteria met
- ✅ Red Queen: 3 generations defended
- ✅ All previous RQ tests still pass (regression check)
- ✅ `moon run :ci` passes
- ✅ Bead synced and pushed
- ✅ Task marked complete

---

## SIGNALS

After TDD15 complete: `<promise>READY_FOR_RED_QUEEN</promise>`
After Red Queen complete: `<promise>READY_FOR_NEXT_TASK</promise>`

---

## COMPLETION

When all beads complete:
```
<promise>COMPLETE</promise>

🎉 All NUOC beads implemented (fast mode)!

Implementation Phase (TDD15):
  ✅ RED phases: 186
  ✅ GREEN phases: 186
  ✅ REFACTOR phases: 186
  ✅ VERIFY phases: 186

Evolution Phase (Red Queen):
  ✅ Total generations: 558 (186 beads × 3 gen)
  ✅ Adversarial tests: 558
  ✅ Attacks defended: 558
  ✅ Regression tests: 100%

Total: ~2,232 iterations (down from ~5,200)
Speed: ~2.3x faster
```

---

## START NOW

```bash
bd ready | head -1
bd show <bead_id>
# Execute FAST TDD15 + RQ workflow
```

**Remember**: Fast mode = fewer iterations, same quality.
