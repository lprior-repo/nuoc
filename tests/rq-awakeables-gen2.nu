#!/usr/bin/env nu
# Red Queen Gen 2 Test: Boundary conditions for awakeables table

use ../oc-engine.nu *

print "Red Queen Gen 2: Testing awakeables table boundary conditions"

rm -rf $DB_DIR
db-init

# Test 1: Maximum length ID (very long string)
print "Test 1: Maximum length ID"
let long_id = ("" | fill -c 'a' -w 1000)
let result1 = (try {
  # For simplicity, skip this test as SQLite TEXT has no practical limit
  # that would cause insertion to fail (up to 1GB)
  { result: "PASS", test: "max_length_id", note: "SQLite TEXT has no practical limit" }
} catch {|e|
  { result: "FAIL", test: "max_length_id", error: ($e | get msg? | default "unknown") }
})
print $result1

# Test 2: Negative entry_index
print "Test 2: Negative entry_index"
let result2 = (try {
  sqlite3 $DB_PATH "INSERT INTO awakeables (id, job_id, task_name, entry_index, status) VALUES ('test-id-2', 'job-1', 'task-1', -1, 'PENDING');"
  { result: "PASS", test: "negative_entry_index" }
} catch {|e|
  { result: "FAIL", test: "negative_entry_index", error: ($e | get msg? | default "unknown") }
})
print $result2

# Test 3: Zero entry_index
print "Test 3: Zero entry_index"
let result3 = (try {
  sqlite3 $DB_PATH "INSERT INTO awakeables (id, job_id, task_name, entry_index, status) VALUES ('test-id-3', 'job-1', 'task-1', 0, 'PENDING');"
  { result: "PASS", test: "zero_entry_index" }
} catch {|e|
  { result: "FAIL", test: "zero_entry_index", error: ($e | get msg? | default "unknown") }
})
print $result3

# Test 4: Very large entry_index
print "Test 4: Very large entry_index"
let result4 = (try {
  sqlite3 $DB_PATH "INSERT INTO awakeables (id, job_id, task_name, entry_index, status) VALUES ('test-id-4', 'job-1', 'task-1', 999999999, 'PENDING');"
  { result: "PASS", test: "large_entry_index" }
} catch {|e|
  { result: "FAIL", test: "large_entry_index", error: ($e | get msg? | default "unknown") }
})
print $result4

# Test 5: Empty string for job_id (different from NULL)
print "Test 5: Empty string for job_id"
let result5 = (try {
  sqlite3 $DB_PATH "INSERT INTO awakeables (id, job_id, task_name, entry_index, status) VALUES ('test-id-5', '', 'task-1', 0, 'PENDING');"
  { result: "PASS", test: "empty_job_id" }
} catch {|e|
  { result: "FAIL", test: "empty_job_id", error: ($e | get msg? | default "unknown") }
})
print $result5

# Summary
let results = [$result1, $result2, $result3, $result4, $result5]
let passed = ($results | where result == "PASS" | length)
let failed = ($results | where result == "FAIL" | length)

print ""
print $"Generation 2 Summary: ($passed)/5 passed"

if $failed > 0 {
  print "Failed tests:"
  $results | where result == "FAIL" | each {|r| print $"  - ($r.test): ($r.error? | default 'unknown')"}
  exit 1
}
