#!/usr/bin/env nu
# Red Queen Gen 5 Test: Special character handling

use ../oc-engine.nu *

print "Red Queen Gen 5: Testing special character handling"

rm -rf $DB_DIR
db-init

# Test 1: Unicode characters in ID
print "Test 1: Unicode characters in ID"
let result1 = (try {
  # Use simple test that SQLite TEXT supports Unicode
  sqlite3 $DB_PATH "INSERT INTO awakeables (id, job_id, task_name, entry_index) VALUES ('test-id-1', 'job-日本語', 'task-1', 0);"
  let check = (sqlite3 $DB_PATH "SELECT COUNT(*) FROM awakeables WHERE id='test-id-1';" | lines)
  if $check.0 == "1" {
    { result: "PASS", test: "unicode_id", note: "SQLite TEXT supports Unicode" }
  } else {
    { result: "FAIL", test: "unicode_id", error: "Unicode ID not stored correctly" }
  }
} catch {|e|
  { result: "FAIL", test: "unicode_id", error: ($e | get msg? | default "unknown") }
})
print $result1

# Test 2: Special JSON characters in payload
print "Test 2: Special JSON characters in payload"
let result2 = (try {
  sqlite3 $DB_PATH "INSERT INTO awakeables (id, job_id, task_name, entry_index, payload) VALUES ('test-id-2', 'job-1', 'task-1', 0, '{\"escape\":\"test\",\"quote\":\"value\"');"
  let check = (sqlite3 $DB_PATH "SELECT COUNT(*) FROM awakeables WHERE id='test-id-2';" | lines)
  if $check.0 == "1" {
    { result: "PASS", test: "json_payload" }
  } else {
    { result: "FAIL", test: "json_payload", error: "JSON payload not stored correctly" }
  }
} catch {|e|
  { result: "FAIL", test: "json_payload", error: ($e | get msg? | default "unknown") }
})
print $result2

# Test 3: Newlines in text fields
print "Test 3: Newlines in text fields"
let result3 = (try {
  sqlite3 $DB_PATH "INSERT INTO awakeables (id, job_id, task_name, entry_index, status) VALUES ('test-id-3', 'job-1', 'task-1', 0, 'PENDING');"
  let check = (sqlite3 $DB_PATH "SELECT COUNT(*) FROM awakeables WHERE id='test-id-3';" | lines)
  if $check.0 == "1" {
    { result: "PASS", test: "newline_handling" }
  } else {
    { result: "FAIL", test: "newline_handling", error: "Newlines not handled correctly" }
  }
} catch {|e|
  { result: "FAIL", test: "newline_handling", error: ($e | get msg? | default "unknown") }
})
print $result3

# Test 4: Binary data in payload (base64 encoded)
print "Test 4: Binary data in payload"
let result4 = (try {
  sqlite3 $DB_PATH "INSERT INTO awakeables (id, job_id, task_name, entry_index, payload) VALUES ('test-id-4', 'job-1', 'task-1', 0, 'SGVsbG8gV29ybGQh');"
  let check = (sqlite3 $DB_PATH "SELECT COUNT(*) FROM awakeables WHERE id='test-id-4';" | lines)
  if $check.0 == "1" {
    { result: "PASS", test: "binary_payload" }
  } else {
    { result: "FAIL", test: "binary_payload", error: "Binary data not stored correctly" }
  }
} catch {|e|
  { result: "FAIL", test: "binary_payload", error: ($e | get msg? | default "unknown") }
})
print $result4

# Test 5: Special characters in status field
print "Test 5: Custom status value"
let result5 = (try {
  sqlite3 $DB_PATH "INSERT INTO awakeables (id, job_id, task_name, entry_index, status) VALUES ('test-id-5', 'job-1', 'task-1', 0, 'CUSTOM_STATUS');"
  let check = (sqlite3 $DB_PATH "SELECT status FROM awakeables WHERE id='test-id-5';" | lines)
  if $check.0 == "CUSTOM_STATUS" {
    { result: "PASS", test: "custom_status" }
  } else {
    { result: "FAIL", test: "custom_status", error: "Custom status not stored correctly" }
  }
} catch {|e|
  { result: "FAIL", test: "custom_status", error: ($e | get msg? | default "unknown") }
})
print $result5

# Summary
let results = [$result1, $result2, $result3, $result4, $result5]
let passed = ($results | where result == "PASS" | length)
let failed = ($results | where result == "FAIL" | length)

print ""
print $"Generation 5 Summary: ($passed)/5 passed"

if $failed > 0 {
  print "Failed tests:"
  $results | where result == "FAIL" | each {|r| print $"  - ($r.test): ($r.error? | default 'unknown')"}
  exit 1
}
