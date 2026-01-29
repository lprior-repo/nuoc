# NUOC - Core Agent Guidelines

## Build/Test Commands

**ALWAYS use Moon:**
```bash
moon run :test     # All tests
moon run :check    # Type check
moon run :quick    # Format + lint
moon run :ci       # Full CI
```

**NEVER use cargo/nu directly.**

## Idiomatic Nushell

**Official docs: https://www.nushell.sh/book/**

**Key patterns:**
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

## Model Usage

**ALWAYS use Opus for all work** - Maximum quality, full Red Queen coverage, comprehensive analysis.

## Writing Beads

```bash
bd create --title="[Category] verb what" --type=task|bug|feature --priority=0-4
```

**Examples:**
- `[SQL] Parameterize job queries` --type=bug --priority=0
- `[Workflow] Add checkpoint retry` --type=feature --priority=1

**Priority:** 0=critical, 1=high, 2=medium, 3=low, 4=backlog

## Core Rules

1. Use Opus for all code
2. Consult nushell.sh for idioms
3. No comments - self-documenting code
4. Immutability preferred
5. Use `par-each` for parallel tasks
6. Return structured error records
7. Always escape SQL inputs
8. NEVER skip git push - work incomplete until pushed

## Session End

MANDATORY:
```bash
bd sync
git push
git status  # MUST show "up to date"
```

## Using bv as an AI Sidecar

**`bv`** is a graph-aware triage engine for Beads projects (.beads/beads.jsonl). It uses robot flags for deterministic, dependency-aware outputs with precomputed metrics (PageRank, betweenness, critical path, cycles, HITS, eigenvector, k-core).

**Scope boundary:** bv handles *what to work on* (triage, priority, planning). For agent-to-agent coordination, use MCP Agent Mail.

**⚠️ CRITICAL: Use ONLY `--robot-*` flags.** Bare `bv` launches an interactive TUI that blocks your session.

### The Workflow: Start With Triage

**`bv --robot-triage` is your single entry point.** Returns:
- `quick_ref`: at-a-glance counts + top 3 picks
- `recommendations`: ranked actionable items with scores, reasons, unblock info
- `quick_wins`: low-effort high-impact items
- `blockers_to_clear`: items that unblock the most downstream work
- `project_health`: status/type/priority distributions, graph metrics
- `commands`: copy-paste shell commands for next steps

```bash
# THE MEGA-COMMAND: start here
bv --robot-triage

# Minimal: just the single top pick + claim command
bv --robot-next

# Token-optimized output (TOON) for lower LLM context usage
bv --robot-triage --format toon
export BV_OUTPUT_FORMAT=toon
bv --robot-next
```

### Other Commands

**Planning:**
```bash
bv --robot-plan          # Parallel execution tracks with unblocks lists
bv --robot-priority      # Priority misalignment detection with confidence
```

**Graph Analysis:**
```bash
bv --robot-insights              # Full metrics: PageRank, betweenness, HITS, critical path, cycles, k-core, articulation points
bv --robot-label-health          # Per-label health: health_level, velocity_score, staleness, blocked_count
bv --robot-label-flow            # Cross-label dependency: flow_matrix, dependencies, bottleneck_labels
bv --robot-label-attention       # Attention-ranked labels: (pagerank × staleness × block_impact) / velocity
```

**History & Change Tracking:**
```bash
bv --robot-history               # Bead-to-commit correlations: stats, histories, commit_index
bv --robot-diff --diff-since <ref>  # Changes since ref: new/closed/modified issues, cycles introduced/resolved
```

**Other Commands:**
```bash
bv --robot-burndown <sprint>     # Sprint burndown, scope changes, at-risk items
bv --robot-forecast <id|all>     # ETA predictions with dependency-aware scheduling
bv --robot-alerts                # Stale issues, blocking cascades, priority mismatches
bv --robot-suggest               # Hygiene: duplicates, missing deps, label suggestions, cycle breaks
bv --robot-graph                 # Dependency graph export (json|dot|mermaid)
bv --export-graph <file.html>    # Self-contained interactive HTML visualization
```

### Scoping & Filtering

```bash
bv --robot-plan --label backend              # Scope to label's subgraph
bv --robot-insights --as-of HEAD~30          # Historical point-in-time
bv --recipe actionable --robot-plan          # Pre-filter: ready to work (no blockers)
bv --recipe high-impact --robot-triage       # Pre-filter: top PageRank scores
bv --robot-triage --robot-triage-by-track    # Group by parallel work streams
bv --robot-triage --robot-triage-by-label    # Group by domain
```

### Understanding Robot Output

**All robot JSON includes:**
- `data_hash` — Fingerprint of source beads.jsonl (verify consistency across calls)
- `status` — Per-metric state: `computed|approx|timeout|skipped` + elapsed ms
- `as_of` / `as_of_commit` — Present when using `--as-of`; contains ref and resolved SHA

**Two-phase analysis:**
- **Phase 1 (instant):** degree, topo sort, density — always available immediately
- **Phase 2 (async, 500ms timeout):** PageRank, betweenness, HITS, eigenvector, cycles — check `status` flags

**For large graphs (>500 nodes):** Some metrics may be approximated or skipped. Always check `status`.

### jq Quick Reference

```bash
bv --robot-triage | jq '.quick_ref'                        # At-a-glance summary
bv --robot-triage | jq '.recommendations[0]'               # Top recommendation
bv --robot-plan | jq '.plan.summary.highest_impact'        # Best unblock target
bv --robot-insights | jq '.status'                         # Check metric readiness
bv --robot-insights | jq '.Cycles'                         # Circular deps (must fix!)
bv --robot-label-health | jq '.results.labels[] | select(.health_level == "critical")'
```

**Performance:** Phase 1 instant, Phase 2 async (500ms timeout). Prefer `--robot-plan` over `--robot-insights` when speed matters. Results cached by data hash.

Use bv instead of parsing beads.jsonl—it computes PageRank, critical paths, cycles, and parallel tracks deterministically.
