# Awakeables Implementation Summary

## Issue: nuoc-7mg - Implement awakeables — durable promises resolvable by external systems

**Status**: ✅ COMPLETED
**Priority**: P0 (Critical)
**Type**: Feature

## What Was Implemented

### 1. Core Awakeable Functionality (Already Existed)
The following functions were already implemented in `oc-engine.nu`:
- `ctx-awakeable()` - Create an awakeable
- `ctx-awakeable-timeout()` - Create an awakeable with timeout
- `ctx-await-awakeable()` - Suspend task until awakeable is resolved
- `resolve-awakeable()` - Resolve an awakeable with a payload
- `reject-awakeable()` - Reject an awakeable with an error
- `check-awakeable-timeouts()` - Process expired awakeables
- `cancel-job-awakeables()` - Cancel all awakeables for a job

### 2. CLI Tool (`oc-cli.nu`) - NEW
Created a comprehensive CLI tool for awakeable and job management:

**Awakeable Commands:**
- `nu oc-cli.nu awakeable resolve <id> --payload <data>` - Resolve an awakeable
- `nu oc-cli.nu awakeable resolve <id> --file <path>` - Resolve with payload from file
- `nu oc-cli.nu awakeable reject <id> --error <msg>` - Reject an awakeable
- `nu oc-cli.nu awakeable list [--job <id>] [--status <status>]` - List awakeables
- `nu oc-cli.nu awakeable show <id>` - Show awakeable details

**Job Commands:**
- `nu oc-cli.nu job status <id>` - Show job status
- `nu oc-cli.nu job list` - List all jobs
- `nu oc-cli.nu job cancel <id>` - Cancel a job
- `nu oc-cli.nu job retry <id>` - Retry a failed job

**System Commands:**
- `nu oc-cli.nu timeout check` - Check and process expired awakeable timeouts
- `nu oc-cli.nu events [--job <id>] [--limit <n>]` - View event log

### 3. User Approval Gate Integration - NEW
Refactored the `user_approval` gate to use awakeables instead of auto-approving:

**Before:**
```nu
"user_approval" => {
  # Auto-approve in automated mode
  { pass: true, reason: "auto-approved" }
}
```

**After:**
- When `user_approval` gate is evaluated, the system:
  1. Creates an awakeable for the approval
  2. Suspends the task (status: `suspended`)
  3. Waits for external resolution via CLI or HTTP
  4. Resumes and completes (approve) or fails (reject) based on resolution

### 4. HTTP API (Already Existed)
The HTTP server in `oc-http-server.py` already provided:
- `POST /awakeables/:id/resolve` - Resolve an awakeable via HTTP
- `GET /health` - Health check endpoint

### 5. Documentation - NEW
Created comprehensive documentation in `docs/awakeables.md`:
- Overview and core concepts
- CLI command reference
- HTTP API documentation
- Programmatic usage examples
- User approval gate guide
- Crash recovery explanation
- Complete approval flow example
- Testing instructions
- Architecture details

### 6. Tests - NEW
Added comprehensive test coverage:

**CLI Tests (`tests/test-cli-awakeable.nu`):**
- Test resolve command
- Test reject command
- Test show/query command

**User Approval Tests (`tests/test-user-approval-awakeable.nu`):**
- Test awakeable creation for approval
- Test rejection fails task
- Test timeout handling

**Existing Tests (Already Passed):**
- `tests/test-resolve-awakeable.nu` - Core resolve functionality
- `tests/test-awakeable-suspension.nu` - Task suspension
- `tests/test-awakeable-timeout.nu` - Timeout handling
- `tests/test-awakeable-http-endpoint.nu` - HTTP API
- `tests/test-awakeable-cleanup.nu` - Job cleanup
- `tests/test-duplicate-resolution-rejection.nu` - Duplicate rejection
- `tests/test-task-wake-and-resume.nu` - Task wake/resume
- `tests/test-reject-awakeable.nu` - Rejection handling

## ATDD Requirements - All Met ✅

1. ✅ **CLI command**: `oc awakeable resolve <id> --payload <data>`
   - Implemented in `oc-cli.nu`
   - Supports JSON and plain text payloads
   - Supports loading payload from file

2. ✅ **HTTP endpoint**: POST /awakeables/:id/resolve
   - Already existed in `oc-http-server.py`
   - Fully functional with error handling

3. ✅ **Awakeable state persisted in journal, survives crash**
   - All awakeable operations journaled
   - Deterministic replay on engine restart
   - Suspension state restored from journal

4. ✅ **user_approval gate refactored to use awakeable**
   - Modified `run-task()` in `oc-engine.nu`
   - Creates awakeable and suspends task
   - Resumes based on external resolution

## EARS Requirements - All Met ✅

- ✅ **WHEN a task calls ctx.awakeable()**, THE SYSTEM SHALL generate a unique awakeable ID, persist it in the journal, and suspend the task.
- ✅ **WHEN an external system calls resolve-awakeable with the ID and a payload**, THE SYSTEM SHALL resume the suspended task with that payload.
- ✅ **IF the engine crashes while a task is suspended on an awakeable**, THE SYSTEM SHALL restore the suspension state on recovery and continue waiting.
- ✅ **WHERE an awakeable has a timeout**, THE SYSTEM SHALL fail the awakeable if not resolved within the timeout.

## BDD Scenarios - All Working ✅

### Scenario: Human approval via awakeable ✅
```bash
# Task creates awakeable
nu oc-cli.nu awakeable list

# User approves
nu oc-cli.nu awakeable resolve prom_1abc123 --payload '{"action":"approve"}'

# Task resumes and completes
```

### Scenario: Webhook resolves awakeable ✅
```bash
# Webhook callback
curl -X POST http://localhost:4097/awakeables/prom_1abc123/resolve \
  -H "Content-Type: application/json" \
  -d '{"action":"deploy","status":"success"}'

# Task resumes with webhook payload
```

### Scenario: Awakeable survives crash ✅
- Awakeable state persisted to journal
- Engine crash recovery replays from journal
- Task suspension state restored
- Resolution still works after crash

### Scenario: Awakeable timeout ✅
```nu
# Create awakeable with 300s timeout
let awakeable = (ctx-awakeable-timeout $job_id $task_name $attempt 300)

# After 300s without resolution, awakeable marked TIMEOUT
# Task fails with timeout error
```

## Test Results

All tests passing:
```
== Test Summary ==
Total test suites: 3
Passed: 3
Failed: 0
```

Specific awakeable tests:
- ✅ Core resolve functionality
- ✅ Task suspension
- ✅ Timeout handling
- ✅ HTTP endpoint
- ✅ Job cleanup
- ✅ Duplicate rejection
- ✅ Task wake/resume
- ✅ CLI commands
- ✅ User approval gate

## Files Modified/Created

### Modified:
- `oc-engine.nu` - Refactored user_approval gate to use awakeables

### Created:
- `oc-cli.nu` - CLI tool for awakeable and job management
- `docs/awakeables.md` - Comprehensive documentation
- `tests/test-cli-awakeable.nu` - CLI command tests
- `tests/test-user-approval-awakeable.nu` - User approval gate tests

## Usage Example

### Complete Approval Flow

```bash
# 1. Start workflow (creates job with user_approval gate)
nu oc-orchestrate.nu run

# 2. Check job status (shows suspended task)
nu oc-cli.nu job status test-job-1
# Output: [z] verify [suspended] [gate: user_approval]

# 3. List awakeables to find the ID
nu oc-cli.nu awakeable list --job test-job-1
# Output: [·] prom_1abc123
#         Job: test-job-1
#         Task: verify
#         Status: PENDING

# 4. Approve via CLI
nu oc-cli.nu awakeable resolve prom_1abc123 --payload '{"action":"approve"}'

# 5. Task resumes and completes
nu oc-cli.nu job status test-job-1
# Output: ✓ verify [COMPLETED]
```

### Alternative: HTTP API

```bash
# Approve via HTTP
curl -X POST http://localhost:4097/awakeables/prom_1abc123/resolve \
  -H "Content-Type: application/json" \
  -d '{"action":"approve"}'
```

### Alternative: Reject

```bash
# Reject via CLI
nu oc-cli.nu awakeable reject prom_1abc123 --error "approval denied"

# Reject via HTTP
curl -X POST http://localhost:4097/awakeables/prom_1abc123/resolve \
  -H "Content-Type: application/json" \
  -d '{"action":"reject","reason":"quality issues"}'
```

## Design By Contract Compliance

### Preconditions ✅
- Awakeable ID is unique and generated by the engine
- job_id and task_name are validated identifiers
- timeout_sec is positive (for timeout variant)

### Postconditions ✅
- Exactly one resolution per awakeable ID (duplicate rejection enforced)
- Suspended task consumes zero execution resources until resolved
- Journal entry created for all awakeable operations

### Invariants ✅
- Awakeable state transitions: PENDING → (RESOLVED | REJECTED | TIMEOUT | CANCELLED)
- Task status transitions: running → suspended → pending (on resolution)
- No duplicate resolutions allowed (409 conflict)

## Next Steps

The awakeables feature is now fully implemented and ready for use. Potential future enhancements:

1. **OR groups** - Wait for first of multiple conditions (blocked by nuoc-8nn)
2. **Awakeable workflows** - Complex multi-awakeable coordination
3. **Webhook registration** - Automatic webhook delivery on awakeable creation
4. **Approval UI** - Web interface for approving awakeables
5. **Batch operations** - Resolve/reject multiple awakeables at once

## Conclusion

Awakeables are now fully functional with:
- ✅ CLI commands for all operations
- ✅ HTTP API for external system integration
- ✅ User approval gate integration
- ✅ Timeout support
- ✅ Crash recovery
- ✅ Comprehensive test coverage
- ✅ Complete documentation

The implementation satisfies all ATDD requirements, EARS requirements, and BDD scenarios specified in issue nuoc-7mg.
