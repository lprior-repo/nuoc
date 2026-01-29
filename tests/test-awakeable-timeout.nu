#!/usr/bin/env nu

# test-awakeable-timeout.nu - TDD15 RED phase for awakeable timeout handling

use std testing
use ../oc-engine.nu *

# Test: awakeable with timeout gets marked as TIMEOUT after timeout expires
def test-awakeable-timeout-expires [] {
  rm -rf $DB_DIR
  db-init

  let job_id = "test-job-timeout-1"
  job-create {
    name: $job_id,
    inputs: { bead_id: "test-bead" },
    tasks: [
      { name: "task-1" }
    ]
  }

  let task_name = "task-1"
  let attempt = 1
  init-execution-context $job_id $task_name $attempt

  # Create awakeable with 1 second timeout
  let awakeable = (ctx-awakeable-timeout $job_id $task_name $attempt 1)
  let awakeable_id = $awakeable.id
  print $"    Awakeable ID: ($awakeable_id)"

  # Verify awakeable is PENDING
  let awakeable_before = (sqlite3 -json $DB_PATH $"SELECT status, timeout_at FROM awakeables WHERE id = '($awakeable_id)'" | from json).0
  assert equal $awakeable_before.status "PENDING"
  print $"    [ok] Awakeable status is PENDING before timeout"

  # Wait for timeout to expire
  print "    Waiting for timeout..."
  sleep 2sec

  # Process timeouts
  check-awakeable-timeouts

  # Verify awakeable is now TIMEOUT
  let awakeable_after = (sqlite3 -json $DB_PATH $"SELECT status FROM awakeables WHERE id = '($awakeable_id)'" | from json).0
  assert equal $awakeable_after.status "TIMEOUT"
  print $"    [ok] Awakeable marked as TIMEOUT"

  print "  [ok] awakeable-timeout-expires"
}

# Test: ctx-await-awakeable returns error for TIMEOUT awakeable
def test-await-timeout-awakeable-error [] {
  rm -rf $DB_DIR
  db-init

  let job_id = "test-job-timeout-2"
  job-create {
    name: $job_id,
    inputs: { bead_id: "test-bead" },
    tasks: [
      { name: "task-1" }
    ]
  }

  let task_name = "task-1"
  let attempt = 1
  init-execution-context $job_id $task_name $attempt

  # Create awakeable with 1 second timeout
  let awakeable = (ctx-awakeable-timeout $job_id $task_name $attempt 1)
  let awakeable_id = $awakeable.id

  # Wait for timeout
  sleep 2sec

  # Process timeouts
  check-awakeable-timeouts

  # Try to await the timed-out awakeable
  let result = (try { ctx-await-awakeable $job_id $task_name $attempt $awakeable_id } catch {|e| { error: ($e | get msg? | default "unknown") } })

  assert not ($result.error | is-empty)
  print $"    [ok] ctx-await-awakeable returns error for TIMEOUT awakeable: ($result.error)"

  print "  [ok] await-timeout-awakeable-error"
}

# Test: awakeable without timeout never times out
def test-awakeable-no-timeout [] {
  rm -rf $DB_DIR
  db-init

  let job_id = "test-job-timeout-3"
  job-create {
    name: $job_id,
    inputs: { bead_id: "test-bead" },
    tasks: [
      { name: "task-1" }
    ]
  }

  let task_name = "task-1"
  let attempt = 1
  init-execution-context $job_id $task_name $attempt

  # Create awakeable without timeout
  let awakeable = (ctx-awakeable $job_id $task_name $attempt)
  let awakeable_id = $awakeable.id

  # Wait a bit
  sleep 2sec

  # Process timeouts
  check-awakeable-timeouts

  # Verify awakeable is still PENDING (not TIMEOUT)
  let awakeable_after = (sqlite3 -json $DB_PATH $"SELECT status FROM awakeables WHERE id = '($awakeable_id)'" | from json).0
  assert equal $awakeable_after.status "PENDING"
  print $"    [ok] Awakeable without timeout remains PENDING"

  print "  [ok] awakeable-no-timeout"
}

# Test: awakeable resolved before timeout doesn't time out
def test-awakeable-resolved-before-timeout [] {
  rm -rf $DB_DIR
  db-init

  let job_id = "test-job-timeout-4"
  job-create {
    name: $job_id,
    inputs: { bead_id: "test-bead" },
    tasks: [
      { name: "task-1" }
    ]
  }

  let task_name = "task-1"
  let attempt = 1
  init-execution-context $job_id $task_name $attempt

  # Create awakeable with 5 second timeout
  let awakeable = (ctx-awakeable-timeout $job_id $task_name $attempt 5)
  let awakeable_id = $awakeable.id

  # Resolve immediately
  resolve-awakeable $awakeable_id { result: "early resolution" }

  # Wait for timeout
  sleep 6sec

  # Process timeouts
  check-awakeable-timeouts

  # Verify awakeable is still RESOLVED (not TIMEOUT)
  let awakeable_after = (sqlite3 -json $DB_PATH $"SELECT status FROM awakeables WHERE id = '($awakeable_id)'" | from json).0
  assert equal $awakeable_after.status "RESOLVED"
  print $"    [ok] Resolved awakeable doesn't time out"

  print "  [ok] awakeable-resolved-before-timeout"
}

def main [] {
  print "\n=== Awakeable Timeout Handling Tests (RED Phase) ===\n"

  test-awakeable-timeout-expires
  test-await-timeout-awakeable-error
  test-awakeable-no-timeout
  test-awakeable-resolved-before-timeout

  print "\n=== All RED Tests Complete ===\n"
}
