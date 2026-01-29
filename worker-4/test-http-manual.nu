#!/usr/bin/env nu
use ../oc-engine.nu *

rm -rf .oc-workflow
db-init

let job_id = "test-job-http-1"
job-create {
  name: $job_id,
  inputs: { bead_id: "test-bead" },
  tasks: [
    { name: "task-1" }
  ]
}

let task_name = "task-1"
let attempt = 1
init-execution-context $job_id $task_name $attempt

let awakeable = (ctx-awakeable $job_id $task_name $attempt)
let awakeable_id = $awakeable.id
print $"Awakeable ID: ($awakeable_id)"

# Start server
^python3 scripts/oc-http-server.py 4099 &
let server_pid = $env.LAST_PID
print $"Server PID: ($server_pid)"

# Wait for server to start
sleep 3sec

# Test resolve via HTTP
let payload = { result: "test" }
let response = (http post $"http://localhost:4099/awakeables/($awakeable_id)/resolve" $payload --content-type application/json)
print $"Response: ($response)"

# Kill server
^kill $server_pid
