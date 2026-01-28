# OpenCode Workflow Engine

Nushell-based workflow orchestration engine for OpenCode. Implements TDD15 phase-based development using a DAG (Directed Acyclic Graph) execution model inspired by Tork. The system manages jobs, tasks, and dependencies with SQLite persistence and supports regression through task replay.

## Features

- **DAG Workflow Engine**: Topological sort-based execution using Kahn's algorithm
- **Tork-inspired Task Management**: Jobs, tasks, dependencies, and event logging
- **TDD15 Phases**: Complete 16-phase development workflow (triage through landing)
- **SQLite Persistence**: Durable job journal for crash recovery
- **Regression Support**: Task replay with downstream task reset
- **Retry Logic**: Exponential backoff with configurable scaling
- **Event Auditing**: Complete event log for debugging

## Quick Start

```bash
# Run all tests
moon run test

# Quick syntax validation
moon run quick

# Full CI pipeline
moon run ci

# Run workflow on beads
nu oc-orchestrate.nu run [--beads <id1,id2>]

# Resume from crash
nu oc-orchestrate.nu resume

# Check status
nu oc-orchestrate.nu status
```

## Architecture

### Core Modules

- **oc-agent.nu**: OpenCode HTTP API client for session management
- **oc-engine.nu**: DAG workflow engine with SQLite journal
- **oc-tdd15.nu**: TDD15 phase definitions and prompts
- **oc-orchestrate.nu**: Top-level CLI orchestrator

### TDD15 Phases

The TDD15 workflow supports three complexity routes:

- **Simple**: Phases [0, 4, 5, 6, 14, 15] - Triage, RED, GREEN, REFACTOR, Liability, Landing
- **Medium**: Phases [0, 1, 2, 4, 5, 6, 7, 9, 11, 15] - Adds Research, Plan, MF1, Verify Criteria, QA
- **Complex**: All 16 phases - Full research, planning, verification, and QA pipeline

## Testing

Uses Nushell's std testing framework:

```bash
# Run all tests
nu tests/run-all-tests.nu

# Run via Moon
moon run test
```

Test coverage includes:
- Constants and configuration validation
- Function signature testing
- Phase route mapping
- Job structure validation
- SQL escaping and injection safety

## Database Schema

The SQLite journal stores:
- **Jobs**: id, name, bead_id, inputs, status, position, timestamps
- **Tasks**: id, job_id, name, status, run_cmd, agent, gate, retry config
- **Dependencies**: task_deps (task-to-task), job_deps (job-to-job)
- **Events**: Complete event log for state changes
- **Webhooks**: Event-driven webhook subscriptions

## Moon Pipeline

Moon task runner configuration:

| Task | Description |
|-------|-------------|
| `test` | Run all tests using Nushell std testing |
| `check` | Syntax validation for all `.nu` files |
| `quick` | Quick validation (syntax + parse) |
| `ci` | Full CI pipeline (tests + validation) |

## Code Style

- **Functions**: `kebab-case` naming
- **Variables**: `snake_case` naming
- **Constants**: `SCREAMING_SNAKE_CASE`
- **Error Handling**: Try/catch with structured error records
- **Immutability**: Prefer functional patterns, avoid `mut` where possible

See [AGENTS.md](AGENTS.md) for detailed coding guidelines.

## License

See project LICENSE file.
