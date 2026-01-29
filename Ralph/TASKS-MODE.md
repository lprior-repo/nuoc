# Ralph Tasks Mode - Dynamic Workflow for All 186 Beads

## ✅ Properly Configured

Ralph is now set up to work through **ALL 186 beads** using Tasks Mode with dynamic task replenishment.

---

## 🔄 How It Works

### 1. Initial Task Population

On first iteration, Ralph will:
```bash
# Get first 20 ready beads
bd ready | head -20
# Add to .ralph/ralph-tasks.md as uncompleted tasks
```

### 2. Work Through Tasks

For each task:
1. Mark as `[/]` (in progress)
2. Execute TDD15 workflow (RED → GREEN → REFACTOR → VERIFY)
3. Execute Red Queen evolution (5-10 adversarial generations)
4. Close bead and mark task `[x]` (complete)
5. Output `<promise>READY_FOR_NEXT_TASK</promise>`

### 3. Automatic Task Replenishment

**Before each iteration**, Ralph checks:
```bash
PENDING=$(grep -c "^\- \[ \]" .ralph/ralph-tasks.md)

if [ $PENDING -lt 5 ]; then
  # Add 10 more beads from bd ready
  bd ready | head -10 >> .ralph/ralph-tasks.md
fi
```

This ensures the task list **never runs empty** until all beads are done.

### 4. Completion Detection

Ralph only outputs `<promise>COMPLETE</promise>` when:
- ✅ All tasks in `.ralph/ralph-tasks.md` are `[x]`
- ✅ `bd ready` returns 0 beads
- ✅ `bd stats` shows 186 closed beads

---

## 📊 Current Status

**Already Complete:** 10 / 186 beads (5.4%)
- ✅ Full Awakeable system implemented

**Ready to Work:** 40 beads (no blockers)
**Blocked:** 136 beads (unlock as dependencies complete)

---

## 🚀 Launch Command

```bash
./launch-ralph-full.sh
```

This will:
- Start Ralph with tasks mode enabled
- Populate initial 20 tasks from `bd ready`
- Work through tasks with TDD15 + Red Queen
- Auto-replenish tasks as they complete
- Continue until all 186 beads are closed

---

## 📁 Key Files

- **launch-ralph-full.sh** - Main launch script (--tasks enabled)
- **ralph-prompt-with-red-queen.md** - Instructions with dynamic task logic
- **monitor-ralph-full.sh** - Progress monitoring
- **babysit-ralph.sh** - 8-hour auto-monitoring
- **.ralph/ralph-tasks.md** - Task list (created on first run)

---

## 🔍 Monitoring

### Watch Progress
```bash
# Real-time monitoring (refresh every 10s)
watch -n 10 ./monitor-ralph-full.sh

# View task list
cat .ralph/ralph-tasks.md

# Check beads status
bd stats
bd ready

# Watch log
tail -f ralph-full-*.log
```

### Check Ralph Status
```bash
ralph --status --tasks
```

---

## 🎯 What Ralph Will Do

### Per Bead (20-25 minutes each)

1. **TDD15 (15 phases):**
   - Phase 0: Understanding
   - Phase 1-2: RED (write failing tests)
   - Phase 3-7: GREEN (make tests pass)
   - Phase 8-12: REFACTOR (clean code)
   - Phase 13-15: VERIFY (acceptance testing)

2. **Red Queen (5-10 generations):**
   - Generate adversarial tests
   - Find weaknesses
   - Fix and defend
   - Build battle-hardened code

3. **Complete:**
   - Close bead
   - Mark task complete
   - Sync and push
   - Move to next task

### Overall Progress (176 beads remaining)

At ~25 min/bead:
- **176 beads** × 25 min = **~73 hours** (3 days)
- With parallel work and optimization, likely faster
- Can run multiple 8-hour sessions

---

## ✅ Quality Guarantees

Every completed bead will have:
- ✅ Full TDD15 test coverage
- ✅ Red Queen battle-testing
- ✅ Clean git commits with phase markers
- ✅ All acceptance criteria met
- ✅ CI pipeline passing
- ✅ Code pushed to main

---

## 🆘 Troubleshooting

### If Ralph Stops Early

Check:
```bash
# Is task list empty?
cat .ralph/ralph-tasks.md

# Are there ready beads?
bd ready

# What's the last log entry?
tail -50 ralph-full-*.log
```

If task list is empty but beads remain:
```bash
# Manually replenish
bd ready | head -20 > .ralph/ralph-tasks.md
# Restart Ralph
./launch-ralph-full.sh
```

### If Stuck on One Bead

Ralph will auto-recover, but you can assist:
```bash
# Add context hint
ralph --add-context "Skip if stuck >30 min, move to next"
```

---

**Ready to complete all 186 beads with TDD15 + Red Queen!** 🚀
