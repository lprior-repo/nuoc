#!/usr/bin/env nu
# rq-reject-awakeable-gen3.nu - Red Queen Generation 3: Unicode and encoding bypasses

use ../oc-engine.nu *

def test-reject-awakeable-unicode-bypass [] {
  rm -rf $DB_DIR

  db-init

  let job_id = "test-rq-gen3-1"
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

  # Test with Unicode homographs for SQL injection
  let unicode_injection = "'; DROP TABLE awakeables;—"  # em-dash instead of hyphen
  let result = (try { reject-awakeable $awakeable_id $unicode_injection } catch {|e| { exception: true, error: ($e | get msg? | default "unknown") } })

  if ($result.exception? == true) {
    print "  [fail] Gen 3.1: Unicode SQL injection - should be handled"
  } else if ($result.rejected? == true) {
    print "  [ok] Gen 3.1: Unicode injection safely escaped"
  } else {
    print "  [fail] Gen 3.1: Unexpected result"
  }

  # Verify database intact
  let table_exists = (sqlite3 $DB_PATH "SELECT name FROM sqlite_master WHERE type='table' AND name='awakeables'")
  if ($table_exists | is-not-empty) {
    print "  [ok] Gen 3.1: Awakeables table intact"
  } else {
    print "  [fail] Gen 3.1: Awakeables table dropped!"
  }
}

def test-reject-awakeable-null-byte [] {
  rm -rf $DB_DIR

  db-init

  let job_id = "test-rq-gen3-2"
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

  # Test with unusual whitespace and control characters
  let control_char_error = "Error\u{200B}message"  # zero-width space
  let result = (try { reject-awakeable $awakeable_id $control_char_error } catch {|e| { exception: true, error: ($e | get msg? | default "unknown") } })

  if ($result.exception? == true) {
    print "  [fail] Gen 3.2: Control characters - should be handled"
  } else if ($result.rejected? == true) {
    print "  [ok] Gen 3.2: Control characters handled"
  } else {
    print "  [fail] Gen 3.2: Unexpected result"
  }

  # Verify error stored correctly
  let awakeable_payload = (sqlite3 -json $DB_PATH $"SELECT payload FROM awakeables WHERE id = '($awakeable_id)'" | from json)
  if ($awakeable_payload.0.payload | is-not-empty) {
    print "  [ok] Gen 3.2: Payload stored with control characters"
  } else {
    print "  [fail] Gen 3.2: Payload is empty"
  }
}

def test-reject-awakeable-emoji [] {
  rm -rf $DB_DIR

  db-init

  let job_id = "test-rq-gen3-3"
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

  # Test with emoji and multi-byte characters
  let emoji_error = "❌ Error: 🚫 Forbidden ⚠️"
  let result = (try { reject-awakeable $awakeable_id $emoji_error } catch {|e| { exception: true, error: ($e | get msg? | default "unknown") } })

  if ($result.exception? == true) {
    print "  [fail] Gen 3.3: Emoji - should be handled"
  } else if ($result.rejected? == true) {
    print "  [ok] Gen 3.3: Emoji accepted"
  } else {
    print "  [fail] Gen 3.3: Unexpected result"
  }

  # Verify error stored correctly and can be retrieved
  let awakeable_record = (sqlite3 -json $DB_PATH $"SELECT status, payload FROM awakeables WHERE id = '($awakeable_id)'" | from json)
  if ($awakeable_record.0.status == "REJECTED") {
    print "  [ok] Gen 3.3: Awakeable rejected"
    let stored_error = ($awakeable_record.0.payload | from json)
    if ($stored_error | str contains "❌") and ($stored_error | str contains "🚫") and ($stored_error | str contains "⚠️") {
      print "  [ok] Gen 3.3: Emoji preserved correctly"
    } else {
      print $"  [fail] Gen 3.3: Emoji corrupted: ($stored_error)"
    }
  } else {
    print $"  [fail] Gen 3.3: Status is ($awakeable_record.0.status), expected REJECTED"
  }
}

def main [] {
  print "Running Red Queen Gen 3 tests for reject-awakeable..."

  test-reject-awakeable-unicode-bypass
  test-reject-awakeable-null-byte
  test-reject-awakeable-emoji

  print "Red Queen Gen 3 complete"
}
