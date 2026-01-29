#!/usr/bin/env nu
# rq-reject-awakeable-gen2.nu - Red Queen Generation 2: Boundary conditions

use ../oc-engine.nu *

def test-reject-awakeable-already-resolved [] {
  rm -rf $DB_DIR

  db-init

  let job_id = "test-rq-gen2-1"
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

  # First resolve
  resolve-awakeable $awakeable_id { result: "success" }

  # Try to reject already resolved awakeable
  let result = (try { reject-awakeable $awakeable_id "Try again later" } catch {|e| { exception: true, error: ($e | get msg? | default "unknown") } })

  if ($result.exception? == true) {
    print "  [ok] Gen 2.1: Rejecting RESOLVED awakeable throws error"
    if ($result.error | str contains "not pending") {
      print "  [ok] Gen 2.1: Error message indicates not pending"
    } else {
      print $"  [fail] Gen 2.1: Unexpected error message: ($result.error)"
    }
  } else {
    print "  [fail] Gen 2.1: Should not reject already resolved awakeable"
  }

  # Verify awakeable stays RESOLVED
  let awakeable_status = (sqlite3 -json $DB_PATH $"SELECT status FROM awakeables WHERE id = '($awakeable_id)'" | from json)
  if ($awakeable_status.0.status == "RESOLVED") {
    print "  [ok] Gen 2.1: Awakeable remains RESOLVED"
  } else {
    print $"  [fail] Gen 2.1: Status is ($awakeable_status.0.status), expected RESOLVED"
  }
}

def test-reject-awakeable-timeouted [] {
  rm -rf $DB_DIR

  db-init

  let job_id = "test-rq-gen2-2"
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

  # Create awakeable with very short timeout
  let awakeable = (ctx-awakeable-timeout $job_id $task_name $attempt 1)
  let awakeable_id = $awakeable.id

  ctx-await-awakeable $job_id $task_name $attempt $awakeable_id

  # Wait for timeout
  sleep 2sec

  # Process timeouts
  check-awakeable-timeouts

  # Try to reject timeouted awakeable
  let result = (try { reject-awakeable $awakeable_id "Manual reject" } catch {|e| { exception: true, error: ($e | get msg? | default "unknown") } })

  if ($result.exception? == true) {
    print "  [ok] Gen 2.2: Rejecting TIMEOUT awakeable throws error"
    if ($result.error | str contains "not pending") {
      print "  [ok] Gen 2.2: Error message indicates not pending"
    } else {
      print $"  [fail] Gen 2.2: Unexpected error message: ($result.error)"
    }
  } else {
    print "  [fail] Gen 2.2: Should not reject timeouted awakeable"
  }

  # Verify awakeable stays TIMEOUT
  let awakeable_status = (sqlite3 -json $DB_PATH $"SELECT status FROM awakeables WHERE id = '($awakeable_id)'" | from json)
  if ($awakeable_status.0.status == "TIMEOUT") {
    print "  [ok] Gen 2.2: Awakeable remains TIMEOUT"
  } else {
    print $"  [fail] Gen 2.2: Status is ($awakeable_status.0.status), expected TIMEOUT"
  }
}

def test-reject-awakeable-twice [] {
  rm -rf $DB_DIR

  db-init

  let job_id = "test-rq-gen2-3"
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

  # First reject
  reject-awakeable $awakeable_id "First rejection"

  # Try to reject again
  let result = (try { reject-awakeable $awakeable_id "Second rejection" } catch {|e| { exception: true, error: ($e | get msg? | default "unknown") } })

  if ($result.exception? == true) {
    print "  [ok] Gen 2.3: Rejecting REJECTED awakeable throws error"
    if ($result.error | str contains "not pending") {
      print "  [ok] Gen 2.3: Error message indicates not pending"
    } else {
      print $"  [fail] Gen 2.3: Unexpected error message: ($result.error)"
    }
  } else {
    print "  [fail] Gen 2.3: Should not reject already rejected awakeable"
  }

  # Verify awakeable stays REJECTED with first error
  let awakeable_record = (sqlite3 -json $DB_PATH $"SELECT status, payload FROM awakeables WHERE id = '($awakeable_id)'" | from json)
  if ($awakeable_record.0.status == "REJECTED") {
    print "  [ok] Gen 2.3: Awakeable remains REJECTED"
    let stored_error = ($awakeable_record.0.payload | from json)
    if $stored_error == "First rejection" {
      print "  [ok] Gen 2.3: First error message preserved"
    } else {
      print $"  [fail] Gen 2.3: Error changed to ($stored_error)"
    }
  } else {
    print $"  [fail] Gen 2.3: Status is ($awakeable_record.0.status), expected REJECTED"
  }
}

def main [] {
  print "Running Red Queen Gen 2 tests for reject-awakeable..."

  test-reject-awakeable-already-resolved
  test-reject-awakeable-timeouted
  test-reject-awakeable-twice

  print "Red Queen Gen 2 complete"
}
