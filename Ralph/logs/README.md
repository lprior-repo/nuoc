# Ralph Logs Directory

This directory contains all Ralph execution logs.

## Files

- `ralph-full-*.log` - Complete Ralph session logs
- `babysit-log.txt` - Babysitter monitoring output
- `archive/` - Archived old logs

## Usage

```bash
# Watch live log
tail -f logs/ralph-full-*.log

# View babysitter output
cat logs/babysit-log.txt

# Archive old logs
mv logs/ralph-full-*.log logs/archive/
```

All logs are gitignored and won't be committed to the repository.
