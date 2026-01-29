#!/usr/bin/env nu
# test-entity-types.nu — Tests for Services, Virtual Objects, and Workflows

use std assert
use ../oc-entity.nu *
use ../oc-dispatch.nu *

# Test database setup
const TEST_DB = "/tmp/test-entity-types.db"

def setup-test-db [] {
  rm -f $TEST_DB
  mkdir /tmp/test-entity-types

  # Override DB_PATH for testing
  $env.DB_DIR = "/tmp/test-entity-types"
  $env.DB_PATH = $TEST_DB

  # Initialize database
  entity-db-init
  ctx-object db-init
  ctx-workflow db-init
}

def teardown-test-db [] {
  rm -rf /tmp/test-entity-types
}

# Test 1: Entity registration
export def test-entity-registration [] {
  print "Test: Entity registration"

  setup-test-db

  # Register a service
  entity register "EmailService" "service" { send: ["sendEmail"] }

  # Register a virtual object
  entity register "ShoppingCart" "virtual_object" { write: ["addItem", "removeItem"], read: ["getCart"] }

  # Register a workflow
  entity register "OrderProcess" "workflow" { run: ["processOrder"], signal: ["updateAddress"] }

  # Verify registrations
  assert equal (entity exists "EmailService") true "Service should be registered"
  assert equal (entity exists "ShoppingCart") true "Virtual Object should be registered"
  assert equal (entity exists "OrderProcess") true "Workflow should be registered"

  # Verify entity types
  assert equal (entity get-type "EmailService") "service" "Should be service type"
  assert equal (entity get-type "ShoppingCart") "virtual_object" "Should be virtual_object type"
  assert equal (entity get-type "OrderProcess") "workflow" "Should be workflow type"

  teardown-test-db
  print "  [PASS] Entity registration"
}

# Test 2: Service parallelism
export def test-service-parallelism [] {
  print "Test: Service parallelism"

  setup-test-db
  entity register "TestService" "service" { process: ["processItem"] }

  # Service invocations should execute without queuing
  let result1 = (dispatch service "TestService" "processItem" { data: "item1" })
  let result2 = (dispatch service "TestService" "processItem" { data: "item2" })

  assert equal $result1.status "executed" "First invocation should execute"
  assert equal $result2.status "executed" "Second invocation should execute"

  # No locks should be created for services
  assert equal (vo lock-held? "TestService" "any-key") false "Service should not create locks"

  teardown-test-db
  print "  [PASS] Service parallelism"
}

# Test 3: Virtual Object single-writer
export def test-vo-single-writer [] {
  print "Test: Virtual Object single-writer"

  setup-test-db
  entity register "TestCart" "virtual_object" { write: ["addItem"], read: ["getCart"] }

  # Acquire write lock
  let lock1 = (vo lock-acquire "TestCart" "user-123" "invocation-1")
  assert equal $lock1.acquired true "First write handler should acquire lock"

  # Try to acquire again - should fail
  let lock2 = (vo lock-acquire "TestCart" "user-123" "invocation-2")
  assert equal $lock2.acquired false "Second write handler should not acquire lock"
  assert equal $lock2.holder "invocation-1" "Lock should be held by first invocation"

  # Release lock
  let release = (vo lock-release "TestCart" "user-123" "invocation-1")
  assert equal $release.released true "Lock should be released"

  # Now second invocation can acquire
  let lock3 = (vo lock-acquire "TestCart" "user-123" "invocation-2")
  assert equal $lock3.acquired true "Second write handler should acquire lock after release"

  teardown-test-db
  print "  [PASS] Virtual Object single-writer"
}

# Test 4: Virtual Object concurrent readers
export def test-vo-concurrent-readers [] {
  print "Test: Virtual Object concurrent readers"

  setup-test-db
  entity register "TestCart" "virtual_object" { write: ["addItem"], read: ["getCart"] }

  # Read handlers should not acquire locks
  let result1 = (dispatch virtual-object "TestCart" "user-123" "getCart" "read" {})
  let result2 = (dispatch virtual-object "TestCart" "user-123" "getCart" "read" {})

  assert equal $result1.status "executed" "First read should execute"
  assert equal $result2.status "executed" "Second read should execute"

  # No locks should be held by reads
  assert equal (vo lock-held? "TestCart" "user-123") false "Read handlers should not hold locks"

  teardown-test-db
  print "  [PASS] Virtual Object concurrent readers"
}

# Test 5: Workflow exactly-once
export def test-workflow-exactly-once [] {
  print "Test: Workflow exactly-once"

  setup-test-db
  entity register "TestWorkflow" "workflow" { run: ["process"], signal: ["update"] }

  # First invocation should execute
  let result1 = (dispatch workflow "TestWorkflow" "order-456" "process" {})
  assert equal $result1.status "executed" "First invocation should execute"

  # Verify run was recorded
  assert equal (workflow run-exists? "TestWorkflow" "order-456") true "Workflow run should be recorded"

  # Second invocation should return cached result
  let result2 = (dispatch workflow "TestWorkflow" "order-456" "process" {})
  assert equal $result2.status "cached" "Second invocation should return cached result"

  teardown-test-db
  print "  [PASS] Workflow exactly-once"
}

# Test 6: ObjectContext state operations
export def test-objectcontext-state [] {
  print "Test: ObjectContext state operations"

  setup-test-db
  entity register "StateTest" "virtual_object" { write: ["setState"], read: ["getState"] }

  # Set state
  ctx-object set "StateTest" "key1" "field1" "value1"
  ctx-object set "StateTest" "key1" "field2" "value2"

  # Get state
  let value1 = (ctx-object get "StateTest" "key1" "field1")
  assert equal $value1 "value1" "Should retrieve value1"

  let value2 = (ctx-object get "StateTest" "key1" "field2")
  assert equal $value2 "value2" "Should retrieve value2"

  # Get all state
  let all_state = (ctx-object get-all "StateTest" "key1")
  assert equal $all_state.field1 "value1" "All state should include field1"
  assert equal $all_state.field2 "value2" "All state should include field2"

  # Clear specific field
  ctx-object clear "StateTest" "key1" "field1"
  let cleared = (ctx-object get "StateTest" "key1" "field1")
  assert equal $cleared null "Cleared field should be null"

  # Clear all state
  ctx-object clear-all "StateTest" "key1"
  let all_cleared = (ctx-object get-all "StateTest" "key1")
  assert equal ($all_cleared | length) 0 "All state should be cleared"

  teardown-test-db
  print "  [PASS] ObjectContext state operations"
}

# Test 7: Workflow run tracking
export def test-workflow-run-tracking [] {
  print "Test: Workflow run tracking"

  setup-test-db
  entity register "TrackerTest" "workflow" { run: ["run"] }

  # Start workflow run
  let start = (workflow run-start "TrackerTest" "wf-1" "inv-1")
  assert equal $start.status "started" "Workflow run should start"

  # Check run exists
  assert equal (workflow run-exists? "TrackerTest" "wf-1") true "Run should exist"

  # Get run details
  let run = (workflow run-get "TrackerTest" "wf-1")
  assert equal $run.status "running" "Run should be in running state"

  # Complete run
  workflow run-complete "TrackerTest" "wf-1" "success"

  # Verify completion
  let completed = (workflow run-get "TrackerTest" "wf-1")
  assert equal $completed.status "completed" "Run should be completed"
  assert equal $completed.result "success" "Run should have result"

  teardown-test-db
  print "  [PASS] Workflow run tracking"
}

# Test 8: Generic dispatch routing
export def test-generic-dispatch [] {
  print "Test: Generic dispatch routing"

  setup-test-db

  # Register entities
  entity register "Svc" "service" { handler: ["h"] }
  entity register "Vo" "virtual_object" { write: ["w"], read: ["r"] }
  entity register "Wf" "workflow" { run: ["run"] }

  # Dispatch to service
  let svc_result = (dispatch invoke "Svc" "h" {} --handler-type "write")
  assert equal $svc_result.status "executed" "Service dispatch should work"

  # Dispatch to virtual object
  let vo_result = (dispatch invoke "Vo" "w" {} --object-key "key1" --handler-type "write")
  assert equal $vo_result.status "executed" "VO dispatch should work"

  # Dispatch to workflow
  let wf_result = (dispatch invoke "Wf" "run" {} --workflow-id "wf-1")
  assert equal $wf_result.status "executed" "Workflow dispatch should work"

  teardown-test-db
  print "  [PASS] Generic dispatch routing"
}

# Run all tests
export def main [] {
  print "Running Entity Types Tests..."
  print ""

  test-entity-registration
  test-service-parallelism
  test-vo-single-writer
  test-vo-concurrent-readers
  test-workflow-exactly-once
  test-objectcontext-state
  test-workflow-run-tracking
  test-generic-dispatch

  print ""
  print "All entity type tests passed!"
}
