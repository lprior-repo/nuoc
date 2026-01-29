# Ralph Wiggum - Overnight TDD15 Execution Setup

## Quick Start

### Launch Ralph (run overnight)
```bash
./launch-ralph.sh
```

Or manually:
```bash
ralph --prompt-file ralph-prompt.md \
  --agent claude-code \
  --max-iterations 150 \
  --completion-promise "COMPLETE" \
  --allow-all \
  --model anthropic/claude-sonnet-4.5
```

### Monitor Progress (in another terminal)
```bash
./monitor-ralph.sh                 # One-time status check
watch -n 10 ./monitor-ralph.sh     # Auto-refresh every 10s
```

### Watch Live Log
```bash
tail -f ralph-overnight-*.log
```

### Add Mid-Flight Guidance
```bash
ralph --add-context "Focus on the SQL injection fix first"
ralph --add-context "The bug is in oc-engine.nu line 142"
```

### Stop Ralph
```bash
kill $(pgrep -f ralph)    # Graceful stop
# or just Ctrl+C in the Ralph terminal
```

## What Ralph Will Do

Ralph will work through **10 P0 features** using **TDD15 methodology** for each:

1. **nuoc-0zq** - SQL injection prevention
2. **nuoc-3cd** - Phase-prompt dispatcher fix
3. **nuoc-j14** - 8-state lifecycle schema
4. **nuoc-577** - Deterministic replay (CORE)
5. **nuoc-8wi** - Complete journal types
6. **nuoc-mnw** - 8-state state machine
7. **nuoc-ajp** - Services/VirtualObjects/Workflows
8. **nuoc-235** - Service Invocation Protocol
9. **nuoc-26t** - Complete Context API
10. **nuoc-a1o** - ctx.cancel implementation

### TDD15 Phases (per feature)
Each feature goes through 15 phases:
- **0**: Understanding
- **1-2**: RED (write failing tests)
- **3-7**: GREEN (minimal implementation)
- **8-12**: REFACTOR (clean code)
- **13-15**: VERIFY (acceptance testing)

**Total iterations**: ~150 (15 phases × 10 features)

## File Structure

```
ralph-prompt.md         # Master instructions for Ralph
ralph-features.json     # Feature definitions with acceptance criteria
launch-ralph.sh         # Launch script
monitor-ralph.sh        # Progress monitoring script
ralph-overnight-*.log   # Execution logs
.ralph/                 # Ralph working directory (created on first run)
  ├── ralph-tasks.md    # Task tracking (if using --tasks mode)
  └── ralph-context.md  # Pending context/hints
```

## Progress Tracking

### Ralph Status
```bash
ralph --status                # Current iteration, history, struggle indicators
ralph --status --tasks        # Include task list
```

### Beads Status
```bash
bd stats                      # Overall project statistics
bd list --status=in_progress  # Currently working on
bd list --status=closed       # Completed issues
bd ready                      # Ready to work (no blockers)
```

### Features Status
```bash
jq '.features[] | select(.passes == false) | .bead_id' ralph-features.json
# Shows remaining features
```

### Git Status
```bash
git log --oneline -20         # Recent commits (TDD15 phase commits)
git diff                      # Current changes
```

## Expected Behavior

### Per Feature
1. Ralph reads feature from `ralph-features.json`
2. Claims bead: `bd update <bead_id> --status=in_progress`
3. Follows TDD15:
   - Phase 0-2: Understanding + RED (failing tests)
   - Phase 3-7: GREEN (passing tests)
   - Phase 8-12: REFACTOR (clean code)
   - Phase 13-15: VERIFY (acceptance)
4. Updates feature: `"passes": true` in ralph-features.json
5. Closes bead: `bd close <bead_id>`
6. Commits: `git commit -m "feat: <bead_id> complete"`
7. Syncs: `bd sync && git push`
8. Moves to next feature

### Completion Signal
When all 10 features pass, Ralph outputs:
```
<promise>COMPLETE</promise>

All 10 P0 features implemented via TDD15:
✅ nuoc-0zq - SQL injection prevention
...
```

## Troubleshooting

### Ralph Seems Stuck
```bash
ralph --status                        # Check for struggle indicators
ralph --add-context "Try approach X"  # Give it a hint
```

### Check Current Work
```bash
git diff                              # See what Ralph changed
git log -1 --stat                     # Last commit details
bd list --status=in_progress          # Which bead is active
```

### Feature Not Passing
```bash
# Ralph will add notes to bead if stuck >3 iterations
bd show <bead_id>                     # Check notes field
```

### Stop and Resume
```bash
kill $(pgrep -f ralph)                # Stop
./launch-ralph.sh                     # Resume (Ralph sees previous work in files)
```

## Quality Gates

Ralph enforces these automatically:
- ✅ Tests must fail before implementation (RED phase)
- ✅ Tests must pass before refactoring (GREEN phase)
- ✅ All acceptance criteria verified (VERIFY phase)
- ✅ Beads closed only when complete
- ✅ Git commits after each phase
- ✅ bd sync after each feature

## Morning Checklist

When you wake up:

1. **Check completion**:
   ```bash
   tail -50 ralph-overnight-*.log | grep COMPLETE
   ```

2. **Review progress**:
   ```bash
   ./monitor-ralph.sh
   ```

3. **Check features**:
   ```bash
   jq '.features[] | {bead_id, passes}' ralph-features.json
   ```

4. **Review commits**:
   ```bash
   git log --oneline --since="yesterday"
   ```

5. **Check beads**:
   ```bash
   bd stats
   bd list --status=closed | tail -20
   ```

6. **If incomplete**:
   ```bash
   ralph --status              # See where it stopped
   bd list --status=in_progress  # See what's in progress
   # Review blocker and decide to continue or intervene
   ```

## Success Criteria

✅ All 10 features in ralph-features.json have `"passes": true`
✅ All 10 beads closed in beads tracker
✅ All tests passing
✅ Git pushed to remote
✅ Ralph output contains `<promise>COMPLETE</promise>`

---

**Configured for overnight autonomous execution with TDD15 discipline.**
