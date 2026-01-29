# NUOC Documentation Index

**Metadata:**
- **Title:** NUOC Documentation Index
- **Description:** Complete index of NUOC project documentation
- **Last Updated:** 2025-01-29

---

## Core Documentation

### Agent Guidelines
- **[AGENTS.md](../AGENTS.md)** - Core agent guidelines (Opus, Nushell idioms, bead format, bv triage)
  - Build/test commands (Moon)
  - Idiomatic Nushell patterns
  - Model usage (Opus)
  - Writing bead tickets
  - bv triage engine reference

### Technical References
- **[CLAUDE.md](../CLAUDE.md)** - Identical to AGENTS.md (mirrored)
- **[zjj Deep Dive](../zjj-deep-dive.md)** - Complete zjj command reference and workflow
- **[zjj Merge Strategy](../zjj-merge-strategy.md)** - How to safely merge parallel work

### Nushell Documentation (Progressive Disclosure)

**Quick Start:**
- **[Nushell Production Guide - Index](./nushell/INDEX.md)** - Progressive disclosure guide
  - Foundation: Core philosophy, syntax, data manipulation
  - Functional Patterns: Map/filter/reduce, composition, streaming
  - Type System: Type signatures, runtime checking, testing
  - Error Handling: Safe navigation, validation, try/catch
  - Performance: Streaming, parallel processing, optimization
  - Production Patterns: Health checks, logging, deployment
  - Reference: Style guide, anti-patterns, real-world examples

### Ralph Prompts
- **[Ralph/ralph-prompt-zjj-opus-full-rq.md](../Ralph/ralph-prompt-zjj-opus-full-rq.md)** - Opus + full TDD15 + full Red Queen (10 gen)
- **[Ralph/ralph-prompt-fast-zjj.md](../Ralph/ralph-prompt-fast-zjj.md)** - Fast mode (8 phases + 3 gen RQ)

### Scripts
- **[zjj-spawn-parallel.sh](../zjj-spawn-parallel.sh)** - Spawn N parallel Opus workers
- **[zjj-sync-all.sh](../zjj-sync-all.sh)** - Sync all zjj workers to main

---

## Quick Reference

### Moon Commands
```bash
moon run :test     # All tests
moon run :check    # Type check
moon run :quick    # Format + lint
moon run :ci       # Full CI
```

### Idiomatic Nushell
```nu
# Function with types
export def func_name [param: string]: nothing -> record {
  { key: "value" }
}

# Pipeline
list | where status == "PENDING" | each {|x| transform($x)}

# Error handling
try { risky_op } catch {|e|
  { status: "FAILED", error: ($e | get msg? | default "unknown") }
}

# Safe access
$record.field? | default "fallback"
```

### Bead Tickets
```bash
bd create --title="[Category] verb what" --type=task|bug|feature --priority=0-4
```

### bv Triage
```bash
bv --robot-triage       # Mega-command: everything you need
bv --robot-next         # Top pick + claim command
bv --robot-insights     # Full graph metrics
```

---

## External References

- **[Nushell Book](https://www.nushell.sh/book/)** - Official Nushell documentation
- **[Nushell Commands](https://www.nushell.sh/commands/)** - Complete command reference
- **[Jujutsu Documentation](https://docs.jj-vcs.dev/latest/)** - jj version control
- **[zjj](https://github.com/nickgerace/zjj)** - zellij + jj workspace isolation
