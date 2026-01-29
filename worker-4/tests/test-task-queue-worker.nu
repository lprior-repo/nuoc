#!/usr/bin/env nu
# Tests for Task Queue Worker Model (nuoc-ima)

use std testing
use ../oc-engine.nu *

print "Testing Task Queue Worker Model..."

# ── Schema Tests ─────────────────────────────────────────────────────────────

# Test: task_queues table exists after db-init
def test-task-queues-table-exists [] {
  # Create a test database
  const test_db = "/tmp/test-task-queue-worker.db"
  rm -f $test_db
  
  # Initialize database (should create task_queues and workers tables)
  db-init
  
  # Verify tables exist
  let result = (sqlite3 $DB_PATH ".tables")
  assert str contains "task_queues" $result
  assert str contains "workers" $result
}

# Test: workers can register
def test-worker-register [] {
  db-init
  
  # Register a worker
  let worker_id = "worker-test-1"
  worker-register $worker_id ["agent:general-purpose", "agent:code"] --max-slots 5
  
  # Verify worker exists in database
  let workers = (sqlite3 $DB_PATH $"SELECT id, max_slots, active_slots FROM workers WHERE id = '($worker_id)'")
  assert equal ($workers | length) 1
  assert equal ($workers | get 0 | get id) $worker_id
  assert equal ($workers | get 0 | get max_slots) 5
  assert equal ($workers | get 0 | get active_slots) 0
}

# Test: worker heartbeat updates
def test-worker-heartbeat [] {
  db-init

  let worker_id = "worker-test-2"
  worker-register $worker_id ["agent:general-purpose"]

  # Get initial heartbeat
  let worker1 = (sqlite3 $DB_PATH $"SELECT last_heartbeat FROM workers WHERE id = '($worker_id)'")
  let initial_heartbeat = $worker1.0.last_heartbeat

  # Sleep a bit to ensure time difference
  sleep 100ms

  # Update heartbeat
  worker-heartbeat $worker_id

  # Verify heartbeat was updated (should be different)
  let worker2 = (sqlite3 $DB_PATH $"SELECT last_heartbeat FROM workers WHERE id = '($worker_id)'")
  let updated_heartbeat = $worker2.0.last_heartbeat

  assert not-equal $initial_heartbeat $updated_heartbeat
}

# Test: worker unregister
def test-worker-unregister [] {
  db-init
  
  let worker_id = "worker-test-3"
  worker-register $worker_id ["agent:general-purpose"]
  
  # Unregister
  worker-unregister $worker_id
  
  # Verify worker is removed
  let workers = (sqlite3 $DB_PATH $"SELECT id FROM workers WHERE id = '($worker_id)'")
  assert equal ($workers | length) 0
}

# ── Task Enqueue Tests ───────────────────────────────────────────────────────

# Test: task can be enqueued
def test-task-enqueue [] {
  db-init

  # Create a job and task
  let job_id = "job-enqueue-test"
  sqlite3 $DB_PATH $'INSERT INTO jobs (id, name, status) VALUES (\'($job_id)\', \'test-job\', \'ready\')'
  sqlite3 $DB_PATH $'INSERT INTO tasks (id, job_id, name, status, agent_type) VALUES (\'task-1\', \'($job_id)\', \'test-task\', \'ready\', \'general-purpose\')'

  # Enqueue the task
  task-enqueue $job_id "test-task" --agent-type "general-purpose"

  # Verify task is in queue
  let queued = (sqlite3 $DB_PATH $'SELECT * FROM task_queues WHERE job_id = \'($job_id)\' AND task_name = \'test-task\'')
  assert equal ($queued | length) 1
  assert equal ($queued | get 0 | get status) "QUEUED"
  assert equal ($queued | get 0 | get queue_name) "agent:general-purpose"
}

# Test: queue naming convention
def test-queue-naming-convention [] {
  db-init

  # Test agent task
  let job1 = "job-queue-1"
  sqlite3 $DB_PATH $"INSERT INTO jobs (id, name, status) VALUES ('($job1)', 'test', 'ready')"
  sqlite3 $DB_PATH $"INSERT INTO tasks (id, job_id, name, status, agent_type) VALUES ('task-a1', '($job1)', 'agent-task', 'ready', 'general-purpose')"
  task-enqueue $job1 "agent-task" --agent-type "general-purpose"

  let queue1 = (sqlite3 $DB_PATH $"SELECT queue_name FROM task_queues WHERE job_id = '($job1)'")
  assert equal ($queue1 | get 0 | get queue_name) "agent:general-purpose"

  # Test another agent type
  let job2 = "job-queue-2"
  sqlite3 $DB_PATH $"INSERT INTO jobs (id, name, status) VALUES ('($job2)', 'test', 'ready')"
  sqlite3 $DB_PATH $"INSERT INTO tasks (id, job_id, name, status, agent_type) VALUES ('task-a2', '($job2)', 'agent-task2', 'ready', 'code')"
  task-enqueue $job2 "agent-task2" --agent-type "code"

  let queue2 = (sqlite3 $DB_PATH $"SELECT queue_name FROM task_queues WHERE job_id = '($job2)'")
  assert equal ($queue2 | get 0 | get queue_name) "agent:code"
}

# ── Worker Polling Tests ──────────────────────────────────────────────────────

# Test: worker can poll and claim task
def test-worker-poll-claim [] {
  db-init
  
  # Register worker
  let worker_id = "worker-poll-1"
  worker-register $worker_id ["agent:general-purpose"]
  
  # Enqueue a task
  let job_id = "job-poll-test"
  sqlite3 $DB_PATH $"INSERT INTO jobs (id, name, status) VALUES ('($job_id)', 'test', 'ready')"
  sqlite3 $DB_PATH $"INSERT INTO tasks (id, job_id, name, status, agent_type) VALUES ('task-p1', '($job_id)', 'poll-task', 'ready', 'general-purpose')"
  task-enqueue $job_id "poll-task" --agent-type "general-purpose"
  
  # Poll for task
  let task = (worker-poll $worker_id "agent:general-purpose")
  
  # Verify task was claimed
  assert not ($task | is-empty)
  assert equal ($task | get job_id) $job_id
  assert equal ($task | get task_name) "poll-task"
  assert equal ($task | get claimed_by) $worker_id
  
  # Verify worker slot count updated
  let worker = (sqlite3 $DB_PATH $"SELECT active_slots FROM workers WHERE id = '($worker_id)'")
  assert equal ($worker | get 0 | get active_slots) 1
}

# Test: worker respects slot limit
def test-worker-slot-limit [] {
  db-init
  
  # Register worker with 2 slots
  let worker_id = "worker-slots-1"
  worker-register $worker_id ["agent:general-purpose"] --max-slots 2
  
  # Enqueue 3 tasks
  let job_id = "job-slots-test"
  sqlite3 $DB_PATH $"INSERT INTO jobs (id, name, status) VALUES ('($job_id)', 'test', 'ready')"
  
  for i in 1..3 {
    let task_id = $"task-($i)"
    sqlite3 $DB_PATH $"INSERT INTO tasks (id, job_id, name, status, agent_type) VALUES ('($task_id)', '($job_id)', '($task_id)', 'ready', 'general-purpose')"
    task-enqueue $job_id $task_id --agent-type "general-purpose"
  }
  
  # Poll twice - should get tasks
  let task1 = (worker-poll $worker_id "agent:general-purpose")
  assert not ($task1 | is-empty)
  
  let task2 = (worker-poll $worker_id "agent:general-purpose")
  assert not ($task2 | is-empty)
  
  # Third poll should return empty (worker at capacity)
  let task3 = (worker-poll $worker_id "agent:general-purpose")
  assert ($task3 | is-empty)
}

# Test: empty queue returns null
def test-worker-poll-empty [] {
  db-init
  
  let worker_id = "worker-empty-1"
  worker-register $worker_id ["agent:general-purpose"]
  
  # Poll from empty queue
  let task = (worker-poll $worker_id "agent:general-purpose")
  
  assert ($task | is-empty)
}

# ── Heartbeat & Reaper Tests ──────────────────────────────────────────────────

# Test: heartbeat timeout detection
def test-reaper-timeout [] {
  db-init
  
  # Register worker and claim task
  let worker_id = "worker-reaper-1"
  worker-register $worker_id ["agent:general-purpose"]
  
  let job_id = "job-reaper-test"
  sqlite3 $DB_PATH $"INSERT INTO jobs (id, name, status) VALUES ('($job_id)', 'test', 'ready')"
  sqlite3 $DB_PATH $"INSERT INTO tasks (id, job_id, name, status, agent_type) VALUES ('task-r1', '($job_id)', 'reaper-task', 'ready', 'general-purpose')"
  task-enqueue $job_id "reaper-task" "general-purpose"
  
  let task = (worker-poll $worker_id "agent:general-purpose")
  
  # Simulate old heartbeat (set to 60 seconds ago)
  let old_time = (date now) - 60sec
  sqlite3 $DB_PATH $"UPDATE workers SET last_heartbeat = '($old_time | date to-text '%Y-%m-%d %H:%M:%S')' WHERE id = '($worker_id)'"
  sqlite3 $DB_PATH $"UPDATE task_queues SET heartbeat_at = '($old_time | date to-text '%Y-%m-%d %H:%M:%S')' WHERE job_id = '($job_id)'"
  
  # Run reaper with 30 second timeout
  reaper-run --timeout-sec 30
  
  # Verify task was re-enqueued (claimed_by is null)
  let reclaimed = (sqlite3 $DB_PATH $"SELECT claimed_by FROM task_queues WHERE job_id = '($job_id)'")
  assert equal ($reclaimed | get 0 | get claimed_by) null
  
  # Verify worker slot count decremented
  let worker = (sqlite3 $DB_PATH $"SELECT active_slots FROM workers WHERE id = '($worker_id)'")
  assert equal ($worker | get 0 | get active_slots) 0
}

# Test: reaper respects timeout
def test-reaper-respects-timeout [] {
  db-init
  
  # Register worker and claim task
  let worker_id = "worker-reaper-2"
  worker-register $worker_id ["agent:general-purpose"]
  
  let job_id = "job-reaper-test2"
  sqlite3 $DB_PATH $"INSERT INTO jobs (id, name, status) VALUES ('($job_id)', 'test', 'ready')"
  sqlite3 $DB_PATH $"INSERT INTO tasks (id, job_id, name, status, agent_type) VALUES ('task-r2', '($job_id)', 'reaper-task2', 'ready', 'general-purpose')"
  task-enqueue $job_id "reaper-task2" "general-purpose"
  
  let task = (worker-poll $worker_id "agent:general-purpose")
  
  # Update heartbeat to recent time (10 seconds ago)
  let recent_time = (date now) - 10sec
  sqlite3 $DB_PATH $"UPDATE workers SET last_heartbeat = '($recent_time | date to-text '%Y-%m-%d %H:%M:%S')' WHERE id = '($worker_id)'"
  sqlite3 $DB_PATH $"UPDATE task_queues SET heartbeat_at = '($recent_time | date to-text '%Y-%m-%d %H:%M:%S')' WHERE job_id = '($job_id)'"
  
  # Run reaper with 30 second timeout
  reaper-run --timeout-sec 30
  
  # Verify task is still claimed
  let claimed = (sqlite3 $DB_PATH $"SELECT claimed_by FROM task_queues WHERE job_id = '($job_id)'")
  assert equal ($claimed | get 0 | get claimed_by) $worker_id
}

# ── Backpressure Tests ────────────────────────────────────────────────────────

# Test: tasks queue when workers full
def test-backpressure-full-workers [] {
  db-init
  
  # Register two workers with 1 slot each
  worker-register "worker-bp-1" ["agent:general-purpose"] --max-slots 1
  worker-register "worker-bp-2" ["agent:general-purpose"] --max-slots 1
  
  # Enqueue 3 tasks
  let job_id = "job-bp-test"
  sqlite3 $DB_PATH $"INSERT INTO jobs (id, name, status) VALUES ('($job_id)', 'test', 'ready')"
  
  for i in 1..3 {
    let task_id = $"task-bp-($i)"
    sqlite3 $DB_PATH $"INSERT INTO tasks (id, job_id, name, status, agent_type) VALUES ('($task_id)', '($job_id)', '($task_id)', 'ready', 'general-purpose')"
    task-enqueue $job_id $task_id --agent-type "general-purpose"
  }
  
  # Both workers claim one task each
  let task1 = (worker-poll "worker-bp-1" "agent:general-purpose")
  let task2 = (worker-poll "worker-bp-2" "agent:general-purpose")
  
  # Verify 2 tasks claimed, 1 remains queued
  let queued = (sqlite3 $DB_PATH "SELECT COUNT(*) as count FROM task_queues WHERE status = 'QUEUED'")
  assert equal ($queued | get 0 | get count | into int) 1
  
  # Third worker poll should return empty
  let task3 = (worker-poll "worker-bp-1" "agent:general-purpose")
  assert ($task3 | is-empty)
}

# Test: queue depth observable
def test-queue-depth-observable [] {
  db-init
  
  # Register worker
  worker-register "worker-depth-1" ["agent:general-purpose"] --max-slots 1
  
  # Enqueue 3 tasks
  let job_id = "job-depth-test"
  sqlite3 $DB_PATH $"INSERT INTO jobs (id, name, status) VALUES ('($job_id)', 'test', 'ready')"
  
  for i in 1..3 {
    let task_id = $"task-depth-($i)"
    sqlite3 $DB_PATH $"INSERT INTO tasks (id, job_id, name, status, agent_type) VALUES ('($task_id)', '($job_id)', '($task_id)', 'ready', 'general-purpose')"
    task-enqueue $job_id $task_id --agent-type "general-purpose"
  }
  
  # Get queue depth
  let depth = (queue-depth "agent:general-purpose")
  assert equal $depth 3
  
  # Claim one task
  worker-poll "worker-depth-1" "agent:general-purpose"
  
  # Verify depth decreased
  let depth2 = (queue-depth "agent:general-purpose")
  assert equal $depth2 2
}

# ── Run All Tests ────────────────────────────────────────────────────────────

print "Running task queue worker tests..."

test-task-queues-table-exists
print "  ✓ task_queues table exists"

test-worker-register
print "  ✓ worker can register"

test-worker-heartbeat
print "  ✓ worker heartbeat updates"

test-worker-unregister
print "  ✓ worker can unregister"

test-task-enqueue
print "  ✓ task can be enqueued"

test-queue-naming-convention
print "  ✓ queue naming convention works"

test-worker-poll-claim
print "  ✓ worker can poll and claim task"

test-worker-slot-limit
print "  ✓ worker respects slot limit"

test-worker-poll-empty
print "  ✓ empty queue returns null"

test-reaper-timeout
print "  ✓ heartbeat timeout detection works"

test-reaper-respects-timeout
print "  ✓ reaper respects timeout"

test-backpressure-full-workers
print "  ✓ backpressure when workers full"

test-queue-depth-observable
print "  ✓ queue depth is observable"

print "All task queue worker tests passed!"
