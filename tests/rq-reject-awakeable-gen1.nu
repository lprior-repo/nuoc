#!/usr/bin/env nu
# rq-reject-awakeable-gen1.nu - Red Queen Generation 1: Basic edge cases

use ../oc-engine.nu *

def test-reject-awakeable-empty-error [] {
  rm -rf $DB_DIR

  db-init

  let job_id = "test-rq-gen1-1"
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

  # Test 1: Empty error message
  let result = (try { reject-awakeable $awakeable_id "" } catch {|e| { error: ($e | get msg? | default "unknown") } })

  if ($result.error? | is-not-empty) {
    print "  [fail] Gen 1.1: Empty error message - should be allowed"
  } else if ($result.rejected? == true) {
    print "  [ok] Gen 1.1: Empty error message accepted"
  } else {
    print "  [fail] Gen 1.1: Unexpected result"
  }

  # Verify awakeable is rejected
  let awakeable_status = (sqlite3 -json $DB_PATH $"SELECT status FROM awakeables WHERE id = '($awakeable_id)'" | from json)
  if ($awakeable_status.0.status == "REJECTED") {
    print "  [ok] Gen 1.1: Awakeable rejected with empty error"
  } else {
    print $"  [fail] Gen 1.1: Status is ($awakeable_status.0.status), expected REJECTED"
  }
}

def test-reject-awakeable-sql-injection-in-error [] {
  rm -rf $DB_DIR

  db-init

  let job_id = "test-rq-gen1-2"
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

  # Test 2: SQL injection attempt in error message
  let sql_injection = "'; DROP TABLE awakeables;--"
  let result = (try { reject-awakeable $awakeable_id $sql_injection } catch {|e| { exception: true, error: ($e | get msg? | default "unknown") } })

  if ($result.exception? == true) {
    print "  [fail] Gen 1.2: SQL injection threw exception - should be safely escaped"
  } else if ($result.rejected? == true) {
    print "  [ok] Gen 1.2: SQL injection safely escaped"
  } else {
    print "  [fail] Gen 1.2: Unexpected result"
  }

  # Verify awakeable is still in database (not dropped)
  let awakeable_status = (sqlite3 -json $DB_PATH $"SELECT status FROM awakeables WHERE id = '($awakeable_id)'" | from json)
  if ($awakeable_status | is-empty) {
    print "  [fail] Gen 1.2: Awakeable table dropped by SQL injection!"
  } else if ($awakeable_status.0.status == "REJECTED") {
    print "  [ok] Gen 1.2: Awakeable rejected, database intact"
  } else {
    print $"  [fail] Gen 1.2: Status is ($awakeable_status.0.status), expected REJECTED"
  }
}

def test-reject-awakeable-special-characters [] {
  rm -rf $DB_DIR

  db-init

  let job_id = "test-rq-gen1-3"
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

  # Test 3: Special characters in error message
  let special_chars = "Error: \n\t\r\"'\\`$@#$%^&*()[]{}|;:,.<>/?~`"
  let result = (try { reject-awakeable $awakeable_id $special_chars } catch {|e| { exception: true, error: ($e | get msg? | default "unknown") } })

  if ($result.exception? == true) {
    print "  [fail] Gen 1.3: Special characters - should be handled"
  } else if ($result.rejected? == true) {
    print "  [ok] Gen 1.3: Special characters accepted"
  } else {
    print "  [fail] Gen 1.3: Unexpected result"
  }

  # Verify error stored correctly
  let awakeable_payload = (sqlite3 -json $DB_PATH $"SELECT payload FROM awakeables WHERE id = '($awakeable_id)'" | from json)
  if ($awakeable_payload.0.payload | is-not-empty) {
    print "  [ok] Gen 1.3: Special characters stored correctly"
  } else {
    print "  [fail] Gen 1.3: Payload is empty"
  }
}

def main [] {
  print "Running Red Queen Gen 1 tests for reject-awakeable..."

  test-reject-awakeable-empty-error
  test-reject-awakeable-sql-injection-in-error
  test-reject-awakeable-special-characters

  print "Red Queen Gen 1 complete"
}
