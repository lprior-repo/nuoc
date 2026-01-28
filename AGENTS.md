# OpenCode Workflow Engine - Agent Guidelines

## Project Overview

Nushell-based workflow orchestration engine for OpenCode. Implements TDD15 phase-based development using DAG execution (Tork-inspired) with SQLite persistence and regression support.

## Build/Test/Lint Commands

**Primary Tooling**: Moon task runner

```bash
# Run all tests
moon run :test

# Type checking
moon run :check

# Format + lint (quick validation)
moon run :quick

# Full CI pipeline (tests + type check + lint)
moon run :ci

# Run a single test file (adjust pattern as needed)
moon run :test --filter "test_name_pattern"
```

**Workflow Commands**:

```bash
# Run TDD15 workflow on beads
nu oc-orchestrate.nu run [--beads <id1,id2>] [--port 4096] [--dry-run]

# Resume from crash/checkpoint
nu oc-orchestrate.nu resume

# View status
nu oc-orchestrate.nu status

# Retry failed job
nu oc-orchestrate.nu retry --job <job_id>

# Cancel running job
nu oc-orchestrate.nu cancel --job <job_id>

# List all jobs
nu oc-orchestrate.nu list

# View event log
nu oc-orchestrate.nu events --job <job_id> [--limit 50]
```

## Code Style Guidelines

### Nushell Conventions

**Function Definitions**:
- Use `export def` for public functions
- Include type signatures: `def func_name [param: type]: nothing -> return_type`
- Default parameters: `--flag: int = 4096`
- Optional parameters: `param?: string`
- Pipeline operators: `|` for data transformation

**Constants**: Define at module level with `const`, use `SCREAMING_SNAKE_CASE`

**String Formatting**: Use interpolation `$"hello ($name)"`, use `str replace --all` for bulk replacement

**Error Handling**:
```nu
try {
  risky_operation
} catch {|e|
  { status: "FAILED", error: ($e | get msg? | default "unknown error") }
}
```

**Record & List Operations**:
- Create: `{ key: "value", nested: { field: 1 } }`
- Access: `$record.field` or `$record.field?` (safe access)
- Filter: `list | where status == "PENDING"`
- Transform: `list | each {|item| transform($item) }`
- Parallel: `list | par-each {|item| expensive_op($item) }`
- Remove nulls: `list | compact`

**SQL Integration**:
- Read: `sqlite3 -json $DB_PATH "query" | from json`
- Write: `sql-exec "INSERT/UPDATE/DELETE ..."`
- Escape inputs with `sql-escape`

### Naming Conventions

**Functions**: `kebab-case` - `def job-create [...]`
**Variables**: `snake_case` - `let job_id = ...`
**Constants**: `SCREAMING_SNAKE_CASE` - `const DEFAULT_PORT = 4096`
**Database Columns**: `snake_case` - `created_at`, `job_id`

### Type Patterns

**Return Types**: `nothing -> string|record|list<record>|list<string>`

**Common Types**: `record`, `list<type>`, `string`, `int`, `bool`

**Null Handling**:
- Check empty: `if ($value | is-empty)`
- Safe access: `$value.field? | default "fallback"`
- Remove nulls: `list | compact`

### Error Handling Patterns

**Try/Catch**:
```nu
let result = (try { risky_operation } catch {|e|
  error make { msg: $"Operation failed: ($e | get msg? | default 'unknown')" }
})
```

**Return Error Record**: `return { status: "FAILED", error: "description" }`

**Default Fallback**: `let value = ($record.field? | default "default_value")`

**Check Empty**:
```nu
if ($list | is-empty) { print "No items found"; return }
```

### Architecture Patterns

**Task Execution**: Use `par-each` for parallel independent ops, `each` for sequential dependent ops. Handle errors in parallel blocks.

**Database Queries**: Read with `sql "SELECT ..."`, write with `sql-exec`, escape inputs.

**State Management**: Prefer immutability, use functional patterns, avoid `mut` when possible.

**Event Logging**: `emit-event $job_id $task_name "task.StateChange" $old $new $payload`

### Module Organization

**File Structure**:
- `oc-agent.nu` - OpenCode HTTP API client
- `oc-engine.nu` - DAG workflow engine + SQLite journal
- `oc-tdd15.nu` - TDD15 phase definitions + prompts
- `oc-orchestrate.nu` - Top-level CLI orchestrator

**Import Pattern**: `use oc-engine.nu *`

### Gates and Phase Checks

**Gate Evaluation**: Return `{ pass: bool, reason: string }`. Default to pass for unknown gates (fail-safe).

**Phase Routing**: Routes in `oc-tdd15.nu` (PHASES_SIMPLE, PHASES_MEDIUM, PHASES_COMPLEX). Conditional: `if: "{{ tasks.triage.route contains 1 }}"`. Regression: `on_fail: { regress_to: "phase_name" }`.

### Testing

**TDD15 Workflow**: RED (fail) → GREEN (pass) → REFACTOR. Tests must fail initially. Minimal implementation to pass. Refactor without breaking.

**Commands**: `moon run :test` (all), `moon run :test --filter <pattern>` (filtered), `moon run :quick` (format + lint)

## Database Schema

**Jobs Table**: id, name, bead_id, inputs, defaults, status (PENDING/RUNNING/COMPLETED/FAILED/CANCELLED), position, timestamps, error, result

**Tasks Table**: id (job_id:task_name), job_id, name, var, status, run_cmd, agent_type, agent_model, gate, condition, on_fail_regress, priority, timeout_sec, input, output, error, attempt, max_attempts, retry_delay_sec, retry_scaling

**Dependencies**: task_deps (task-to-task), job_deps (job-to-job)

**Events**: event log for auditing

**Webhooks**: webhook subscriptions

## Important Notes

1. **No comments** - Code should be self-documenting
2. **Immutability preferred** - Use functional patterns
3. **Parallel execution** - Use `par-each` for independent tasks
4. **Error propagation** - Always return structured error records
5. **SQL injection** - Always escape user inputs with `sql-escape`
6. **Event logging** - Log state changes for debugging
7. **Regression** - Support task regression via `task-regress`
8. **Replay safety** - Check task status before execution to avoid rework

## Landing the Plane (Session Completion)

**When ending a work session**, you MUST complete ALL steps below. Work is NOT complete until `git push` succeeds.

**MANDATORY WORKFLOW:**

1. **File issues for remaining work** - Create issues for anything that needs follow-up
2. **Run quality gates** (if code changed) - Tests, linters, builds
3. **Update issue status** - Close finished work, update in-progress items
4. **PUSH TO REMOTE** - This is MANDATORY:
   ```bash
   git pull --rebase
   bd sync
   git push
   git status  # MUST show "up to date with origin"
   ```
5. **Clean up** - Clear stashes, prune remote branches
6. **Verify** - All changes committed AND pushed
7. **Hand off** - Provide context for next session

**CRITICAL RULES:**
- Work is NOT complete until `git push` succeeds
- NEVER stop before pushing - that leaves work stranded locally
- NEVER say "ready to push when you are" - YOU must push
- If push fails, resolve and retry until it succeeds
