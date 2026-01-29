#!/usr/bin/env nu
# test-awakeable-http-endpoint.nu - TDD15 RED phase for HTTP endpoint

use std testing
use ../oc-engine.nu *

# Helper: Start HTTP server
def start-server [port: int] {
  ^python3 scripts/oc-http-server.py $port &
}

# Helper: Stop HTTP server
def stop-server [port: int] {
  try {
    ^pkill -f $"python3.*oc-http-server.py ($port)"
  } catch {|e|
  }
}

# Test: HTTP server starts and responds to health check
def test-server-health-check [] {
  rm -rf $DB_DIR

  # Start server
  let port = 4098
  start-server $port

  # Wait for server to start
  sleep 2sec

  mut test_passed = false
  try {
    # Health check
    let health = (http get $"http://localhost:($port)/health")
    assert equal $health.status "ok"
    assert not ($health.message | is-empty)

    print "  [ok] Server health check passed"
    $test_passed = true
  } catch {
    print $"  [fail] Server health check failed"
  }

  # Stop server
  stop-server $port
  sleep 1sec

  if not $test_passed {
    error make { msg: "test failed" }
  }
}

# Test: POST /awakeables/{id}/resolve accepts JSON payload
def test-resolve-awakeable-accepts-json [] {
  rm -rf $DB_DIR

  db-init

  # Create job and awakeable
  let job_id = "test-job-http-1"
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

  # Start server
  let port = 4099
  start-server $port
  sleep 2sec

  mut test_passed = false
  try {
    # Resolve awakeable via HTTP
    let payload = { result: "success from HTTP" }
    let response = (http post $"http://localhost:($port)/awakeables/($awakeable_id)/resolve" $payload --content-type application/json)

    assert equal $response.success true
    assert equal $response.awakeable_id $awakeable_id
    assert not ($response.payload | is-empty)

    print "  [ok] HTTP endpoint accepts JSON payload"
    $test_passed = true
  } catch {
    print "  [fail] HTTP endpoint accepts JSON payload"
  }

  # Stop server
  stop-server $port
  sleep 1sec

  if not $test_passed {
    error make { msg: "test failed" }
  }
}

# Test: POST /awakeables/{id}/resolve returns success/error
def test-resolve-awakeable-returns-success-error [] {
  rm -rf $DB_DIR

  db-init

  # Create job and awakeable
  let job_id = "test-job-http-2"
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

  # Start server
  let port = 4100
  start-server $port
  sleep 2sec

  mut test_passed = false
  try {
    # Test success case
    let payload = { status: "completed" }
    let response = (http post $"http://localhost:($port)/awakeables/($awakeable_id)/resolve" $payload --content-type application/json)

    if ($response.success? | default false) {
      print "  [ok] HTTP endpoint returns success on valid resolve"
    } else {
      print "  [fail] HTTP endpoint returns success on valid resolve: got error response"
    }

    # Test error case - resolve non-existent awakeable
    let error_response = (try {
      http post $"http://localhost:($port)/awakeables/nonexistent-id/resolve" { dummy: "data" } --content-type application/json
    } catch {|e|
      { error: ($e | get msg? | default "request failed") }
    })

    if ($error_response | get -o "error" | default "") != "" or ($error_response.success? | default true) == false {
      print "  [ok] HTTP endpoint returns error for non-existent awakeable"
      $test_passed = true
    } else {
      print "  [fail] HTTP endpoint returns error for non-existent awakeable"
    }

  } catch {
    print "  [fail] HTTP endpoint returns success/error"
  }

  # Stop server
  stop-server $port
  sleep 1sec

  if not $test_passed {
    error make { msg: "test failed" }
  }
}

# Test: POST /awakeables/{id}/resolve wakes task
def test-resolve-awakeable-wakes-task [] {
  rm -rf $DB_DIR

  db-init

  # Create job and awakeable
  let job_id = "test-job-http-3"
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

  # Suspend task on awakeable
  ctx-await-awakeable $job_id $task_name $attempt $awakeable_id

  # Verify task is suspended
  let task_status_before = (sqlite3 -json $DB_PATH $"SELECT status FROM tasks WHERE job_id = '($job_id)' AND name = '($task_name)'" | from json)

  if ($task_status_before.0.status != "suspended") {
    print "  [fail] Task not suspended before HTTP resolve"
    return
  }

  # Start server
  let port = 4101
  start-server $port
  sleep 2sec

  mut test_passed = false
  try {
    # Resolve awakeable via HTTP
    let payload = { result: "wake up from HTTP" }
    let response = (http post $"http://localhost:($port)/awakeables/($awakeable_id)/resolve" $payload --content-type application/json)

    # Check task status after resolve
    let task_status_after = (sqlite3 -json $DB_PATH $"SELECT status FROM tasks WHERE job_id = '($job_id)' AND name = '($task_name)'" | from json)

    if ($task_status_after.0.status == "pending") {
      print "  [ok] Task woken on HTTP resolve"
      $test_passed = true
    } else {
      print $"  [fail] Task woken on HTTP resolve: expected pending, got ($task_status_after.0.status)"
    }

  } catch {
    print "  [fail] Task woken on HTTP resolve"
  }

  # Stop server
  stop-server $port
  sleep 1sec

  if not $test_passed {
    error make { msg: "test failed" }
  }
}

# Test: Duplicate resolution is rejected
def test-duplicate-resolution-rejected [] {
  rm -rf $DB_DIR

  db-init

  # Create job and awakeable
  let job_id = "test-job-http-4"
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

  # Start server
  let port = 4102
  start-server $port
  sleep 2sec

  mut test_passed = false
  try {
    # Resolve awakeable first time
    let payload1 = { result: "first resolve" }
    let response1 = (http post $"http://localhost:($port)/awakeables/($awakeable_id)/resolve" $payload1 --content-type application/json)

    if ($response1.success? | default false) {
      print "  [ok] First resolve succeeded"
    } else {
      print "  [fail] First resolve succeeded"
    }

    # Try to resolve again - should fail
    let payload2 = { result: "second resolve" }
    let response2 = (try {
      http post $"http://localhost:($port)/awakeables/($awakeable_id)/resolve" $payload2 --content-type application/json
    } catch {|e|
      { success: false, error: ($e | get msg? | default "duplicate resolution") }
    })

    if (not ($response2.success? | default true)) or ($response2.error? | default "") != "" {
      print "  [ok] Duplicate resolution rejected"
      $test_passed = true
    } else {
      print "  [fail] Duplicate resolution rejected"
    }

  } catch {
    print "  [fail] Duplicate resolution rejected"
  }

  # Stop server
  stop-server $port
  sleep 1sec

  if not $test_passed {
    error make { msg: "test failed" }
  }
}

def main [] {
  print "Running RED phase tests for awakeable HTTP endpoint..."

  test-server-health-check
  test-resolve-awakeable-accepts-json
  test-resolve-awakeable-returns-success-error
  test-resolve-awakeable-wakes-task
  test-duplicate-resolution-rejected

  print "All RED tests completed"
}
