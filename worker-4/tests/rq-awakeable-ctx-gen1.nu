#!/usr/bin/env nu
# Red Queen Generation 1 - Basic Edge Cases for ctx.awakeable
# Tests: empty job_id, negative entry_index, SQL injection attempts

use std testing
use ../oc-engine.nu *

print "Running Red Queen Gen 1 tests for ctx.awakeable..."

# Test 1: Empty job_id should fail gracefully
def test-rq-gen1-empty-job-id [] {
  let test_db_dir = "/tmp/rq-gen1-empty-job-($env.PID)"
  rm -rf $test_db_dir

  try {
    $env.NUOC_DB_DIR = $test_db_dir
    db-init

    init-execution-context "" "task-1" 1 --replay-mode
    next-entry-index "" "task-1" 1
    ctx-awakeable "" "task-1" 1

    error make { msg: "Should have failed with empty job_id" }
  } catch {|e|
    assert ($e.msg | str contains "empty")
  }

  rm -rf $test_db_dir
}

# Test 2: Empty task_name should fail gracefully
def test-rq-gen1-empty-task-name [] {
  let test_db_dir = "/tmp/rq-gen1-empty-task-($env.PID)"
  rm -rf $test_db_dir

  try {
    $env.NUOC_DB_DIR = $test_db_dir
    db-init

    init-execution-context "job-1" "" 1 --replay-mode
    next-entry-index "job-1" "" 1
    ctx-awakeable "job-1" "" 1

    error make { msg: "Should have failed with empty task_name" }
  } catch {|e|
    assert ($e.msg | str contains "empty")
  }

  rm -rf $test_db_dir
}

# Test 3: SQL injection in job_id (should be caught by validate-ident)
def test-rq-gen1-sql-injection-job-id [] {
  let test_db_dir = "/tmp/rq-gen1-sql-job-($env.PID)"
  rm -rf $test_db_dir

  try {
    $env.NUOC_DB_DIR = $test_db_dir
    db-init

    let malicious_job = "job-1'; DROP TABLE awakeables;--"
    init-execution-context $malicious_job "task-1" 1 --replay-mode
    next-entry-index $malicious_job "task-1" 1
    ctx-awakeable $malicious_job "task-1" 1

    error make { msg: "Should have failed with invalid identifier" }
  } catch {|e|
    assert ($e.msg | str contains "invalid")
  }

  rm -rf $test_db_dir
}

# Test 4: SQL injection in task_name (should be caught by validate-ident)
def test-rq-gen1-sql-injection-task-name [] {
  let test_db_dir = "/tmp/rq-gen1-sql-task-($env.PID)"
  rm -rf $test_db_dir

  try {
    $env.NUOC_DB_DIR = $test_db_dir
    db-init

    let malicious_task = "task-1'; DELETE FROM awakeables;--"
    init-execution-context "job-1" $malicious_task 1 --replay-mode
    next-entry-index "job-1" $malicious_task 1
    ctx-awakeable "job-1" $malicious_task 1

    error make { msg: "Should have failed with invalid identifier" }
  } catch {|e|
    assert ($e.msg | str contains "invalid")
  }

  rm -rf $test_db_dir
}

# Test 5: Negative attempt (edge case)
def test-rq-gen1-negative-attempt [] {
  let test_db_dir = "/tmp/rq-gen1-neg-attempt-($env.PID)"
  rm -rf $test_db_dir

  try {
    $env.NUOC_DB_DIR = $test_db_dir
    db-init

    init-execution-context "job-1" "task-1" -1 --replay-mode
    next-entry-index "job-1" "task-1" -1
    ctx-awakeable "job-1" "task-1" -1

    error make { msg: "Should have failed with negative attempt" }
  } catch {|e|
    print "Failed as expected: ($e.msg)"
  }

  rm -rf $test_db_dir
}

# Run all Gen 1 tests
test test-rq-gen1-empty-job-id
test test-rq-gen1-empty-task-name
test test-rq-gen1-sql-injection-job-id
test test-rq-gen1-sql-injection-task-name
test test-rq-gen1-negative-attempt

print "Red Queen Gen 1 tests completed"
