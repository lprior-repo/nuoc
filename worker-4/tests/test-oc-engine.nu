#!/usr/bin/env nu
# Tests for oc-engine.nu - DAG Workflow Engine

use std testing

print "Testing oc-engine.nu..."

# Import the module
use ../oc-engine.nu *

# ── Identifier Validation Tests ──────────────────────────────────────────────

# Test: validate-ident accepts valid identifiers
def test-validate-ident-valid [] {
  # Basic alphanumeric
  assert equal (validate-ident "hello" "test") "hello"
  assert equal (validate-ident "test123" "test") "test123"
  assert equal (validate-ident "Test_Name" "test") "Test_Name"

  # With hyphens and dots (common in job IDs like "tdd15-beads-abc123")
  assert equal (validate-ident "tdd15-beads-abc123" "test") "tdd15-beads-abc123"
  assert equal (validate-ident "job.name" "test") "job.name"
  assert equal (validate-ident "task_1.sub-2" "test") "task_1.sub-2"
}

# Test: validate-ident rejects empty string
def test-validate-ident-empty-rejected [] {
  let result = (try { validate-ident "" "test" } catch { "error" })
  assert equal $result "error"
}

# Test: validate-ident rejects SQL injection attempts
def test-validate-ident-sql-injection-rejected [] {
  # Classic SQL injection
  let result1 = (try { validate-ident "'; DROP TABLE jobs;--" "test" } catch { "error" })
  assert equal $result1 "error"

  # Single quote
  let result2 = (try { validate-ident "test'" "test" } catch { "error" })
  assert equal $result2 "error"

  # Double quote
  let result3 = (try { validate-ident "test\"" "test" } catch { "error" })
  assert equal $result3 "error"

  # Semicolon
  let result4 = (try { validate-ident "test;select" "test" } catch { "error" })
  assert equal $result4 "error"

  # Parentheses
  let result5 = (try { validate-ident "test()" "test" } catch { "error" })
  assert equal $result5 "error"

  # Spaces
  let result6 = (try { validate-ident "test value" "test" } catch { "error" })
  assert equal $result6 "error"
}

# Test: validate-ident rejects unicode and special chars
def test-validate-ident-unicode-rejected [] {
  # Em-dash (different from hyphen)
  let result1 = (try { validate-ident "job—with—dashes" "test" } catch { "error" })
  assert equal $result1 "error"

  # En-dash
  let result2 = (try { validate-ident "job–with–dashes" "test" } catch { "error" })
  assert equal $result2 "error"

  # Unicode quotes
  let result3 = (try { validate-ident "test'name" "test" } catch { "error" })
  assert equal $result3 "error"
}

# Test: validate-ident-opt allows empty string
def test-validate-ident-opt-empty-allowed [] {
  assert equal (validate-ident-opt "" "test") ""
}

# Test: validate-ident-opt validates non-empty
def test-validate-ident-opt-validates-nonempty [] {
  assert equal (validate-ident-opt "valid-name" "test") "valid-name"
  let result = (try { validate-ident-opt "invalid;name" "test" } catch { "error" })
  assert equal $result "error"
}

# ── SQL Escape Text Tests ────────────────────────────────────────────────────

# Test: sql-escape-text basic
def test-sql-escape-text-basic [] {
  let escaped = (sql-escape-text "hello")
  assert equal $escaped "hello"
}

# Test: sql-escape-text with single quote
def test-sql-escape-text-single-quote [] {
  let escaped = (sql-escape-text "it's")
  assert equal $escaped "it''s"
}

# Test: sql-escape-text with multiple quotes
def test-sql-escape-text-multiple-quotes [] {
  let escaped = (sql-escape-text "it's a 'test'")
  assert equal $escaped "it''s a ''test''"
}

# Test: sql-escape-text empty string
def test-sql-escape-text-empty [] {
  let escaped = (sql-escape-text "")
  assert equal $escaped ""
}

# ── BDD Scenarios from Issue Spec ────────────────────────────────────────────

# Scenario: Malicious job ID rejected at creation
def test-bdd-malicious-job-id-rejected [] {
  let malicious_name = "test'; DROP TABLE jobs;--"
  let job_def = { name: $malicious_name, tasks: [] }
  let result = (try { job-create $job_def } catch {|e| $e.msg })
  assert ($result | str contains "invalid identifier")
}

# Scenario: Valid job ID accepted (requires db-init, skip in unit test)
# This would be an integration test

# Scenario: Unicode and special chars rejected
def test-bdd-unicode-chars-rejected [] {
  let unicode_name = "job—with–dashes"
  let job_def = { name: $unicode_name, tasks: [] }
  let result = (try { job-create $job_def } catch {|e| $e.msg })
  assert ($result | str contains "invalid identifier")
}

# Scenario: Circular dependency detected at job-create
def test-bdd-circular-dependency-rejected [] {
  let job_def = {
    name: "test-circular",
    tasks: [
      { name: "task-a", needs: ["task-b"] },
      { name: "task-b", needs: ["task-a"] }
    ]
  }
  let result = (try { job-create $job_def } catch {|e| $e.msg })
  assert ($result | str contains "Circular dependency")
}

# Scenario: Self-referencing task dependency rejected
def test-bdd-self-referencing-dependency-rejected [] {
  let job_def = {
    name: "test-self-ref",
    tasks: [
      { name: "task-a", needs: ["task-a"] }
    ]
  }
  let result = (try { job-create $job_def } catch {|e| $e.msg })
  assert ($result | str contains "Circular dependency")
}

# Scenario: Complex circular dependency detected
def test-bdd-complex-circular-dependency-rejected [] {
  let job_def = {
    name: "test-complex-circular",
    tasks: [
      { name: "task-a", needs: ["task-b"] },
      { name: "task-b", needs: ["task-c"] },
      { name: "task-c", needs: ["task-a"] }
    ]
  }
  let result = (try { job-create $job_def } catch {|e| $e.msg })
  assert ($result | str contains "Circular dependency")
}

# Scenario: Valid acyclic dependencies accepted
def test-bdd-acyclic-dependencies-accepted [] {
  let job_def = {
    name: "test-acyclic",
    tasks: [
      { name: "task-a", needs: [] },
      { name: "task-b", needs: ["task-a"] },
      { name: "task-c", needs: ["task-a", "task-b"] }
    ]
  }
  # Should not throw
  job-create $job_def
}

# Scenario: Diamond dependency (valid DAG) accepted
def test-bdd-diamond-dependency-accepted [] {
  let job_def = {
    name: "test-diamond",
    tasks: [
      { name: "task-a", needs: [] },
      { name: "task-b", needs: ["task-a"] },
      { name: "task-c", needs: ["task-a"] },
      { name: "task-d", needs: ["task-b", "task-c"] }
    ]
  }
  # Should not throw - diamond is valid DAG
  job-create $job_def
}

# ── Awakeables Table Tests ─────────────────────────────────────────────────────

# Test: awakeables table is created by db-init
def test-awakeables-table-created [] {
  let test_db_dir = "/tmp/test-awakeables-db-($env.PID)"
  let test_db_path = $"($test_db_dir)/journal.db"
  
  rm -rf $test_db_dir
  
  do {
    $env.NUOC_DB_DIR = $test_db_dir
    db-init
    let tables = (sqlite3 $test_db_path "SELECT name FROM sqlite_master WHERE type='table' AND name='awakeables' ORDER BY name;" | from ssv)
    assert equal ($tables | length) 1
    assert equal $tables.0.name "awakeables"
  }
  
  rm -rf $test_db_dir
}

# Test: awakeables table has correct schema
def test-awakeables-table-schema [] {
  let test_db_dir = "/tmp/test-awakeables-db-($env.PID)"
  let test_db_path = $"($test_db_dir)/journal.db"
  
  rm -rf $test_db_dir
  
  do {
    $env.NUOC_DB_DIR = $test_db_dir
    db-init
    let schema = (sqlite3 $test_db_path "PRAGMA table_info(awakeables);" | from ssv)
    
    assert equal ($schema | where name == "id" | length) 1
    assert equal ($schema | where name == "job_id" | length) 1
    assert equal ($schema | where name == "task_name" | length) 1
    assert equal ($schema | where name == "entry_index" | length) 1
    assert equal ($schema | where name == "status" | length) 1
    assert equal ($schema | where name == "payload" | length) 1
    assert equal ($schema | where name == "timeout_at" | length) 1
    assert equal ($schema | where name == "created_at" | length) 1
    assert equal ($schema | where name == "resolved_at" | length) 1
    
    let id_col = ($schema | where name == "id")
    assert equal $id_col.0.pk 1
    
    let status_col = ($schema | where name == "status")
    assert equal $status_col.0.dflt_value "'PENDING'"
  }
  
  rm -rf $test_db_dir
}

# Test: awakeables table has index on (job_id, task_name)
def test-awakeables-index-created [] {
  let test_db_dir = "/tmp/test-awakeables-db-($env.PID)"
  let test_db_path = $"($test_db_dir)/journal.db"
  
  rm -rf $test_db_dir
  
  do {
    $env.NUOC_DB_DIR = $test_db_dir
    db-init
    let indexes = (sqlite3 $test_db_path "SELECT name FROM sqlite_master WHERE type='index' AND tbl_name='awakeables' ORDER BY name;" | from ssv)
    let has_index = ($indexes | where name =~ "idx_awakeables_job_task" | length) > 0
    assert equal $has_index true
  }
  
  rm -rf $test_db_dir
}

# ── Awakeable ID Generation Tests ──────────────────────────────────────────────

# Test: awakeable-id-generate has correct prefix
def test-awakeable-id-generate-prefix [] {
  let result = (awakeable-id-generate "job-123" 0)
  assert ($result | str starts-with "prom_1")
}

# Test: awakeable-id-generate produces globally unique IDs
def test-awakeable-id-generate-unique [] {
  let id1 = (awakeable-id-generate "job-123" 0)
  let id2 = (awakeable-id-generate "job-123" 1)
  let id3 = (awakeable-id-generate "job-456" 0)
  
  assert not ($id1 == $id2)
  assert not ($id1 == $id3)
  assert not ($id2 == $id3)
}

# Test: awakeable-id-generate uses base64url encoding
def test-awakeable-id-generate-base64url [] {
  let result = (awakeable-id-generate "job-123" 0)
  # Base64url should not have '+' or '/' characters (they're replaced with '-' and '_')
  assert not ($result | str contains '+')
  assert not ($result | str contains '/')
}

# Test: awakeable-id-generate encodes job_id and entry_index
def test-awakeable-id-generate-encodes-inputs [] {
  let result1 = (awakeable-id-generate "job-abc" 0)
  let result2 = (awakeable-id-generate "job-abc" 1)
  let result3 = (awakeable-id-generate "job-def" 0)
  
  # Different entry_index should produce different IDs
  assert not ($result1 == $result2)
  # Different job_id should produce different IDs  
  assert not ($result1 == $result3)
}

# ── Awakeable ID Parsing Tests ───────────────────────────────────────────────

# Test: awakeable-id-parse extracts invocation_id
def test-awakeable-id-parse-extract-invocation-id [] {
  let awakeable_id = (awakeable-id-generate "job-123" 0)
  let parsed = (awakeable-id-parse $awakeable_id)
  assert equal $parsed.invocation_id "job-123"
}

# Test: awakeable-id-parse extracts entry_index
def test-awakeable-id-parse-extract-entry-index [] {
  let awakeable_id = (awakeable-id-generate "job-123" 5)
  let parsed = (awakeable-id-parse $awakeable_id)
  assert equal $parsed.entry_index 5
}

# Test: awakeable-id-parse handles zero entry_index
def test-awakeable-id-parse-zero-entry-index [] {
  let awakeable_id = (awakeable-id-generate "job-123" 0)
  let parsed = (awakeable-id-parse $awakeable_id)
  assert equal $parsed.entry_index 0
}

# Test: awakeable-id-parse handles large entry_index
def test-awakeable-id-parse-large-entry-index [] {
  let awakeable_id = (awakeable-id-generate "job-123" 999)
  let parsed = (awakeable-id-parse $awakeable_id)
  assert equal $parsed.entry_index 999
}

# Test: awakeable-id-parse errors on invalid prefix
def test-awakeable-id-parse-invalid-prefix [] {
  let result = (try { awakeable-id-parse "invalid_prefix_base64" } catch {|e| $e.msg })
  assert ($result | str contains "invalid awakeable ID format")
}

# Test: awakeable-id-parse errors on empty ID
def test-awakeable-id-parse-empty-id [] {
  let result = (try { awakeable-id-parse "" } catch {|e| $e.msg })
  assert ($result | str contains "invalid awakeable ID format")
}

# Test: awakeable-id-parse errors on missing base64 content
def test-awakeable-id-parse-missing-content [] {
  let result = (try { awakeable-id-parse "prom_1" } catch {|e| $e.msg })
  assert ($result | str contains "invalid awakeable ID format")
}

# Test: awakeable-id-parse errors on invalid base64
def test-awakeable-id-parse-invalid-base64 [] {
  let result = (try { awakeable-id-parse "prom_1!!!invalid!!!" } catch {|e| $e.msg })
  assert ($result | str contains "invalid awakeable ID format")
}

# Test: awakeable-id-parse errors on malformed decoded content (missing colon)
def test-awakeable-id-parse-malformed-content [] {
  let result = (try { awakeable-id-parse "prom_1invalid_no_colon" } catch {|e| $e.msg })
  assert ($result | str contains "invalid awakeable ID format")
}

# Test: awakeable-id-parse errors on non-numeric entry_index
def test-awakeable-id-parse-non-numeric-entry-index [] {
  let result = (try { awakeable-id-parse "prom_1invalid:not_a_number" } catch {|e| $e.msg })
  assert ($result | str contains "invalid awakeable ID format")
}

# Test: awakeable-id-parse is inverse of generate
def test-awakeable-id-parse-generate-roundtrip [] {
  let job_id = "test-job-123"
  let entry_index = 42
  
  let generated = (awakeable-id-generate $job_id $entry_index)
  let parsed = (awakeable-id-parse $generated)
  
  assert equal $parsed.invocation_id $job_id
  assert equal $parsed.entry_index $entry_index
}

# ── Awakeable Creation Tests ──────────────────────────────────────────────────

# Test: ctx.awakeable returns an ID
def test-ctx-awakeable-returns-id [] {
  let test_db_dir = "/tmp/test-ctx-awakeable-($env.PID)"
  let test_db_path = $"($test_db_dir)/journal.db"

  rm -rf $test_db_dir

  do {
    $env.NUOC_DB_DIR = $test_db_dir
    db-init

    let job_id = "test-job-awakeable"
    let task_name = "test-task"
    let attempt = 1
    init-execution-context $job_id $task_name $attempt --replay-mode
    let entry_index = (next-entry-index $job_id $task_name $attempt)

    let result = (ctx-awakeable $job_id $task_name $attempt)

    assert ($result.id | is-not-empty)
    assert ($result.id | str starts-with "prom_1")
  }

  rm -rf $test_db_dir
}

# Test: ctx.awakeable inserts record into awakeables table
def test-ctx-awakeable-inserts-record [] {
  let test_db_dir = "/tmp/test-ctx-awakeable-insert-($env.PID)"
  let test_db_path = $"($test_db_dir)/journal.db"

  rm -rf $test_db_dir

  do {
    $env.NUOC_DB_DIR = $test_db_dir
    db-init

    let job_id = "test-job-insert"
    let task_name = "test-task"
    let attempt = 1
    init-execution-context $job_id $task_name $attempt --replay-mode
    let entry_index = (next-entry-index $job_id $task_name $attempt)

    let result = (ctx-awakeable $job_id $task_name $attempt)

    let records = (sqlite3 -json $test_db_path $"SELECT * FROM awakeables WHERE id='($result.id)'" | from json)
    assert equal ($records | length) 1
    assert equal $records.0.id $result.id
    assert equal $records.0.job_id $job_id
    assert equal $records.0.task_name $task_name
    assert equal $records.0.entry_index $entry_index
    assert equal $records.0.status "PENDING"
  }

  rm -rf $test_db_dir
}

# Test: ctx.awakeable journals the operation for replay
def test-ctx-awakeable-journals-operation [] {
  let test_db_dir = "/tmp/test-ctx-awakeable-journal-($env.PID)"
  let test_db_path = $"($test_db_dir)/journal.db"

  rm -rf $test_db_dir

  do {
    $env.NUOC_DB_DIR = $test_db_dir
    db-init

    let job_id = "test-job-journal"
    let task_name = "test-task"
    let attempt = 1
    init-execution-context $job_id $task_name $attempt --replay-mode
    let entry_index = (next-entry-index $job_id $task_name $attempt)

    let result = (ctx-awakeable $job_id $task_name $attempt)

    let journal_entries = (sqlite3 -json $test_db_path $"SELECT * FROM journal WHERE job_id='($job_id)' AND task_name='($task_name)' AND attempt=($attempt) AND entry_index=($entry_index)" | from json)
    assert equal ($journal_entries | length) 1
    assert equal $journal_entries.0.op_type "awakeable-create"
  }

  rm -rf $test_db_dir
}

# Test: ctx.awakeable uses current entry_index from execution context
def test-ctx-awakeable-uses-current-entry-index [] {
  let test_db_dir = "/tmp/test-ctx-awakeable-entry-($env.PID)"
  let test_db_path = $"($test_db_dir)/journal.db"

  rm -rf $test_db_dir

  do {
    $env.NUOC_DB_DIR = $test_db_dir
    db-init

    let job_id = "test-job-entry"
    let task_name = "test-task"
    let attempt = 1
    init-execution-context $job_id $task_name $attempt --replay-mode

    let entry_index_1 = (next-entry-index $job_id $task_name $attempt)
    let result_1 = (ctx-awakeable $job_id $task_name $attempt)

    let entry_index_2 = (next-entry-index $job_id $task_name $attempt)
    let result_2 = (ctx-awakeable $job_id $task_name $attempt)

    assert not ($result_1.id == $result_2.id)
    assert ($result_1.id | is-not-empty)
    assert ($result_2.id | is-not-empty)
  }

  rm -rf $test_db_dir
}

# Run awakeables tests
test test-awakeables-table-created
test test-awakeables-table-schema
test test-awakeables-index-created
test test-awakeable-id-generate-prefix
test test-awakeable-id-generate-unique
test test-awakeable-id-generate-base64url
test test-awakeable-id-generate-encodes-inputs
test test-awakeable-id-parse-extract-invocation-id
test test-awakeable-id-parse-extract-entry-index
test test-awakeable-id-parse-zero-entry-index
test test-awakeable-id-parse-large-entry-index
test test-awakeable-id-parse-invalid-prefix
test test-awakeable-id-parse-empty-id
test test-awakeable-id-parse-missing-content
test test-awakeable-id-parse-invalid-base64
test test-awakeable-id-parse-malformed-content
test test-awakeable-id-parse-non-numeric-entry-index
test test-awakeable-id-parse-generate-roundtrip
test test-ctx-awakeable-returns-id
test test-ctx-awakeable-inserts-record
test test-ctx-awakeable-journals-operation
test test-ctx-awakeable-uses-current-entry-index

print "[ok] oc-engine.nu tests completed"
