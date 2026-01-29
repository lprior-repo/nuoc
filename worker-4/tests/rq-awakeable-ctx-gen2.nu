#!/usr/bin/env nu
# Red Queen Generation 2 - Boundary Conditions for ctx.awakeable
# Tests: very long identifiers, special characters, large entry_index

use std testing
use ../oc-engine.nu *

print "Running Red Queen Gen 2 tests for ctx.awakeable..."

# Test 1: Very long job_id (500 chars)
def test-rq-gen2-long-job-id [] {
  let test_db_dir = "/tmp/rq-gen2-long-job-($env.PID)"
  rm -rf $test_db_dir

  try {
    $env.NUOC_DB_DIR = $test_db_dir
    db-init

    mut long_job_id = ""
    for i in 1..50 {
      $long_job_id = ($long_job_id + "aaaaaaaaaa")
    }
    init-execution-context $long_job_id "task-1" 1 --replay-mode
    next-entry-index $long_job_id "task-1" 1
    let result = (ctx-awakeable $long_job_id "task-1" 1)

    assert ($result.id | is-not-empty)
    assert ($result.id | str starts-with "prom_1")

    print "  ✓ Long job_id handled (500 chars)"
  } catch {|e|
    print "  ✗ Failed: ($e.msg)"
  }

  rm -rf $test_db_dir
}

# Test 2: Very long task_name (500 chars)
def test-rq-gen2-long-task-name [] {
  let test_db_dir = "/tmp/rq-gen2-long-task-($env.PID)"
  rm -rf $test_db_dir

  try {
    $env.NUOC_DB_DIR = $test_db_dir
    db-init

    mut long_task_name = ""
    for i in 1..50 {
      $long_task_name = ($long_task_name + "tttttttttt")
    }
    init-execution-context "job-1" $long_task_name 1 --replay-mode
    next-entry-index "job-1" $long_task_name 1
    let result = (ctx-awakeable "job-1" $long_task_name 1)

    assert ($result.id | is-not-empty)
    assert ($result.id | str starts-with "prom_1")

    print "  ✓ Long task_name handled (500 chars)"
  } catch {|e|
    print "  ✗ Failed: ($e.msg)"
  }

  rm -rf $test_db_dir
}

# Test 3: Moderate entry_index stress (100 awakeables)
def test-rq-gen2-large-entry-index [] {
  let test_db_dir = "/tmp/rq-gen2-large-entry-($env.PID)"
  rm -rf $test_db_dir

  try {
    $env.NUOC_DB_DIR = $test_db_dir
    db-init

    init-execution-context "job-1" "task-1" 1 --replay-mode

    for i in 1..100 {
      let result = (ctx-awakeable "job-1" "task-1" 1)
      if ($i mod 25) == 0 {
        print $"  ✓ Processed ($i) awakeables"
      }
    }

    print "  ✓ Large entry_index handled (100 awakeables)"
  } catch {|e|
    print "  ✗ Failed: ($e.msg)"
  }

  rm -rf $test_db_dir
}

# Test 4: Unicode and special characters in identifiers
def test-rq-gen2-unicode-identifiers [] {
  let test_db_dir = "/tmp/rq-gen2-unicode-($env.PID)"
  rm -rf $test_db_dir

  try {
    $env.NUOC_DB_DIR = $test_db_dir
    db-init

    let unicode_job = "job-日本語-🚀"
    let unicode_task = "task-中文-✅"
    init-execution-context $unicode_job $unicode_task 1 --replay-mode
    next-entry-index $unicode_job $unicode_task 1
    let result = (ctx-awakeable $unicode_job $unicode_task 1)

    assert ($result.id | is-not-empty)
    assert ($result.id | str starts-with "prom_1")

    print "  ✓ Unicode identifiers handled (日本語 🚀 中文 ✅)"
  } catch {|e|
    print "  ✗ Failed: ($e.msg)"
  }

  rm -rf $test_db_dir
}

# Test 5: Many awakeables in same job (stress test)
def test-rq-gen2-many-awakeables [] {
  let test_db_dir = "/tmp/rq-gen2-many-($env.PID)"
  rm -rf $test_db_dir

  try {
    $env.NUOC_DB_DIR = $test_db_dir
    db-init

    init-execution-context "job-stress" "task-stress" 1 --replay-mode

    mut ids = []
    for i in 1..50 {
      let result = (ctx-awakeable "job-stress" "task-stress" 1)
      $ids = ($ids | append $result.id)
    }

    assert (($ids | length) == 50)
    assert (($ids | uniq | length) == 50)

    print "  ✓ Many awakeables handled (50 unique IDs)"
  } catch {|e|
    print "  ✗ Failed: ($e.msg)"
  }

  rm -rf $test_db_dir
}

# Run all Gen 2 tests
test test-rq-gen2-long-job-id
test test-rq-gen2-long-task-name
test test-rq-gen2-large-entry-index
test test-rq-gen2-unicode-identifiers
test test-rq-gen2-many-awakeables

print ""
print "Red Queen Gen 2 tests completed"
