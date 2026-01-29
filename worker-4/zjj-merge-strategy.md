# zjj Merge Strategy - Landing Parallel Work to Main

## Overview

zjj workers implement beads in isolated jj workspaces. This document describes how to safely merge that work to main without conflicts.

## Partitioning Strategy (Prevent Conflicts)

**Beads are partitioned by module/path:**
- `oc-agent.nu` beads → Worker 1
- `oc-engine.nu` beads → Worker 2
- `oc-tdd15.nu` beads → Worker 3
- `oc-orchestrate.nu` beads → Worker 4
- Database schema beads → Worker 5
- Core workflow beads → Workers 6-8

**Rule**: No two workers ever touch the same files. This prevents merge conflicts.

## Merge Workflow

### Per Worker (When Bead Complete)

```bash
# In zjj workspace:
cd ~/.zjj/workspaces/nuoc__workspaces/bead-nuoc-xxx

# 1. Ensure all tests pass
moon run :ci

# 2. Rebase on latest main
jj rebase -d main

# 3. Push to git (this updates jj's git view)
jj git push

# 4. Exit workspace
exit
```

### Coordinating Multiple Workers (Mega-Merge)

When multiple workers complete simultaneously:

```bash
# In main repo:
cd /home/lewis/src/nuoc

# 1. Pull latest changes
jj git fetch

# 2. Create mega-merge commit with all worker branches
jj new bead-worker1 bead-worker2 bead-worker3

# 3. Resolve any conflicts (should be minimal if partitioning worked)
jj resolve

# 4. Run full test suite on merged result
moon run :ci

# 5. If tests pass, push to main
jj git push
```

## Inspired by Orchestration Tools

### Bazel (Hermetic Builds)
- **Principle**: Each build target is isolated, hermetic
- **Our application**: Each zjj workspace is hermetic - doesn't affect others until merge
- **Benefit**: No cross-contamination, reproducible builds

### Nx/Turborepo (Affected Graph)
- **Principle**: Only rebuild what changed
- **Our application**: Only rebasing/merging workers that actually completed work
- **Benefit**: Incremental merging, not all-or-nothing

### Pants 2.0 (Remote Caching)
- **Principle**: Cache build results, distribute execution
- **Our application**: Each worker's result is "cached" in their workspace, distributed to main on merge
- **Benefit**: Parallel work doesn't block each other

### jj's Merge Workflow
- **Principle**: Manipulate merge commits safely, add/remove parents
- **Our application**: Use `jj new worker1 worker2` to create mega-merge, `jj rebase` to reposition
- **Benefit**: Safe conflict resolution, easy to undo

## Quality Gates Before Merge

1. **Workspace must pass all tests**: `moon run :ci` in workspace
2. **Rebase on latest main**: `jj rebase -d main`
3. **No local changes**: `jj status` shows clean
4. **Conflict-free merge**: Partition strategy ensures no overlapping files

## Failure Recovery

If merge has conflicts:

```bash
# 1. Investigate conflict
jj log
jj diff

# 2. If partitioning failed (two workers touched same file):
#    - Abort merge
#    - Reassign bead to different worker
#    - Re-run bead in isolation

# 3. If minor conflict:
#    - Resolve manually
#    - Run tests: `moon run :ci`
#    - Commit resolution
```

## Automation

The `zjj-sync-all.sh` script handles the common case:

```bash
./zjj-sync-all.sh
# Equivalent to:
#   zjj sync (rebase all workers on main, push to git)
```

## References

- [A Better Merge Workflow with Jujutsu](https://ofcr.se/jujutsu-merge-workflow/) - Multi-parent merge commits
- [Bazel Hermeticity](https://bazel.build/basics/hermeticity) - Isolated builds
- [Nx Parallel Execution](https://nx.dev/docs/concepts/ci-concepts/parallelization-distribution) - Distributed task execution
- [Pants Remote Execution](https://www.pantsbuild.org/dev/docs/using-pants/remote-caching-and-execution) - Caching and distribution

## Summary

**Key insight**: By partitioning beads by file/module and using jj's safe merge manipulation, we can have 8 workers implementing beads in parallel with minimal merge conflicts. Each worker is hermetic (Bazel-style), merges incrementally (Nx-style), and distributes results (Pants-style).
