# Ralph Quick Start

## 🚀 Launch Ralph (Work ALL 186 Beads)

```bash
./launch-ralph-full.sh
```

## 📊 Monitor Progress (in another terminal)

```bash
# Auto-refresh every 10 seconds
watch -n 10 ./monitor-ralph-full.sh

# Or manual check
./monitor-ralph-full.sh
```

## 📋 Check Status

```bash
# Ralph status
ralph --status --tasks

# Beads progress
bd stats
bd ready

# Task list
cat Ralph/.ralph/ralph-tasks.md

# Live log
tail -f Ralph/logs/ralph-full-*.log
```

## 🛑 Stop Ralph

```bash
# Graceful stop
kill $(pgrep -f ralph)

# Or just Ctrl+C in Ralph terminal
```

## 📈 Progress Summary

- **Complete:** 10 / 186 beads (5.4%)
- **Remaining:** 176 beads
- **Ready:** 40 beads (no blockers)
- **Method:** TDD15 + Red Queen per bead

## 📚 Documentation

- `README-RALPH.md` - Complete guide
- `RALPH-TASKS-MODE.md` - Tasks mode details
- Full prompt: `ralph-prompt-with-red-queen.md`

---

**Ralph will work through all 186 beads automatically with dynamic task replenishment.**
