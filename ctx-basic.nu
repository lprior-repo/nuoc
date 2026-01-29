#!/usr/bin/env nu
# ctx-basic.nu — BasicContext for Services (stateless, unlimited parallelism)
# Services have no state methods, only ctx.run for replay support

use ctx.nu "ctx run"

# ── BasicContext ──────────────────────────────────────────────────────────────
# For Services: Stateless logic with unlimited parallel execution
# No state manipulation methods - only ctx.run for deterministic replay

# Create a BasicContext for a service
export def ctx-basic-create [] {
  {
    context_type: "basic",
    has_state: false,
    parallelism: "unlimited"
  }
}

# Execute handler with BasicContext
export def "ctx-basic invoke" [
  handler: closure
  input: any
] {
  # Set up environment for basic context
  let old_job_id = ($env.JOB_ID? | default null)
  let old_task_name = ($env.TASK_NAME? | default null)
  let old_attempt = ($env.ATTEMPT? | default null)

  # Execute handler with replay support
  let result = (do $handler $input)

  # Restore environment
  if $old_job_id != null { $env.JOB_ID = $old_job_id }
  if $old_task_name != null { $env.TASK_NAME = $old_task_name }
  if $old_attempt != null { $env.ATTEMPT = $old_attempt }

  $result
}
