# Awakeables — Durable Promises for External Signals

## Overview

Awakeables are durable promises that allow workflows to suspend execution and wait for external signals. They enable:

- **Human-in-the-loop approval**: Tasks can wait for manual approval
- **Webhook callbacks**: External systems can resume workflows via HTTP callbacks
- **Cross-workflow coordination**: Workflows can signal each other
- **Timeout handling**: Automatic failure if no response within timeout period

## Core Concepts

An awakeable has three states:

1. **PENDING**: Created and waiting for resolution
2. **RESOLVED**: Successfully resolved with a payload
3. **REJECTED**: Rejected with an error message
4. **TIMEOUT**: Expired without resolution
5. **CANCELLED**: Job was cancelled

## CLI Commands

### Resolve an Awakeable

```bash
# Resolve with JSON payload
nu oc-cli.nu awakeable resolve <awakeable_id> --payload '{"action":"approve"}'

# Resolve with plain text payload
nu oc-cli.nu awakeable resolve <awakeable_id> --payload "approved"

# Read payload from file
nu oc-cli.nu awakeable resolve <awakeable_id> --file payload.json
```

### Reject an Awakeable

```bash
# Reject with default error message
nu oc-cli.nu awakeable reject <awakeable_id>

# Reject with custom error message
nu oc-cli.nu awakeable reject <awakeable_id> --error "approval denied"
```

### List Awakeables

```bash
# List all awakeables
nu oc-cli.nu awakeable list

# Filter by job ID
nu oc-cli.nu awakeable list --job <job_id>

# Filter by status (PENDING, RESOLVED, REJECTED, TIMEOUT, CANCELLED)
nu oc-cli.nu awakeable list --status PENDING
```

### Show Awakeable Details

```bash
nu oc-cli.nu awakeable show <awakeable_id>
```

## HTTP API

### Resolve Awakeable

```bash
curl -X POST http://localhost:4097/awakeables/<awakeable_id>/resolve \
  -H "Content-Type: application/json" \
  -d '{"action":"approve","data":{"key":"value"}}'
```

Response:
```json
{
  "success": true,
  "awakeable_id": "prom_1abc123",
  "payload": {"action":"approve","data":{"key":"value"}},
  "message": "Awakeable resolved successfully"
}
```

Error Responses:

- `404` - Awakeable not found
- `409` - Awakeable not in PENDING state (already resolved/rejected)
- `400` - Invalid JSON payload

### Health Check

```bash
curl http://localhost:4097/health
```

## Programmatic Usage

### Creating an Awakeable in a Task

```nu
use oc-engine.nu *

# In your task execution context:
let awakeable = (ctx-awakeable $env.JOB_ID $env.TASK_NAME $env.ATTEMPT)
let awakeable_id = $awakeable.id

# Send the awakeable_id to external system (e.g., webhook, notification)
# Task will suspend when you await it
```

### Awaiting an Awakeable

```nu
# Suspend task until awakeable is resolved
let result = (ctx-await-awakeable $env.JOB_ID $env.TASK_NAME $env.ATTEMPT $awakeable_id)

if $result.suspended {
  # Task is suspended, waiting for external resolution
  return { status: "suspended", awakeable_id: $result.awakeable_id }
} else if $result.resumed {
  # Task resumed with payload
  let payload = $result.payload
  # Continue execution with payload
}
```

### Creating an Awakeable with Timeout

```nu
# Create awakeable that expires after 300 seconds
let awakeable = (ctx-awakeable-timeout $env.JOB_ID $env.TASK_NAME $env.ATTEMPT 300)
```

## User Approval Gate

The `user_approval` gate now uses awakeables instead of auto-approving:

```yaml
tasks:
  - name: deploy
    agent:
      type: opencode
      model: claude-opus-4
    run: deploy
    gate: user_approval  # Creates awakeable and suspends task
```

When the task runs:

1. Agent produces output
2. System creates an awakeable for approval
3. Task suspends (status: `suspended`)
4. External system resolves awakeable with `{"action":"approve"}` or `{"action":"reject"}`
5. Task resumes and completes or fails based on approval

### Resolving User Approval

```bash
# Approve
nu oc-cli.nu awakeable resolve <awakeable_id> --payload '{"action":"approve"}'

# Reject
nu oc-cli.nu awakeable resolve <awakeable_id> --payload '{"action":"reject"}'
```

## Job Commands

### Show Job Status

```bash
nu oc-cli.nu job status <job_id>
```

### List Jobs

```bash
nu oc-cli.nu job list
```

### Cancel Job

```bash
nu oc-cli.nu job cancel <job_id>
```

### Retry Failed Job

```bash
nu oc-cli.nu job retry <job_id>
```

## System Commands

### Check Awakeable Timeouts

```bash
nu oc-cli.nu timeout check
```

### View Event Log

```bash
# Show recent events
nu oc-cli.nu events

# Filter by job
nu oc-cli.nu events --job <job_id>

# Limit results
nu oc-cli.nu events --limit 100
```

## Crash Recovery

Awakeables are durable and survive engine crashes:

1. Task creates awakeable → persisted to journal
2. Engine crashes
3. Engine restarts and replays from journal
4. Task suspended state is restored
5. Awakeable can still be resolved via CLI or HTTP
6. Task resumes normally

## Example: Complete Approval Flow

```bash
# 1. Start workflow
nu oc-orchestrate.nu run

# 2. Workflow creates awakeable for approval
# (Task suspends, status: "suspended")

# 3. Check job status to see awakeable
nu oc-cli.nu job status <job_id>
# Output: ✓ verify [suspended] [gate: user_approval]

# 4. List awakeables to find the ID
nu oc-cli.nu awakeable list --job <job_id>
# Output: [·] prom_1abc123
#           Job: test-job-1
#           Task: verify
#           Status: PENDING

# 5. Resolve awakeable (approve)
nu oc-cli.nu awakeable resolve prom_1abc123 --payload '{"action":"approve"}'

# 6. Task resumes and completes
# Job status shows: ✓ verify [COMPLETED]
```

## Testing

Run awakeable tests:

```bash
# Core awakeable functionality
nu tests/test-resolve-awakeable.nu
nu tests/test-awakeable-suspension.nu
nu tests/test-awakeable-timeout.nu

# CLI commands
nu tests/test-cli-awakeable.nu

# User approval gate
nu tests/test-user-approval-awakeable.nu

# All tests
moon run :test
```

## Architecture

### Database Schema

```sql
CREATE TABLE awakeables (
  id TEXT PRIMARY KEY,              -- Globally unique ID (prom_1<base64>)
  job_id TEXT NOT NULL,             -- Parent job
  task_name TEXT NOT NULL,          -- Parent task
  entry_index INTEGER NOT NULL,     -- Journal position
  status TEXT DEFAULT 'PENDING',    -- Current state
  payload TEXT,                     -- Resolution payload (JSON)
  timeout_at TEXT,                  -- Expiration timestamp
  created_at TEXT DEFAULT (datetime('now')),
  resolved_at TEXT                  -- Resolution timestamp
);

CREATE INDEX idx_awakeables_job_task ON awakeables(job_id, task_name);
```

### Awakeable ID Format

Awakeable IDs follow the Restate format: `prom_1<base64url(job_id:entry_index)>`

Example: `prom_1am9vLWpvYi0xOjA=`

Parse with:
```nu
let parsed = (awakeable-id-parse "prom_1am9vLWpvYi0xOjA=")
# Returns: { invocation_id: "my-job-1", entry_index: 0 }
```

## Design By Contract

### Preconditions
- Awakeable ID is unique and generated by the engine
- job_id and task_name are validated identifiers
- timeout_sec is positive (for timeout variant)

### Postconditions
- Exactly one resolution per awakeable ID
- Suspended task consumes zero execution resources until resolved
- Journal entry created for all awakeable operations

### Invariants
- Awakeable state transitions: PENDING → (RESOLVED | REJECTED | TIMEOUT | CANCELLED)
- Task status transitions: running → suspended → pending (on resolution)
- No duplicate resolutions allowed (409 conflict)
