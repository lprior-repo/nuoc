#!/usr/bin/env nu
use std testing
use ../oc-protocol.nu *
print "Testing oc-protocol.nu..."
def test-msg-start [] {
  let msg = (msg-start "inv-123" 0 {key: "value"} 42)
  assert equal $msg.type $MSG_START
  assert equal $msg.invocation_id "inv-123"
  assert equal $msg.known_entries 0
}
def test-msg-completion [] {
  let msg = (msg-completion 5 {status: "success"})
  assert equal $msg.type $MSG_COMPLETION
  assert equal $msg.entry_index 5
}
def test-msg-suspension [] {
  let msg = (msg-suspension [5 6 7])
  assert equal $msg.type $MSG_SUSPENSION
  assert equal $msg.entry_indexes [5 6 7]
}
def test-msg-error [] {
  let msg = (msg-error 1 "Test error" 2)
  assert equal $msg.type $MSG_ERROR
  assert equal $msg.code 1
}
def test-msg-end [] {
  let msg = (msg-end)
  assert equal $msg.type $MSG_END
}
def test-msg-serialize [] {
  let msg = (msg-start "inv-123" 0 {} 42)
  let serialized = (msg-serialize $msg)
  let deserialized = (msg-deserialize $serialized)
  assert equal $deserialized.type $MSG_START
  assert equal $deserialized.invocation_id "inv-123"
}
def test-msg-is-from-runtime [] {
  assert (msg-is-from-runtime {type: $MSG_START})
  assert (msg-is-from-runtime {type: $MSG_COMPLETION})
  assert not (msg-is-from-runtime {type: $MSG_SUSPENSION})
}
def test-msg-is-from-handler [] {
  assert (msg-is-from-handler {type: $MSG_SUSPENSION})
  assert (msg-is-from-handler {type: $MSG_ERROR})
  assert not (msg-is-from-handler {type: $MSG_START})
}
def test-msg-requires-ack [] {
  assert (msg-requires-ack {flags: $FLAG_REQUIRES_ACK})
  assert not (msg-requires-ack {flags: 0})
}
def test-msg-type-name [] {
  assert equal (msg-type-name $MSG_START) "StartMessage"
  assert equal (msg-type-name $MSG_COMPLETION) "CompletionMessage"
}
print "All oc-protocol tests completed!"
