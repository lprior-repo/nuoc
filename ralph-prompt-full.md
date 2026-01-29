# NUOC - Complete Implementation of All 186 Beads with TDD15

## Mission
Implement ALL 186 beads in the nuoc project using strict TDD15 methodology. Work through dependencies systematically - as you complete beads, blocked beads become unblocked.

## Current Status
- **Total beads**: 186
- **Ready to work**: Check dynamically with `bd ready`
- **Blocked**: Will become ready as dependencies complete
- **Methodology**: TDD15 for every single bead

## Core Workflow Loop

### 1. Get Next Ready Bead
```bash
bd ready | head -1
```
This shows the highest priority bead with no blockers.

### 2. Read Full Bead Context
```bash
bd show <bead_id>
```
Read the full issue description, acceptance criteria, dependencies, and notes.

### 3. Claim the Bead
```bash
bd update <bead_id> --status=in_progress
```

### 4. Execute TDD15 Cycle (15 Phases)

**Phase 0: Understanding** (1-2 iterations)
- Read all referenced files
- Understand the acceptance criteria
- Map requirements to test cases
- Identify what needs to change

**Phase 1-2: RED - Write Failing Tests** (2-3 iterations)
- Write tests FIRST that verify acceptance criteria
- Run tests, verify they FAIL with expected errors
- Commit: `git add -A && git commit -m "RED: <bead_id> - failing tests for <title>"`
- **CRITICAL**: Tests must fail before implementation

**Phase 3-7: GREEN - Minimal Implementation** (3-5 iterations)
- Implement JUST enough to make tests pass
- No extra features, no gold plating
- Run tests frequently
- When all tests pass, commit: `git add -A && git commit -m "GREEN: <bead_id> - tests passing"`
- **CRITICAL**: Make tests pass with minimal code

**Phase 8-12: REFACTOR - Clean Code** (3-5 iterations)
- Improve code quality while keeping tests green
- Follow Nushell idioms
- Remove duplication
- Improve names and structure
- Run tests after each refactor
- Commit: `git add -A && git commit -m "REFACTOR: <bead_id> - clean implementation"`
- **CRITICAL**: Tests stay green during refactoring

**Phase 13-15: VERIFY - Acceptance Testing** (2-3 iterations)
- Run all acceptance criteria from bead description
- Verify ATDD tests pass
- Verify DBC contracts hold
- Verify BDD scenarios work
- Run full test suite
- Commit: `git add -A && git commit -m "VERIFY: <bead_id> - all acceptance criteria pass"`

### 5. Close the Bead
```bash
bd close <bead_id> --reason="Implemented via TDD15, all tests pass"
```

### 6. Sync Progress
```bash
bd sync
git push
```

### 7. Check Progress and Continue
```bash
bd stats  # See how many remain
bd ready  # Get next bead
```

### 8. Loop Until Complete
Repeat steps 1-7 until `bd stats` shows **0 open beads**.

## TDD15 Discipline - CRITICAL RULES

### Red Phase Rules
- ✅ **MUST** write tests before implementation
- ✅ **MUST** verify tests fail initially
- ✅ Tests should fail for the RIGHT reason (not syntax errors)
- ❌ **NEVER** write implementation code in RED phase
- ❌ **NEVER** skip RED phase

### Green Phase Rules
- ✅ **MUST** make tests pass with minimal code
- ✅ Run tests frequently (after every small change)
- ✅ Hardcode values if needed - refactor later
- ❌ **NEVER** add features beyond acceptance criteria
- ❌ **NEVER** refactor while tests are red

### Refactor Phase Rules
- ✅ **MUST** keep tests green throughout
- ✅ Run tests after every refactoring step
- ✅ Improve design, remove duplication, enhance readability
- ❌ **NEVER** add new functionality
- ❌ **NEVER** refactor with failing tests

### Verify Phase Rules
- ✅ **MUST** check all acceptance criteria
- ✅ Run full test suite
- ✅ Verify edge cases
- ✅ Check BDD scenarios if present
- ❌ **NEVER** skip verification steps

## Dependency Management

### Handling Blocked Beads
- Some beads depend on others (shown in `bd show <bead_id>` BLOCKS section)
- `bd ready` automatically filters to show only unblocked beads
- As you complete beads, their dependents become unblocked
- **Strategy**: Always work on `bd ready` beads - this maximizes parallelizable work

### Priority Order
- P0 beads first (critical path)
- Then P1, P2, etc.
- Within same priority, work top to bottom from `bd ready`

## Quality Gates - Must Pass Before Closing Bead

1. ✅ All tests pass
2. ✅ All acceptance criteria verified
3. ✅ Code follows Nushell best practices
4. ✅ No TODOs or FIXME comments
5. ✅ Git commits show clear RED → GREEN → REFACTOR → VERIFY progression
6. ✅ Bead description requirements fully met
7. ✅ If bead has ATDD/BDD/DBC specs, all must pass

## Special Cases

### Bug Beads
- Write regression test that reproduces the bug (RED)
- Fix the bug (GREEN)
- Refactor if needed (REFACTOR)
- Verify fix works (VERIFY)

### Feature Beads
- Break down into smaller test cases
- Implement incrementally
- Each slice follows TDD15

### Task Beads
- Often simpler (schema changes, config updates)
- Still follow TDD15 - write tests for schema, verify migrations work
- Don't skip phases even if "simple"

## Progress Tracking

### After Each Bead
```bash
echo "✅ Completed <bead_id>"
bd stats  # Show updated progress
bd ready | head -5  # Preview next work
```

### Periodic Status
Every 10 beads, output progress report:
```
Progress Report:
  Completed: X/186
  Remaining: Y
  Ready to work: Z
  Blocked: W
  Last completed: <bead_id> - <title>
```

### Mid-Flight Recovery
If interrupted:
```bash
bd list --status=in_progress  # See what was in progress
bd update <bead_id> --status=open  # Reset if needed
bd ready  # Get next ready bead
```

## Iteration Budget

- **Total beads**: 186
- **Average phases per bead**: 15
- **Average iterations per phase**: 1-2
- **Estimated total iterations**: 186 × 15 × 1.5 = ~4,200 iterations
- **Safety margin**: Set max to 5,000

## Completion Signal

When ALL beads complete, output:

```
<promise>COMPLETE</promise>

🎉 All 186 NUOC beads implemented via TDD15!

Final Statistics:
  Total beads: 186
  Completed: 186
  Failed: 0

TDD15 Phases Executed:
  RED phases: 186
  GREEN phases: 186
  REFACTOR phases: 186
  VERIFY phases: 186

Git commits: ~744 (186 × 4 phases)
All tests passing ✅
All acceptance criteria met ✅
Beads synced and pushed ✅
```

## Error Handling

### If Stuck on a Bead (>20 iterations)
```bash
bd update <bead_id> --notes="BLOCKER: <description of issue>"
bd update <bead_id> --status=open  # Release for later
bd ready  # Get a different bead
```

### If Tests Won't Pass
- Review acceptance criteria - are tests correct?
- Check for missing dependencies
- Verify test environment setup
- Add detailed notes to bead before moving on

### If Build Breaks
- Fix build FIRST before continuing
- Build breakage = immediate priority
- Use `git log` to find what changed
- Revert if necessary, fix properly

## Code Quality Standards

### Nushell Best Practices
- Use pipes and functional style
- Prefer immutability
- Use type hints where helpful
- Follow existing code patterns
- Keep functions small and focused

### Security
- **CRITICAL**: All SQL must use parameterized queries (nuoc-0zq)
- Validate all external inputs
- No hardcoded secrets
- Follow least privilege

### Testing
- Test files named `test_*.nu` or `*_test.nu`
- Use descriptive test names
- One assertion per test when possible
- Test edge cases and error paths

## Starting Point

Begin immediately:

1. Run `bd ready | head -1` to get first bead
2. Run `bd show <bead_id>` to read full context
3. Start TDD15 Phase 0: Understanding
4. Proceed through all 15 phases
5. Close bead and get next from `bd ready`
6. Continue until all 186 beads complete

## Notes

- Each bead gets full TDD15 treatment - no shortcuts
- Dependencies resolve automatically as beads complete
- Git history will show clear phase progression
- Beads tracker maintains project state
- Tests are the source of truth for "done"

---

**START NOW**: Run `bd ready | head -1` and begin TDD15 on the first available bead.
