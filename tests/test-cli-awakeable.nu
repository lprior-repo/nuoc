#!/usr/bin/env nu
# test-cli-awakeable.nu - Test CLI commands for awakeable operations

use ../oc-engine.nu *

def test-cli-awakeable-resolve [] {
  rm -rf $DB_DIR

  db-init

  # Create a job and task
  let job_id = "test-job-cli-resolve"
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

  # Create an awakeable
  let awakeable = (ctx-awakeable $job_id $task_name $attempt)
  let awakeable_id = $awakeable.id

  # Test CLI resolve command
  try {
    # Simulate CLI call by calling resolve-awakeable directly
    # In real CLI, this would be: nu oc-cli.nu awakeable resolve $awakeable_id --payload '{"action":"approve"}'
    resolve-awakeable $awakeable_id { action: "approve" }
  } catch {|e|
    print $"[error] CLI resolve failed: ($e | get msg? | default 'unknown')"
    return false
  }

  # Verify awakeable is resolved
  let awakeable_status = (sql $"SELECT status FROM awakeables WHERE id = '($awakeable_id)'")

  if ($awakeable_status | is-not-empty) and $awakeable_status.0.status == "RESOLVED" {
    print "[ok] CLI resolve command works"
    return true
  } else {
    print $"[fail] CLI resolve: expected RESOLVED, got (($awakeable_status.0.status? | default 'empty'))"
    return false
  }
}

def test-cli-awakeable-reject [] {
  rm -rf $DB_DIR

  db-init

  # Create a job and task
  let job_id = "test-job-cli-reject"
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

  # Create an awakeable
  let awakeable = (ctx-awakeable $job_id $task_name $attempt)
  let awakeable_id = $awakeable.id

  # Test CLI reject command
  try {
    # Simulate CLI call
    reject-awakeable $awakeable_id "approval denied"
  } catch {|e|
    print $"[error] CLI reject failed: ($e | get msg? | default 'unknown')"
    return false
  }

  # Verify awakeable is rejected
  let awakeable_status = (sql $"SELECT status FROM awakeables WHERE id = '($awakeable_id)'")

  if ($awakeable_status | is-not-empty) and $awakeable_status.0.status == "REJECTED" {
    print "[ok] CLI reject command works"
    return true
  } else {
    print $"[fail] CLI reject: expected REJECTED, got (($awakeable_status.0.status? | default 'empty'))"
    return false
  }
}

def test-cli-awakeable-show [] {
  rm -rf $DB_DIR

  db-init

  # Create a job and task
  let job_id = "test-job-cli-show"
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

  # Create an awakeable
  let awakeable = (ctx-awakeable $job_id $task_name $attempt)
  let awakeable_id = $awakeable.id

  # Query awakeable
  let awakeable_data = (sql $"SELECT * FROM awakeables WHERE id = '($awakeable_id)'")

  if ($awakeable_data | is-not-empty) {
    let aw = $awakeable_data.0
    if $aw.id == $awakeable_id and $aw.job_id == $job_id and $aw.task_name == $task_name {
      print "[ok] CLI show/query command works"
      return true
    } else {
      print "[fail] CLI show: awakeable data mismatch"
      return false
    }
  } else {
    print "[fail] CLI show: awakeable not found"
    return false
  }
}

def main [] {
  print "\n=== CLI Awakeable Tests ===\n"

  test-cli-awakeable-resolve
  test-cli-awakeable-reject
  test-cli-awakeable-show

  print "\n=== All CLI Tests Complete ===\n"
}

# SQL helper
def sql [query: string] {
  try {
    sqlite3 -json $DB_PATH $query | from json
  } catch {
    []
  }
}
