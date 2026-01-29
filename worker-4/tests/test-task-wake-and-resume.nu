#!/usr/bin/env nu
# test-task-wake-and-resume.nu - Test complete task wake and resume flow

use ../oc-engine.nu *

def test-task-can-resume-after-wake [] {
  rm -rf $DB_DIR

  db-init

  let job_id = "test-job-wake"
  job-create {
    name: $job_id,
    inputs: { bead_id: "test-bead" },
    tasks: [
      { name: "task-1", var: "result", run_cmd: "echo 'first part'" }
    ]
  }

  let task_name = "task-1"
  let attempt = 1
  init-execution-context $job_id $task_name $attempt

  # Create and await awakeable
  let awakeable = (ctx-awakeable $job_id $task_name $attempt)
  let awakeable_id = $awakeable.id

  ctx-await-awakeable $job_id $task_name $attempt $awakeable_id

  # Task should be suspended
  let task_status_before = (sqlite3 -json $DB_PATH $"SELECT status FROM tasks WHERE job_id = '($job_id)' AND name = '($task_name)'" | from json)
  if ($task_status_before.0.status != "suspended") {
    error make { msg: $"Task not suspended: got ($task_status_before.0.status)" }
  }

  # Resolve the awakeable
  resolve-awakeable $awakeable_id { result: "wake payload" }

  # Task should be woken (status pending)
  let task_status_after = (sqlite3 -json $DB_PATH $"SELECT status FROM tasks WHERE job_id = '($job_id)' AND name = '($task_name)'" | from json)
  if ($task_status_after.0.status != "pending") {
    error make { msg: $"Task not woken: got ($task_status_after.0.status)" }
  }

  # Try to execute the task again - this should resume from suspension point
  # If ctx-await-awakeable doesn't check for resolution, this will suspend again
  let exec_context = (try {
    init-execution-context $job_id $task_name $attempt
    ctx-await-awakeable $job_id $task_name $attempt $awakeable_id
    { status: "continued" }
  } catch {|e|
    { status: "suspended_again", error: ($e | get msg? | default "unknown") }
  })

  if $exec_context.status == "suspended_again" {
    print "  [fail] Task suspended again after wake - ctx-await-awakeable doesn't check resolution"
    return false
  }

  print "  [ok] Task can resume after wake"
  return true
}

def main [] {
  print "Testing task wake and resume flow..."

  let result = (test-task-can-resume-after-wake)

  if $result {
    print "All tests passed ✓"
  } else {
    print "Test failed - task wake needs implementation"
  }
}
