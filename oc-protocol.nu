#!/usr/bin/env nu
# oc-protocol.nu — Service Invocation Protocol
export const MSG_START = 0x0000
export const MSG_COMPLETION = 0x8000
export const MSG_ENTRY_ACK = 0x8001
export const MSG_SUSPENSION = 0x0001
export const MSG_ERROR = 0x0002
export const MSG_END = 0x0003
export const FLAG_REQUIRES_ACK = 0x80000000
export const FLAG_COMPLETED = 0x00000100
export def msg-start [invocation_id: string, known_entries: int, state_map: record, random_seed: int] {
  {type: $MSG_START, invocation_id: $invocation_id, known_entries: $known_entries, state_map: $state_map, random_seed: $random_seed}
}
export def msg-completion [entry_index: int, result: record, requires_ack: bool = false] {
  let flags = (if $requires_ack { $FLAG_REQUIRES_ACK } else { 0 })
  {type: $MSG_COMPLETION, flags: $flags, entry_index: $entry_index, result: $result}
}
export def msg-entry-ack [entry_index: int] {
  {type: $MSG_ENTRY_ACK, entry_index: $entry_index}
}
export def msg-suspension [entry_indexes: list<int>] {
  {type: $MSG_SUSPENSION, entry_indexes: $entry_indexes}
}
export def msg-error [code: int, message: string, related_entry_index: int = -1] {
  {type: $MSG_ERROR, code: $code, message: $message, related_entry_index: $related_entry_index}
}
export def msg-end [] {
  {type: $MSG_END}
}
export def msg-serialize [message: record, requires_ack: bool = false] {
  let base_flags = ($message | get -o flags | default 0)
  let flags = (if $requires_ack { ($base_flags | bit-or $FLAG_REQUIRES_ACK) } else { $base_flags })
  let payload = ($message | to json)
  let header = {type: $message.type, flags: $flags, length: ($payload | str length)}
  ([$header, ($payload | from json)] | to json)
}
export def msg-deserialize [data: string] {
  let parts = ($data | from json)
  let header = $parts.0
  let payload = $parts.1
  $payload | insert flags $header.flags
}
export def msg-is-from-runtime [message: record] {
  $message.type in [$MSG_START, $MSG_COMPLETION, $MSG_ENTRY_ACK]
}
export def msg-is-from-handler [message: record] {
  $message.type in [$MSG_SUSPENSION, $MSG_ERROR, $MSG_END]
}
export def msg-requires-ack [message: record] {
  let flags = ($message | get -o flags | default 0)
  ($flags | bit-and $FLAG_REQUIRES_ACK) != 0
}
export def msg-type-name [msg_type: int] {
  match $msg_type {
    $MSG_START => "StartMessage"
    $MSG_COMPLETION => "CompletionMessage"
    $MSG_ENTRY_ACK => "EntryAckMessage"
    $MSG_SUSPENSION => "SuspensionMessage"
    $MSG_ERROR => "ErrorMessage"
    $MSG_END => "EndMessage"
    _ => $"Unknown(0x(($msg_type | into binary | encode hex)))"
  }
}
