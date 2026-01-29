#!/usr/bin/env nu
# rq-reject-awakeable-gen5.nu - Red Queen Generation 5: Creative exploits and assumption violations

use ../oc-engine.nu *

def test-reject-awakeable-json-attack [] {
  rm -rf $DB_DIR

  db-init

  let job_id = "test-rq-gen5-1"
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

  # Test with JSON injection attempt (nested quotes and brackets)
  let json_attack = "\"status\": \"RESOLVED\", \"payload\": {\"hacked\": true}}"
  let result = (try { reject-awakeable $awakeable_id $json_attack } catch {|e| { exception: true, error: ($e | get msg? | default "unknown") } })

  if ($result.exception? == true) {
    print "  [fail] Gen 5.1: JSON injection - should be handled"
  } else if ($result.rejected? == true) {
    print "  [ok] Gen 5.1: JSON injection handled as string"
  } else {
    print "  [fail] Gen 5.1: Unexpected result"
  }

  # Verify awakeable stays REJECTED (not corrupted to RESOLVED)
  let awakeable_status = (sqlite3 -json $DB_PATH $"SELECT status FROM awakeables WHERE id = '($awakeable_id)'" | from json)
  if ($awakeable_status.0.status == "REJECTED") {
    print "  [ok] Gen 5.1: Awakeable remains REJECTED (not corrupted)"
  } else {
    print $"  [fail] Gen 5.1: Status is ($awakeable_status.0.status), expected REJECTED"
  }
}

def test-reject-awakeable-xml-attack [] {
  rm -rf $DB_DIR

  db-init

  let job_id = "test-rq-gen5-2"
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

  # Test with XML injection attempt
  let xml_attack = "<status>RESOLVED</status><payload>hacked</payload>"
  let result = (try { reject-awakeable $awakeable_id $xml_attack } catch {|e| { exception: true, error: ($e | get msg? | default "unknown") } })

  if ($result.exception? == true) {
    print "  [fail] Gen 5.2: XML injection - should be handled"
  } else if ($result.rejected? == true) {
    print "  [ok] Gen 5.2: XML injection handled as string"
  } else {
    print "  [fail] Gen 5.2: Unexpected result"
  }

  # Verify awakeable stays REJECTED
  let awakeable_status = (sqlite3 -json $DB_PATH $"SELECT status FROM awakeables WHERE id = '($awakeable_id)'" | from json)
  if ($awakeable_status.0.status == "REJECTED") {
    print "  [ok] Gen 5.2: Awakeable remains REJECTED"
  } else {
    print $"  [fail] Gen 5.2: Status is ($awakeable_status.0.status), expected REJECTED"
  }
}

def test-reject-awakeable-script-attack [] {
  rm -rf $DB_DIR

  db-init

  let job_id = "test-rq-gen5-3"
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

  # Test with script tag injection (XSS)
  let script_attack = "<script>alert('XSS')</script>"
  let result = (try { reject-awakeable $awakeable_id $script_attack } catch {|e| { exception: true, error: ($e | get msg? | default "unknown") } })

  if ($result.exception? == true) {
    print "  [fail] Gen 5.3: Script injection - should be handled"
  } else if ($result.rejected? == true) {
    print "  [ok] Gen 5.3: Script injection handled as string"
  } else {
    print "  [fail] Gen 5.3: Unexpected result"
  }

  # Verify error stored correctly
  let awakeable_payload = (sqlite3 -json $DB_PATH $"SELECT payload FROM awakeables WHERE id = '($awakeable_id)'" | from json)
  if ($awakeable_payload.0.payload | is-not-empty) {
    print "  [ok] Gen 5.3: Script stored as data (not executed)"
  } else {
    print "  [fail] Gen 5.3: Payload is empty"
  }
}

def test-reject-awakeable-path-traversal [] {
  rm -rf $DB_DIR

  db-init

  let job_id = "test-rq-gen5-4"
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

  # Test with path traversal attempt
  let path_traversal = "../../../../etc/passwd"
  let result = (try { reject-awakeable $awakeable_id $path_traversal } catch {|e| { exception: true, error: ($e | get msg? | default "unknown") } })

  if ($result.exception? == true) {
    print "  [fail] Gen 5.4: Path traversal - should be handled"
  } else if ($result.rejected? == true) {
    print "  [ok] Gen 5.4: Path traversal handled as string"
  } else {
    print "  [fail] Gen 5.4: Unexpected result"
  }

  # Verify error stored correctly
  let awakeable_payload = (sqlite3 -json $DB_PATH $"SELECT payload FROM awakeables WHERE id = '($awakeable_id)'" | from json)
  if ($awakeable_payload.0.payload | is-not-empty) {
    print "  [ok] Gen 5.4: Path stored as data (not traversed)"
  } else {
    print "  [fail] Gen 5.4: Payload is empty"
  }
}

def main [] {
  print "Running Red Queen Gen 5 tests for reject-awakeable..."

  test-reject-awakeable-json-attack
  test-reject-awakeable-xml-attack
  test-reject-awakeable-script-attack
  test-reject-awakeable-path-traversal

  print "Red Queen Gen 5 complete"
}
