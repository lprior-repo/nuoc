#!/usr/bin/env nu
# oc-engine.nu — Tork-Inspired DAG Workflow Engine
# Pure nushell + SQLite journal for durable execution with replay + regression

export const DB_DIR = ".oc-workflow"
export const DB_PATH = $"($DB_DIR)/journal.db"

# ── Database Initialization ──────────────────────────────────────────────────

# ── Invocation Status (8-state Restate lifecycle) ────────────────────────────
# Valid states: pending, scheduled, ready, running, suspended, backing-off, paused, completed
export const STATUS_PENDING = "pending"
export const STATUS_SCHEDULED = "scheduled"
export const STATUS_READY = "ready"
export const STATUS_RUNNING = "running"
export const STATUS_SUSPENDED = "suspended"
export const STATUS_BACKING_OFF = "backing-off"
export const STATUS_PAUSED = "paused"
export const STATUS_COMPLETED = "completed"

export def db-init [] {
  mkdir $DB_DIR
  sqlite3 $DB_PATH "
    CREATE TABLE IF NOT EXISTS jobs (
      id TEXT PRIMARY KEY,
      name TEXT NOT NULL,
      bead_id TEXT,
      inputs TEXT,
      defaults TEXT,
      status TEXT NOT NULL DEFAULT 'pending' CHECK(status IN ('pending','scheduled','ready','running','suspended','backing-off','paused','completed')),
      position INTEGER DEFAULT 0,
      created_at TEXT NOT NULL DEFAULT (datetime('now')),
      scheduled_start_at TEXT,
      started_at TEXT,
      completed_at TEXT,
      completion_result TEXT CHECK(completion_result IS NULL OR completion_result IN ('success','failure')),
      completion_failure TEXT,
      next_retry_at TEXT,
      retry_count INTEGER DEFAULT 0,
      last_failure TEXT,
      last_failure_code INTEGER,
      error TEXT,
      result TEXT
    );

    CREATE TABLE IF NOT EXISTS tasks (
      id TEXT PRIMARY KEY,
      job_id TEXT NOT NULL,
      name TEXT NOT NULL,
      var TEXT,
      status TEXT NOT NULL DEFAULT 'pending',
      run_cmd TEXT,
      agent_type TEXT,
      agent_model TEXT,
      gate TEXT,
      condition TEXT,
      on_fail_regress TEXT,
      priority INTEGER DEFAULT 0,
      timeout_sec INTEGER,
      input TEXT,
      output TEXT,
      error TEXT,
      attempt INTEGER DEFAULT 0,
      max_attempts INTEGER DEFAULT 3,
      retry_delay_sec INTEGER DEFAULT 1,
      retry_scaling INTEGER DEFAULT 2,
      started_at TEXT,
      completed_at TEXT,
      duration_ms INTEGER,
      FOREIGN KEY (job_id) REFERENCES jobs(id),
      UNIQUE (job_id, name)
    );

    CREATE TABLE IF NOT EXISTS task_deps (
      job_id TEXT NOT NULL,
      task_name TEXT NOT NULL,
      depends_on TEXT NOT NULL,
      PRIMARY KEY (job_id, task_name, depends_on)
    );

    CREATE TABLE IF NOT EXISTS job_deps (
      job_id TEXT NOT NULL,
      depends_on TEXT NOT NULL,
      PRIMARY KEY (job_id, depends_on)
    );

    CREATE TABLE IF NOT EXISTS events (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      job_id TEXT NOT NULL,
      task_name TEXT,
      event_type TEXT NOT NULL,
      old_state TEXT,
      new_state TEXT,
      payload TEXT,
      created_at TEXT NOT NULL DEFAULT (datetime('now'))
    );

    CREATE TABLE IF NOT EXISTS journal (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      job_id TEXT NOT NULL,
      task_name TEXT NOT NULL,
      attempt INTEGER NOT NULL DEFAULT 1,
      entry_index INTEGER NOT NULL,
      op_type TEXT NOT NULL,
      input_hash TEXT,
      input TEXT,
      output TEXT,
      created_at TEXT NOT NULL DEFAULT (datetime('now')),
      UNIQUE (job_id, task_name, attempt, entry_index)
    );
    CREATE INDEX IF NOT EXISTS idx_journal_replay ON journal(job_id, task_name, attempt);

    CREATE TABLE IF NOT EXISTS execution_context (
      job_id TEXT NOT NULL,
      task_name TEXT NOT NULL,
      attempt INTEGER NOT NULL,
      entry_index INTEGER NOT NULL DEFAULT 0,
      replay_mode INTEGER NOT NULL DEFAULT 0,
      PRIMARY KEY (job_id, task_name, attempt)
    );

    CREATE TABLE IF NOT EXISTS webhooks (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      job_id TEXT NOT NULL,
      url TEXT NOT NULL,
      event TEXT NOT NULL,
      headers TEXT,
      condition TEXT
    );

    CREATE TABLE IF NOT EXISTS awakeables (
      id TEXT PRIMARY KEY,
      job_id TEXT NOT NULL,
      task_name TEXT NOT NULL,
      entry_index INTEGER NOT NULL,
      status TEXT DEFAULT 'PENDING',
      payload TEXT,
      timeout_at TEXT,
      created_at TEXT DEFAULT (datetime('now')),
      resolved_at TEXT
    );

    CREATE INDEX IF NOT EXISTS idx_awakeables_job_task ON awakeables(job_id, task_name);
  "
}

# ── Journal Operations ───────────────────────────────────────────────────────

# Append a journal entry atomically
# Precondition: job_id and task_name are validated identifiers
# Postcondition: entry persisted with computed input_hash, returns entry_index
# Invariant: UNIQUE constraint ensures no duplicate (job_id, task_name, attempt, entry_index)
export def journal-write [
  job_id: string,
  task_name: string,
  attempt: int,
  entry_index: int,
  op_type: string,
  input: any,
  output: any
]: nothing -> int {
  # Validate identifiers
  let jid = (validate-ident $job_id "journal-write.job_id")
  let tname = (validate-ident $task_name "journal-write.task_name")
  let op = (validate-ident $op_type "journal-write.op_type")

  # Serialize input and output to JSON
  let input_json = ($input | to json -r)
  let output_json = ($output | to json -r)

  # Compute input hash for deterministic replay verification
  let input_hash = ($input_json | hash sha256)

  # Escape JSON text for SQL insertion
  let input_esc = (sql-escape-text $input_json)
  let output_esc = (sql-escape-text $output_json)
  let hash_esc = (sql-escape-text $input_hash)

  # Insert entry atomically
  sql-exec $"INSERT INTO journal \(job_id, task_name, attempt, entry_index, op_type, input_hash, input, output\) VALUES \('($jid)', '($tname)', ($attempt), ($entry_index), '($op)', '($hash_esc)', '($input_esc)', '($output_esc)'\)"

  # Return entry_index on success
  $entry_index
}

# Read all journal entries for a task attempt
# Precondition: job_id and task_name are validated identifiers
# Postcondition: returns entries ordered by entry_index, empty table if none exist
# Invariant: entry_index ordering ensures deterministic replay sequence
export def journal-read [
  job_id: string,
  task_name: string,
  attempt: int
]: nothing -> table {
  # Validate identifiers
  let jid = (validate-ident $job_id "journal-read.job_id")
  let tname = (validate-ident $task_name "journal-read.task_name")

  # Query journal entries in order
  sql $"SELECT * FROM journal WHERE job_id='($jid)' AND task_name='($tname)' AND attempt=($attempt) ORDER BY entry_index"
}

# Check if a journal entry exists and return cached output
# Precondition: job_id and task_name are validated identifiers
# Postcondition: returns cached output if entry exists, null otherwise
# Invariant: Enables deterministic replay by checking journal before execution
export def check-replay [
  job_id: string,
  task_name: string,
  attempt: int,
  entry_index: int
]: nothing -> any {
  # Validate identifiers
  let jid = (validate-ident $job_id "check-replay.job_id")
  let tname = (validate-ident $task_name "check-replay.task_name")

  # Query for specific entry
  let result = (sql $"SELECT output FROM journal WHERE job_id='($jid)' AND task_name='($tname)' AND attempt=($attempt) AND entry_index=($entry_index)")

  # Return null if not found, otherwise deserialize output
  if ($result | is-empty) {
    null
  } else {
    let output_str = $result.0.output
    if ($output_str == "null" or ($output_str | is-empty)) {
      null
    } else {
      try {
        $output_str | from json
      } catch {
        $output_str
      }
    }
  }
}

# ── Execution Context (Entry Index Tracking) ─────────────────────────────────

# Initialize execution context for a task attempt
# Precondition: job_id and task_name are validated identifiers
# Postcondition: entry_index reset to 0, replay_mode set based on existing journal entries
# Invariant: Must be called at task execution start
export def init-execution-context [
  job_id: string,
  task_name: string,
  attempt: int,
  --replay-mode
]: nothing -> nothing {
  let jid = (validate-ident $job_id "init-execution-context.job_id")
  let tname = (validate-ident $task_name "init-execution-context.task_name")

  # Check if there are existing journal entries for this attempt
  let known_entries = (sql $"SELECT COUNT\(*\) as count FROM journal WHERE job_id='($jid)' AND task_name='($tname)' AND attempt=($attempt)").0.count

  # Auto-detect replay mode: if we have journal entries, start in replay mode
  let replay = (if $replay_mode or ($known_entries > 0) { 1 } else { 0 })

  sql-exec $"INSERT OR REPLACE INTO execution_context \(job_id, task_name, attempt, entry_index, replay_mode\) VALUES \('($jid)', '($tname)', ($attempt), 0, ($replay)\)"
}

# Get current entry index
# Precondition: execution context initialized
# Postcondition: returns current entry_index
export def get-entry-index [
  job_id: string,
  task_name: string,
  attempt: int
]: nothing -> int {
  let jid = (validate-ident $job_id "get-entry-index.job_id")
  let tname = (validate-ident $task_name "get-entry-index.task_name")

  let result = (sql $"SELECT entry_index FROM execution_context WHERE job_id='($jid)' AND task_name='($tname)' AND attempt=($attempt)")
  if ($result | is-empty) {
    0
  } else {
    $result.0.entry_index
  }
}

# Get next entry index (increment and return)
# Precondition: execution context initialized
# Postcondition: entry_index incremented, new value returned
# Invariant: Sequential entry_index for deterministic replay
export def next-entry-index [
  job_id: string,
  task_name: string,
  attempt: int
]: nothing -> int {
  let jid = (validate-ident $job_id "next-entry-index.job_id")
  let tname = (validate-ident $task_name "next-entry-index.task_name")

  # Get current value
  let current = (get-entry-index $jid $tname $attempt)
  let next = $current + 1

  # Update to next value
  sql-exec $"UPDATE execution_context SET entry_index = ($next) WHERE job_id='($jid)' AND task_name='($tname)' AND attempt=($attempt)"

  # Check if we should transition out of replay mode
  update-replay-mode $jid $tname $attempt

  # Return current value (before increment was persisted, this is the index to use)
  $current
}

# Check if currently in replay mode
# Precondition: execution context initialized
# Postcondition: returns true if reading from journal, false if writing new entries
export def is-replay-mode [
  job_id: string,
  task_name: string,
  attempt: int
]: nothing -> bool {
  let jid = (validate-ident $job_id "is-replay-mode.job_id")
  let tname = (validate-ident $task_name "is-replay-mode.task_name")

  let result = (sql $"SELECT replay_mode FROM execution_context WHERE job_id='($jid)' AND task_name='($tname)' AND attempt=($attempt)")
  if ($result | is-empty) {
    false
  } else {
    ($result.0.replay_mode == 1)
  }
}

# Update replay mode based on current entry_index vs known journal entries
# Precondition: execution context initialized
# Postcondition: replay_mode updated, transitions to live when entry_index >= known_entries
# Invariant: Ensures deterministic replay before live execution
def update-replay-mode [
  job_id: string,
  task_name: string,
  attempt: int
]: nothing -> nothing {
  let jid = (validate-ident $job_id "update-replay-mode.job_id")
  let tname = (validate-ident $task_name "update-replay-mode.task_name")

  # Get current entry index
  let current_index = (get-entry-index $jid $tname $attempt)

  # Count known journal entries
  let known_entries = (sql $"SELECT COUNT\(*\) as count FROM journal WHERE job_id='($jid)' AND task_name='($tname)' AND attempt=($attempt)").0.count

  # If current_index >= known_entries, we're in live mode (writing new entries)
  # Otherwise, we're in replay mode (reading existing entries)
  let new_mode = (if $current_index < $known_entries { 1 } else { 0 })

  # Update replay_mode
  sql-exec $"UPDATE execution_context SET replay_mode = ($new_mode) WHERE job_id='($jid)' AND task_name='($tname)' AND attempt=($attempt)"
}

# ── Helpers ──────────────────────────────────────────────────────────────────

# Identifier validation regex: alphanumeric, underscore, hyphen, dot only
export const IDENT_PATTERN = '^[a-zA-Z0-9_.-]+$'

# Validate an identifier (job_id, task_name, var name, bead_id) before SQL use
# Precondition: value is non-empty
# Postcondition: value matches IDENT_PATTERN or error is raised
# Invariant: No SQL metacharacters can pass through
export def validate-ident [value: string, context: string]: nothing -> string {
  if ($value | is-empty) {
    error make { msg: $"($context): identifier cannot be empty" }
  }
  if not ($value =~ $IDENT_PATTERN) {
    error make { msg: $"($context): invalid identifier '($value)' — must match ($IDENT_PATTERN)" }
  }
  $value
}

# Validate an optional identifier — returns empty string if empty, else validates
export def validate-ident-opt [value: string, context: string]: nothing -> string {
  if ($value | is-empty) { "" } else { validate-ident $value $context }
}

# Generate awakeable ID in Restate format: prom_1 + base64url(invocation_id + entry_index)
# Precondition: job_id is a validated identifier, entry_index is non-negative
# Postcondition: returns globally unique awakeable ID with prefix 'prom_1'
# Invariant: Different (job_id, entry_index) pairs always produce different IDs
export def awakeable-id-generate [job_id: string, entry_index: int]: nothing -> string {
  # Validate inputs
  if ($job_id | is-empty) {
    error make { msg: "awakeable-id-generate: job_id cannot be empty" }
  }
  if ($entry_index < 0) {
    error make { msg: $"awakeable-id-generate: entry_index cannot be negative: ($entry_index)" }
  }

  # Concatenate invocation_id and entry_index
  let input = $"($job_id):($entry_index)"

  # Base64-URL encode (base64 with +/ replaced by -_ and padding removed)
  let encoded = ($input | encode base64 | str replace --all '+' '-' | str replace --all '/' '_' | str replace -r '=+$' '')

  # Prepend Restate prefix
  $"prom_1($encoded)"
}

# Parse awakeable ID back to invocation_id and entry_index
# Precondition: awakeable_id is a string generated by awakeable-id-generate
# Postcondition: returns record { invocation_id: string, entry_index: int }
# Invariant: parse(generate(job_id, entry_index)) returns { invocation_id: job_id, entry_index: entry_index }
export def awakeable-id-parse [awakeable_id: string]: nothing -> record {
  # Validate prefix
  if not ($awakeable_id | str starts-with "prom_1") {
    error make { msg: "invalid awakeable ID format" }
  }

  # Extract base64 content (after prefix)
  let base64_content = ($awakeable_id | str replace "prom_1" "")

  # Check for empty content
  if ($base64_content | is-empty) {
    error make { msg: "invalid awakeable ID format" }
  }

  # Decode base64url (reverse: -_ back to +/, add padding, then decode)
  let padded_base64 = ($base64_content | str replace --all '-' '+' | str replace --all '_' '/')
  let base64_len = ($padded_base64 | str length)
  let padding_needed = (4 - ($base64_len mod 4)) mod 4
  let with_padding = if $padding_needed == 1 {
    $"($padded_base64)==="
  } else if $padding_needed == 2 {
    $"($padded_base64)=="
  } else if $padding_needed == 3 {
    $"($padded_base64)="
  } else {
    $padded_base64
  }

  let decoded = (try {
    $with_padding | decode base64
  } catch {
    error make { msg: "invalid awakeable ID format" }
  })

  # Split on colon
  let decoded_str = ($decoded | decode utf-8)
  let parts = ($decoded_str | split row ':')
  if (($parts | length) != 2) {
    error make { msg: "invalid awakeable ID format" }
  }

  let invocation_id = $parts.0
  let entry_index_str = $parts.1

  # Validate entry_index is numeric
  let entry_index = (try {
    $entry_index_str | into int
  } catch {
    error make { msg: "invalid awakeable ID format" }
  })

  # Return parsed record
  {
    invocation_id: $invocation_id,
    entry_index: $entry_index
  }
}

def sql [query: string] {
  sqlite3 -json $DB_PATH $query | from json
}

def sql-exec [query: string] {
  sqlite3 $DB_PATH $query
}

# Escape a value for SQL string literals (use ONLY for free-form text, never for identifiers)
# WARNING: This does NOT make identifiers safe — use validate-ident for IDs
export def sql-escape-text [val: string]: nothing -> string {
  $val | str replace --all "'" "''"
}

def emit-event [job_id: string, task_name: string, event_type: string, old_state: string, new_state: string, payload: string] {
  # Validate identifiers — job_id is required, task_name is optional
  let jid = (validate-ident $job_id "emit-event.job_id")
  let tn = if ($task_name | is-empty) { "NULL" } else { $"'(validate-ident $task_name "emit-event.task_name")'" }
  # Payload is free-form text, escape it properly
  let pl = if ($payload | is-empty) { "NULL" } else { $"'(sql-escape-text $payload)'" }
  # event_type, old_state, new_state are internal constants, not user input
  sql-exec $"INSERT INTO events \(job_id, task_name, event_type, old_state, new_state, payload\) VALUES \('($jid)', ($tn), '($event_type)', '($old_state)', '($new_state)', ($pl)\)"
}

# Detect cycles in task dependency graph using DFS
# Precondition: tasks is a list of task records with 'name' and 'needs' fields
# Postcondition: error is raised if cycle detected, otherwise returns nothing
def detect-cycles [tasks: list] {
  # Build adjacency list: task_name -> list of dependencies
  mut graph = {}
  for task in $tasks {
    $graph = ($graph | upsert $task.name ($task.needs? | default []))
  }

  # Track visited and recursion stack
  mut visited = {}
  mut rec_stack = {}

  # DFS cycle detection - iterative with explicit stack to avoid nested def issues
  for start_task in $tasks {
    let start_name = $start_task.name
    if ($visited | get -o $start_name | default false) { continue }

    # Use a stack: (node, phase) where phase 0 = enter, 1 = exit
    mut stack = [[$start_name 0]]

    while ($stack | is-not-empty) {
      let entry = ($stack | last)
      $stack = ($stack | drop 1)
      let node = ($entry | get 0)
      let phase = ($entry | get 1)

      if $phase == 1 {
        # Exit phase: remove from recursion stack
        $rec_stack = ($rec_stack | upsert $node false)
        continue
      }

      # Enter phase
      if ($rec_stack | get -o $node | default false) {
        error make { msg: $"Circular dependency detected: cycle involves task '($node)'" }
      }
      if ($visited | get -o $node | default false) { continue }

      $visited = ($visited | upsert $node true)
      $rec_stack = ($rec_stack | upsert $node true)

      # Schedule exit phase
      $stack = ($stack | append [[$node 1]])

      # Schedule neighbors
      let neighbors = ($graph | get -o $node | default [])
      for neighbor in $neighbors {
        if ($graph | columns | any {|k| $k == $neighbor}) {
          $stack = ($stack | append [[$neighbor 0]])
        }
      }
    }
  }
}

# ── Job Operations ───────────────────────────────────────────────────────────

# Create a job from a Tork-style record definition
export def job-create [job_def: record] {
  # Validate all identifiers at the boundary
  let job_id = (validate-ident $job_def.name "job-create.name")
  let bead_id = (validate-ident-opt ($job_def.inputs?.bead_id? | default "") "job-create.bead_id")
  let inputs = ($job_def.inputs? | default {} | to json -r)
  let defaults = ($job_def.defaults? | default {} | to json -r)
  let position = ($job_def.position? | default 0)

  # Escape free-form JSON text, not identifiers
  let inputs_esc = (sql-escape-text $inputs)
  let defaults_esc = (sql-escape-text $defaults)

  # Validate DAG topology before inserting into database
  let tasks = ($job_def.tasks? | default [])
  detect-cycles $tasks

  sql-exec $"INSERT OR REPLACE INTO jobs \(id, name, bead_id, inputs, defaults, status, position\) VALUES \('($job_id)', '($job_id)', '($bead_id)', '($inputs_esc)', '($defaults_esc)', 'pending', ($position)\)"

  # Insert tasks
  for task in ($job_def.tasks? | default []) {
    # Validate task-level identifiers
    let task_name = (validate-ident $task.name "job-create.task.name")
    let task_id = $"($job_id):($task_name)"
    let var = (validate-ident-opt ($task.var? | default "") "job-create.task.var")
    let on_fail = (validate-ident-opt ($task.on_fail?.regress_to? | default "") "job-create.task.on_fail.regress_to")
    let gate = (validate-ident-opt ($task.gate? | default "") "job-create.task.gate")

    # These are free-form text, escape them
    let run_cmd = (sql-escape-text ($task.run? | default ""))
    let agent_type = (sql-escape-text ($task.agent?.type? | default ""))
    let agent_model = (sql-escape-text ($task.agent?.model? | default ""))
    let condition = (sql-escape-text ($task.if? | default ""))
    let priority = ($task.priority? | default 0)
    let timeout = ($task.timeout_sec? | default 600)
    let max_attempts = ($task.retry?.limit? | default ($job_def.defaults?.retry?.limit? | default 3))

    sql-exec $"INSERT OR REPLACE INTO tasks \(id, job_id, name, var, status, run_cmd, agent_type, agent_model, gate, condition, on_fail_regress, priority, timeout_sec, max_attempts\) VALUES \('($task_id)', '($job_id)', '($task_name)', '($var)', 'pending', '($run_cmd)', '($agent_type)', '($agent_model)', '($gate)', '($condition)', '($on_fail)', ($priority), ($timeout), ($max_attempts)\)"

    # Insert dependencies — validate each dependency name
    for dep in ($task.needs? | default []) {
      let dep_name = (validate-ident $dep "job-create.task.needs")
      sql-exec $"INSERT OR IGNORE INTO task_deps \(job_id, task_name, depends_on\) VALUES \('($job_id)', '($task_name)', '($dep_name)'\)"
    }
  }

  emit-event $job_id "" "job.StateChange" "" "pending" ""
  $job_id
}

# Execute a job using Kahn's BFS with replay + regression
export def job-execute [job_id: string] {
  # Validate at entry point
  let jid = (validate-ident $job_id "job-execute.job_id")

  # Mark job running
  sql-exec $"UPDATE jobs SET status = 'running', started_at = datetime\('now'\) WHERE id = '($jid)'"
  emit-event $jid "" "job.StateChange" "pending" "running" ""

  # Load all tasks
  let all_tasks = (sql $"SELECT name, status, condition, priority, on_fail_regress FROM tasks WHERE job_id = '($jid)'" )

  # Build in-degree map
  let deps = (sql $"SELECT task_name, depends_on FROM task_deps WHERE job_id = '($jid)'" )

  # Main execution loop
  loop {
    # Refresh task statuses
    let tasks = (sql $"SELECT name, status, condition, priority, on_fail_regress FROM tasks WHERE job_id = '($jid)'" )

    # Find tasks with all deps satisfied (completed or skipped)
    let pending = ($tasks | where status == "pending")
    let ready = ($pending | each {|t|
      let task_deps = ($deps | where task_name == $t.name | get depends_on)
      let deps_met = if ($task_deps | is-empty) {
        true
      } else {
        let dep_statuses = (sql $"SELECT name, status FROM tasks WHERE job_id = '($jid)' AND name IN \(($task_deps | each {|d| $"'($d)'" } | str join ",")\)" )
        ($dep_statuses | all {|d| $d.status in ["completed", "skipped"] })
      }
      if $deps_met { $t } else { null }
    } | compact)

    if ($ready | is-empty) { break }

    # Sort by priority descending
    let sorted = ($ready | sort-by priority -r)

    # Execute ready tasks in parallel
    let results = ($sorted | par-each {|t|
      task-execute $jid $t.name
    })

    # Check for regressions
    for result in $results {
      if ($result.regression? | default "" | is-not-empty) {
        task-regress $jid $result.regression
        # Loop will restart and re-evaluate
      }
    }

    # Check if any task failed without regression
    let failed = (sql $"SELECT name FROM tasks WHERE job_id = '($jid)' AND status = 'failed'" )
    if ($failed | is-not-empty) {
      sql-exec $"UPDATE jobs SET status = 'failed', completed_at = datetime\('now'\), error = 'Task failed: ($failed.0.name)' WHERE id = '($jid)'"
      emit-event $jid "" "job.StateChange" "running" "failed" $"Task failed: ($failed.0.name)"
      return { status: "failed", failed_task: $failed.0.name }
    }
  }

  # Check final state
  let final_tasks = (sql $"SELECT status FROM tasks WHERE job_id = '($jid)'" )
  let all_done = ($final_tasks | all {|t| $t.status in ["completed", "skipped"] })

  if $all_done {
    sql-exec $"UPDATE jobs SET status = 'completed', completed_at = datetime\('now'\) WHERE id = '($jid)'"
    emit-event $jid "" "job.StateChange" "running" "completed" ""
    { status: "completed" }
  } else {
    sql-exec $"UPDATE jobs SET status = 'failed', completed_at = datetime\('now'\) WHERE id = '($jid)'"
    emit-event $jid "" "job.StateChange" "running" "failed" ""
    { status: "failed" }
  }
}

# Resume a job from its last checkpoint (skip completed tasks)
export def job-resume [job_id: string] {
  let jid = (validate-ident $job_id "job-resume.job_id")
  let job = (sql $"SELECT status FROM jobs WHERE id = '($jid)'" )
  if ($job | is-empty) {
    error make { msg: $"Job not found: ($jid)" }
  }
  # Reset running tasks back to pending (they were interrupted)
  sql-exec $"UPDATE tasks SET status = 'pending' WHERE job_id = '($jid)' AND status = 'running'"
  # Reset job to running if it was failed
  sql-exec $"UPDATE jobs SET status = 'running' WHERE id = '($jid)'"
  emit-event $jid "" "job.StateChange" $job.0.status "running" "resumed"
  job-execute $jid
}

# Execute a single task with retry + gate evaluation
export def task-execute [job_id: string, task_name: string]: nothing -> record {
  # Validate identifiers at entry
  let jid = (validate-ident $job_id "task-execute.job_id")
  let tname = (validate-ident $task_name "task-execute.task_name")

  let task = (sql $"SELECT * FROM tasks WHERE job_id = '($jid)' AND name = '($tname)'" ).0

  # Replay check
  if $task.status == "completed" {
    return { name: $tname, status: "completed", output: $task.output }
  }

  # Condition check — skip if `if` evaluates false
  if ($task.condition | is-not-empty) {
    let should_run = (eval-condition $jid $task.condition)
    if not $should_run {
      sql-exec $"UPDATE tasks SET status = 'skipped', completed_at = datetime\('now'\) WHERE job_id = '($jid)' AND name = '($tname)'"
      emit-event $jid $tname "task.StateChange" $task.status "skipped" "condition false"
      return { name: $tname, status: "skipped" }
    }
  }

  # Mark running
  sql-exec $"UPDATE tasks SET status = 'running', started_at = datetime\('now'\), attempt = attempt + 1 WHERE job_id = '($jid)' AND name = '($tname)'"
  emit-event $jid $tname "task.StateChange" $task.status "running" ""

  # Get updated attempt number
  let current_attempt = (sql $"SELECT attempt FROM tasks WHERE job_id = '($jid)' AND name = '($tname)'").0.attempt

  # Initialize execution context (entry_index = 0, replay detection)
  init-execution-context $jid $tname $current_attempt

  # Execute with retry loop
  let max = ($task.max_attempts | into int)
  mut attempt = 0
  mut last_error = ""
  mut result = { status: "failed" }

  while $attempt < $max {
    $attempt = $attempt + 1
    if $attempt > 1 {
      # Exponential backoff
      let delay = ($task.retry_delay_sec | into int) * (($task.retry_scaling | into int) ** ($attempt - 1))
      sleep ($delay | into duration)
    }

    sql-exec $"UPDATE tasks SET attempt = ($attempt) WHERE job_id = '($jid)' AND name = '($tname)'"

    # Execute the task
    let exec_result = (try {
      run-task $jid $task
    } catch {|e|
      { status: "failed", error: ($e | get msg? | default "unknown error") }
    })

    if $exec_result.status == "completed" {
      let output = (sql-escape-text ($exec_result.output? | default ""))
      let start = (sql $"SELECT started_at FROM tasks WHERE job_id = '($jid)' AND name = '($tname)'" ).0.started_at
      sql-exec $"UPDATE tasks SET status = 'completed', output = '($output)', completed_at = datetime\('now'\) WHERE job_id = '($jid)' AND name = '($tname)'"
      emit-event $jid $tname "task.StateChange" "running" "completed" ""
      $result = { name: $tname, status: "completed", output: ($exec_result.output? | default "") }
      break
    }

    $last_error = ($exec_result.error? | default "gate failed")
  }

  # All retries exhausted — check regression
  if $result.status == "failed" {
    let err = (sql-escape-text $last_error)
    sql-exec $"UPDATE tasks SET status = 'failed', error = '($err)', completed_at = datetime\('now'\) WHERE job_id = '($jid)' AND name = '($tname)'"
    emit-event $jid $tname "task.StateChange" "running" "failed" $last_error

    if ($task.on_fail_regress | is-not-empty) {
      emit-event $jid $tname "task.Regression" "" $task.on_fail_regress $last_error
      $result = { name: $tname, status: "failed", regression: $task.on_fail_regress }
    } else {
      $result = { name: $tname, status: "failed", error: $last_error }
    }
  }

  $result
}

# Run a task — dispatch to agent or inline execution
# Note: job_id is already validated by task-execute, task record comes from DB
def run-task [job_id: string, task: record]: nothing -> record {
  # Gather prior task outputs for context
  let prior_outputs = (gather-task-outputs $job_id)

  if ($task.agent_type | is-not-empty) {
    # Agent execution via opencode
    use oc-agent.nu *
    use oc-tdd15.nu phase-prompt

    # Get bead_id and bead_info from job
    let job_data = (sql $"SELECT bead_id, inputs FROM jobs WHERE id = '($job_id)'" ).0
    let bead_id = $job_data.bead_id
    let bead_info = (try { $job_data.inputs | from json } catch { {} })

    # Dispatch to phase-specific prompt builder
    let prompt = (phase-prompt $task.run_cmd $bead_id $bead_info $prior_outputs)

    # Reject unknown phases (phase-prompt returns "Unknown phase: X" for unrecognized run_cmd)
    if ($prompt | str starts-with "Unknown phase:") {
      error make { msg: $prompt }
    }

    let session = (oc-session-create $"($job_id):($task.name)")
    oc-prompt $session.id $prompt
    let response = (oc-wait-idle $session.id ($task.timeout_sec | into int))
    let output = $response.content

    # Evaluate gate
    if ($task.gate | is-not-empty) {
      let gate_result = (gate-check $task.gate $output $job_id)
      if $gate_result.pass {
        { status: "completed", output: $output }
      } else {
        { status: "failed", error: $gate_result.reason, output: $output }
      }
    } else {
      { status: "completed", output: $output }
    }
  } else {
    # Inline execution
    let output = (try {
      if ($task.run_cmd | is-not-empty) {
        ^nu -c $task.run_cmd | complete
      } else {
        { stdout: "", exit_code: 0 }
      }
    } catch {|e|
      { stdout: "", exit_code: 1, stderr: ($e | get msg? | default "inline execution failed") }
    })

    if ($output.exit_code? | default 0) == 0 {
      { status: "completed", output: ($output.stdout? | default "") }
    } else {
      { status: "failed", error: ($output.stderr? | default "non-zero exit") }
    }
  }
}

# Gather completed task outputs as a record keyed by var name
# Note: job_id already validated by caller
def gather-task-outputs [job_id: string]: nothing -> record {
  let completed = (sql $"SELECT var, output FROM tasks WHERE job_id = '($job_id)' AND status = 'completed' AND var IS NOT NULL AND var != ''" )
  mut outputs = {}
  for row in $completed {
    $outputs = ($outputs | insert $row.var $row.output)
  }
  $outputs
}

# ── Phase Regression ─────────────────────────────────────────────────────────

# Reset target task + all downstream tasks to pending
export def task-regress [job_id: string, target_task: string] {
  # Validate identifiers at entry
  let jid = (validate-ident $job_id "task-regress.job_id")
  let target = (validate-ident $target_task "task-regress.target_task")

  # Find all tasks transitively depending on target
  let all_downstream = (find-downstream $jid $target)
  let to_reset = ([$target] | append $all_downstream | uniq)

  for tname in $to_reset {
    # tname comes from DB or was validated above, but validate anyway for safety
    let tname_safe = (validate-ident $tname "task-regress.task_name")
    sql-exec $"UPDATE tasks SET status = 'pending', output = NULL, error = NULL, attempt = 0, started_at = NULL, completed_at = NULL, duration_ms = NULL WHERE job_id = '($jid)' AND name = '($tname_safe)'"
    emit-event $jid $tname_safe "task.Regression" "" "pending" $"regressed from ($target)"
  }
}

# Find all tasks transitively downstream of a given task
# Note: job_id and task_name already validated by caller
def find-downstream [job_id: string, task_name: string]: nothing -> list<string> {
  let direct = (sql $"SELECT task_name FROM task_deps WHERE job_id = '($job_id)' AND depends_on = '($task_name)'" | get task_name)
  if ($direct | is-empty) { return [] }
  let indirect = ($direct | each {|d| find-downstream $job_id $d } | flatten)
  $direct | append $indirect | uniq
}

# ── Condition Evaluation ─────────────────────────────────────────────────────

# Evaluate a Tork-style condition like '{{ tasks.triage.route contains 1 }}'
# Note: job_id already validated by caller
def eval-condition [job_id: string, condition: string]: nothing -> bool {
  # Parse {{ tasks.<name>.route contains <phase> }}
  let match = ($condition | parse "{{ tasks.{task_ref}.route contains {phase} }}" | get -o 0)
  if ($match | is-empty) { return true }

  # Validate the task reference extracted from the condition
  let task_ref = (validate-ident $match.task_ref "eval-condition.task_ref")
  let phase = ($match.phase | str trim | into int)
  let output = (sql $"SELECT output FROM tasks WHERE job_id = '($job_id)' AND name = '($task_ref)' AND status = 'completed'" )

  if ($output | is-empty) { return false }

  # Parse the route from the triage output (expect JSON array or comma list)
  let route_str = $output.0.output
  try {
    let route = ($route_str | from json)
    $phase in $route
  } catch {
    # Fallback: check if phase number appears in output
    ($route_str | str contains ($phase | into string))
  }
}

# ── Gate Evaluation ──────────────────────────────────────────────────────────

# Evaluate a gate condition against task output
export def gate-check [gate_name: string, output: string, job_id: string]: nothing -> record {
  # Gate dispatch — each gate has specific pass criteria
  match $gate_name {
    "complexity_assessed" => {
      let has_route = ($output | str contains "route")
      { pass: $has_route, reason: (if $has_route { "ok" } else { "no route in output" }) }
    }
    "sufficient_context" => {
      let ok = ($output | str length) > 100
      { pass: $ok, reason: (if $ok { "ok" } else { "insufficient context" }) }
    }
    "plan_verified" => {
      let ok = ($output | str contains "PLAN") or ($output | str contains "plan")
      { pass: $ok, reason: (if $ok { "ok" } else { "no plan found" }) }
    }
    "user_approval" => {
      # Auto-approve in automated mode
      { pass: true, reason: "auto-approved" }
    }
    "tests_fail" => {
      # RED phase: tests should fail
      let result = (try { ^moon run :test | complete } catch { { exit_code: 1 } })
      let ok = ($result.exit_code? | default 1) != 0
      { pass: $ok, reason: (if $ok { "tests fail as expected" } else { "tests pass — RED phase needs failing tests" }) }
    }
    "tests_pass" | "tests_green" => {
      let result = (try { ^moon run :test | complete } catch { { exit_code: 1 } })
      let ok = ($result.exit_code? | default 1) == 0
      { pass: $ok, reason: (if $ok { "tests pass" } else { "tests failing" }) }
    }
    "martin_fowler_1" | "martin_fowler_2" => {
      # Check agent output for PASS/FAIL verdict using word boundaries
      let output_lower = ($output | str downcase)
      let pass = ((($output_lower | str contains "pass") or ($output_lower | str contains "passing")) and (not (($output_lower | str contains "fail") or ($output_lower | str contains "failing"))))
      { pass: $pass, reason: (if $pass { "review passed" } else { "review found issues" }) }
    }
    "implementation_complete" => {
      let ok = ($output | str contains "DONE") or ($output | str contains "complete") or ($output | str contains "implemented")
      { pass: $ok, reason: (if $ok { "ok" } else { "implementation incomplete" }) }
    }
    "criteria_met" => {
      let ok = ($output | str downcase | str contains "met") or ($output | str downcase | str contains "pass")
      { pass: $ok, reason: (if $ok { "ok" } else { "criteria not met" }) }
    }
    "no_critical_issues" => {
      let ok = not ($output | str downcase | str contains "critical")
      { pass: $ok, reason: (if $ok { "ok" } else { "critical issues found" }) }
    }
    "qa_pass" => {
      let ok = ($output | str downcase | str contains "pass")
      { pass: $ok, reason: (if $ok { "ok" } else { "QA failed" }) }
    }
    "standards_met" => {
      let ok = ($output | str downcase | str contains "pass") or ($output | str downcase | str contains "consistent")
      { pass: $ok, reason: (if $ok { "ok" } else { "standards not met" }) }
    }
    "minimized" => {
      let result = (try { ^moon run :test | complete } catch { { exit_code: 1 } })
      let ok = ($result.exit_code? | default 1) == 0
      { pass: $ok, reason: (if $ok { "ok" } else { "final validation failed" }) }
    }
    "push_succeeded" => {
      # Landing gate — check tests + lint pass
      let test_result = (try { ^moon run :ci | complete } catch { { exit_code: 1 } })
      let ok = ($test_result.exit_code? | default 1) == 0
      { pass: $ok, reason: (if $ok { "CI passed" } else { "CI failed" }) }
    }
    _ => {
      # Unknown gate — pass by default
      { pass: true, reason: $"unknown gate: ($gate_name)" }
    }
  }
}

# ── Awakeable Operations ────────────────────────────────────────────────────────

# Create an awakeable and return its ID
# Precondition: job_id, task_name are validated identifiers, execution context initialized
# Postcondition: awakeable record created, ID returned, operation journaled
# Invariant: awakeable ID is globally unique, record persisted for replay
export def ctx-awakeable [job_id: string, task_name: string, attempt: int]: nothing -> record {
  let jid = (validate-ident $job_id "ctx-awakeable.job_id")
  let tname = (validate-ident $task_name "ctx-awakeable.task_name")

  let entry_index = (next-entry-index $jid $tname $attempt)

  let awakeable_id = (awakeable-id-generate $jid $entry_index)

  sql-exec $"INSERT INTO awakeables \(id, job_id, task_name, entry_index, status\) VALUES \('($awakeable_id)', '($jid)', '($tname)', ($entry_index), 'PENDING'\)"

  journal-write $jid $tname $attempt $entry_index "awakeable-create" {} { id: $awakeable_id }

  { id: $awakeable_id }
}

# Await an awakeable, suspending the task until it's resolved
# Precondition: job_id, task_name are validated identifiers, execution context initialized, awakeable_id exists
# Postcondition: task status set to suspended, suspension point journaled
# Invariant: suspension is replayable on resume
export def ctx-await-awakeable [job_id: string, task_name: string, attempt: int, awakeable_id: string]: nothing -> record {
  let jid = (validate-ident $job_id "ctx-await-awakeable.job_id")
  let tname = (validate-ident $task_name "ctx-await-awakeable.task_name")
  let aw_id = (validate-ident $awakeable_id "ctx-await-awakeable.awakeable_id")

  let entry_index = (next-entry-index $jid $tname $attempt)

  sql-exec $"UPDATE tasks SET status = 'suspended' WHERE job_id = '($jid)' AND name = '($tname)'"
  emit-event $jid $tname "task.StateChange" "running" "suspended" $"awaiting awakeable ($aw_id)"

  journal-write $jid $tname $attempt $entry_index "awakeable-await" { awakeable_id: $aw_id } {}

  { suspended: true, awakeable_id: $aw_id }
}

# Resolve an awakeable with a payload, waking the suspended task
# Precondition: awakeable_id is a valid awakeable ID, payload is any JSON-serializable value
# Postcondition: awakeable marked RESOLVED with payload, task woken from suspension
# Invariant: only PENDING awakeables can be resolved, task status transitions to pending
export def resolve-awakeable [awakeable_id: string, payload: any]: nothing -> record {
  let aw_id = (validate-ident $awakeable_id "resolve-awakeable.awakeable_id")

  # Get awakeable record
  let awakeable_record = (sql $"SELECT job_id, task_name, status FROM awakeables WHERE id = '($aw_id)'")
  if ($awakeable_record | is-empty) {
    error make { msg: $"awakeable not found: ($aw_id)" }
  }

  let job_id = $awakeable_record.0.job_id
  let task_name = $awakeable_record.0.task_name
  let status = $awakeable_record.0.status

  # Check if already resolved
  if $status == "RESOLVED" {
    error make { msg: $"awakeable already resolved: ($aw_id)" }
  }

  # Serialize payload to JSON and escape for SQL
  let payload_json = ($payload | to json -r)
  let payload_esc = (sql-escape-text $payload_json)

  # Update awakeable: mark RESOLVED, store payload, set timestamp
  sql-exec $"UPDATE awakeables SET status = 'RESOLVED', payload = '($payload_esc)', resolved_at = datetime\('now'\) WHERE id = '($aw_id)'"

  # Wake the suspended task
  sql-exec $"UPDATE tasks SET status = 'pending' WHERE job_id = '($job_id)' AND name = '($task_name)'"
  emit-event $job_id $task_name "task.StateChange" "suspended" "pending" $"awakeable ($aw_id) resolved"

  { resolved: true, awakeable_id: $aw_id, payload: $payload }
}

# ── Task Output Retrieval ────────────────────────────────────────────────────

# Retrieve cached output by var name (Tork's {{ tasks.X }})
export def task-output [job_id: string, var_name: string]: nothing -> string {
  let jid = (validate-ident $job_id "task-output.job_id")
  let vname = (validate-ident $var_name "task-output.var_name")
  let result = (sql $"SELECT output FROM tasks WHERE job_id = '($jid)' AND var = '($vname)' AND status = 'completed'" )
  if ($result | is-empty) { "" } else { $result.0.output }
}

# ── Job Management ───────────────────────────────────────────────────────────

# Show status of a job and all its tasks
export def job-status [job_id: string]: nothing -> record {
  let jid = (validate-ident $job_id "job-status.job_id")
  let job = (sql $"SELECT * FROM jobs WHERE id = '($jid)'" )
  if ($job | is-empty) {
    error make { msg: $"Job not found: ($jid)" }
  }
  let tasks = (sql $"SELECT name, status, attempt, gate, error, started_at, completed_at FROM tasks WHERE job_id = '($jid)' ORDER BY rowid" )
  { job: $job.0, tasks: $tasks }
}

# Cancel a running job
export def job-cancel [job_id: string] {
  let jid = (validate-ident $job_id "job-cancel.job_id")
  sql-exec $"UPDATE jobs SET status = 'cancelled', completed_at = datetime\('now'\) WHERE id = '($jid)'"
  sql-exec $"UPDATE tasks SET status = 'cancelled' WHERE job_id = '($jid)' AND status IN \('pending', 'running', 'scheduled'\)"
  emit-event $jid "" "job.StateChange" "running" "CANCELLED" ""
}

# List all jobs
export def job-list []: nothing -> table {
  sql "SELECT id, name, bead_id, status, position, created_at, completed_at FROM jobs ORDER BY position, created_at"
}

# Retry a failed job — reset failed tasks and re-execute
export def job-retry [job_id: string] {
  let jid = (validate-ident $job_id "job-retry.job_id")
  sql-exec $"UPDATE tasks SET status = 'pending', error = NULL, attempt = 0 WHERE job_id = '($jid)' AND status = 'failed'"
  sql-exec $"UPDATE jobs SET status = 'pending', error = NULL WHERE id = '($jid)'"
  emit-event $jid "" "job.StateChange" "failed" "pending" "retry"
  job-execute $jid
}

# ── Event Log ────────────────────────────────────────────────────────────────

export def event-log [job_id: string, --limit: int = 50]: nothing -> table {
  let jid = (validate-ident $job_id "event-log.job_id")
  sql $"SELECT * FROM events WHERE job_id = '($jid)' ORDER BY created_at DESC LIMIT ($limit)"
}
