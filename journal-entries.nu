#!/usr/bin/env nu
# journal-entries.nu — Complete Restate Journal Entry Types
# Exact parity with Restate's journal protocol

# ── Entry Type Codes (Restate Protocol) ─────────────────────────────────────

# Input/Output
export const ENTRY_INPUT = 0x0400
export const ENTRY_OUTPUT = 0x0401

# State Operations
export const ENTRY_GET_STATE = 0x0800
export const ENTRY_SET_STATE = 0x0801
export const ENTRY_CLEAR_STATE = 0x0802
export const ENTRY_CLEAR_ALL_STATE = 0x0803
export const ENTRY_GET_STATE_KEYS = 0x0804

# Promise Operations
export const ENTRY_GET_PROMISE = 0x0808
export const ENTRY_PEEK_PROMISE = 0x0809
export const ENTRY_COMPLETE_PROMISE = 0x080A

# Durable Operations
export const ENTRY_SLEEP = 0x0C00
export const ENTRY_CALL = 0x0C01
export const ENTRY_ONE_WAY_CALL = 0x0C02
export const ENTRY_AWAKEABLE = 0x0C03
export const ENTRY_COMPLETE_AWAKEABLE = 0x0C04
export const ENTRY_RUN = 0x0C05

# Invocation Management
export const ENTRY_CANCEL_INVOCATION = 0x0C06
export const ENTRY_GET_CALL_INVOCATION_ID = 0x0C07
export const ENTRY_ATTACH_INVOCATION = 0x0C08
export const ENTRY_GET_INVOCATION_OUTPUT = 0x0C09
export const ENTRY_SEND_SIGNAL = 0x0C0A

# Entry Flags
export const FLAG_COMPLETABLE = 0x01
export const FLAG_FALLIBLE = 0x02
export const FLAG_COMPLETED = 0x04
export const FLAG_FAILED = 0x08

# ── Entry Type Registry ──────────────────────────────────────────────────────

export const ENTRY_TYPES = {
  "0x0400": {
    name: "InputCommandMessage",
    code: 0x0400,
    flags: 0,
    completable: false,
    fallible: false,
    description: "Invocation input with headers and value"
  },
  "0x0401": {
    name: "OutputCommandMessage",
    code: 0x0401,
    flags: 0,
    completable: false,
    fallible: false,
    description: "Return value or failure"
  },
  "0x0800": {
    name: "GetStateCommandMessage",
    code: 0x0800,
    flags: 3,
    completable: true,
    fallible: true,
    description: "Retrieve state value (lazy/eager)"
  },
  "0x0801": {
    name: "SetStateCommandMessage",
    code: 0x0801,
    flags: 1,
    completable: true,
    fallible: false,
    description: "Set state key-value"
  },
  "0x0802": {
    name: "ClearStateCommandMessage",
    code: 0x0802,
    flags: 1,
    completable: true,
    fallible: false,
    description: "Delete state key"
  },
  "0x0803": {
    name: "ClearAllStateCommandMessage",
    code: 0x0803,
    flags: 1,
    completable: true,
    fallible: false,
    description: "Delete all state"
  },
  "0x0804": {
    name: "GetStateKeysCommandMessage",
    code: 0x0804,
    flags: 3,
    completable: true,
    fallible: true,
    description: "List state keys"
  },
  "0x0808": {
    name: "GetPromiseCommandMessage",
    code: 0x0808,
    flags: 3,
    completable: true,
    fallible: true,
    description: "Await promise (blocking)"
  },
  "0x0809": {
    name: "PeekPromiseCommandMessage",
    code: 0x0809,
    flags: 3,
    completable: true,
    fallible: true,
    description: "Check promise (non-blocking)"
  },
  "0x080A": {
    name: "CompletePromiseCommandMessage",
    code: 0x080A,
    flags: 1,
    completable: true,
    fallible: false,
    description: "Resolve promise"
  },
  "0x0C00": {
    name: "SleepCommandMessage",
    code: 0x0C00,
    flags: 1,
    completable: true,
    fallible: false,
    description: "Timer with wake_up_time"
  },
  "0x0C01": {
    name: "CallCommandMessage",
    code: 0x0C01,
    flags: 3,
    completable: true,
    fallible: true,
    description: "Sync invocation (completable, fallible)"
  },
  "0x0C02": {
    name: "OneWayCallCommandMessage",
    code: 0x0C02,
    flags: 1,
    completable: true,
    fallible: false,
    description: "Fire-and-forget with optional delay"
  },
  "0x0C03": {
    name: "AwakeableCommandMessage",
    code: 0x0C03,
    flags: 1,
    completable: true,
    fallible: false,
    description: "Create awakeable"
  },
  "0x0C04": {
    name: "CompleteAwakeableCommandMessage",
    code: 0x0C04,
    flags: 1,
    completable: true,
    fallible: false,
    description: "Resolve awakeable"
  },
  "0x0C05": {
    name: "RunCommandMessage",
    code: 0x0C05,
    flags: 3,
    completable: true,
    fallible: true,
    description: "Execute side effect"
  },
  "0x0C06": {
    name: "CancelInvocationCommandMessage",
    code: 0x0C06,
    flags: 1,
    completable: true,
    fallible: false,
    description: "Cancel target"
  },
  "0x0C07": {
    name: "GetCallInvocationIdCommandMessage",
    code: 0x0C07,
    flags: 3,
    completable: true,
    fallible: true,
    description: "Get call's invocation ID"
  },
  "0x0C08": {
    name: "AttachInvocationCommandMessage",
    code: 0x0C08,
    flags: 3,
    completable: true,
    fallible: true,
    description: "Attach to invocation"
  },
  "0x0C09": {
    name: "GetInvocationOutputCommandMessage",
    code: 0x0C09,
    flags: 3,
    completable: true,
    fallible: true,
    description: "Get invocation result"
  },
  "0x0C0A": {
    name: "SendSignalCommandMessage",
    code: 0x0C0A,
    flags: 1,
    completable: true,
    fallible: false,
    description: "Send signal to invocation"
  }
}

# ── Helper Functions ───────────────────────────────────────────────────────────

# Get entry type info by code
export def get-entry-type [entry_code: int] {
  $ENTRY_TYPES
  | values
  | where {|x| $x.code == $entry_code}
  | first
}

# Get entry type info by name
export def get-entry-type-by-name [name: string] {
  $ENTRY_TYPES
  | values
  | where {|x| $x.name == $name}
  | first
}

# Format entry code as hex string
export def format-entry-code [entry_code: int] {
  $"0x(($entry_code | into binary | encode hex))"
}

# Check if entry is completable
export def is-completable [entry_code: int] {
  let entry_info = (get-entry-type $entry_code)
  $entry_info.completable
}

# Check if entry is fallible
export def is-fallible [entry_code: int] {
  let entry_info = (get-entry-type $entry_code)
  $entry_info.fallible
}

# ── Entry Creation Functions ───────────────────────────────────────────────────

# Create InputCommandMessage entry
export def create-input-entry [
  job_id: string,
  task_name: string,
  attempt: int,
  entry_index: int,
  headers: record<>,
  value: any
] {
  let input_json = ({headers: $headers, value: $value} | to json)
  {
    entry_type: 0x0400,
    entry_name: "InputCommandMessage",
    input: $input_json,
    flags: 0,
    completed: true
  }
}

# Create OutputCommandMessage entry
export def create-output-entry [
  job_id: string,
  task_name: string,
  attempt: int,
  entry_index: int,
  result: any
] {
  {
    entry_type: 0x0401,
    entry_name: "OutputCommandMessage",
    input: ({result: $result} | to json),
    flags: 0,
    completed: true
  }
}

# Create GetStateCommandMessage entry
export def create-get-state-entry [
  job_id: string,
  task_name: string,
  attempt: int,
  entry_index: int,
  key: string,
  lazy: bool = false
] {
  {
    entry_type: 0x0800,
    entry_name: "GetStateCommandMessage",
    input: ({key: $key, lazy: $lazy} | to json),
    flags: 3,
    completed: false
  }
}

# Create SetStateCommandMessage entry
export def create-set-state-entry [
  job_id: string,
  task_name: string,
  attempt: int,
  entry_index: int,
  key: string,
  value: any
] {
  {
    entry_type: 0x0801,
    entry_name: "SetStateCommandMessage",
    input: ({key: $key, value: $value} | to json),
    flags: 1,
    completed: false
  }
}

# Create ClearStateCommandMessage entry
export def create-clear-state-entry [
  job_id: string,
  task_name: string,
  attempt: int,
  entry_index: int,
  key: string
] {
  {
    entry_type: 0x0802,
    entry_name: "ClearStateCommandMessage",
    input: ({key: $key} | to json),
    flags: 1,
    completed: false
  }
}

# Create ClearAllStateCommandMessage entry
export def create-clear-all-state-entry [
  job_id: string,
  task_name: string,
  attempt: int,
  entry_index: int
] {
  {
    entry_type: 0x0803,
    entry_name: "ClearAllStateCommandMessage",
    input: ({} | to json),
    flags: 1,
    completed: false
  }
}

# Create GetStateKeysCommandMessage entry
export def create-get-state-keys-entry [
  job_id: string,
  task_name: string,
  attempt: int,
  entry_index: int
] {
  {
    entry_type: 0x0804,
    entry_name: "GetStateKeysCommandMessage",
    input: ({} | to json),
    flags: 3,
    completed: false
  }
}

# Create SleepCommandMessage entry
export def create-sleep-entry [
  job_id: string,
  task_name: string,
  attempt: int,
  entry_index: int,
  wake_up_time: int
] {
  {
    entry_type: 0x0C00,
    entry_name: "SleepCommandMessage",
    input: ({wake_up_time: $wake_up_time} | to json),
    flags: 1,
    completed: false
  }
}

# Create CallCommandMessage entry
export def create-call-entry [
  job_id: string,
  task_name: string,
  attempt: int,
  entry_index: int,
  service: string,
  handler: string,
  input: any
] {
  {
    entry_type: 0x0C01,
    entry_name: "CallCommandMessage",
    input: ({service: $service, handler: $handler, input: $input} | to json),
    flags: 3,
    completed: false
  }
}

# Create OneWayCallCommandMessage entry
export def create-one-way-call-entry [
  job_id: string,
  task_name: string,
  attempt: int,
  entry_index: int,
  service: string,
  handler: string,
  input: any,
  delay_ms: int = 0
] {
  {
    entry_type: 0x0C02,
    entry_name: "OneWayCallCommandMessage",
    input: ({service: $service, handler: $handler, input: $input, delay_ms: $delay_ms} | to json),
    flags: 1,
    completed: false
  }
}

# Create AwakeableCommandMessage entry
export def create-awakeable-entry [
  job_id: string,
  task_name: string,
  attempt: int,
  entry_index: int
] {
  {
    entry_type: 0x0C03,
    entry_name: "AwakeableCommandMessage",
    input: ({} | to json),
    flags: 1,
    completed: false
  }
}

# Create RunCommandMessage entry
export def create-run-entry [
  job_id: string,
  task_name: string,
  attempt: int,
  entry_index: int,
  side_effect: string
] {
  {
    entry_type: 0x0C05,
    entry_name: "RunCommandMessage",
    input: ({side_effect: $side_effect} | to json),
    flags: 3,
    completed: false
  }
}
