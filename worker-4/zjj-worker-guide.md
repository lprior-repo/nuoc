# zjj Parallel Bead Processing - Worker Guide

## Overview

Each zjj workspace is an **isolated jj environment** for implementing a single bead. Workers run in parallel, each using Moon + TDD15 + Red Queen.

## Spawning Workers

```bash
# Spawn 8 parallel workers (auto-assigns beads)
./zjj-spawn-workers.sh 8

# Or spawn specific number
./zjj-spawn-workers.sh 4
```

## Worker Workflow (Per Workspace)

### 1. Enter Workspace
```bash
zjj attach bead-nuoc-xxx
```

### 2. Claim Bead
```bash
bd update nuoc-xxx --status=in_progress
bd show nuoc-xxx
```

### 3. Implement Using TDD15 + Red Queen

**Use Moon (Haiku) for all code generation:**

```bash
# In Claude, specify:
model: haiku

# Reference these docs:
- CLAUDE.md (full guidelines)
- AGENTS.md (same content)
- https://www.nushell.sh/book/ (idioms)
```

**TDD15 Phases** (8 fast phases):
1. **Understanding** - Read context, map tests
2. **RED** - Write failing tests, `git commit -m "RED: nuoc-xxx"`
3. **GREEN** - Make tests pass, `git commit -m "GREEN: nuoc-xxx"`
4. **REFACTOR** - Clean code, `git commit -m "REFACTOR: nuoc-xxx"`
5. **VERIFY** - `moon run :ci`, `git commit -m "VERIFY: nuoc-xxx"`

**Red Queen** (3 generations):
1. Gen 1: Basic edge cases
2. Gen 2: Boundary conditions
3. Gen 3: Critical attack

### 4. Close and Sync
```bash
bd close nuoc-xxx --reason="Complete - TDD15 + Red Queen"
bd sync
git push
```

### 5. Exit and Get Next Bead
```bash
# Exit workspace
exit

# Spawn new worker for next bead
./zjj-spawn-workers.sh 1
```

## Monitoring

```bash
# See all workers
zjj status

# List all workers
zjj list

# Sync all workers to main
zjj sync

# Attach to specific worker
zjj attach bead-nuoc-xxx
```

## Speed Strategy

- **Parallel workers**: 8 workers = 8x speedup
- **Fast TDD15**: 8 phases (not 15) = 1.9x speedup
- **Fast Red Queen**: 3 generations (not 10) = 3.3x speedup
- **Total**: **~50x faster** than single-threaded full Ralph

## Quality

Same quality guarantees:
- ✅ TDD15 (RED → GREEN → REFACTOR → VERIFY)
- ✅ Red Queen (3 critical generations)
- ✅ Moon (Haiku) for code
- ✅ Idiomatic Nushell (nushell.sh)
- ✅ Bead tickets format enforced
