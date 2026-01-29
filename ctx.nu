#!/usr/bin/env nu
# ctx.nu — Task Execution Context with Replay Support
# Provides ctx.run for deterministic replay from journal

use oc-engine.nu *

# ── Public API ───────────────────────────────────────────────────────────────

# Execute a closure with replay support
# If in replay mode and entry exists, return cached output
# Otherwise, execute closure and journal the result
export def "ctx run" [closure: closure]: nothing -> any {
  # Get CURRENT entry index (before incrementing)
  let idx = (get-entry-index $env.JOB_ID $env.TASK_NAME $env.ATTEMPT)

  # Check if we're in replay mode and have a cached entry
  let replay_mode = (is-replay-mode $env.JOB_ID $env.TASK_NAME $env.ATTEMPT)

  # Get known entries count
  let known_entries = (sql $"SELECT COUNT\(*\) as count FROM journal WHERE job_id='($env.JOB_ID)' AND task_name='($env.TASK_NAME)' AND attempt=($env.ATTEMPT)").0.count | into int

  if $replay_mode and ($idx < $known_entries) {
    # Replay mode: return cached output
    let cached = (check-replay $env.JOB_ID $env.TASK_NAME $env.ATTEMPT $idx)

    if ($cached != null) {
      # Increment entry index after successful replay
      let _ = (next-entry-index $env.JOB_ID $env.TASK_NAME $env.ATTEMPT)
      return $cached
    }

    # Fallback: if cache miss, execute live (shouldn't happen in normal flow)
    error make {
      msg: $"Replay cache miss at entry ($idx)"
      label: {
        text: "Entry not found in journal"
        span: (metadata $closure).span
      }
    }
  }

  # Live mode: increment entry index first, then execute closure and journal result
  let next_idx = (next-entry-index $env.JOB_ID $env.TASK_NAME $env.ATTEMPT)

  let result = (do $closure)

  # Journal the result
  journal-write $env.JOB_ID $env.TASK_NAME $env.ATTEMPT $next_idx "run" {} $result

  $result
}

# ── SQL Helper ───────────────────────────────────────────────────────────────

# SQL query helper (returns table or empty)
def sql [query: string] {
  sqlite3 -json ".oc-workflow/journal.db" $query | from json
}
