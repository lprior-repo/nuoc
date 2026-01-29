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

print "[ok] oc-engine.nu tests completed"
