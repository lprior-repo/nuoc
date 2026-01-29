#!/usr/bin/env nu
# test-awakeable-cleanup.nu - TDD15 RED phase for awakeable cleanup on job completion

use std testing
use ../oc-engine.nu *

# Test: job completion cancels all pending awakeables
def test-job-completion-cancels-awakeables [] {
  let test_dir = "/tmp/test-awakeable-cleanup-1"
  let test_db_path = $"($test_dir)/.oc-workflow/journal.db"

  rm -rf $test_dir
  mkdir $test_dir

  try {
    cd $test_dir
    db-init

    # Create a job and task
    let job_id = "test-job-1"
    job-create {
      name: $job_id,
      inputs: { bead_id: "test-bead" },
      tasks: [
        { name: "task-1", var: "result" }
      ]
    }

    # Get task attempt
    let task_name = "task-1"
    let attempt = 1

    # Initialize execution context
    init-execution-context $job_id $task_name $attempt

    # Create an awakeable
    let awakeable = (ctx-awakeable $job_id $task_name $attempt)
    let awakeable_id = $awakeable.id

    # Verify awakeable is PENDING
    let awakeable_before = (sqlite3 -json $test_db_path $"SELECT status FROM awakeables WHERE id = '($awakeable_id)'" | from json)
    if ($awakeable_before | is-empty) {
      print "    [fail] Awakeable not found before job completion"
      return
    }

    # Complete the job
    sqlite3 $test_db_path $"UPDATE jobs SET status = 'completed', completed_at = datetime\('now'\) WHERE id = '($job_id)'"
    cancel-job-awakeables $job_id

    # Verify awakeable is now CANCELLED
    let awakeable_after = (sqlite3 -json $test_db_path $"SELECT status FROM awakeables WHERE id = '($awakeable_id)'" | from json)
    if ($awakeable_after | is-empty) {
      print "    [fail] Awakeable not found after job completion"
      return
    }

    if ($awakeable_after.0.status == "CANCELLED") {
      print "    [ok] Awakeable marked as CANCELLED on job completion"
    } else {
      print $"    [fail] Awakeable status after job completion: got ($awakeable_after.0.status), expected CANCELLED"
      return
    }
  } catch {|e|
    print $"    [error] test-job-completion-cancels-awakeables: ($e | get msg? | default 'unknown error')"
  }

  print "  [ok] job-completion-cancels-awakeables"
}

# Test: job cancellation cancels all pending awakeables
def test-job-cancellation-cancels-awakeables [] {
  let test_dir = "/tmp/test-awakeable-cleanup-2"
  let test_db_path = $"($test_dir)/.oc-workflow/journal.db"

  rm -rf $test_dir
  mkdir $test_dir

  try {
    cd $test_dir
    db-init

    # Create a job and task
    let job_id = "test-job-2"
    job-create {
      name: $job_id,
      inputs: { bead_id: "test-bead" },
      tasks: [
        { name: "task-1", var: "result" }
      ]
    }

    # Get task attempt
    let task_name = "task-1"
    let attempt = 1

    # Initialize execution context
    init-execution-context $job_id $task_name $attempt

    # Create an awakeable
    let awakeable = (ctx-awakeable $job_id $task_name $attempt)
    let awakeable_id = $awakeable.id

    # Verify awakeable is PENDING
    let awakeable_before = (sqlite3 -json $test_db_path $"SELECT status FROM awakeables WHERE id = '($awakeable_id)'" | from json)
    if ($awakeable_before | is-empty) {
      print "    [fail] Awakeable not found before job cancellation"
      return
    }

    # Cancel the job
    job-cancel $job_id

    # Verify awakeable is now CANCELLED
    let awakeable_after = (sqlite3 -json $test_db_path $"SELECT status FROM awakeables WHERE id = '($awakeable_id)'" | from json)
    if ($awakeable_after | is-empty) {
      print "    [fail] Awakeable not found after job cancellation"
      return
    }

    if ($awakeable_after.0.status == "CANCELLED") {
      print "    [ok] Awakeable marked as CANCELLED on job cancellation"
    } else {
      print $"    [fail] Awakeable status after job cancellation: got ($awakeable_after.0.status), expected CANCELLED"
      return
    }
  } catch {|e|
    print $"    [error] test-job-cancellation-cancels-awakeables: ($e | get msg? | default 'unknown error')"
  }

  print "  [ok] job-cancellation-cancels-awakeables"
}

# Test: reject resolution of CANCELLED awakeable
def test-reject-cancelled-awakeable-resolution [] {
  let test_dir = "/tmp/test-awakeable-cleanup-3"
  let test_db_path = $"($test_dir)/.oc-workflow/journal.db"

  rm -rf $test_dir
  mkdir $test_dir

  try {
    cd $test_dir
    db-init

    # Create a job and task
    let job_id = "test-job-3"
    job-create {
      name: $job_id,
      inputs: { bead_id: "test-bead" },
      tasks: [
        { name: "task-1", var: "result" }
      ]
    }

    # Get task attempt
    let task_name = "task-1"
    let attempt = 1

    # Initialize execution context
    init-execution-context $job_id $task_name $attempt

    # Create an awakeable
    let awakeable = (ctx-awakeable $job_id $task_name $attempt)
    let awakeable_id = $awakeable.id

    # Cancel the job
    sqlite3 $test_db_path $"UPDATE jobs SET status = 'cancelled', completed_at = datetime\('now'\) WHERE id = '($job_id)'"
    cancel-job-awakeables $job_id

    # Try to resolve the cancelled awakeable - should fail
    let result = (try { resolve-awakeable $awakeable_id { result: "should not resolve" } } catch {|e| { error: ($e | get msg? | default "unknown") } })

    if ($result | get --optional error) != null {
      print $"    [ok] resolve-awakeable rejected CANCELLED awakeable: ($result.error)"
    } else {
      print "    [fail] resolve-awakeable should reject CANCELLED awakeable"
      return
    }
  } catch {|e|
    print $"    [error] test-reject-cancelled-awakeable-resolution: ($e | get msg? | default 'unknown error')"
  }

  print "  [ok] reject-cancelled-awakeable-resolution"
}

# Run all tests
print "Running awakeable cleanup tests..."
test-job-completion-cancels-awakeables
test-job-cancellation-cancels-awakeables
test-reject-cancelled-awakeable-resolution
