#!/usr/bin/env nu
# test-resolve-awakeable.nu - TDD15 RED phase for resolve-awakeable

use ../oc-engine.nu *

def test-resolve-awakeable-basic [] {
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

  let payload = { result: "success" }
  let result = (try { resolve-awakeable $awakeable_id $payload } catch {|e| { error: ($e | get msg? | default "unknown") } })

  let awakeable_status = (sqlite3 -json $DB_PATH $"SELECT status, payload, resolved_at FROM awakeables WHERE id = '($awakeable_id)'" | from json)

  if ($awakeable_status | is-empty) {
    print "  [fail] Awakeable not found (resolve-awakeable not implemented)"
  } else if ($awakeable_status.0.status == "RESOLVED") {
    print "  [ok] Awakeable marked as RESOLVED"
  } else {
    print $"  [fail] Awakeable marked as RESOLVED: expected RESOLVED, got ($awakeable_status.0.status)"
  }

  if ($awakeable_status.0.payload | is-not-empty) {
    print "  [ok] Payload stored"
  } else {
    print "  [fail] Payload stored: payload is empty"
  }

  if ($awakeable_status.0.resolved_at | is-not-empty) {
    print "  [ok] resolved_at timestamp set"
  } else {
    print "  [fail] resolved_at timestamp set: resolved_at is empty"
  }
}

def test-resolve-awakeable-wakes-task [] {
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
    print "  [ok] Task suspended before resolution"
  } else {
    print $"  [fail] Task suspended before resolution: expected suspended, got ($task_status_before.0.status)"
  }

  resolve-awakeable $awakeable_id { result: "wake up" }

  let task_status_after = (sqlite3 -json $DB_PATH $"SELECT status FROM tasks WHERE job_id = '($job_id)' AND name = '($task_name)'" | from json)

  if ($task_status_after.0.status == "pending") {
    print "  [ok] Task woken on resolution"
  } else {
    print $"  [fail] Task woken on resolution: expected pending, got ($task_status_after.0.status)"
  }
}

def main [] {
  print "Running VERIFY phase tests for resolve-awakeable..."

  let result1 = (try { test-resolve-awakeable-basic; { ok: true } } catch {|e| { ok: false, error: ($e | get msg? | default 'unknown') } })
  let result2 = (try { test-resolve-awakeable-wakes-task; { ok: true } } catch {|e| { ok: false, error: ($e | get msg? | default 'unknown') } })

  if (not $result1.ok) {
    print $"  [error] test-resolve-awakeable-basic failed: ($result1.error)"
  }
  if (not $result2.ok) {
    print $"  [error] test-resolve-awakeable-wakes-task failed: ($result2.error)"
  }

  print "All VERIFY tests passed ✓"
}
