# 8-State Invocation Lifecycle Implementation Status

## Completed (Phase 1-5)

### Core State Machine Functions ✅
- `is-valid-transition`: Validates state transitions per Restate spec
- `transition-state`: Atomic state transition with validation and event emission
- `job-pickup`: Transitions pending → ready (processor acknowledgement)
- `calc-next-retry-at`: Exponential backoff calculation
- `job-scheduler-poll`: Finds scheduled jobs ready to run
- `job-retry-poll`: Finds backing-off jobs ready for retry

### Database Schema ✅
All required fields already exist in jobs table:
- `scheduled_start_at`: For delayed invocation
- `completion_result`: Records 'success' or 'failure'
- `completion_failure`: Error details on failure
- `next_retry_at`: When to retry
- `retry_count`: Current retry attempt
- `last_failure`: Last error message
- `last_failure_code`: Error code

### State Constants ✅
All 8 states defined:
- pending, scheduled, ready, running, suspended, backing-off, paused, completed

### State Transition Matrix ✅
Valid transitions enforced:
- Entry: pending → ready, pending → scheduled, scheduled → ready
- Execution: ready → running, running → suspended/backing-off/completed
- Recovery: suspended → running, backing-off → running, paused → running
- Failure: backing-off → paused/completed

### Tests ✅
- `tests/test-8state-lifecycle.nu`: Comprehensive test suite
- All state constants defined
- Transition validation works correctly
- Manual testing confirms functions work

## Remaining Integration Work

### High Priority
1. **Update `job-execute`**: Require ready state on entry, transition to running
2. **Update `task-execute`**: Use backing-off on retriable failure instead of immediate fail
3. **Update `awakeable-await`**: Suspend job while waiting
4. **Update `awakeable-resolve/reject`**: Resume suspended jobs
5. **Update `job-resume`**: Handle paused state

### Medium Priority
6. **Update `job-create`**: Use scheduled state if invoke_time set
7. **Update `job-cancel`**: Handle all active states
8. **Update completion logic**: Record completion_result properly

### Low Priority
9. **Add polling scheduler**: Background process to call job-scheduler-poll
10. **Add retry scheduler**: Background process to call job-retry-poll

## State Machine Diagram

```
                    ┌─────────────┐
                    │   pending   │ (initial)
                    └──────┬──────┘
                           │
           ┌───────────────┴───────────────┐
           │                               │
           ▼                               ▼
    ┌─────────────┐                 ┌─────────────┐
    │  scheduled  │                 │    ready    │
    └──────┬──────┘                 └──────┬──────┘
           │                               │
           │ (time reached)                │
           └───────────────────────────────┘
                                           │
                                           ▼
                                    ┌─────────────┐
                    ┌──────────────▶│   running   │◀─────────┐
                    │               └──────┬──────┘          │
                    │                      │                 │
                    │     ┌────────────────┼────────────────┤
                    │     │                │                │
                    ▼     ▼                ▼                ▼
              ┌──────────┐        ┌──────────┐      ┌──────────┐
              │suspended │        │backing-off│      │completed │
              └────┬─────┘        └────┬─────┘      └──────────┘
                   │                  │
                   │ (resolved)       │ ├─────────────┐
                   │                  │ │             │
                   └──────────────────┘ ▼             ▼
                                       ┌──────────┐ ┌──────────┐
                                       │  paused  │ │completed │
                                       └────┬─────┘ └──────────┘
                                            │
                                            │ (manual resume)
                                            └───────────────────┘
```

## Testing Strategy

### Unit Tests (✅ Completed)
- State constants defined
- Transition validation
- Individual state transitions
- Exponential backoff calculation
- Poll functions return correct types

### Integration Tests (Remaining)
- Full lifecycle: pending → scheduled → ready → running → completed
- Full lifecycle: running → suspended → running → completed
- Full lifecycle: running → backing-off → running → completed
- Full lifecycle: backing-off → paused → running → completed
- Retry with exponential backoff
- Scheduled invocation fires at correct time

## Next Steps for Full Integration

1. **Modify existing functions** to use new state transitions:
   - `job-execute`: Check for ready state, transition to running
   - `task-execute`: On failure, call `transition-state` to backing-off
   - `awakeable-await`: Call `transition-state` to suspended
   - `awakeable-resolve/reject`: Call `transition-state` to running

2. **Add background schedulers**:
   - Call `job-scheduler-poll` every second
   - Call `job-retry-poll` every second

3. **Update completion logic**:
   - Set `completion_result` on job completion
   - Set `completion_failure` on failure

4. **Run full integration tests**

## Compatibility Notes

- Existing 5-state system still works (pending, running, completed, failed, cancelled)
- New states are additive, not breaking
- Gradual migration path: use new functions where appropriate
- Database schema already supports all 8 states

## Files Modified

- `oc-engine.nu`: Added 6 new functions, state transition matrix
- `tests/test-8state-lifecycle.nu`: Comprehensive test suite (NEW)

## Files to Modify (Remaining)

- `oc-engine.nu`: Update job-execute, task-execute, awakeable handlers, job-resume, job-create, job-cancel

## References

- Restate State Machine: https://docs.restate.dev/dev/state_machine
- Issue: nuoc-mnw
- Bead Description: "Implement 8-state invocation lifecycle — exact Restate state machine"
