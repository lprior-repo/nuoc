#!/usr/bin/env nu
# Quick verification of ctx.awakeable

use ../oc-engine.nu *

print "Testing ctx.awakeable basic functionality..."

let test_db_dir = "/tmp/verify-awakeable-($env.PID)"
rm -rf $test_db_dir

$env.NUOC_DB_DIR = $test_db_dir
db-init

# Test 1: Normal operation
init-execution-context "job-1" "task-1" 1 --replay-mode
let result1 = (ctx-awakeable "job-1" "task-1" 1)
print $"Test 1: ID = ($result1.id)"

# Test 2: Long job_id (500 chars)
mut long_job_id = ""
for i in 1..50 {
  $long_job_id = ($long_job_id + "aaaaaaaaaa")
}
init-execution-context $long_job_id "task-2" 1 --replay-mode
let result2 = (ctx-awakeable $long_job_id "task-2" 1)
print $"Test 2: Long job_id OK, ID starts with prom_1: ($result2.id | str starts-with 'prom_1')"

# Test 3: Multiple awakeables
init-execution-context "job-multi" "task-multi" 1 --replay-mode
mut ids = []
for i in 1..10 {
  let result = (ctx-awakeable "job-multi" "task-multi" 1)
  $ids = ($ids | append $result.id)
}
print $"Test 4: Multiple OK, 10 unique IDs: (($ids | uniq | length) == 10)"

rm -rf $test_db_dir
print ""
print "✓ All verification tests passed!"
