#!/usr/bin/env nu
# test-journal-entry-types.nu — Complete Restate Journal Entry Types Test Suite

# Load dependencies
use ../journal-entries.nu
use ../oc-engine.nu

# ── Test Helpers ──────────────────────────────────────────────────────────────────

def assert [condition: bool, message: string = ""] {
  if not $condition {
    error make {
      msg: ($message | default "Assertion failed")
    }
  }
}

# ── Test Setup ───────────────────────────────────────────────────────────────────

# Use the same DB path as oc-engine
const TEST_DB_DIR = ".oc-workflow"
const TEST_DB = $"($TEST_DB_DIR)/journal.db"

def setup-test [] {
  rm -rf $TEST_DB_DIR

  # Initialize the database using oc-engine's db-init
  oc-engine db-init
}

def teardown-test [] {
  # Keep DB for inspection
}

# ── Entry Type Tests ──────────────────────────────────────────────────────────────

def test-entry-type-registry [] {
  print "Testing entry type registry..."

  # Test InputCommandMessage
  let input_entry = (journal-entries get-entry-type 0x0400)
  assert ($input_entry.name == "InputCommandMessage") "Input entry name mismatch"
  assert ($input_entry.code == 0x0400)
  assert ($input_entry.completable == false)

  # Test GetStateCommandMessage
  let get_state_entry = (journal-entries get-entry-type 0x0800)
  assert ($get_state_entry.name == "GetStateCommandMessage")
  assert ($get_state_entry.completable == true)
  assert ($get_state_entry.fallible == true)

  # Test CallCommandMessage
  let call_entry = (journal-entries get-entry-type 0x0C01)
  assert ($call_entry.name == "CallCommandMessage")
  assert ($call_entry.completable == true)
  assert ($call_entry.fallible == true)

  print "✓ Entry type registry tests passed"
}

def test-entry-creation [] {
  print "Testing entry creation..."

  # Test Input entry
  print "  Creating Input entry..."
  let input_entry = (journal-entries create-input-entry "job-1" "task-1" 1 0 {headers: {}} "value")
  print $"  Input entry: ($input_entry | to json)"
  assert ($input_entry.entry_type == 0x0400)
  assert ($input_entry.entry_name == "InputCommandMessage")
  assert ($input_entry.completed == true)

  # Test GetState entry
  let get_state_entry = (journal-entries create-get-state-entry "job-1" "task-1" 1 1 "key" false)
  assert ($get_state_entry.entry_type == 0x0800)
  assert ($get_state_entry.entry_name == "GetStateCommandMessage")
  assert ($get_state_entry.completed == false)
  assert ($get_state_entry.flags == 0x03)

  # Test SetState entry
  let set_state_entry = (journal-entries create-set-state-entry "job-1" "task-1" 1 2 "key" "value")
  assert ($set_state_entry.entry_type == 0x0801)
  assert ($set_state_entry.entry_name == "SetStateCommandMessage")
  assert ($set_state_entry.completed == false)
  assert ($set_state_entry.flags == 0x01)

  # Test Call entry
  let call_entry = (journal-entries create-call-entry "job-1" "task-1" 1 3 "service" "handler" {input: "value"})
  assert ($call_entry.entry_type == 0x0C01)
  assert ($call_entry.entry_name == "CallCommandMessage")
  assert ($call_entry.completed == false)
  assert ($call_entry.flags == 0x03)

  # Test OneWayCall entry
  let one_way_entry = (journal-entries create-one-way-call-entry "job-1" "task-1" 1 4 "service" "handler" {input: "value"} 1000)
  assert ($one_way_entry.entry_type == 0x0C02)
  assert ($one_way_entry.entry_name == "OneWayCallCommandMessage")
  assert ($one_way_entry.completed == false)
  assert ($one_way_entry.flags == 0x01)

  # Test Sleep entry
  let sleep_entry = (journal-entries create-sleep-entry "job-1" "task-1" 1 5 1234567890)
  assert ($sleep_entry.entry_type == 0x0C00)
  assert ($sleep_entry.entry_name == "SleepCommandMessage")
  assert ($sleep_entry.completed == false)

  print "✓ Entry creation tests passed"
}

def test-journal-write [] {
  print "Testing journal write..."

  setup-test

  # Write GetState entry
  let entry = (journal-entries create-get-state-entry "job-1" "task-1" 1 0 "key" false)
  let input_data = ($entry.input | from json)
  let entry_index = (oc-engine journal-write "job-1" "task-1" 1 0 $entry.entry_type $entry.entry_name $entry.flags $input_data null)

  assert ($entry_index == 0)

  # Verify entry was written
  let result = (oc-engine sql "SELECT * FROM journal WHERE entry_index = 0")
  assert (not ($result | is-empty))
  let row = ($result | first)
  assert (($row.entry_type | into int) == 0x0800)
  assert ($row.entry_name == "GetStateCommandMessage")
  assert (($row.flags | into int) == 3)
  assert (($row.completed | into int) == 0)

  print "✓ Journal write tests passed"

  teardown-test
}

def test-journal-complete [] {
  print "Testing journal complete..."

  setup-test

  # Write entry
  let entry = (journal-entries create-get-state-entry "job-1" "task-1" 1 0 "key" false)
  let input_data = ($entry.input | from json)
  oc-engine journal-write "job-1" "task-1" 1 0 $entry.entry_type $entry.entry_name $entry.flags $input_data null

  # Complete entry with success
  oc-engine journal-complete "job-1" "task-1" 1 0 "value" -1 ""

  # Verify entry was completed
  let result = (oc-engine sql "SELECT * FROM journal WHERE entry_index = 0")
  let row = ($result | first)
  print $"  Row: ($row | to json)"
  assert (($row.completed | into int) == 1) "completed should be 1"
  assert ($row.completed_at != null) "completed_at should not be null"
  assert (($row.output | from json) == "value") "output should be 'value'"

  print "✓ Journal complete tests passed"

  teardown-test
}

def test-journal-complete-with-failure [] {
  print "Testing journal complete with failure..."

  setup-test

  # Write entry
  let entry = (journal-entries create-get-state-entry "job-1" "task-1" 1 0 "key" false)
  let input_data = ($entry.input | from json)
  oc-engine journal-write "job-1" "task-1" 1 0 $entry.entry_type $entry.entry_name $entry.flags $input_data null

  # Complete entry with failure
  oc-engine journal-complete "job-1" "task-1" 1 0 null 1 "State not found"

  # Verify entry was completed with failure
  let result = (oc-engine sql "SELECT * FROM journal WHERE entry_index = 0")
  let row = ($result | first)
  assert (($row.completed | into int) == 1)
  assert (($row.failure_code | into int) == 1)
  assert ($row.failure_message == "State not found")
  assert ((($row.flags | into int) mod 16) >= 8)

  print "✓ Journal complete with failure tests passed"

  teardown-test
}

def test-check-replay [] {
  print "Testing check replay..."

  setup-test

  # Write and complete entry
  let entry = (journal-entries create-get-state-entry "job-1" "task-1" 1 0 "key" false)
  let input_data = ($entry.input | from json)
  oc-engine journal-write "job-1" "task-1" 1 0 $entry.entry_type $entry.entry_name $entry.flags $input_data null
  oc-engine journal-complete "job-1" "task-1" 1 0 "cached_value" -1 ""

  # Check replay returns cached value
  let replay_value = (oc-engine check-replay "job-1" "task-1" 1 0)
  assert ($replay_value == "cached_value")

  # Check replay for non-existent entry returns null
  let null_value = (oc-engine check-replay "job-1" "task-1" 1 99)
  assert ($null_value == null)

  print "✓ Check replay tests passed"

  teardown-test
}

def test-replay-with-failure [] {
  print "Testing replay with failure..."

  setup-test

  # Write and complete entry with failure
  let entry = (journal-entries create-get-state-entry "job-1" "task-1" 1 0 "key" false)
  let input_data = ($entry.input | from json)
  oc-engine journal-write "job-1" "task-1" 1 0 $entry.entry_type $entry.entry_name $entry.flags $input_data null
  oc-engine journal-complete "job-1" "task-1" 1 0 null 1 "State not found"

  # Check replay returns error record
  let result = (try {
    oc-engine check-replay "job-1" "task-1" 1 0
  } catch {|e|
    {error: true, msg: $e.msg, code: $e.code}
  })

  assert ($result.error == true)
  assert ($result.msg == "State not found")
  assert ($result.code == 1)

  print "✓ Replay with failure tests passed"

  teardown-test
}

# ── Scenario Tests ───────────────────────────────────────────────────────────────

def test-state-operations-journaled [] {
  print "Testing state operations journaled..."

  setup-test

  # GetState operation
  let get_entry = (journal-entries create-get-state-entry "job-1" "task-1" 1 0 "user:123" false)
  let get_input = ($get_entry.input | from json)
  oc-engine journal-write "job-1" "task-1" 1 0 $get_entry.entry_type $get_entry.entry_name $get_entry.flags $get_input null

  # SetState operation
  let set_entry = (journal-entries create-set-state-entry "job-1" "task-1" 1 1 "user:123" {name: "Alice"})
  let set_input = ($set_entry.input | from json)
  oc-engine journal-write "job-1" "task-1" 1 1 $set_entry.entry_type $set_entry.entry_name $set_entry.flags $set_input null

  # ClearState operation
  let clear_entry = (journal-entries create-clear-state-entry "job-1" "task-1" 1 2 "user:123")
  let clear_input = ($clear_entry.input | from json)
  oc-engine journal-write "job-1" "task-1" 1 2 $clear_entry.entry_type $clear_entry.entry_name $clear_entry.flags $clear_input null

  # Verify all entries were journaled
  let entries = (oc-engine sql "SELECT * FROM journal ORDER BY entry_index")
  assert (($entries | length) == 3)
  let entry0 = ($entries | get 0)
  let entry1 = ($entries | get 1)
  let entry2 = ($entries | get 2)
  assert (($entry0.entry_type | into int) == 0x0800)
  assert (($entry1.entry_type | into int) == 0x0801)
  assert (($entry2.entry_type | into int) == 0x0802)

  print "✓ State operations journaled tests passed"

  teardown-test
}

def test-call-vs-one-way-call [] {
  print "Testing call vs one-way call..."

  setup-test

  # Call operation (completable, fallible)
  let call_entry = (journal-entries create-call-entry "job-1" "task-1" 1 0 "UserService" "GetUser" {user_id: 123})
  let call_input = ($call_entry.input | from json)
  oc-engine journal-write "job-1" "task-1" 1 0 $call_entry.entry_type $call_entry.entry_name $call_entry.flags $call_input null

  # OneWayCall operation (completable, not fallible)
  let one_way_entry = (journal-entries create-one-way-call-entry "job-1" "task-1" 1 1 "NotificationService" "SendEmail" {to: "user@example.com"} 0)
  let one_way_input = ($one_way_entry.input | from json)
  oc-engine journal-write "job-1" "task-1" 1 1 $one_way_entry.entry_type $one_way_entry.entry_name $one_way_entry.flags $one_way_input null

  # Verify entries have correct flags
  let entries = (oc-engine sql "SELECT * FROM journal ORDER BY entry_index")
  # Check flags: bit 0 (completable) and bit 1 (fallible)
  let flags0 = ($entries.0.flags | into int)
  let flags1 = ($entries.1.flags | into int)
  assert (($flags0 mod 2) == 1)
  assert ((($flags0 // 2) mod 2) == 1)
  assert (($flags1 mod 2) == 1)
  assert ((($flags1 // 2) mod 2) == 0)

  print "✓ Call vs one-way call tests passed"

  teardown-test
}

def test-entry-index-sequential [] {
  print "Testing entry index sequential..."

  setup-test

  # Create multiple entries
  for i in 0..10 {
    let entry = (journal-entries create-sleep-entry "job-1" "task-1" 1 $i 1234567890)
    let input_data = ($entry.input | from json)
    oc-engine journal-write "job-1" "task-1" 1 $i $entry.entry_type $entry.entry_name $entry.flags $input_data null
  }

  # Verify sequential indexes
  let entries = (sqlite3 $TEST_DB "SELECT entry_index FROM journal ORDER BY entry_index")
  for i in 0..10 {
    assert ($entries.0.entry_index == $i)
  }

  print "✓ Entry index sequential tests passed"

  teardown-test
}

# ── Run All Tests ────────────────────────────────────────────────────────────────

def run-all-tests [] {
  print "\n=== Running Journal Entry Types Test Suite ===\n"

  test-entry-type-registry
  test-entry-creation
  test-journal-write
  test-journal-complete
  test-journal-complete-with-failure
  test-check-replay
  test-replay-with-failure
  test-state-operations-journaled
  test-call-vs-one-way-call
  test-entry-index-sequential

  print "\n=== All tests passed! ===\n"
}

# Main
run-all-tests
