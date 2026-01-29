# zjj Deep Dive - Complete Command Reference & Workflow

## What is zjj?

**zjj** = **z**ellij + **jj** workspace isolation. Creates isolated jj workspaces paired with Zellij tabs for parallel development.

**Version**: 0.3.1
**Dependencies**: zellij (0.43.1), jj (0.36.0), beads (0.49.0), claude (2.1.23)

## Core Concepts

### Two Modes of Work

1. **`zjj add`** - Manual interactive work (YOU work in the session)
2. **`zjj spawn`** - Automated agent work (AI AGENT works autonomously)

### Architecture

```
Main Repo (nuoc)
├── .jj/                    (jj metadata)
├── .zjj/                   (zjj state database + config)
└── ~/.zjj/workspaces/nuoc__workspaces/
    ├── bead-worker-1/      (isolated jj workspace)
    ├── bead-worker-2/      (isolated jj workspace)
    └── bead-worker-3/      (isolated jj workspace)
```

Each workspace is:
- Isolated jj repository (colocated with main)
- Separate Zellij tab
- Independent git/jj branch
- Mergable back to main with `zjj done`

## Complete Command Reference

### Initialization

```bash
zjj init                    # Initialize zjj in jj repo
zjj doctor                   # Run health checks
zjj context                  # Show environment context
zjj introspect              # Show capabilities and system state
```

### Manual Work (zjj add)

```bash
# Create workspace for interactive work
zjj add feature-auth        # Create with standard layout
zjj add bugfix-123 -t minimal  # Create with minimal layout
zjj add experiment --no-open  # Create without opening Zellij

# Templates:
#   - minimal: Single pane
#   - standard: Work + status panes (default)
#   - full: Work + status + beads + float

# Work in workspace
zjj attach feature-auth     # Enter Zellij session
zjj focus feature-auth      # Switch tab (inside Zellij)

# Finish and merge
zjj done                    # Merge to main and cleanup
zjj done -m "Fix auth bug"  # Custom commit message
zjj done --keep-workspace   # Keep workspace after merge
zjj done --dry-run          # Preview without executing
```

### Automated Agent Work (zjj spawn)

```bash
# Spawn agent to work on bead autonomously
zjj spawn nuoc-abc12        # Spawn workspace with Claude agent
zjj spawn nuoc-xyz34 -b     # Run in background
zjj spawn nuoc-def56 --no-auto-merge  # Don't auto-merge on success

# Spawn runs:
# 1. Creates isolated jj workspace
# 2. Runs agent (default: claude)
# 3. Auto-merges on success
# 4. Cleans up workspace

# Custom agent:
zjj spawn nuoc-ghi78 --agent-command=llm-run

# Timeout (default: 4 hours)
zjj spawn nuoc-ijk90 --timeout=7200  # 2 hours
```

### Session Management

```bash
zjj list                    # List all sessions
zjj status                  # Show detailed status
zjj diff                    # Show diff vs main
zjj remove feature-auth     # Remove session and workspace
zjj clean                   # Remove stale sessions
```

### Sync & Query

```bash
# Sync workspace with main (rebase)
zjj sync feature-auth       # Sync named session
zjj sync                    # Sync current workspace

# Query system state
zjj query session-exists feature    # Check if session exists
zjj query session-count              # Count active sessions
zjj query can-run                    # Check if zjj can run
zjj query suggest-name feat          # Get name suggestion
```

### Dashboard

```bash
zjj dashboard               # Launch interactive TUI (kanban view)
```

## Parallel Bead Processing Workflow

### Strategy 1: Spawn Multiple Agents (Fastest)

```bash
# Spawn 8 parallel workers for beads
bd ready | head -8 | grep -oE 'nuoc-[a-z0-9]+' | xargs -I {} zjj spawn {} -b

# Monitor workers
zjj list
zjj status

# Each worker will:
# 1. Create isolated workspace
# 2. Run Opus with full TDD15 + Red Queen
# 3. Auto-merge to main on success
# 4. Cleanup workspace

# Wait for completion or check dashboard
zjj dashboard
```

### Strategy 2: Manual Interactive Work

```bash
# Create workspace for yourself
zjj add bead-worker-1

# Work in the workspace
zjj attach bead-worker-1

# Inside workspace:
#   1. Claim bead: bd update nuoc-xxx --status=in_progress
#   2. Read context: bd show nuoc-xxx
#   3. Implement with Opus + TDD15 + Red Queen
#   4. Test: moon run :ci
#   5. Commit work
#   6. Exit workspace: exit

# Merge to main
zjj done bead-worker-1
```

### Strategy 3: Hybrid (Spawn + Manual)

```bash
# Spawn 4 agents for simple beads
bd ready | head -4 | grep -oE 'nuoc-[a-z0-9]+' | xargs -I {} zjj spawn {} -b

# Create 1 manual workspace for complex bead
zjj add complex-bead

# Work in manual workspace while agents run
zjj attach complex-bead
```

## Merge Strategy

### How zjj Merges Workspaces

When you run `zjj done` or `zjj spawn` succeeds:

1. **Sync with main**: `jj rebase -d main`
2. **Resolve conflicts** (if any)
3. **Push to git**: `jj git push`
4. **Update bead**: `bd close <bead_id>`
5. **Cleanup workspace**: `rm -rf ~/.zjj/workspaces/nuoc__workspaces/<name>`

### Multi-Parent Merge (Mega-Merge)

For coordinating multiple simultaneous completions:

```bash
# In main repo, create merge commit with all worker branches
jj new worker1 worker2 worker3

# Resolve conflicts (minimal if partitioning works)
jj resolve

# Test merged result
moon run :ci

# Push to main
jj git push
```

## Partitioning Strategy (Avoid Conflicts)

Beads are partitioned by file/module:

| Worker | Files              | Bead Types              |
|--------|--------------------|-------------------------|
| 1      | `oc-agent.nu`      | API client beads        |
| 2      | `oc-engine.nu`     | Core engine beads       |
| 3      | `oc-tdd15.nu`      | TDD15 workflow beads    |
| 4      | `oc-orchestrate.nu`| Orchestration beads     |
| 5      | Database schema    | Migration/DDL beads     |
| 6-8    | Integration tests  | Complex workflow beads  |

**Result**: No two workers ever touch the same file → no merge conflicts.

## Quality Gates

Before `zjj done` completes:

- ✅ All tests pass: `moon run :ci`
- ✅ Bead closed: `bd close <bead_id>`
- ✅ jj synced: `jj rebase -d main`
- ✅ Pushed to git: `jj git push`
- ✅ Workspace clean: `jj status` shows no uncommitted changes

## Monitoring & Debugging

```bash
# Check all workers
zjj list                    # List sessions
zjj status                  # Detailed status
zjj diff                    # See what changed

# Interactive dashboard
zjj dashboard               # TUI with kanban view

# Health check
zjj doctor                   # System health
zjj context                  # Environment context
```

## Best Practices

1. **Spawn for automated work**, `add` for manual work
2. **Use background mode** (`-b`) for multiple spawns
3. **Let zjj auto-merge** on success (default behavior)
4. **Use `--no-auto-merge`** if you want to review before merging
5. **Check `zjj list`** before spawning to avoid name conflicts
6. **Run `zjj clean`** periodically to remove stale workspaces
7. **Use `zjj dashboard`** for interactive monitoring

## Comparison to Alternatives

| Feature          | zjj                  | git worktree        | jj alone         |
|------------------|--------------------- |---------------------|------------------|
| Isolation        | ✅ jj workspace      | ✅ Separate dir     | ❌ Same repo     |
| UI integration   | ✅ Zellij tabs       | ❌ Manual           | ❌ Manual        |
| Agent support    | ✅ Built-in spawn    | ❌ Manual           | ❌ Manual        |
| Auto-merge       | ✅ `zjj done`        | ❌ Manual           | ❌ Manual        |
| Beads integration | ✅ Built-in         | ❌ Manual           | ❌ Manual        |
| Background work  | ✅ `-b` flag         | ❌ Manual           | ❌ Manual        |
| Dashboard        | ✅ TUI kanban        | ❌ None             | ❌ None          |

## References

- [zjj GitHub](https://github.com/nickgerace/zjj) (hypothetical)
- [jj documentation](https://docs.jj-vcs.dev/latest/)
- [Zellij documentation](https://zellij.dev/)
- [A Better Merge Workflow with Jujutsu](https://ofcr.se/jujutsu-merge-workflow/)

---

**Summary**: zjj is the optimal tool for parallel bead processing - it combines jj's safe merge manipulation with Zellij's terminal multiplexing and adds first-class support for automated agent workflows.
