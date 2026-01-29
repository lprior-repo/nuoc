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

  let awakeable_status = (sql $"SELECT status FROM awakeables WHERE id = '($awakeable_id)'")

  if ($awakeable_status | is-empty) {
    print "  [fail] Awakeable not found (resolve-awakeable not implemented)"
  } else if ($awakeable_status.0.status == "RESOLVED") {
    print "  [ok] Awakeable marked as RESOLVED"
  } else {
    print $"  [fail] Awakeable marked as RESOLVED: expected RESOLVED, got ($awakeable_status.0.status)"
  }
}

def main [] {
  print "Running RED phase tests for resolve-awakeable..."

  let result = (try { test-resolve-awakeable-basic; { ok: true } } catch {|e| { ok: false, error: ($e | get msg? | default 'unknown') } })

  if (not $result.ok) {
    print $"  [error] test failed: ($result.error)"
  }

  print "All RED tests should fail (resolve-awakeable not implemented yet) ✓"
}
