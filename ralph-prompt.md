# NUOC Durable Execution Engine - Feature Implementation

## Mission
Implement all P0 features from `ralph-features.json` using strict TDD15 methodology for each bead.

## Context
- Project: NUOC - Restate/Temporal-compatible durable execution engine in Nushell
- Features: 10 P0 features defined in `ralph-features.json`
- Methodology: TDD15 (15-phase test-driven development cycle) for each feature
- Tracking: Beads issue tracker (`bd` commands)

## Workflow

### For Each Feature in ralph-features.json:

1. **Read Feature Definition**
   - Load feature from `ralph-features.json`
   - Note the `bead_id`, acceptance criteria, test steps, and blocked issues
   - Check if feature already passes - if yes, skip to next

2. **Claim Bead**
   ```bash
   bd update <bead_id> --status=in_progress
   ```

3. **Apply TDD15 Methodology**
   Follow the 15-phase cycle:

   **Phase 0: Understanding**
   - Read all referenced files
   - Understand existing architecture
   - Map acceptance criteria to test cases

   **Phase 1-2: RED (Write Failing Tests)**
   - Write tests for acceptance criteria FIRST
   - Run tests, verify they fail
   - Commit: `git commit -m "RED: <bead_id> - failing tests"`

   **Phase 3-7: GREEN (Minimal Implementation)**
   - Implement JUST enough to pass tests
   - No gold-plating, no extra features
   - Run tests frequently
   - Commit: `git commit -m "GREEN: <bead_id> - tests passing"`

   **Phase 8-12: REFACTOR (Clean Code)**
   - Refactor without changing behavior
   - Keep tests green
   - Follow Nushell idioms
   - Commit: `git commit -m "REFACTOR: <bead_id> - clean implementation"`

   **Phase 13-15: VERIFY (Acceptance)**
   - Run all test steps from feature definition
   - Verify all acceptance criteria met
   - Update `passes: true` in ralph-features.json
   - Commit: `git commit -m "VERIFY: <bead_id> - feature complete"`

4. **Close Bead**
   ```bash
   bd close <bead_id> --reason="Implemented via TDD15, all acceptance criteria pass"
   ```

5. **Sync and Continue**
   ```bash
   bd sync
   git push
   ```

6. **Move to Next Feature**
   - Mark current feature `passes: true` in ralph-features.json
   - Proceed to next feature with `passes: false`

## Critical Rules

### TDD15 Discipline
- **NEVER write implementation before tests**
- **NEVER skip the RED phase** - tests must fail first
- **NEVER refactor while tests are red**
- **ALWAYS commit after each phase**: RED → GREEN → REFACTOR → VERIFY

### Quality Gates
- All tests must pass before marking feature complete
- All acceptance criteria must be verified
- Code must follow Nushell best practices
- No SQL injection vectors (parameterized queries only)
- Deterministic replay must work (for replay features)

### Beads Integration
- Use `bd show <bead_id>` to read full issue context
- Use `bd update <bead_id> --status=in_progress` when starting
- Use `bd close <bead_id>` when complete
- Use `bd sync` to push progress to remote

### Error Handling
- If stuck for >3 iterations, add context to bead notes:
  ```bash
  bd update <bead_id> --notes="Blocker: <description>"
  ```
- If dependencies missing, check blocked issues:
  ```bash
  bd show <bead_id>  # See BLOCKS section
  ```

## Progress Tracking

After each feature completion:
1. Update ralph-features.json: `"passes": true`
2. Close bead: `bd close <bead_id>`
3. Commit and push: `git add -A && git commit -m "feat: <bead_id> complete" && git push`
4. Sync beads: `bd sync`

## Completion Signal

Output this exact text when ALL features pass:

```
<promise>COMPLETE</promise>

All 10 P0 features implemented via TDD15:
✅ nuoc-0zq - SQL injection prevention
✅ nuoc-3cd - Phase-prompt dispatcher
✅ nuoc-j14 - 8-state lifecycle
✅ nuoc-577 - Deterministic replay
✅ nuoc-8wi - Complete journal types
✅ nuoc-mnw - 8-state state machine
✅ nuoc-ajp - Services/VirtualObjects/Workflows
✅ nuoc-235 - Service Invocation Protocol
✅ nuoc-26t - Complete Context API
✅ nuoc-a1o - ctx.cancel
```

## Starting Point

Begin with first feature where `passes: false`:
1. Read `ralph-features.json`
2. Find first feature with `"passes": false`
3. Read bead details: `bd show <bead_id>`
4. Start TDD15 Phase 0: Understanding
5. Proceed through all 15 phases
6. Mark complete and move to next

## Notes

- **Persistence**: Ralph sees previous work in files and git history
- **Determinism**: Use git commits to track TDD15 phase transitions
- **Context**: Each iteration has full context from previous work
- **Quality**: TDD15 ensures high test coverage and clean design
- **Beads**: Issue tracker maintains project-wide visibility

---

**Remember**: Tests first, then implementation. RED → GREEN → REFACTOR → VERIFY. No exceptions.
