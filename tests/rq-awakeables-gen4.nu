#!/usr/bin/env nu
# Red Queen Gen 4 Test: Data integrity

use ../oc-engine.nu *

print "Red Queen Gen 4: Testing data integrity"

rm -rf $DB_DIR
db-init

# Test 1: Valid insert with all optional fields
print "Test 1: Insert with all optional fields"
let result1 = (try {
  sqlite3 $DB_PATH "INSERT INTO awakeables (id, job_id, task_name, entry_index, status, payload, timeout_at, resolved_at) VALUES ('test-id-1', 'job-1', 'task-1', 0, 'RESOLVED', '{\"result\":\"success\"}', '2025-01-01T00:00:00Z', '2025-01-01T01:00:00Z');"
  let check = (sqlite3 $DB_PATH "SELECT COUNT(*) FROM awakeables WHERE id='test-id-1';" | lines)
  if $check.0 == "1" {
    { result: "PASS", test: "insert_with_all_fields" }
  } else {
    { result: "FAIL", test: "insert_with_all_fields", error: "Insert failed" }
  }
} catch {|e|
  { result: "FAIL", test: "insert_with_all_fields", error: ($e | get msg? | default "unknown") }
})
print $result1

# Test 2: Update status from PENDING to RESOLVED
print "Test 2: Update status"
let result2 = (try {
  sqlite3 $DB_PATH "INSERT INTO awakeables (id, job_id, task_name, entry_index) VALUES ('test-id-2', 'job-1', 'task-1', 0);"
  sqlite3 $DB_PATH "UPDATE awakeables SET status='RESOLVED', resolved_at=datetime('now') WHERE id='test-id-2';"
  let check = (sqlite3 $DB_PATH "SELECT status FROM awakeables WHERE id='test-id-2';" | lines)
  if $check.0 == "RESOLVED" {
    { result: "PASS", test: "update_status" }
  } else {
    { result: "FAIL", test: "update_status", error: "Status was not updated" }
  }
} catch {|e|
  { result: "FAIL", test: "update_status", error: ($e | get msg? | default "unknown") }
})
print $result2

# Test 3: Delete awakeable
print "Test 3: Delete awakeable"
let result3 = (try {
  sqlite3 $DB_PATH "INSERT INTO awakeables (id, job_id, task_name, entry_index) VALUES ('test-id-3', 'job-1', 'task-1', 0);"
  sqlite3 $DB_PATH "DELETE FROM awakeables WHERE id='test-id-3';"
  let check = (sqlite3 $DB_PATH "SELECT COUNT(*) FROM awakeables WHERE id='test-id-3';" | lines)
  if $check.0 == "0" {
    { result: "PASS", test: "delete_awakeable" }
  } else {
    { result: "FAIL", test: "delete_awakeable", error: "Delete failed" }
  }
} catch {|e|
  { result: "FAIL", test: "delete_awakeable", error: ($e | get msg? | default "unknown") }
})
print $result3

# Test 4: Query by job_id and task_name (using index)
print "Test 4: Query by indexed fields"
let result4 = (try {
  sqlite3 $DB_PATH "INSERT INTO awakeables (id, job_id, task_name, entry_index) VALUES ('test-id-4a', 'job-2', 'task-2', 0);"
  sqlite3 $DB_PATH "INSERT INTO awakeables (id, job_id, task_name, entry_index) VALUES ('test-id-4b', 'job-2', 'task-2', 1);"
  sqlite3 $DB_PATH "INSERT INTO awakeables (id, job_id, task_name, entry_index) VALUES ('test-id-4c', 'job-3', 'task-3', 0);"
  let check = (sqlite3 $DB_PATH "SELECT COUNT(*) FROM awakeables WHERE job_id='job-2' AND task_name='task-2';" | lines)
  if $check.0 == "2" {
    { result: "PASS", test: "query_by_indexed_fields" }
  } else {
    { result: "FAIL", test: "query_by_indexed_fields", error: $"Expected 2, got ($check.0)" }
  }
} catch {|e|
  { result: "FAIL", test: "query_by_indexed_fields", error: ($e | get msg? | default "unknown") }
})
print $result4

# Summary
let results = [$result1, $result2, $result3, $result4]
let passed = ($results | where result == "PASS" | length)
let failed = ($results | where result == "FAIL" | length)

print ""
print $"Generation 4 Summary: ($passed)/4 passed"

if $failed > 0 {
  print "Failed tests:"
  $results | where result == "FAIL" | each {|r| print $"  - ($r.test): ($r.error? | default 'unknown')"}
  exit 1
}
