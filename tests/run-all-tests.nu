#!/usr/bin/env nu
# Run all tests using Nushell std testing module

use std testing

print "Running OpenCode Workflow Engine Tests..."
print ""

# Import modules
use ../oc-agent.nu *
use ../oc-engine.nu *
use ../oc-tdd15.nu *

# Define test runners for each module
def test-oc-agent [] {
  # Test: base-url function
  let url = (base-url)
  if ($url == "http://localhost:4096") {
    print "  [ok] base-url with default port"
  } else {
    print $"  [fail] base-url with default port: expected http://localhost:4096, got ($url)"
  }
  
  # Test: base-url with custom port
  let url = (base-url --port 8080)
  if ($url == "http://localhost:8080") {
    print "  [ok] base-url with custom port"
  } else {
    print $"  [fail] base-url with custom port: expected http://localhost:8080, got ($url)"
  }
  
  # Test: constants
  if ($DEFAULT_PORT == 4096) {
    print "  [ok] DEFAULT_PORT constant"
  } else {
    print $"  [fail] DEFAULT_PORT constant"
  }
  
  if ($DEFAULT_HOST == "http://localhost") {
    print "  [ok] DEFAULT_HOST constant"
  } else {
    print $"  [fail] DEFAULT_HOST constant"
  }
}

def test-oc-engine [] {
  # Test: constants
  if ($DB_DIR == ".oc-workflow") {
    print "  [ok] DB_DIR constant"
  } else {
    print $"  [fail] DB_DIR constant"
  }

  if ($DB_PATH == ".oc-workflow/journal.db") {
    print "  [ok] DB_PATH constant"
  } else {
    print $"  [fail] DB_PATH constant"
  }

  # Test: sql-escape-text (renamed from sql-escape)
  let escaped = (sql-escape-text "hello")
  if ($escaped == "hello") {
    print "  [ok] sql-escape-text basic"
  } else {
    print $"  [fail] sql-escape-text basic"
  }

  let escaped = (sql-escape-text "it's")
  if ($escaped == "it''s") {
    print "  [ok] sql-escape-text single quote"
  } else {
    print $"  [fail] sql-escape-text single quote"
  }

  let escaped = (sql-escape-text "")
  if ($escaped == "") {
    print "  [ok] sql-escape-text empty"
  } else {
    print $"  [fail] sql-escape-text empty"
  }

  # Test: validate-ident accepts valid identifiers
  let valid = (validate-ident "tdd15-beads-abc123" "test")
  if ($valid == "tdd15-beads-abc123") {
    print "  [ok] validate-ident valid"
  } else {
    print $"  [fail] validate-ident valid"
  }

  # Test: validate-ident rejects SQL injection
  let result = (try { validate-ident "'; DROP TABLE jobs;--" "test" } catch { "error" })
  if ($result == "error") {
    print "  [ok] validate-ident rejects SQL injection"
  } else {
    print $"  [fail] validate-ident rejects SQL injection"
  }

  # Test: validate-ident rejects empty
  let result = (try { validate-ident "" "test" } catch { "error" })
  if ($result == "error") {
    print "  [ok] validate-ident rejects empty"
  } else {
    print $"  [fail] validate-ident rejects empty"
  }

  # Test: validate-ident-opt allows empty
  let result = (validate-ident-opt "" "test")
  if ($result == "") {
    print "  [ok] validate-ident-opt allows empty"
  } else {
    print $"  [fail] validate-ident-opt allows empty"
  }

  # Test: job-create rejects malicious job ID (BDD scenario)
  let job_def = { name: "test'; DROP TABLE jobs;--", tasks: [] }
  let result = (try { job-create $job_def } catch {|e| $e.msg })
  if ($result | str contains "invalid identifier") {
    print "  [ok] job-create rejects SQL injection"
  } else {
    print $"  [fail] job-create rejects SQL injection: got ($result)"
  }

  # Test: 8-state status constants exist
  let states = [$STATUS_PENDING $STATUS_SCHEDULED $STATUS_READY $STATUS_RUNNING $STATUS_SUSPENDED $STATUS_BACKING_OFF $STATUS_PAUSED $STATUS_COMPLETED]
  if (($states | length) == 8) {
    print "  [ok] 8-state lifecycle constants"
  } else {
    print $"  [fail] 8-state lifecycle constants"
  }

  # Test: status values are lowercase
  if (($states | all {|s| $s == ($s | str downcase)})) {
    print "  [ok] status values lowercase"
  } else {
    print $"  [fail] status values lowercase"
  }

  # Test: awakeables table is created by db-init
  rm -rf $DB_DIR
  db-init
  let tables = (sqlite3 $DB_PATH "SELECT name FROM sqlite_master WHERE type='table' AND name='awakeables' ORDER BY name;" | from ssv)
  if (($tables | length) == 1) and ($tables.0.name == "awakeables") {
    print "  [ok] awakeables table created"
  } else {
    print $"  [fail] awakeables table created: expected 1 table named awakeables, got ($tables | length) tables"
  }

  # Test: awakeables table has correct schema
  let schema = (sqlite3 $DB_PATH "PRAGMA table_info(awakeables);" | from ssv)
  
  let id_exists = ($schema | where name == "id" | length) == 1
  let job_id_exists = ($schema | where name == "job_id" | length) == 1
  let task_name_exists = ($schema | where name == "task_name" | length) == 1
  let entry_index_exists = ($schema | where name == "entry_index" | length) == 1
  let status_exists = ($schema | where name == "status" | length) == 1
  let payload_exists = ($schema | where name == "payload" | length) == 1
  let timeout_at_exists = ($schema | where name == "timeout_at" | length) == 1
  let created_at_exists = ($schema | where name == "created_at" | length) == 1
  let resolved_at_exists = ($schema | where name == "resolved_at" | length) == 1
  
  if ($id_exists and $job_id_exists and $task_name_exists and $entry_index_exists and $status_exists and $payload_exists and $timeout_at_exists and $created_at_exists and $resolved_at_exists) {
    print "  [ok] awakeables table has all columns"
  } else {
    print $"  [fail] awakeables table has all columns"
  }
  
  let id_col = ($schema | where name == "id")
  if ($id_col.0.pk == 1) {
    print "  [ok] awakeables id is PRIMARY KEY"
  } else {
    print $"  [fail] awakeables id is PRIMARY KEY"
  }
  
  let status_col = ($schema | where name == "status")
  if ($status_col.0.dflt_value == "'PENDING'") {
    print "  [ok] awakeables status defaults to PENDING"
  } else {
    print $"  [fail] awakeables status defaults to PENDING: got ($status_col.0.dflt_value)"
  }

  # Test: awakeables table has index on (job_id, task_name)
  let indexes = (sqlite3 $DB_PATH "SELECT name FROM sqlite_master WHERE type='index' AND tbl_name='awakeables' ORDER BY name;" | from ssv)
  let has_index = ($indexes | where name =~ "idx_awakeables_job_task" | length) > 0
  if $has_index {
    print "  [ok] awakeables has index on (job_id, task_name)"
  } else {
    print $"  [fail] awakeables has index on (job_id, task_name)"
  }
}

def test-oc-tdd15 [] {
  # Test: phase-prompt returns correct prompt for RED phase
  let prompt = (phase-prompt "phase-4-red" "test-bead" {} {})
  if ($prompt | str contains "Phase 4: RED") {
    print "  [ok] phase-prompt RED phase"
  } else {
    print $"  [fail] phase-prompt RED phase"
  }

  # Test: phase-prompt returns correct prompt for GREEN phase
  let prompt = (phase-prompt "phase-5-green" "test-bead" {} { red: "test code" })
  if (($prompt | str contains "Phase 5: GREEN") and ($prompt | str contains "test code")) {
    print "  [ok] phase-prompt GREEN phase with prior output"
  } else {
    print $"  [fail] phase-prompt GREEN phase with prior output"
  }

  # Test: phase-prompt returns error for unknown phase
  let prompt = (phase-prompt "phase-99-unknown" "test-bead" {} {})
  if ($prompt | str contains "Unknown phase") {
    print "  [ok] phase-prompt unknown phase"
  } else {
    print $"  [fail] phase-prompt unknown phase"
  }

  # Test: phase-prompt triage includes bead info
  let bead_info = { title: "Test Bead", type: "feature" }
  let prompt = (phase-prompt "phase-0-triage" "test-bead" $bead_info {})
  if (($prompt | str contains "Phase 0: TRIAGE") and ($prompt | str contains "Test Bead")) {
    print "  [ok] phase-prompt triage with bead info"
  } else {
    print $"  [fail] phase-prompt triage with bead info"
  }

  # Test: PHASES_COMPLEX
  let phases_len = ($PHASES_COMPLEX | length)
  if ($phases_len == 16) {
    print "  [ok] PHASES_COMPLEX length"
  } else {
    print $"  [fail] PHASES_COMPLEX length"
  }
  
  # Test: PHASES_MEDIUM
  let expected = [0 1 2 4 5 6 7 9 11 15]
  if ($PHASES_MEDIUM == $expected) {
    print "  [ok] PHASES_MEDIUM"
  } else {
    print $"  [fail] PHASES_MEDIUM"
  }
  
  # Test: PHASES_SIMPLE
  let expected = [0 4 5 6 14 15]
  if ($PHASES_SIMPLE == $expected) {
    print "  [ok] PHASES_SIMPLE"
  } else {
    print $"  [fail] PHASES_SIMPLE"
  }
  
  # Test: tdd15-route
  let route = (tdd15-route "complex")
  if ($route == $PHASES_COMPLEX) {
    print "  [ok] tdd15-route complex"
  } else {
    print $"  [fail] tdd15-route complex"
  }
  
  let route = (tdd15-route "simple")
  if ($route == $PHASES_SIMPLE) {
    print "  [ok] tdd15-route simple"
  } else {
    print $"  [fail] tdd15-route simple"
  }
  
  let route = (tdd15-route "unknown")
  if ($route == $PHASES_SIMPLE) {
    print "  [ok] tdd15-route unknown defaults to simple"
  } else {
    print $"  [fail] tdd15-route unknown defaults to simple"
  }
  
  # Test: tdd15-job structure
  let job = (tdd15-job "test-bead")
  
  if ($job.name == "tdd15-test-bead") {
    print "  [ok] tdd15-job name"
  } else {
    print $"  [fail] tdd15-job name"
  }
  
  if ($job.position == 0) {
    print "  [ok] tdd15-job position"
  } else {
    print $"  [fail] tdd15-job position"
  }
  
  if ($job.inputs.bead_id == "test-bead") {
    print "  [ok] tdd15-job inputs"
  } else {
    print $"  [fail] tdd15-job inputs"
  }
  
  if ($job.tasks | is-not-empty) {
    print "  [ok] tdd15-job has tasks"
  } else {
    print $"  [fail] tdd15-job has tasks"
  }
}

# Run tests and collect results
print "--- Testing oc-agent.nu ---"
let result1 = (try { test-oc-agent; { ok: true } } catch {|e| { ok: false, error: ($e | get msg? | default 'unknown') } })
if (not $result1.ok) {
  print $"  [error] oc-agent.nu: ($result1.error)"
}

print ""
print "--- Testing oc-engine.nu ---"
let result2 = (try { test-oc-engine; { ok: true } } catch {|e| { ok: false, error: ($e | get msg? | default 'unknown') } })
if (not $result2.ok) {
  print $"  [error] oc-engine.nu: ($result2.error)"
}

print ""
print "--- Testing oc-tdd15.nu ---"
let result3 = (try { test-oc-tdd15; { ok: true } } catch {|e| { ok: false, error: ($e | get msg? | default 'unknown') } })
if (not $result3.ok) {
  print $"  [error] oc-tdd15.nu: ($result3.error)"
}

# Print summary
let total_tests = 3
let passed_tests = ([$result1.ok, $result2.ok, $result3.ok] | where $it == true | length)
let failed_tests = ([$result1.ok, $result2.ok, $result3.ok] | where $it == false | length)

print ""
print "== Test Summary =="
print $"Total test suites: ($total_tests)"
print $"Passed: ($passed_tests)"
print $"Failed: ($failed_tests)"

# Exit with error code if any tests failed
if $failed_tests > 0 {
  exit 1
}
