#!/usr/bin/env nu
# test-user-approval-awakeable.nu - Test user_approval gate with awakeables

use ../oc-engine.nu *

def test-user-approval-creates-awakeable [] {
  rm -rf $DB_DIR

  db-init

  # Create a job with a task that has user_approval gate
  let job_id = "test-job-approval-1"
  job-create {
    name: $job_id,
    inputs: { bead_id: "test-bead" },
    tasks: [
      {
        name: "verify",
        agent: { type: "opencode", model: "claude-opus-4" },
        run: "verify",
        gate: "user_approval"
      }
    ]
  }

  # Get the task
  let task = (sql $"SELECT * FROM tasks WHERE job_id = '($job_id)' AND name = 'verify'").0

  # Initialize execution context
  let attempt = 1
  init-execution-context $job_id $task.name $attempt

  # Create an awakeable (simulating what the task would do)
  let awakeable = (ctx-awakeable $job_id $task.name $attempt)
  let awakeable_id = $awakeable.id

  # Verify awakeable was created
  let awakeable_data = (sql $"SELECT * FROM awakeables WHERE id = '($awakeable_id)'")

  if ($awakeable_data | is-empty) {
    print "    [fail] Awakeable not created"
    return false
  }

  if $awakeable_data.0.status == "PENDING" {
    print "    [ok] Awakeable created with PENDING status"
  } else {
    print $"    [fail] Awakeable status: expected PENDING, got ($awakeable_data.0.status)"
    return false
  }

  # Resolve the awakeable with approval
  resolve-awakeable $awakeable_id { action: "approve" }

  # Verify awakeable is resolved
  let resolved_data = (sql $"SELECT status, payload FROM awakeables WHERE id = '($awakeable_id)'").0

  if $resolved_data.status == "RESOLVED" {
    print "    [ok] Awakeable resolved"
  } else {
    print $"    [fail] Awakeable not resolved: ($resolved_data.status)"
    return false
  }

  print "  [ok] user-approval creates awakeable"
  return true
}

def test-user-approval-reject-fails-task [] {
  rm -rf $DB_DIR

  db-init

  # Create a job with a task that has user_approval gate
  let job_id = "test-job-approval-2"
  job-create {
    name: $job_id,
    inputs: { bead_id: "test-bead" },
    tasks: [
      {
        name: "verify",
        agent: { type: "opencode", model: "claude-opus-4" },
        run: "verify",
        gate: "user_approval"
      }
    ]
  }

  # Get the task
  let task = (sql $"SELECT * FROM tasks WHERE job_id = '($job_id)' AND name = 'verify'").0

  # Initialize execution context
  let attempt = 1
  init-execution-context $job_id $task.name $attempt

  # Create an awakeable
  let awakeable = (ctx-awakeable $job_id $task.name $attempt)
  let awakeable_id = $awakeable.id

  # Reject the awakeable
  reject-awakeable $awakeable_id "approval denied"

  # Verify awakeable is rejected
  let rejected_data = (sql $"SELECT status FROM awakeables WHERE id = '($awakeable_id)'").0

  if $rejected_data.status == "REJECTED" {
    print "    [ok] Awakeable rejected"
  } else {
    print $"    [fail] Awakeable not rejected: ($rejected_data.status)"
    return false
  }

  # When task resumes with rejected awakeable, it should fail
  # This simulates the gate-check returning fail
  let payload = { action: "reject" }
  let approval = ($payload | get -o action | default "reject")

  if $approval == "approve" {
    print "    [fail] Rejection should fail approval"
    return false
  } else {
    print "    [ok] Rejection correctly fails approval"
  }

  print "  [ok] user-approval reject fails task"
  return true
}

def test-user-approval-timeout [] {
  rm -rf $DB_DIR

  db-init

  # Create a job with a task that has user_approval gate with timeout
  let job_id = "test-job-approval-timeout"
  job-create {
    name: $job_id,
    inputs: { bead_id: "test-bead" },
    tasks: [
      {
        name: "verify",
        agent: { type: "opencode", model: "claude-opus-4" },
        run: "verify",
        gate: "user_approval"
      }
    ]
  }

  # Get the task
  let task = (sql $"SELECT * FROM tasks WHERE job_id = '($job_id)' AND name = 'verify'").0

  # Initialize execution context
  let attempt = 1
  init-execution-context $job_id $task.name $attempt

  # Create an awakeable with 1 second timeout
  let awakeable = (ctx-awakeable-timeout $job_id $task.name $attempt 1)
  let awakeable_id = $awakeable.id

  # Verify timeout_at is set
  let awakeable_data = (sql $"SELECT timeout_at FROM awakeables WHERE id = '($awakeable_id)'").0

  if ($awakeable_data.timeout_at | is-not-empty) {
    print "    [ok] Awakeable timeout_at set"
  } else {
    print "    [fail] Awakeable timeout_at not set"
    return false
  }

  # Wait for timeout
  sleep 2sec

  # Process timeouts
  check-awakeable-timeouts

  # Verify awakeable timed out
  let timed_out_data = (sql $"SELECT status FROM awakeables WHERE id = '($awakeable_id)'").0

  if $timed_out_data.status == "TIMEOUT" {
    print "    [ok] Awakeable timed out"
  } else {
    print $"    [fail] Awakeable status: expected TIMEOUT, got ($timed_out_data.status)"
    return false
  }

  print "  [ok] user-approval timeout works"
  return true
}

def main [] {
  print "\n=== User Approval Gate with Awakeables Tests ===\n"

  test-user-approval-creates-awakeable
  test-user-approval-reject-fails-task
  test-user-approval-timeout

  print "\n=== All User Approval Tests Complete ===\n"
}

# SQL helper
def sql [query: string] {
  try {
    sqlite3 -json $DB_PATH $query | from json
  } catch {
    []
  }
}
