# Ralph Wiggum - Autonomous TDD15 + Red Queen Implementation

## 🎯 Quick Start - Run Overnight

```bash
./launch-ralph-full.sh
```

This will:
- Work through **ALL 186 beads** automatically
- Apply **TDD15** (15-phase test-driven development) to each
- Apply **Red Queen** adversarial evolution to each
- Create a **self-healing, battle-hardened** implementation
- Run for **~6,000 iterations** (estimated 8-12 hours)

## 📊 What Gets Built

### Workflow Per Bead

```
┌─────────────────────────────────────────────────────────┐
│ 1. Get next ready bead (bd ready | head -1)            │
│ 2. Claim it (bd update <id> --status=in_progress)      │
└─────────────────────────────────────────────────────────┘
                         ↓
┌─────────────────────────────────────────────────────────┐
│ PHASE 1: TDD15 IMPLEMENTATION (~15 iterations)         │
├─────────────────────────────────────────────────────────┤
│ Phase 0:    Understanding                               │
│ Phase 1-2:  RED (write failing tests)                   │
│ Phase 3-7:  GREEN (make tests pass)                     │
│ Phase 8-12: REFACTOR (clean code)                       │
│ Phase 13-15: VERIFY (acceptance testing)                │
│                                                          │
│ Result: Working implementation with full test coverage  │
└─────────────────────────────────────────────────────────┘
                         ↓
┌─────────────────────────────────────────────────────────┐
│ PHASE 2: RED QUEEN EVOLUTION (~10 iterations)          │
├─────────────────────────────────────────────────────────┤
│ For 5-10 generations:                                   │
│   1. Generate adversarial test                          │
│   2. Run test against implementation                    │
│   3. If FAIL: Fix code, defend against attack          │
│   4. If PASS: Record victory, next generation          │
│   5. Always re-run ALL previous tests (regression)     │
│                                                          │
│ Result: Battle-hardened, self-healing implementation    │
└─────────────────────────────────────────────────────────┘
                         ↓
┌─────────────────────────────────────────────────────────┐
│ 3. Close bead (bd close <id>)                          │
│ 4. Sync (bd sync && git push)                          │
│ 5. Loop to next bead                                    │
└─────────────────────────────────────────────────────────┘
```

## 🧬 Self-Healing Properties

The Red Queen evolution ensures:

1. **Adversarial Testing**: AI generates progressively harder attacks
2. **Evolutionary Hardening**: Weak code doesn't survive
3. **Regression Prevention**: All previous tests must still pass
4. **Comprehensive Coverage**: Explores edge cases humans miss
5. **Battle-Tested Quality**: Each feature survives 10 adversarial generations

## 📁 Files

```
ralph-prompt-with-red-queen.md  # Master instructions (TDD15 + Red Queen)
launch-ralph-full.sh            # Launch script (use this!)
monitor-ralph-full.sh           # Progress monitor
ralph-full-*.log                # Execution logs
.ralph/                         # Ralph working directory
```

## 🔍 Monitor Progress

### In Another Terminal

```bash
# One-time status
./monitor-ralph-full.sh

# Auto-refresh every 10 seconds
watch -n 10 ./monitor-ralph-full.sh

# Watch live log
tail -f ralph-full-*.log

# Check Ralph's internal status
ralph --status

# Check beads progress
bd stats
bd list --status=closed | tail -20
```

### Progress Indicators

The monitor shows:
- **Ralph loop status** (iteration, elapsed time)
- **Beads statistics** (total, completed, remaining)
- **Current work** (in-progress beads)
- **Recent completions** (last 5 closed)
- **Next up** (ready beads)
- **Git activity** (recent commits)
- **Phase distribution** (RED/GREEN/REFACTOR/VERIFY/RQ counts)
- **Progress bar** (visual percentage)

## 🎛️ Control Ralph Mid-Flight

### Add Hints/Guidance
```bash
ralph --add-context "Focus on SQL injection first"
ralph --add-context "The bug is in oc-engine.nu line 142"
```

### Stop Gracefully
```bash
kill $(pgrep -f ralph)
# or just Ctrl+C in the Ralph terminal
```

### Resume After Stop
```bash
./launch-ralph-full.sh
# Ralph sees previous work in git history and continues
```

## 📈 Progress Tracking

### By The Numbers

- **Total beads**: 186
- **Iterations per bead**: ~28 (15 TDD15 + 10 Red Queen + 3 fixes)
- **Total iterations**: ~5,200
- **Max allowed**: 6,000 (safety margin)
- **Estimated time**: 8-12 hours

### Dependencies

- **Ready to work**: 38 beads initially (no blockers)
- **Blocked**: 148 beads initially (waiting on dependencies)
- **As beads complete**: Blocked beads become unblocked automatically
- **bd ready**: Always shows next unblocked bead

### Quality Gates Per Bead

✅ All TDD15 phases complete
✅ All acceptance criteria met
✅ Red Queen evolution complete (5-10 generations)
✅ All adversarial tests defended
✅ No regressions
✅ Code follows best practices
✅ Git history shows clear phases
✅ Bead closed and synced

## 🌅 Morning Checklist

When you wake up:

```bash
# 1. Check completion
tail -100 ralph-full-*.log | grep COMPLETE

# 2. Overall progress
./monitor-ralph-full.sh

# 3. Beads status
bd stats

# 4. Recent work
git log --oneline --since="yesterday" | head -20

# 5. Phase distribution
git log --oneline --since="yesterday" | grep -E "RED:|GREEN:|REFACTOR:|VERIFY:|RQ-" | wc -l

# 6. Any issues?
ralph --status  # Check for struggle indicators
```

## ✅ Success Criteria

Ralph completes when:

✅ All 186 beads closed
✅ All tests passing
✅ All adversarial generations defended
✅ Git pushed to remote
✅ Output contains `<promise>COMPLETE</promise>`

Expected output:
```
<promise>COMPLETE</promise>

🎉 All 186 NUOC beads implemented and battle-hardened!

Total beads: 186
Completed: 186
Failed: 0
Battle-hardened: 186
Total tests: ~3,720
System Status: PRODUCTION-READY 🚀
```

## 🐛 Troubleshooting

### Ralph Seems Stuck
```bash
ralph --status  # Check struggle indicators
ralph --add-context "Try different approach"
```

### Check Current Bead
```bash
bd list --status=in_progress
bd show <bead_id>
```

### Check Last Commit
```bash
git log -1 --stat
git diff HEAD~1
```

### Stop and Investigate
```bash
kill $(pgrep -f ralph)
git log --oneline -20
bd list --status=in_progress
# Review and decide whether to continue or intervene
```

## 🚀 Launch Options

### Full Run (Recommended)
```bash
./launch-ralph-full.sh
```
- All 186 beads
- TDD15 + Red Queen
- 6,000 max iterations
- Overnight execution

### Test Run (First 10 beads only)
```bash
ralph --prompt-file ralph-prompt-with-red-queen.md \
  --max-iterations 300 \
  --completion-promise "COMPLETE" \
  --allow-all
```

### Verbose Mode (Debug)
```bash
ralph --prompt-file ralph-prompt-with-red-queen.md \
  --max-iterations 6000 \
  --completion-promise "COMPLETE" \
  --allow-all \
  --verbose-tools
```

## 📖 Methodology Deep Dive

### TDD15 (Test-Driven Development - 15 Phases)

**RED** → Write tests that fail
**GREEN** → Make tests pass minimally
**REFACTOR** → Clean up while keeping tests green
**VERIFY** → Validate all acceptance criteria

### Red Queen (Adversarial Evolutionary QA)

Named after the Red Queen hypothesis: "It takes all the running you can do, to keep in the same place."

1. Generate adversarial test (attack)
2. Run test against implementation
3. If test fails → implementation has weakness → fix it
4. If test passes → implementation defended → harder attack
5. Each fix must defend against ALL previous attacks (regression suite)
6. After 10 generations → battle-hardened implementation

### Self-Healing Loop

```
Implementation → Adversarial Test → Weakness Found → Fix
       ↑                                              ↓
       ←──────────── Defend + Evolve ←────────────────
```

Code and tests coevolve until robust.

## 🎯 What Makes This Different

### Traditional Development
- Write code
- Write some tests
- Ship when tests pass
- ⚠️ Unknown edge cases lurking

### TDD15 Only
- Write tests first
- Build to spec
- Refactor safely
- ✅ Good test coverage
- ⚠️ Only tests YOU thought of

### TDD15 + Red Queen
- Write tests first
- Build to spec
- Battle-test with adversarial AI
- AI finds edge cases you missed
- Fix weaknesses
- Prove defenses with regression suite
- ✅✅ Battle-hardened, self-healing system

## 📚 Additional Resources

- **Ralph help**: `ralph --help`
- **Beads help**: `bd --help`
- **Monitor script**: `./monitor-ralph-full.sh`
- **Full prompt**: `ralph-prompt-with-red-queen.md`

---

**Ready to launch?**

```bash
./launch-ralph-full.sh
```

Then monitor in another terminal:
```bash
watch -n 10 ./monitor-ralph-full.sh
```

---

**Configured for autonomous overnight execution with battle-hardening.**
