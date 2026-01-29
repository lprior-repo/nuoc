#!/usr/bin/env nu
# oc-dispatch.nu — Handler dispatch for different entity types
# Routes invocations to appropriate implementation based on entity type

use oc-entity.nu *
use ctx-basic.nu *
use ctx-object.nu *
use ctx-workflow.nu *

# ── Service Invocation (unlimited parallelism) ───────────────────────────────

export def "dispatch service" [
  entity_name: string
  handler_name: string
  input: any
] {
  # Verify entity exists and is a service
  let entity_type = (entity get-type $entity_name)

  if $entity_type != $ENTITY_TYPE_SERVICE {
    error make {
      msg: $"Entity ($entity_name) is not a service"
      label: {
        text: $"Entity type is ($entity_type), expected 'service'"
      }
    }
  }

  # Create BasicContext and invoke handler
  let ctx = (ctx-basic-create)
  let result = (ctx-basic invoke { |inp|
    # In real implementation, would look up and call the handler
    { status: "executed", handler: $handler_name, input: $inp }
  } $input)

  $result
}

# ── Virtual Object Invocation (single-writer per key) ────────────────────────

export def "dispatch virtual-object" [
  entity_name: string
  object_key: string
  handler_name: string
  handler_type: string  # "write" or "read"
  input: any
] {
  # Verify entity exists and is a virtual object
  let entity_type = (entity get-type $entity_name)

  if $entity_type != $ENTITY_TYPE_VIRTUAL_OBJECT {
    error make {
      msg: $"Entity ($entity_name) is not a virtual object"
      label: {
        text: $"Entity type is ($entity_type), expected 'virtual_object'"
      }
    }
  }

  # Generate invocation ID
  let invocation_id = $"($entity_name):($object_key):($handler_name):(date now | date to-record | get nanosecond)"

  if $handler_type == "write" {
    # Acquire lock for write handler
    let lock_result = (vo lock-acquire $entity_name $object_key $invocation_id)

    if not ($lock_result.acquired) {
      return {
        status: "queued",
        reason: "lock_held",
        holder: $lock_result.holder,
        acquired_at: $lock_result.acquired_at
      }
    }

    # Execute write handler
    let ctx = (ctx-object-create $entity_name $object_key)
    let result = { status: "executed", handler: $handler_name, input: $input }

    # Release lock
    vo lock-release $entity_name $object_key $invocation_id

    $result
  } else if $handler_type == "read" {
    # Read handlers don't need locks - can execute concurrently
    let ctx = (ctx-object-create $entity_name $object_key)
    let result = { status: "executed", handler: $handler_name, input: $input }

    $result
  } else {
    error make {
      msg: $"Invalid handler type: ($handler_type)"
      label: {
        text: "Must be 'write' or 'read'"
      }
    }
  }
}

# ── Workflow Invocation (exactly-once per workflow_id) ───────────────────────

export def "dispatch workflow" [
  workflow_name: string
  workflow_id: string
  handler_name: string
  input: any
] {
  # Verify entity exists and is a workflow
  let entity_type = (entity get-type $workflow_name)

  if $entity_type != $ENTITY_TYPE_WORKFLOW {
    error make {
      msg: $"Entity ($workflow_name) is not a workflow"
      label: {
        text: $"Entity type is ($entity_type), expected 'workflow'"
      }
    }
  }

  # Generate invocation ID
  let invocation_id = $"($workflow_name):($workflow_id):($handler_name):(date now | date to-record | get nanosecond)"

  if $handler_name == "run" {
    # Special handling for run handler - exactly-once semantics
    let run_result = (workflow run-start $workflow_name $workflow_id $invocation_id)

    if $run_result.status == "cached" {
      # Already executed - return cached result
      return {
        status: "cached",
        workflow_id: $workflow_id,
        result: $run_result.result
      }
    }

    # Execute run handler
    let ctx = (ctx-workflow-create $workflow_name $workflow_id)
    let result = { status: "executed", handler: $handler_name, input: $input }

    # Mark workflow as completed
    workflow run-complete $workflow_name $workflow_id ($result | to json)

    $result
  } else {
    # Signal handler - can execute concurrently with run
    let ctx = (ctx-workflow-shared-create $workflow_name $workflow_id)
    let result = { status: "executed", handler: $handler_name, input: $input }

    $result
  }
}

# ── Generic Dispatch (routes to appropriate implementation) ──────────────────

export def "dispatch invoke" [
  entity_name: string
  handler_name: string
  input: any
  --object-key: string  # For virtual objects
  --workflow-id: string  # For workflows
  --handler-type: string = "write"  # For VOs: "write" or "read"
] {
  # Get entity type
  let entity_type = (entity get-type $entity_name)

  if $entity_type == null {
    error make {
      msg: $"Entity not found: ($entity_name)"
    }
  }

  # Route to appropriate implementation
  if $entity_type == $ENTITY_TYPE_SERVICE {
    dispatch service $entity_name $handler_name $input
  } else if $entity_type == $ENTITY_TYPE_VIRTUAL_OBJECT {
    if $object_key == null {
      error make {
        msg: "Virtual objects require --object-key"
      }
    }
    dispatch virtual-object $entity_name $object_key $handler_name $handler_type $input
  } else if $entity_type == $ENTITY_TYPE_WORKFLOW {
    if $workflow_id == null {
      error make {
        msg: "Workflows require --workflow-id"
      }
    }
    dispatch workflow $entity_name $workflow_id $handler_name $input
  } else {
    error make {
      msg: $"Unknown entity type: ($entity_type)"
    }
  }
}
