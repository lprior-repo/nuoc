# Ralph Wiggum - Autonomous TDD15 + Red Queen Loop

Complete autonomous implementation system for all 186 NUOC beads.

## Quick Start

From project root:
```bash
./launch-ralph.sh
```

Or from this directory:
```bash
./launch-ralph-full.sh
```

## Documentation

- **QUICKSTART.md** - Quick reference guide
- **TASKS-MODE.md** - Detailed tasks mode workflow
- **GUIDE.md** - Complete user guide

## Files

**Scripts:**
- `launch-ralph-full.sh` - Main launcher
- `monitor-ralph-full.sh` - Progress monitor
- `babysit-ralph.sh` - 8-hour auto-monitor

**Configuration:**
- `ralph-prompt-with-red-queen.md` - TDD15 + Red Queen instructions

**Documentation:**
- `README.md` - This file
- `QUICKSTART.md` - Quick reference
- `TASKS-MODE.md` - Tasks workflow
- `GUIDE.md` - Complete guide

**Logs:**
- `logs/` - All execution logs (gitignored)
- `.ralph/` - Ralph working directory (gitignored)

## Status

- **Complete:** 10 / 186 beads (5.4%)
- **Remaining:** 176 beads
- **Method:** TDD15 + Red Queen per bead

Each bead gets:
- Full test coverage (TDD15)
- Battle-hardened with adversarial testing (Red Queen)
- Clean git commits
- Quality gates

## Launch

```bash
cd ..
./launch-ralph.sh
```
