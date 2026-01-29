#!/usr/bin/env nu
# oc-cli.nu — CLI tool for NUOC workflow operations
# Provides commands for awakeable resolution and job management

use oc-engine.nu *

# ── Awakeable Commands ─────────────────────────────────────────────────────────

# Resolve an awakeable with a payload
# Precondition: awakeable_id is a valid awakeable ID
# Postcondition: awakeable marked RESOLVED, task woken from suspension
export def "main awakeable resolve" [
  id: string  # Awakeable ID to resolve
  --payload: string  # Payload to deliver (JSON string or plain text)
  --file: path  # Read payload from file (alternative to --payload)
] {
  db-init

  # Load payload from file or argument
  let payload_data = if $file != null {
    let content = (open $file | str trim)
    # Try to parse as JSON, otherwise use as plain string
    try { $content | from json } catch { $content }
  } else if $payload != null {
    # Try to parse as JSON, otherwise use as plain string
    try { $payload | from json } catch { $payload }
  } else {
    # No payload provided, use empty object
    {}
  }

  # Resolve the awakeable
  let result = (try {
    resolve-awakeable $id $payload_data
  } catch {|e|
    print $"[error] ($e | get msg? | default 'unknown error')"
    exit 1
  })

  print $"[ok] Awakeable resolved"
  print $"    ID: ($result.awakeable_id)"
  print $"    Payload: ($result.payload | to json -r)"
}

# Reject an awakeable with an error message
# Precondition: awakeable_id is a valid awakeable ID
# Postcondition: awakeable marked REJECTED, task woken and will fail
export def "main awakeable reject" [
  id: string  # Awakeable ID to reject
  --error: string = "awakeable rejected"  # Error message
] {
  db-init

  let result = (try {
    reject-awakeable $id $error
  } catch {|e|
    print $"[error] ($e | get msg? | default 'unknown error')"
    exit 1
  })

  print $"[ok] Awakeable rejected"
  print $"    ID: ($result.awakeable_id)"
  print $"    Error: ($result.error)"
}

# List all awakeables
export def "main awakeable list" [
  --job: string  # Filter by job ID
  --status: string  # Filter by status (PENDING, RESOLVED, REJECTED, TIMEOUT, CANCELLED)
] {
  db-init

  let query = if $job != null {
    if $status != null {
      $"SELECT * FROM awakeables WHERE job_id = '($job)' AND status = '($status)' ORDER BY created_at DESC"
    } else {
      $"SELECT * FROM awakeables WHERE job_id = '($job)' ORDER BY created_at DESC"
    }
  } else if $status != null {
    $"SELECT * FROM awakeables WHERE status = '($status)' ORDER BY created_at DESC"
  } else {
    "SELECT * FROM awakeables ORDER BY created_at DESC"
  }

  let awakeables = (sql $query)

  if ($awakeables | is-empty) {
    print "No awakeables found"
    return
  }

  print $"Found ($awakeables | length) awakeable(s)"
  print ""

  for aw in $awakeables {
    let status_icon = match $aw.status {
      "PENDING" => "[·]"
      "RESOLVED" => "[✓]"
      "REJECTED" => "[✗]"
      "TIMEOUT" => "[⏱]"
      "CANCELLED" => "[--]"
      _ => "[?]"
    }

    print $"($status_icon) ($aw.id)"
    print $"    Job: ($aw.job_id)"
    print $"    Task: ($aw.task_name)"
    print $"    Status: ($aw.status)"
    print $"    Created: ($aw.created_at)"

    if $aw.payload != null {
      print $"    Payload: ($aw.payload)"
    }

    if $aw.timeout_at != null {
      print $"    Timeout: ($aw.timeout_at)"
    }

    if $aw.resolved_at != null {
      print $"    Resolved: ($aw.resolved_at)"
    }

    print ""
  }
}

# Show details of a specific awakeable
export def "main awakeable show" [id: string] {
  db-init

  let awakeable = (sql $"SELECT * FROM awakeables WHERE id = '($id)'")

  if ($awakeable | is-empty) {
    print $"[error] Awakeable not found: ($id)"
    exit 1
  }

  let aw = $awakeable.0

  print "Awakeable Details"
  print $"  ID: ($aw.id)"
  print $"  Job ID: ($aw.job_id)"
  print $"  Task Name: ($aw.task_name)"
  print $"  Entry Index: ($aw.entry_index)"
  print $"  Status: ($aw.status)"
  print $"  Created: ($aw.created_at)"

  if $aw.payload != null {
    print $"  Payload: ($aw.payload)"
  }

  if $aw.timeout_at != null {
    print $"  Timeout At: ($aw.timeout_at)"
  }

  if $aw.resolved_at != null {
    print $"  Resolved At: ($aw.resolved_at)"
  }
}

# ── Job Commands ───────────────────────────────────────────────────────────────

# Show job status
export def "main job status" [id: string] {
  db-init

  let status = (job-status $id)

  print $"Job: ($status.job.id)"
  print $"  Status: ($status.job.status)"
  print $"  Created: ($status.job.created_at)"

  if $status.job.started_at != null {
    print $"  Started: ($status.job.started_at)"
  }

  if $status.job.completed_at != null {
    print $"  Completed: ($status.job.completed_at)"
  }

  if ($status.tasks | is-not-empty) {
    print ""
    print "Tasks:"

    for task in $status.tasks {
      let icon = match $task.status {
        "COMPLETED" => "✓"
        "SKIPPED" => "⊘"
        "FAILED" => "✗"
        "RUNNING" => "▶"
        "SUSPENDED" => "[z]"
        "PENDING" => "·"
        _ => "?"
      }

      let gate_info = if $task.gate != null {
        $" [gate: ($task.gate)]"
      } else {
        ""
      }

      let error_info = if $task.error != null {
        $" - ($task.error)"
      } else {
        ""
      }

      print $"  ($icon) ($task.name) [($task.status)]($gate_info)($error_info)"
    }
  }
}

# List all jobs
export def "main job list" [] {
  db-init

  let jobs = (job-list)

  if ($jobs | is-empty) {
    print "No jobs found"
    return
  }

  print $"Jobs: ($jobs | length)"
  print ""

  $jobs | each {|job|
    let icon = match $job.status {
      "COMPLETED" => "[✓]"
      "FAILED" => "[✗]"
      "RUNNING" => "[▶]"
      "PENDING" => "[·]"
      "CANCELLED" => "[--]"
      _ => "[?]"
    }

    print $"($icon) ($job.id) - ($job.status)"
  }
}

# Cancel a job
export def "main job cancel" [id: string] {
  db-init

  job-cancel $id

  print $"[ok] Job cancelled: ($id)"
}

# Retry a failed job
export def "main job retry" [id: string] {
  db-init

  print $"[>>] Retrying job: ($id)"
  let result = (job-retry $id)

  print $"[($result.status | str downcase)] ($id)"
}

# ── System Commands ────────────────────────────────────────────────────────────

# Check and process expired awakeable timeouts
export def "main timeout check" [] {
  db-init

  let result = (check-awakeable-timeouts)

  print $"[ok] Checked awakeable timeouts"
  print $"    Processed: ($result.processed) expired awakeable(s)"
}

# Show event log
export def "main events" [
  --job: string  # Filter by job ID
  --limit: int = 50  # Max events to show
] {
  db-init

  let events = (event-log $job --limit $limit)

  if ($events | is-empty) {
    print "No events found"
    return
  }

  print $"Event Log ($limit | default 'most recent' | $" ($limit) most recent")"
  print ""

  $events | each {|event|
    let time = $event.created_at
    let type = $event.event_type
    let task = if $event.task_name != null { $"($event.task_name): " } else { "" }
    let transition = if $event.old_state != null and $event.new_state != null {
      $" ($event.old_state) → ($event.new_state)"
    } else {
      ""
    }
    let payload = if $event.payload != null { $" - ($event.payload)" } else { "" }

    print $"($time) ($task)($type)($transition)($payload)"
  }
}

# SQL helper for this module
def sql [query: string] {
  try {
    sqlite3 -json $DB_PATH $query | from json
  } catch {
    []
  }
}
