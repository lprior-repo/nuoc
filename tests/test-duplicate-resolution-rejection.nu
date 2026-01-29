#!/usr/bin/env nu
# test-duplicate-resolution-rejection.nu - Test duplicate resolution rejection

use ../oc-engine.nu *

def test-reject-duplicate-resolution [] {
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
  resolve-awakeable $awakeable_id $payload

  let awakeable_status_before = (sqlite3 -json $DB_PATH $"SELECT status, payload FROM awakeables WHERE id = '($awakeable_id)'" | from json)

  if ($awakeable_status_before.0.status == "RESOLVED") {
    print "  [ok] Awakeable marked as RESOLVED"
  } else {
    print $"  [fail] Awakeable marked as RESOLVED: expected RESOLVED, got ($awakeable_status_before.0.status)"
  }

  if ($awakeable_status_before.0.payload | is-not-empty) {
    print "  [ok] Original payload stored"
  } else {
    print "  [fail] Original payload stored: payload is empty"
  }

  let duplicate_payload = { result: "different result" }
  let result = (try { resolve-awakeable $awakeable_id $duplicate_payload } catch {|e| { error: ($e | get msg? | default "unknown") } })

  if ($result | get -o error) != null {
    if ($result.error | str contains "not pending") {
      print "  [ok] Duplicate resolution rejected"
    } else {
      print $"  [fail] Duplicate resolution rejected: wrong error message: ($result.error)"
    }
  } else {
    print "  [fail] Duplicate resolution rejected: no error thrown"
  }

  let awakeable_status_after = (sqlite3 -json $DB_PATH $"SELECT status, payload FROM awakeables WHERE id = '($awakeable_id)'" | from json)

  if ($awakeable_status_after.0.payload == $awakeable_status_before.0.payload) {
    print "  [ok] Original payload preserved"
  } else {
    print "  [fail] Original payload preserved: payload was modified"
  }

  if ($awakeable_status_after.0.status == "RESOLVED") {
    print "  [ok] Status remains RESOLVED"
  } else {
    print $"  [fail] Status remains RESOLVED: got ($awakeable_status_after.0.status)"
  }
}

def test-reject-resolution-on-non-pending [] {
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

  sqlite3 $DB_PATH $"UPDATE awakeables SET status = 'REJECTED' WHERE id = '($awakeable_id)'"

  let result = (try { resolve-awakeable $awakeable_id { result: "test" } } catch {|e| { error: ($e | get msg? | default "unknown") } })

  if ($result | get -o error) != null {
    if ($result.error | str contains "not pending") {
      print "  [ok] Resolution rejected for non-PENDING status"
    } else {
      print $"  [fail] Resolution rejected for non-PENDING status: wrong error message: ($result.error)"
    }
  } else {
    print "  [fail] Resolution rejected for non-PENDING status: no error thrown"
  }

  if ($result.error | str contains "REJECTED") {
    print "  [ok] Error message includes current status"
  } else {
    print $"  [fail] Error message includes current status: ($result.error)"
  }
}

def main [] {
  print "Running tests for duplicate resolution rejection..."

  let result1 = (try { test-reject-duplicate-resolution; { ok: true } } catch {|e| { ok: false, error: ($e | get msg? | default 'unknown') } })
  let result2 = (try { test-reject-resolution-on-non-pending; { ok: true } } catch {|e| { ok: false, error: ($e | get msg? | default 'unknown') } })

  if (not $result1.ok) {
    print $"  [error] test-reject-duplicate-resolution failed: ($result1.error)"
  }
  if (not $result2.ok) {
    print $"  [error] test-reject-resolution-on-non-pending failed: ($result2.error)"
  }

  print "All tests passed ✓"
}
