#!/usr/bin/env nu
# ctx-workflow.nu — WorkflowContext for Workflows (exactly-once orchestration)
# Workflows have special run handler with exactly-once execution per workflow_id

use oc-engine.nu

# ── WorkflowContext (for run handler) ────────────────────────────────────────
# For the main 'run' handler - executes exactly once per workflow_id

# Create a WorkflowContext for the run handler
export def ctx-workflow-create [
  workflow_name: string
  workflow_id: string
] {
  {
    context_type: "workflow",
    workflow_name: $workflow_name,
    workflow_id: $workflow_id,
    is_run_handler: true,
    has_state: false,  # State managed by runtime, not K/V
    parallelism: "exactly-once"
  }
}

# ── WorkflowSharedContext (for signal handlers) ─────────────────────────────
# For signal handlers - read-only access to workflow state

# Create a WorkflowSharedContext for signal handlers
export def ctx-workflow-shared-create [
  workflow_name: string
  workflow_id: string
] {
  {
    context_type: "workflow_shared",
    workflow_name: $workflow_name,
    workflow_id: $workflow_id,
    is_run_handler: false,
    has_state: false,
    parallelism: "concurrent-with-run"
  }
}

# Get workflow state (for signal handlers - read-only)
export def "ctx-workflow get-state" [
  workflow_name: string
  workflow_id: string
] {
  let result = (sqlite3 -json (oc-engine.DB_PATH) $"SELECT state FROM workflow_runs WHERE workflow_name='($workflow_name)' AND workflow_id='($workflow_id)'" | from json)

  if ($result | length) == 0 {
    return null
  }

  $result.0.state
}

# Set workflow state (only from run handler)
export def "ctx-workflow set-state" [
  workflow_name: string
  workflow_id: string
  state: string
] {
  # Escape state for SQL
  let state_escaped = ($state | str replace "'" "''")

  let db_path = oc-engine.DB_PATH; sqlite3 $db_path $"UPDATE workflow_runs SET state='($state_escaped)' WHERE workflow_name='($workflow_name)' AND workflow_id='($workflow_id)'"

  { status: "state_updated" }
}

# Initialize workflow state table
export def "ctx-workflow db-init" [] {
  # Add state column to workflow_runs if it doesn't exist
  try {
    let db_path = oc-engine.DB_PATH; sqlite3 $db_path "ALTER TABLE workflow_runs ADD COLUMN state TEXT"
  } catch {
    # Column already exists - ignore
  }
}
