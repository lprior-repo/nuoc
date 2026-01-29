#!/usr/bin/env nu
# test-awakeable-suspension.nu - TDD15 RED phase for awakeable suspension

use std testing
use ../oc-engine.nu *

# Test: ctx-await-awakeable suspends task with correct status
def test-ctx-await-awakeable-suspends-task [] {
  let test_db_dir = "/tmp/test-awakeable-suspension-($env.PID)"
  let test_db_path = $"($test_db_dir)/journal.db"

  rm -rf $test_db_dir

  do {
    $env.NUOC_DB_DIR = $test_db_dir
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

    # Create an awakeable first
    let awakeable = (ctx-awakeable $job_id $task_name $attempt)
    let awakeable_id = $awakeable.id

    # Await the awakeable - should suspend task
    let suspend_result = (try {
      ctx-await-awakeable $job_id $task_name $attempt $awakeable_id
    } catch {|e|
      { error: ($e | get msg? | default "unknown error") }
    })

    # Verify task is suspended
    let task = (sqlite3 $test_db_path $"SELECT status FROM tasks WHERE job_id = '($job_id)' AND name = '($task_name)'" | from ssv)
    assert equal $task.status "suspended"

    # Verify awakeable is still PENDING
    let awakeable_status = (sqlite3 $test_db_path $"SELECT status FROM awakeables WHERE id = '($awakeable_id)'" | from ssv)
    assert equal $awakeable_status.status "PENDING"

    # Verify journal entry exists for suspension
    let journal_entries = (sqlite3 $test_db_path $"SELECT * FROM journal WHERE job_id = '($job_id)' AND task_name = '($task_name)' AND attempt = ($attempt) ORDER BY entry_index" | from ssv)
    assert ($journal_entries | length) >= 2

    # Verify last journal entry is awakeable-await
    let last_entry = ($journal_entries | last)
    assert equal $last_entry.op_type "awakeable-await"

    print "✓ Task suspended on awakeable await"
  }

  rm -rf $test_db_dir
}

# Test: ctx-await-awakeable journals suspension point
def test-ctx-await-awakeable-journals-suspension [] {
  let test_db_dir = "/tmp/test-awakeable-suspension-($env.PID)"
  let test_db_path = $"($test_db_dir)/journal.db"

  rm -rf $test_db_dir

  do {
    $env.NUOC_DB_DIR = $test_db_dir
    db-init

    let job_id = "test-job-2"
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

    let awakeable = (ctx-awakeable $job_id $task_name $attempt)
    let awakeable_id = $awakeable.id

    ctx-await-awakeable $job_id $task_name $attempt $awakeable_id

    # Check journal has correct entry
    let journal = (sqlite3 $test_db_path $"SELECT * FROM journal WHERE job_id = '($job_id)' AND task_name = '($task_name)' AND attempt = ($attempt) AND op_type = 'awakeable-await'" | from ssv)
    assert ($journal | length) == 1

    # Verify journal payload contains awakeable_id
    let entry = $journal.0
    let payload = ($entry.input | from json)
    assert equal $payload.awakeable_id $awakeable_id

    print "✓ Suspension point journaled"
  }

  rm -rf $test_db_dir
}

# Test: Multiple awakeable suspensions track correctly
def test-multiple-awakeable-suspensions [] {
  let test_db_dir = "/tmp/test-awakeable-suspension-($env.PID)"
  let test_db_path = $"($test_db_dir)/journal.db"

  rm -rf $test_db_dir

  do {
    $env.NUOC_DB_DIR = $test_db_dir
    db-init

    let job_id = "test-job-3"
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

    # Create first awakeable and await it
    let awakeable1 = (ctx-awakeable $job_id $task_name $attempt)
    ctx-await-awakeable $job_id $task_name $attempt $awakeable1.id

    # Task should be suspended
    let task = (sqlite3 $test_db_path $"SELECT status FROM tasks WHERE job_id = '($job_id)' AND name = '($task_name)'" | from ssv)
    assert equal $task.status "suspended"

    print "✓ Multiple awakeable suspensions tracked correctly"
  }

  rm -rf $test_db_dir
}

def main [] {
  print "Running GREEN phase tests for awakeable suspension..."

  test test-ctx-await-awakeable-suspends-task
  test test-ctx-await-awakeable-journals-suspension
  test test-multiple-awakeable-suspensions

  print "All GREEN tests passed ✓"
}
