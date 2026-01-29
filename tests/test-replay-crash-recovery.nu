#!/usr/bin/env nu
# test-replay-crash-recovery.nu — Test deterministic replay from journal
# ATDD: Crash recovery replays without re-execution

use std testing
use ../oc-engine.nu *

# Test: Crash recovery replays completed tasks without re-execution
def test-crash-recovery-replay [] {
  let test_db_dir = "/tmp/test-crash-recovery-replay-($env.PID)"
  let test_db_path = $"($test_db_dir)/journal.db"

  try {
    # Clean up any existing test database
    rm -rf $test_db_dir

    mkdir $test_db_dir
    cd $test_db_dir

    # Initialize database
    db-init

    # Create a job with three tasks: A, B, C
    let job_id = "test-job-crash-recovery"
    sql-exec $"INSERT OR REPLACE INTO jobs \(id, name, status\) VALUES \('($job_id)', 'crash-test', 'running'\)"

    sql-exec $"INSERT OR REPLACE INTO tasks \(id, job_id, name, run_cmd, agent_type, status\) VALUES \('task-a', '($job_id)', 'A', 'echo', 'general-purpose', 'completed'\)"
    sql-exec $"INSERT OR REPLACE INTO tasks \(id, job_id, name, run_cmd, agent_type, status\) VALUES \('task-b', '($job_id)', 'B', 'echo', 'general-purpose', 'completed'\)"
    sql-exec $"INSERT OR REPLACE INTO tasks \(id, job_id, name, run_cmd, agent_type, status\) VALUES \('task-c', '($job_id)', 'C', 'echo', 'general-purpose', 'running'\)"

    # Simulate task A and B completed with journal entries
    let task_name_a = "A"
    let task_name_b = "B"
    let attempt = 1

    # Initialize execution context for task A
    init-execution-context $job_id $task_name_a $attempt

    # Write journal entry for task A's operation
    let entry_index_a = 1
    journal-write $job_id $task_name_a $attempt $entry_index_a "call-agent" {prompt: "Execute A"} "output-a"

    # Mark task A as completed with output
    sql-exec $"UPDATE tasks SET status = 'completed', output = 'output-a', completed_at = datetime\('now'\) WHERE id = 'task-a'"

    # Initialize execution context for task B
    init-execution-context $job_id $task_name_b $attempt

    # Write journal entry for task B's operation
    let entry_index_b = 1
    journal-write $job_id $task_name_b $attempt $entry_index_b "call-agent" {prompt: "Execute B"} "output-b"

    # Mark task B as completed with output
    sql-exec $"UPDATE tasks SET status = 'completed', output = 'output-b', completed_at = datetime\('now'\) WHERE id = 'task-b'"

    # Task C is still running (simulating crash during execution)

    # Now call job-resume
    print "Calling job-resume..."
    try {
      job-resume $job_id
      print "job-resume completed"
    } catch {|e|
      print $"job-resume failed: ($e.msg)"
      print $"Error details: ($e)"
      raise
    }

    # Verify: Task A and B outputs are preserved (no re-execution)
    let task_a_query = (sql $"SELECT output FROM tasks WHERE id = 'task-a'")
    if ($task_a_query | is-empty) {
      error make { msg: "Task A not found" }
    }
    let task_a = $task_a_query.0
    assert equal $task_a.output "output-a"

    let task_b_query = (sql $"SELECT output FROM tasks WHERE id = 'task-b'")
    if ($task_b_query | is-empty) {
      error make { msg: "Task B not found" }
    }
    let task_b = $task_b_query.0
    assert equal $task_b.output "output-b"

    # Verify: Task C can be executed from scratch
    let task_c_query = (sql $"SELECT status FROM tasks WHERE id = 'task-c'")
    if ($task_c_query | is-empty) {
      error make { msg: "Task C not found" }
    }
    let task_c = $task_c_query.0
    assert equal $task_c.status "pending"  # Reset to pending, can be executed again

    # Verify: Journal entries for A and B still exist
    let journal_a = (journal-read $job_id $task_name_a $attempt)
    assert equal ($journal_a | length) 1
    assert equal $journal_a.0.output "output-a"

    let journal_b = (journal-read $job_id $task_name_b $attempt)
    assert equal ($journal_b | length) 1
    assert equal $journal_b.0.output "output-b"

    print "✓ Crash recovery replay test passed"
  } catch { |e|
    print $"✗ Crash recovery replay test failed: ($e)"
    error make { msg: "Test failed" }
  }
}

# Run the test
test test-crash-recovery-replay
