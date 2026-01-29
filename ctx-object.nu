#!/usr/bin/env nu
# ctx-object.nu — ObjectContext for Virtual Objects (keyed stateful, single-writer)
# Virtual Objects have get/set/clear state methods with single-writer concurrency

use oc-engine.nu

# ── ObjectContext ──────────────────────────────────────────────────────────────
# For Virtual Objects: Stateful entities with per-key state isolation
# Single writer per key, concurrent readers allowed

# Create an ObjectContext for a virtual object
export def ctx-object-create [
  entity_name: string
  object_key: string
] {
  {
    context_type: "object",
    entity_name: $entity_name,
    object_key: $object_key,
    has_state: true,
    parallelism: "single-writer"
  }
}

# Get state from virtual object K/V store
export def "ctx-object get" [
  entity_name: string
  object_key: string
  key: string
] {
  let result = (sqlite3 -json (oc-engine.DB_PATH) $"SELECT value FROM virtual_object_state WHERE entity_name='($entity_name)' AND object_key='($object_key)' AND key='($key)'" | from json)

  if ($result | length) == 0 {
    return null
  }

  $result.0.value
}

# Set state in virtual object K/V store
export def "ctx-object set" [
  entity_name: string
  object_key: string
  key: string
  value: string
] {
  # Escape values for SQL
  let value_escaped = ($value | str replace "'" "''")

  let db_path = oc-engine.DB_PATH; sqlite3 $db_path $"INSERT OR REPLACE INTO virtual_object_state (entity_name, object_key, key, value, updated_at) VALUES ('($entity_name)', '($object_key)', '($key)', '($value_escaped)', datetime('now'))"

  { status: "set", key: $key }
}

# Clear state from virtual object K/V store
export def "ctx-object clear" [
  entity_name: string
  object_key: string
  key: string
] {
  let db_path = oc-engine.DB_PATH; sqlite3 $db_path $"DELETE FROM virtual_object_state WHERE entity_name='($entity_name)' AND object_key='($object_key)' AND key='($key)'"

  { status: "cleared", key: $key }
}

# Get all state for a virtual object
export def "ctx-object get-all" [
  entity_name: string
  object_key: string
] {
  sqlite3 -json (oc-engine.DB_PATH) $"SELECT key, value FROM virtual_object_state WHERE entity_name='($entity_name)' AND object_key='($object_key)'"
  | from json
  | reduce -f {} { |row, acc|
    $acc | insert $row.key $row.value
  }
}

# Clear all state for a virtual object
export def "ctx-object clear-all" [
  entity_name: string
  object_key: string
] {
  let db_path = oc-engine.DB_PATH; sqlite3 $db_path $"DELETE FROM virtual_object_state WHERE entity_name='($entity_name)' AND object_key='($object_key)'"

  { status: "cleared_all" }
}

# Initialize virtual object state table
export def "ctx-object db-init" [] {
  let db_path = oc-engine.DB_PATH; sqlite3 $db_path "
    CREATE TABLE IF NOT EXISTS virtual_object_state (
      entity_name TEXT NOT NULL,
      object_key TEXT NOT NULL,
      key TEXT NOT NULL,
      value TEXT,
      updated_at TEXT NOT NULL DEFAULT (datetime('now')),
      PRIMARY KEY (entity_name, object_key, key)
    );

    CREATE INDEX IF NOT EXISTS idx_vo_state_lookup
      ON virtual_object_state(entity_name, object_key);
  "
}
