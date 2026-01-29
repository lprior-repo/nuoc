# NUOC - Full TDD15 + Red Queen for zjj Parallel Workers (Opus)

## Mission
Implement beads using **full TDD15** + **full Red Queen (10 generations)** for maximum quality with Opus model.

## MODEL: Opus (claude-opus-4-5-20251101)

**ALWAYS use Opus** for:
- All code generation
- All test generation
- All architectural decisions
- Red Queen adversarial testing
- Code reviews and refactoring

---

## COMPLETE WORKFLOW PER BEAD

### 1. Claim Bead
```bash
bd update <bead_id> --status=in_progress
bd show <bead_id>
```

### 2. FULL TDD15 (15 Phases)

**Phase 0: Understanding** (2 iterations)
- Read all referenced files
- Map acceptance criteria to test cases
- Identify dependencies and integration points
- Consult https://www.nushell.sh/book/ for idioms

**Phase 1-2: RED** (3 iterations)
- Write comprehensive failing tests
- Verify tests fail for correct reasons
- Edge cases covered
- Commit: `git add -A && git commit -m "RED: <bead_id> - failing tests"`

**Phase 3-7: GREEN** (5 iterations)
- Minimal, correct implementation
- Make all tests pass
- No gold plating
- Use Moon commands: `moon run :test`, `moon run :ci`
- Commit: `git add -A && git commit -m "GREEN: <bead_id> - tests passing"`

**Phase 8-12: REFACTOR** (5 iterations)
- Clean code while keeping tests green
- Apply Nushell idioms from https://www.nushell.sh/book/
- Optimize for clarity and maintainability
- Commit: `git add -A && git commit -m "REFACTOR: <bead_id> - clean code"`

**Phase 13-15: VERIFY** (5 iterations)
- All acceptance criteria met
- Full test suite passes: `moon run :ci`
- Documentation updated if needed
- Code review self-assessment
- Commit: `git add -A && git commit -m "VERIFY: <bead_id> - acceptance complete"`

### 3. FULL RED QUEEN (10 Generations)

**Generation 1-2: Basic Edge Cases**
- Null, empty, zero, negative inputs
- Optional parameters missing
- Type violations

**Generation 3-4: Boundary Conditions**
- Max int, overflow, underflow
- Empty collections
- Single item collections
- Unicode edge cases

**Generation 5-6: Concurrency & Timing**
- Race conditions
- Concurrent access patterns
- Time-based attacks
- Resource exhaustion

**Generation 7-8: Integration & State**
- Database state consistency
- Transaction boundaries
- SQL injection attempts
- State machine violations

**Generation 9-10: Creative Exploits**
- Assumption violations
- Unexpected input combinations
- Protocol violations
- Environmental failures (disk full, network down, etc.)

**Per Generation:**
1. Generate adversarial test targeting weakness
2. Run test against implementation
3. If FAIL: Fix implementation, re-run ALL previous generation tests (regression gate)
4. If PASS: Record and advance
5. Commit each fix: `git commit -m "RQ-FIX: <bead_id> gen<N> - <attack description>"`

**Critical Rule**: All previous tests MUST still pass after each fix. This is non-negotiable.

### 4. Close and Sync
```bash
git add -A && git commit -m "COMPLETE: <bead_id> - TDD15 + Red Queen full (10 gen)"
bd close <bead_id> --reason="Complete - Full TDD15 + 10-gen Red Queen with Opus"
bd sync
git push
```

---

## JJ MERGE STRATEGY (For Landing to Main)

When zjj worker completes bead, the isolated workspace must land to main:

### Option 1: Direct jj rebase (Preferred for isolated beads)
```bash
# In zjj workspace:
jj rebase -d main              # Rebase work on latest main
jj git push                    # Push to remote
```

### Option 2: Mega-merge strategy (For coordinating multiple workers)
```bash
# In main repo:
jj new worker1 worker2 worker3  # Create merge commit with all worker branches
# Resolve any conflicts
jj git push
```

### Key Principles from Orchestration Tools:
1. **Hermetic builds** - Each workspace is isolated (like Bazel/Pants)
2. **Incremental** - Only merge what changed (like Nx/Turborepo affected graph)
3. **Parallel-safe** - No overlapping files between workers (partition beads by module)
4. **Verified before merge** - All tests pass in workspace before landing

---

## QUALITY GATES (Non-Negotiable)

Before closing bead:
- ✅ All 15 TDD15 phases complete (RED → GREEN → REFACTOR → VERIFY)
- ✅ All acceptance criteria met
- ✅ Red Queen: 10 generations defended
- ✅ All previous RQ tests still pass (100% regression gate)
- ✅ `moon run :ci` passes
- ✅ Code follows Nushell idioms (nushell.sh)
- ✅ Bead synced and pushed to main
- ✅ No jj merge conflicts left unresolved

---

## SIGNALS

After TDD15 complete: `<promise>READY_FOR_RED_QUEEN</promise>`
After Red Queen complete: `<promise>READY_FOR_MERGE</promise>`
After merged to main: `<promise>READY_FOR_NEXT_TASK</promise>`

---

## START NOW

```bash
bd ready | head -1
bd show <bead_id>
# Execute FULL TDD15 + FULL RED QUEEN workflow with Opus
```

**Remember**: Opus + full TDD15 + full Red Queen = maximum quality, battle-hardened code.
