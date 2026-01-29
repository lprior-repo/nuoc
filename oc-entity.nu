#!/usr/bin/env nu
# oc-entity.nu — Entity Type System for Services, Virtual Objects, and Workflows
# Implements Restate's three entity types with distinct concurrency semantics

use oc-engine.nu

# ── Entity Type Constants ─────────────────────────────────────────────────────

export const ENTITY_TYPE_SERVICE = "service"
export const ENTITY_TYPE_VIRTUAL_OBJECT = "virtual_object"
export const ENTITY_TYPE_WORKFLOW = "workflow"

# ── Database Schema Initialization ────────────────────────────────────────────

export def entity-db-init [] {
  # Initialize entity tables in the existing database
  let db = oc-engine.DB_PATH
  sqlite3 $db "
    CREATE TABLE IF NOT EXISTS entity_definitions (
      name TEXT PRIMARY KEY,
      entity_type TEXT NOT NULL CHECK (entity_type IN ('service', 'virtual_object', 'workflow')),
      handlers TEXT NOT NULL,
      created_at TEXT NOT NULL DEFAULT (datetime('now'))
    );

    CREATE TABLE IF NOT EXISTS virtual_object_locks (
      entity_name TEXT NOT NULL,
      object_key TEXT NOT NULL,
      holder_invocation_id TEXT,
      acquired_at TEXT,
      PRIMARY KEY (entity_name, object_key)
    );

    CREATE TABLE IF NOT EXISTS workflow_runs (
      workflow_name TEXT NOT NULL,
      workflow_id TEXT NOT NULL,
      run_invocation_id TEXT,
      status TEXT NOT NULL DEFAULT 'pending',
      result TEXT,
      created_at TEXT NOT NULL DEFAULT (datetime('now')),
      completed_at TEXT,
      PRIMARY KEY (workflow_name, workflow_id)
    );

    CREATE INDEX IF NOT EXISTS idx_entity_definitions_type
      ON entity_definitions(entity_type);

    CREATE INDEX IF NOT EXISTS idx_vo_locks_holder
      ON virtual_object_locks(holder_invocation_id);

    CREATE INDEX IF NOT EXISTS idx_workflow_runs_status
      ON workflow_runs(workflow_name, status);
  "

  print "[ok] Entity database schema initialized"
}

# ── Entity Registration ───────────────────────────────────────────────────────

# Register an entity with its type and handlers
export def "entity register" [
  name: string
  entity_type: string
  handlers: record< HandlerType: list<string> >
] {
  # Validate entity type
  if not ($entity_type in [$ENTITY_TYPE_SERVICE, $ENTITY_TYPE_VIRTUAL_OBJECT, $ENTITY_TYPE_WORKFLOW]) {
    error make {
      msg: $"Invalid entity type: ($entity_type)"
      label: {
        text: "Must be 'service', 'virtual_object', or 'workflow'"
      }
    }
  }

  # Serialize handlers to JSON
  let handlers_json = ($handlers | to json)
  let db = oc-engine.DB_PATH

  # Insert into database
  sqlite3 $db $"INSERT INTO entity_definitions (name, entity_type, handlers) VALUES ('($name)', '($entity_type)', '($handlers_json)')"

  { status: "registered", name: $name, entity_type: $entity_type }
}

# Get entity type by name
export def "entity get-type" [name: string] {
  let db = oc-engine.DB_PATH
  let result = (sqlite3 -json $db $"SELECT entity_type FROM entity_definitions WHERE name='($name)'" | from json)

  if ($result | length) == 0 {
    return null
  }

  $result.0.entity_type
}

# Check if entity exists
export def "entity exists" [name: string] -> bool {
  let db = oc-engine.DB_PATH
  let result = (sqlite3 -json $db $"SELECT COUNT(*) as count FROM entity_definitions WHERE name='($name)'" | from json)
  ($result.0.count | into int) > 0
}

# List all entities
export def "entity list" [] {
  let db = oc-engine.DB_PATH
  sqlite3 -json $db "SELECT name, entity_type, handlers, created_at FROM entity_definitions ORDER BY created_at"
  | from json
}

# Get entity details
export def "entity get" [name: string] {
  let db = oc-engine.DB_PATH
  sqlite3 -json $db $"SELECT * FROM entity_definitions WHERE name='($name)'"
  | from json
  | get 0?
}

# ── Virtual Object Locking ────────────────────────────────────────────────────

# Acquire lock for virtual object write handler
export def "vo lock-acquire" [
  entity_name: string
  object_key: string
  invocation_id: string
] {
  let db = oc-engine.DB_PATH

  # Try to acquire lock (INSERT if not exists)
  try {
    sqlite3 $db $"INSERT INTO virtual_object_locks (entity_name, object_key, holder_invocation_id, acquired_at) VALUES ('($entity_name)', '($object_key)', '($invocation_id)', datetime('now'))"
    { acquired: true, holder: $invocation_id }
  } catch {
    # Lock already held - get current holder
    let current = (sqlite3 -json $db $"SELECT holder_invocation_id, acquired_at FROM virtual_object_locks WHERE entity_name='($entity_name)' AND object_key='($object_key)'" | from json).0

    { acquired: false, holder: $current.holder_invocation_id, acquired_at: $current.acquired_at }
  }
}

# Release lock for virtual object
export def "vo lock-release" [
  entity_name: string
  object_key: string
  invocation_id: string
] {
  let db = oc-engine.DB_PATH

  # Only release if we're the holder
  let result = (sqlite3 $db $"DELETE FROM virtual_object_locks WHERE entity_name='($entity_name)' AND object_key='($object_key)' AND holder_invocation_id='($invocation_id)'" | complete | get exit_code)

  { released: ($result == 0) }
}

# Check if lock is held
export def "vo lock-held?" [
  entity_name: string
  object_key: string
] -> bool {
  let db = oc-engine.DB_PATH
  let result = (sqlite3 -json $db $"SELECT COUNT(*) as count FROM virtual_object_locks WHERE entity_name='($entity_name)' AND object_key='($object_key)'" | from json)
  ($result.0.count | into int) > 0
}

# Get current lock holder
export def "vo lock-get-holder" [
  entity_name: string
  object_key: string
] {
  let db = oc-engine.DB_PATH
  let result = (sqlite3 -json $db $"SELECT holder_invocation_id, acquired_at FROM virtual_object_locks WHERE entity_name='($entity_name)' AND object_key='($object_key)'" | from json)

  if ($result | length) == 0 {
    return null
  }

  { holder: $result.0.holder_invocation_id, acquired_at: $result.0.acquired_at }
}

# ── Workflow Run Tracking ─────────────────────────────────────────────────────

# Record workflow run start
export def "workflow run-start" [
  workflow_name: string
  workflow_id: string
  invocation_id: string
] {
  let db = oc-engine.DB_PATH

  # Try to insert - will fail if workflow_id already exists
  try {
    sqlite3 $db $"INSERT INTO workflow_runs (workflow_name, workflow_id, run_invocation_id, status) VALUES ('($workflow_name)', '($workflow_id)', '($invocation_id)', 'running')"

    { status: "started", workflow_id: $workflow_id, invocation_id: $invocation_id }
  } catch { |e|
    # Check if already run
    let existing = (sqlite3 -json $db $"SELECT status, result FROM workflow_runs WHERE workflow_name='($workflow_name)' AND workflow_id='($workflow_id)'" | from json)

    if ($existing | length) > 0 {
      let run = $existing.0
      return { status: "cached", workflow_id: $workflow_id, result: $run.result }
    }

    error make { msg: "Failed to start workflow run" }
  }
}

# Complete workflow run
export def "workflow run-complete" [
  workflow_name: string
  workflow_id: string
  result: string
] {
  let db = oc-engine.DB_PATH
  sqlite3 $db $"UPDATE workflow_runs SET status='completed', result='($result)', completed_at=datetime('now') WHERE workflow_name='($workflow_name)' AND workflow_id='($workflow_id)'"

  { status: "completed", workflow_id: $workflow_id }
}

# Get workflow run status
export def "workflow run-get" [
  workflow_name: string
  workflow_id: string
] {
  let db = oc-engine.DB_PATH
  sqlite3 -json $db $"SELECT * FROM workflow_runs WHERE workflow_name='($workflow_name)' AND workflow_id='($workflow_id)'"
  | from json
  | get 0?
}

# Check if workflow has been run
export def "workflow run-exists?" [
  workflow_name: string
  workflow_id: string
] -> bool {
  let db = oc-engine.DB_PATH
  let result = (sqlite3 -json $db $"SELECT COUNT(*) as count FROM workflow_runs WHERE workflow_name='($workflow_name)' AND workflow_id='($workflow_id)'" | from json)
  ($result.0.count | into int) > 0
}
