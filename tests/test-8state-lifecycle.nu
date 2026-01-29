#!/usr/bin/env nu
# Tests for 8-State Restate Invocation Lifecycle

use std testing
use ../oc-engine.nu *

print "Testing 8-state invocation lifecycle..."

# ── Test Setup ─────────────────────────────────────────────────────────────────

def setup-test-db [] {
  db-init
}

def cleanup-test-db [] {
  rm -rf $DB_DIR
}

# ── State Constants Tests ─────────────────────────────────────────────────────

# Test: All 8 state constants are defined
def test-state-constants-defined [] {
  assert equal $STATUS_PENDING "pending"
  assert equal $STATUS_SCHEDULED "scheduled"
  assert equal $STATUS_READY "ready"
  assert equal $STATUS_RUNNING "running"
  assert equal $STATUS_SUSPENDED "suspended"
  assert equal $STATUS_BACKING_OFF "backing-off"
  assert equal $STATUS_PAUSED "paused"
  assert equal $STATUS_COMPLETED "completed"
}

# ── State Transition Validation Tests ───────────────────────────────────────────

# Test: is-valid-transition correctly validates transitions
def test-is-valid-transition [] {
  assert equal (is-valid-transition "pending" "ready") true
  assert equal (is-valid-transition "pending" "scheduled") true
  assert equal (is-valid-transition "scheduled" "ready") true
  assert equal (is-valid-transition "ready" "running") true
  assert equal (is-valid-transition "running" "suspended") true
  assert equal (is-valid-transition "running" "backing-off") true
  assert equal (is-valid-transition "running" "completed") true
  assert equal (is-valid-transition "suspended" "running") true
  assert equal (is-valid-transition "backing-off" "running") true
  assert equal (is-valid-transition "backing-off" "paused") true
  assert equal (is-valid-transition "backing-off" "completed") true
  assert equal (is-valid-transition "paused" "running") true

  # Invalid transitions
  assert equal (is-valid-transition "pending" "running") false
  assert equal (is-valid-transition "completed" "running") false
  assert equal (is-valid-transition "ready" "suspended") false
  assert equal (is-valid-transition "suspended" "ready") false
}

# Test: Valid transition pending → ready
def test-valid-transition-pending-to-ready [] {
  setup-test-db
  let job_id = (job-create { name: "test-job", tasks: [] })
  job-pickup $job_id
  let job = (sql $"SELECT status FROM jobs WHERE id = '($job_id)'")
  assert equal $job.0.status "ready"
  cleanup-test-db
}

# Test: Valid transition running → suspended
def test-valid-transition-running-to-suspended [] {
  setup-test-db
  let job_id = (job-create { name: "test-job", tasks: [] })
  transition-state $job_id "running" "test suspension"
  transition-state $job_id "suspended" "awaiting dependency"
  let job = (sql $"SELECT status FROM jobs WHERE id = '($job_id)'")
  assert equal $job.0.status "suspended"
  cleanup-test-db
}

# Test: Valid transition running → backing-off
def test-valid-transition-running-to-backing-off [] {
  setup-test-db
  let job_id = (job-create { name: "test-job", tasks: [] })
  transition-state $job_id "running" "test"
  transition-state $job_id "backing-off" "retriable failure"
  let job = (sql $"SELECT status, next_retry_at, retry_count FROM jobs WHERE id = '($job_id)'")
  assert equal $job.0.status "backing-off"
  assert not ($job.0.next_retry_at | is-empty)
  assert equal $job.0.retry_count 1
  cleanup-test-db
}

# Test: Valid transition running → completed (success)
def test-valid-transition-running-to-completed-success [] {
  setup-test-db
  let job_id = (job-create { name: "test-job", tasks: [] })
  transition-state $job_id "running" "test"
  transition-state $job_id "completed" "success"
  let job = (sql $"SELECT status, completion_result FROM jobs WHERE id = '($job_id)'")
  assert equal $job.0.status "completed"
  assert equal $job.0.completion_result "success"
  cleanup-test-db
}

# Test: Valid transition running → completed (failure)
def test-valid-transition-running-to-completed-failure [] {
  setup-test-db
  let job_id = (job-create { name: "test-job", tasks: [] })
  transition-state $job_id "running" "test"
  transition-state $job_id "completed" "failure: task failed"
  let job = (sql $"SELECT status, completion_result, completion_failure FROM jobs WHERE id = '($job_id)'")
  assert equal $job.0.status "completed"
  assert equal $job.0.completion_result "failure"
  assert not ($job.0.completion_failure | is-empty)
  cleanup-test-db
}

# ── Invalid Transition Tests ─────────────────────────────────────────────────────

# Test: Invalid transition pending → running
def test-invalid-transition-pending-to-running [] {
  setup-test-db
  let job_id = (job-create { name: "test-job", tasks: [] })
  let result = (try {
    transition-state $job_id "running" "invalid transition"
    "success"
  } catch { "error" })
  assert equal $result "error"
  let job = (sql $"SELECT status FROM jobs WHERE id = '($job_id)'")
  assert equal $job.0.status "pending"
  cleanup-test-db
}

# Test: Invalid transition completed → running
def test-invalid-transition-completed-to-running [] {
  setup-test-db
  let job_id = (job-create { name: "test-job", tasks: [] })
  transition-state $job_id "running" "test"
  transition-state $job_id "completed" "success"
  let result = (try {
    transition-state $job_id "running" "invalid transition"
    "success"
  } catch { "error" })
  assert equal $result "error"
  let job = (sql $"SELECT status FROM jobs WHERE id = '($job_id)'")
  assert equal $job.0.status "completed"
  cleanup-test-db
}

# ── Retry Backoff Calculation Tests ─────────────────────────────────────────────

# Test: Exponential backoff calculation
def test-calc-next-retry-at [] {
  let retry1 = (calc-next-retry-at 1 2 1)
  let retry2 = (calc-next-retry-at 1 2 2)
  let retry3 = (calc-next-retry-at 1 2 3)
  let retry4 = (calc-next-retry-at 1 2 4)

  assert ($retry1 | into datetime) > (date now)
  assert ($retry2 | into datetime) > ($retry1 | into datetime)
  assert ($retry3 | into datetime) > ($retry2 | into datetime)
  assert ($retry4 | into datetime) > ($retry3 | into datetime)
}

# ── Poll Functions Tests ────────────────────────────────────────────────────────

# Test: job-scheduler-poll function exists and returns list
def test-job-scheduler-poll-exists [] {
  let result = (job-scheduler-poll)
  assert ($result | describe) == "list"
}

# Test: job-retry-poll function exists and returns list
def test-job-retry-poll-exists [] {
  let result = (job-retry-poll)
  assert ($result | describe) == "list"
}

# ── Event Emission Tests ──────────────────────────────────────────────────────────

# Test: Each transition emits an event
def test-transition-emits-event [] {
  setup-test-db
  let job_id = (job-create { name: "test-job", tasks: [] })

  job-pickup $job_id
  let events = (sql $"SELECT * FROM events WHERE job_id = '($job_id)'")
  assert ($events | length) >= 2

  let transition_event = ($events | where event_type == "job.StateChange" | where new_state == "ready")
  assert not ($transition_event | is-empty)
  assert equal $transition_event.0.old_state "pending"

  cleanup-test-db
}

print "All 8-state lifecycle tests defined!"
print ""
print "Running tests..."

# Run all tests
test test-state-constants-defined
test test-is-valid-transition
test test-valid-transition-pending-to-ready
test test-valid-transition-running-to-suspended
test test-valid-transition-running-to-backing-off
test test-valid-transition-running-to-completed-success
test test-valid-transition-running-to-completed-failure
test test-invalid-transition-pending-to-running
test test-invalid-transition-completed-to-running
test test-calc-next-retry-at
test test-job-scheduler-poll-exists
test test-job-retry-poll-exists
test test-transition-emits-event

print "[ok] 8-state lifecycle tests completed"
