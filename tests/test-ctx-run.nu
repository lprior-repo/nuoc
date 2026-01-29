#!/usr/bin/env nu
# test-ctx-run.nu — Tests for ctx.run replay logic

use std testing
use ../oc-engine.nu *
use ../ctx.nu *

print "Testing ctx.run..."

# ── Test Helpers ─────────────────────────────────────────────────────────────

# SQL helper for direct database access
def sql [query: string] {
  sqlite3 -json ".oc-workflow/journal.db" $query | from json
}

def sql-exec [query: string] {
  sqlite3 ".oc-workflow/journal.db" $query
}

def setup-test-job [] {
  db-init

  # Clean up any existing data first
  sql-exec "DELETE FROM journal WHERE job_id = 'test-job'"
  sql-exec "DELETE FROM execution_context WHERE job_id = 'test-job'"
  sql-exec "DELETE FROM tasks WHERE job_id = 'test-job'"
  sql-exec "DELETE FROM jobs WHERE id = 'test-job'"

  # Create a test job
  sql-exec "INSERT INTO jobs (id, name, bead_id, status) VALUES ('test-job', 'Test Job', 'nuoc-zno', 'running')"

  # Create a test task
  sql-exec "INSERT INTO tasks (id, job_id, name, status, attempt) VALUES ('test-task', 'test-job', 'test-task', 'running', 1)"

  # Initialize execution context
  init-execution-context 'test-job' 'test-task' 1
}

def cleanup-test-job [] {
  sql-exec "DELETE FROM journal WHERE job_id = 'test-job'"
  sql-exec "DELETE FROM execution_context WHERE job_id = 'test-job'"
  sql-exec "DELETE FROM tasks WHERE job_id = 'test-job'"
  sql-exec "DELETE FROM jobs WHERE id = 'test-job'"
}

# ── Tests ────────────────────────────────────────────────────────────────────

# Test 1: Replays return cached output
def test-replay-returns-cached-output [] {
  print "  [TEST] Replays return cached output"

  setup-test-job

  # Set environment variables
  $env.JOB_ID = 'test-job'
  $env.TASK_NAME = 'test-task'
  $env.ATTEMPT = 1

  # Create a journal entry manually (simulating previous execution)
  sql-exec "INSERT INTO journal (job_id, task_name, attempt, entry_index, op_type, input, output) VALUES ('test-job', 'test-task', 1, 0, 'run', '{}', '\"cached-result\"')"

  # Re-initialize context to pick up the journal entry (delete old context first)
  sql-exec "DELETE FROM execution_context WHERE job_id = 'test-job'"
  init-execution-context 'test-job' 'test-task' 1 --replay-mode

  # Run ctx.run - should return cached value
  let result = (ctx run { || "this-should-not-execute" })

  # Verify we got the cached result
  if $result != "cached-result" {
    error make { msg: $"Expected 'cached-result', got '($result)'" }
  }

  cleanup-test-job
  print "    ✓ PASS"
}

# Test 2: Live executes closure
def test-live-executes-closure [] {
  print "  [TEST] Live executes closure"

  setup-test-job

  # Set environment variables
  $env.JOB_ID = 'test-job'
  $env.TASK_NAME = 'test-task'
  $env.ATTEMPT = 1

  # Run ctx.run in live mode - should execute closure
  let result = (ctx run { || "live-result" })

  # Verify closure was executed
  if $result != "live-result" {
    error make { msg: $"Expected 'live-result', got '($result)'" }
  }

  cleanup-test-job
  print "    ✓ PASS"
}

# Test 3: Result journaled on live execution
def test-result-journaled-on-live [] {
  print "  [TEST] Result journaled on live execution"

  setup-test-job

  # Set environment variables
  $env.JOB_ID = 'test-job'
  $env.TASK_NAME = 'test-task'
  $env.ATTEMPT = 1

  # Execute via ctx.run
  ctx run { || "journal-test-result" }

  # Check journal was written
  let journal_entries = (sql "SELECT * FROM journal WHERE job_id = 'test-job' AND task_name = 'test-task'")

  # Verify journal entry exists
  if ($journal_entries | length) == 0 {
    error make { msg: "No journal entries found" }
  }

  # Verify the output
  if $journal_entries.0.output != '"journal-test-result"' {
    error make { msg: $"Expected '\"journal-test-result\"', got '($journal_entries.0.output)'" }
  }

  cleanup-test-job
  print "    ✓ PASS"
}

# Test 4: Multiple entries replayed in order
def test-multiple-entries-replayed [] {
  print "  [TEST] Multiple entries replayed in order"

  setup-test-job

  # Set environment variables
  $env.JOB_ID = 'test-job'
  $env.TASK_NAME = 'test-task'
  $env.ATTEMPT = 1

  # Create multiple journal entries
  sql-exec "INSERT INTO journal (job_id, task_name, attempt, entry_index, op_type, input, output) VALUES ('test-job', 'test-task', 1, 0, 'run', '{}', '\"first\"')"
  sql-exec "INSERT INTO journal (job_id, task_name, attempt, entry_index, op_type, input, output) VALUES ('test-job', 'test-task', 1, 1, 'run', '{}', '\"second\"')"
  sql-exec "INSERT INTO journal (job_id, task_name, attempt, entry_index, op_type, input, output) VALUES ('test-job', 'test-task', 1, 2, 'run', '{}', '\"third\"')"

  # Re-initialize context for replay (delete old context first)
  sql-exec "DELETE FROM execution_context WHERE job_id = 'test-job'"
  init-execution-context 'test-job' 'test-task' 1 --replay-mode

  # Replay entries
  let result1 = (ctx run { || "wrong1" })
  let result2 = (ctx run { || "wrong2" })
  let result3 = (ctx run { || "wrong3" })

  # Verify order
  if $result1 != "first" or $result2 != "second" or $result3 != "third" {
    error make { msg: $"Replay order incorrect: got [$result1, $result2, $result3]" }
  }

  cleanup-test-job
  print "    ✓ PASS"
}

# ── Test Runner ─────────────────────────────────────────────────────────────

test-replay-returns-cached-output
test-live-executes-closure
test-result-journaled-on-live
test-multiple-entries-replayed

print ""
print "All ctx.run tests passed! ✓"
