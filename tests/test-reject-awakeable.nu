#!/usr/bin/env nu
# test-reject-awakeable.nu - TDD15 RED phase for reject-awakeable

use ../oc-engine.nu *

def test-reject-awakeable-basic [] {
  rm -rf $DB_DIR

  db-init

  let job_id = "test-job-1"
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

  let error_msg = "Validation failed: invalid input"
  let result = (try { reject-awakeable $awakeable_id $error_msg } catch {|e| { error: ($e | get msg? | default "unknown") } })

  let awakeable_status = (sqlite3 -json $DB_PATH $"SELECT status, payload, resolved_at FROM awakeables WHERE id = '($awakeable_id)'" | from json)

  if ($awakeable_status | is-empty) {
    print "  [fail] Awakeable not found (reject-awakeable not implemented)"
  } else if ($awakeable_status.0.status == "REJECTED") {
    print "  [ok] Awakeable marked as REJECTED"
  } else {
    print $"  [fail] Awakeable marked as REJECTED: expected REJECTED, got ($awakeable_status.0.status)"
  }

  if ($awakeable_status.0.payload | is-not-empty) {
    print "  [ok] Error stored in payload"
  } else {
    print "  [fail] Error stored: payload is empty"
  }

  if ($awakeable_status.0.resolved_at | is-not-empty) {
    print "  [ok] resolved_at timestamp set"
  } else {
    print "  [fail] resolved_at timestamp set: resolved_at is empty"
  }
}

def test-reject-awakeable-wakes-task [] {
  rm -rf $DB_DIR

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

  let task_status_before = (sqlite3 -json $DB_PATH $"SELECT status FROM tasks WHERE job_id = '($job_id)' AND name = '($task_name)'" | from json)

  if ($task_status_before.0.status == "suspended") {
    print "  [ok] Task suspended before rejection"
  } else {
    print $"  [fail] Task suspended before rejection: expected suspended, got ($task_status_before.0.status)"
  }

  reject-awakeable $awakeable_id "Permission denied"

  let task_status_after = (sqlite3 -json $DB_PATH $"SELECT status FROM tasks WHERE job_id = '($job_id)' AND name = '($task_name)'" | from json)

  if ($task_status_after.0.status == "pending") {
    print "  [ok] Task woken on rejection"
  } else {
    print $"  [fail] Task woken on rejection: expected pending, got ($task_status_after.0.status)"
  }
}

def test-reject-awakeable-error-received [] {
  rm -rf $DB_DIR

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

  let awakeable = (ctx-awakeable $job_id $task_name $attempt)
  let awakeable_id = $awakeable.id

  ctx-await-awakeable $job_id $task_name $attempt $awakeable_id

  reject-awakeable $awakeable_id "Invalid data"

  let result = (try { ctx-await-awakeable $job_id $task_name $attempt $awakeable_id } catch {|e| { error: ($e | get msg? | default "unknown") } })

  if ($result.error? | is-not-empty) {
    print "  [ok] Task receives error on rejection"
  } else if ($result.resumed? == true) {
    print $"  [fail] Task receives error: expected error, got resumed with payload ($result.payload? | default {})"
  } else {
    print "  [fail] Task receives error: unexpected result"
  }
}

def main [] {
  print "Running RED phase tests for reject-awakeable..."

  test-reject-awakeable-basic
  test-reject-awakeable-wakes-task
  test-reject-awakeable-error-received

  print "RED phase complete - all tests should fail"
}
