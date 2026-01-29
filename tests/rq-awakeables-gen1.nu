#!/usr/bin/env nu
# Red Queen Gen 1 Test: Basic constraint violations for awakeables table

use ../oc-engine.nu *

print "Red Queen Gen 1: Testing awakeables table constraints"

rm -rf $DB_DIR
db-init

# Test 1: Duplicate ID should fail (PRIMARY KEY constraint)
print "Test 1: Insert duplicate ID"
let result1 = (try {
  sqlite3 $DB_PATH "INSERT INTO awakeables (id, job_id, task_name, entry_index, status) VALUES ('test-id-1', 'job-1', 'task-1', 0, 'PENDING');"
  sqlite3 $DB_PATH "INSERT INTO awakeables (id, job_id, task_name, entry_index, status) VALUES ('test-id-1', 'job-2', 'task-2', 1, 'PENDING');"
  { result: "FAIL", test: "duplicate_id_rejected", error: "Duplicate ID was accepted" }
} catch {|e|
  { result: "PASS", test: "duplicate_id_rejected" }
})
print $result1

# Test 2: NULL for job_id should fail (NOT NULL constraint)
print "Test 2: Insert NULL for job_id"
let result2 = (try {
  sqlite3 $DB_PATH "INSERT INTO awakeables (id, job_id, task_name, entry_index, status) VALUES ('test-id-2', NULL, 'task-1', 0, 'PENDING');"
  { result: "FAIL", test: "null_job_id_rejected", error: "NULL was accepted" }
} catch {|e|
  { result: "PASS", test: "null_job_id_rejected" }
})
print $result2

# Test 3: NULL for task_name should fail (NOT NULL constraint)
print "Test 3: Insert NULL for task_name"
let result3 = (try {
  sqlite3 $DB_PATH "INSERT INTO awakeables (id, job_id, task_name, entry_index, status) VALUES ('test-id-3', 'job-1', NULL, 0, 'PENDING');"
  { result: "FAIL", test: "null_task_name_rejected", error: "NULL was accepted" }
} catch {|e|
  { result: "PASS", test: "null_task_name_rejected" }
})
print $result3

# Test 4: NULL for entry_index should fail (NOT NULL constraint)
print "Test 4: Insert NULL for entry_index"
let result4 = (try {
  sqlite3 $DB_PATH "INSERT INTO awakeables (id, job_id, task_name, entry_index, status) VALUES ('test-id-4', 'job-1', 'task-1', NULL, 'PENDING');"
  { result: "FAIL", test: "null_entry_index_rejected", error: "NULL was accepted" }
} catch {|e|
  { result: "PASS", test: "null_entry_index_rejected" }
})
print $result4

# Summary
let results = [$result1, $result2, $result3, $result4]
let passed = ($results | where result == "PASS" | length)
let failed = ($results | where result == "FAIL" | length)

print ""
print $"Generation 1 Summary: ($passed)/4 passed"

if $failed > 0 {
  print "Failed tests:"
  $results | where result == "FAIL" | each {|r| print $"  - ($r.test): ($r.error? | default 'unknown')"}
  exit 1
}
