#!/usr/bin/env nu

# liza-advanced.nu — Deterministic state machine for Red Queen adversarial QA
#
# State: YAML blackboard (atomic save, auditable)
# Gates: assert-can-* functions (pure field checks, no AI)
# Ratchet: done_when list (permanent, append-only)
# Selection: exit code comparison (deterministic)
# Scoring: survivors / tests_run (arithmetic)
# Beads: filed at survivor selection (never deferred)
#
# AI generates test commands. Everything else is deterministic code.

const BLACKBOARD_DIR = "~/.local/share/liza"
const BLACKBOARD_FILE = "blackboard.yml"

# ── Blackboard Persistence ────────────────────────────────────────────────────

def blackboard-path [] {
  $"($BLACKBOARD_DIR | path expand)/($BLACKBOARD_FILE)"
}

def ensure-dir [] {
  let dir = ($BLACKBOARD_DIR | path expand)
  if not ($dir | path exists) { mkdir $dir }
}

def load-blackboard [] {
  let p = (blackboard-path)
  if ($p | path exists) {
    let result = (try { open $p } catch { null })
    if $result == null {
      error make {msg: $"Blackboard corrupted — cannot parse ($p). Use 'reset' to start fresh or restore from backup."}
    } else if ($result | describe | str starts-with "record") {
      $result
    } else {
      error make {msg: $"Blackboard corrupted — expected YAML record, got ($result | describe). Use 'reset' to start fresh."}
    }
  } else {
    {}
  }
}

def save-blackboard [bb: record] {
  ensure-dir
  $bb | to yaml | save -f (blackboard-path)
}

def get-task [bb: record, task_id: string] {
  if ("tasks" in $bb) and ($task_id in $bb.tasks) {
    $bb.tasks | get $task_id
  } else {
    error make {msg: $"Task '($task_id)' not found"}
  }
}

def set-task [bb: record, task_id: string, task: record] {
  let tasks = if "tasks" in $bb { $bb.tasks } else { {} }
  $bb | upsert tasks ($tasks | upsert $task_id $task)
}

def now-timestamp [] {
  date now | format date "%Y-%m-%dT%H:%M:%S"
}

# ── Deterministic Gates ───────────────────────────────────────────────────────
# Pure field checks. No AI judgment. No exceptions.

def assert-can-submit [task: record] {
  if $task.status != "IN_PROGRESS" {
    error make {msg: $"GATE BLOCKED assert-can-submit: status is '($task.status)', expected 'IN_PROGRESS'"}
  }
  if $task.agent_id == null {
    error make {msg: "GATE BLOCKED assert-can-submit: no agent_id set"}
  }
}

def assert-can-review [task: record] {
  if $task.status != "READY_FOR_REVIEW" {
    error make {msg: $"GATE BLOCKED assert-can-review: status is '($task.status)', expected 'READY_FOR_REVIEW'"}
  }
  if $task.validation_results == null {
    error make {msg: "GATE BLOCKED assert-can-review: no validation results exist"}
  }
}

def assert-can-merge [task: record] {
  if $task.status != "APPROVED" {
    error make {msg: $"GATE BLOCKED assert-can-merge: status is '($task.status)', expected 'APPROVED'"}
  }
  if $task.review_decision != "APPROVED" {
    error make {msg: $"GATE BLOCKED assert-can-merge: review decision is '($task.review_decision)', expected 'APPROVED'"}
  }
}

def assert-no-test-weakening [changed_files: list<string>] {
  let test_files = ($changed_files | where {|f| $f | str starts-with "test/"})
  if ($test_files | length) > 0 {
    error make {msg: $"GATE BLOCKED assert-no-test-weakening: test files modified without explicit permission: ($test_files | str join ', ')"}
  }
}

# ── Severity → Priority Mapping (Deterministic) ──────────────────────────────
# CRITICAL=P0, MAJOR=P1, MINOR=P2, OBSERVATION=P3

def severity-to-priority [severity: string] {
  match $severity {
    "CRITICAL" => 0
    "MAJOR" => 1
    "MINOR" => 2
    "OBSERVATION" => 3
    _ => 2
  }
}

# ── Crown Status (Deterministic) ─────────────────────────────────────────────
# Computed from blackboard fields only. No AI narrative.

def compute-crown-status [task: record] {
  # If no validation results yet, UNKNOWN
  let has_vr = ("validation_results" in $task) and ($task.validation_results != null)
  if not $has_vr {
    "UNKNOWN"
  } else if not $task.validation_results.all_pass {
    # Validation has failures → crown is forfeit
    "CROWN FORFEIT"
  } else {
    # All pass — check if any CRITICAL survivors exist
    let critical_count = ($task.done_when | where {|c| $c.severity == "CRITICAL"} | length)
    if $critical_count > 0 {
      "CROWN CONTESTED"
    } else if $task.survivors_total == 0 {
      "CROWN DEFENDED"
    } else {
      "CROWN CONTESTED"
    }
  }
}

# ── Fitness Computation (Deterministic) ───────────────────────────────────────

def compute-fitness [tests_run: int, survivors: int] {
  if $tests_run > 0 {
    ($survivors / $tests_run) | math round --precision 3
  } else {
    0.0
  }
}

def dimension-status [fitness: float, zero_gens: int] {
  if $zero_gens >= 3 {
    "EXHAUSTED"
  } else if $zero_gens == 2 {
    "DORMANT"
  } else if $fitness > 0.7 {
    "HEMORRHAGING"
  } else if $fitness > 0.5 {
    "HIGH PRESSURE"
  } else if $fitness > 0.3 {
    "CONTESTED"
  } else if $fitness > 0.1 {
    "PROBING"
  } else if $fitness == 0.0 {
    "COOLING"
  } else {
    "ACTIVE"
  }
}

# ── DRQ Coevolution: Escalating Pressure ────────────────────────────────────
# Each generation gets MORE challengers, not fewer. The codebase must constantly
# defend itself against an ever-growing army.

def escalation-multiplier [generation: int] {
  # Pressure increases every 2 generations: 1x, 1x, 1.5x, 1.5x, 2x, 2x, ...
  1.0 + (($generation / 2 | math floor) * 0.5)
}

# Auto-promote severity when a dimension keeps bleeding
def escalate-severity [current_severity: string, consecutive_survivors: int] {
  if $consecutive_survivors >= 3 {
    # 3+ consecutive survivors in same dimension = auto-escalate
    match $current_severity {
      "OBSERVATION" => "MINOR"
      "MINOR" => "MAJOR"
      "MAJOR" => "CRITICAL"
      "CRITICAL" => "CRITICAL"
      _ => $current_severity
    }
  } else {
    $current_severity
  }
}

# Compute lethality: how deadly is each dimension (survivors that were CRITICAL/MAJOR)
def compute-lethality [findings: list, dimension: string] {
  let dim_findings = ($findings | where {|f| $f.dimension == $dimension})
  let lethal = ($dim_findings | where {|f| $f.severity == "CRITICAL" or $f.severity == "MAJOR"} | length)
  let total = ($dim_findings | length)
  if $total > 0 { ($lethal / $total) | math round --precision 3 } else { 0.0 }
}

# DRQ anti-stagnation: reopen dormant dimensions after N quiet generations
# The Red Queen never truly rests — dormant dimensions get probed again
def should-reawaken [zero_gens: int, global_generation: int] {
  # Reawaken every 5 generations even if "exhausted"
  $zero_gens >= 2 and ($global_generation mod 5) == 0
}

# ── Shell Execution (Deterministic) ──────────────────────────────────────────

def run-shell-cmd [cmd: string] {
  do { ^bash -c $cmd } | complete
}

# ── Commands ──────────────────────────────────────────────────────────────────

# Initialize blackboard
def "main init" [] {
  ensure-dir
  let p = (blackboard-path)
  if not ($p | path exists) {
    save-blackboard { tasks: {}, findings: [], beads_filed: [] }
    print "Blackboard initialized"
  } else {
    print "Blackboard already exists"
  }
}

# Reset blackboard (destructive)
def "main reset" [] {
  ensure-dir
  save-blackboard { tasks: {}, findings: [], beads_filed: [] }
  print "Blackboard reset"
}

# Add a task
def "main task-add" [
  task_id: string
  --spec_ref: string = ""
  --champion: string = ""
] {
  # Gate: reject empty task IDs
  if ($task_id | str trim | str length) == 0 {
    error make {msg: "GATE BLOCKED task-add: task_id cannot be empty"}
  }

  let bb = load-blackboard

  # Gate: reject duplicate task IDs (prevents silent state destruction)
  if ("tasks" in $bb) and ($task_id in $bb.tasks) {
    error make {msg: $"GATE BLOCKED task-add: task '($task_id)' already exists. Use 'reset' to start fresh."}
  }

  let task = {
    status: "UNCLAIMED"
    agent_id: null
    spec_ref: $spec_ref
    champion: $champion
    done_when: []
    generation: 0
    gen_active: false
    landscape: {}
    zero_survivor_gens: 0
    survivors_total: 0
    findings: []
    beads_filed: []
    commit_sha: null
    validation_results: null
    review_decision: null
    created_at: (now-timestamp)
  }
  let bb2 = set-task $bb $task_id $task
  save-blackboard $bb2
  print $"Task '($task_id)' added [champion=($champion)]"
}

# Add a done_when check to a task (append-only — the ratchet)
def "main task-add-check" [
  task_id: string
  cmd: string
  --expect_exit: int = 0
  --dimension: string = "contract"
  --generation: int = -1
  --severity: string = "MAJOR"
] {
  if ($cmd | str trim | str length) == 0 {
    error make {msg: "GATE BLOCKED task-add-check: cmd cannot be empty"}
  }
  let bb = load-blackboard
  let task = get-task $bb $task_id
  if $task.status == "MERGED" or $task.status == "APPROVED" {
    error make {msg: $"GATE BLOCKED task-add-check: task is '($task.status)' — cannot modify post-approval"}
  }
  let gen = if $generation == -1 { $task.generation } else { $generation }
  let check = {
    cmd: $cmd
    expect_exit: $expect_exit
    dimension: $dimension
    generation: $gen
    severity: $severity
    added_at: (now-timestamp)
  }
  let new_done = ($task.done_when | append $check)
  let task2 = ($task | upsert done_when $new_done)
  let bb2 = set-task $bb $task_id $task2
  save-blackboard $bb2
  print $"CHECK LOCKED: ($cmd) [expect_exit=($expect_exit), dim=($dimension), sev=($severity)]"
}

# Claim a task (UNCLAIMED → IN_PROGRESS)
def "main claim" [
  task_id: string
  agent_id: string
] {
  if ($agent_id | str trim | str length) == 0 {
    error make {msg: "GATE BLOCKED claim: agent_id cannot be empty"}
  }
  let bb = load-blackboard
  let task = get-task $bb $task_id
  if $task.status != "UNCLAIMED" {
    error make {msg: $"Cannot claim: status is ($task.status), expected UNCLAIMED"}
  }
  let task2 = ($task | upsert status "IN_PROGRESS" | upsert agent_id $agent_id)
  let bb2 = set-task $bb $task_id $task2
  save-blackboard $bb2
  print $"Task '($task_id)' claimed by ($agent_id)"
}

# Start a new generation (increment counter)
def "main gen-start" [task_id: string] {
  let bb = load-blackboard
  let task = get-task $bb $task_id
  if $task.status != "IN_PROGRESS" {
    error make {msg: $"GATE BLOCKED gen-start: status is '($task.status)', expected 'IN_PROGRESS'"}
  }
  let gen_active = if "gen_active" in $task { $task.gen_active } else { false }
  if $gen_active {
    error make {msg: $"GATE BLOCKED gen-start: generation ($task.generation) is still active — call gen-end first"}
  }
  let gen = $task.generation + 1
  let task2 = ($task | upsert generation $gen | upsert gen_active true)
  let bb2 = set-task $bb $task_id $task2
  save-blackboard $bb2
  print $"Generation ($gen) started for '($task_id)'"
}

# Record a survivor (bug found)
# Deterministic: locks regression in done_when + updates landscape + files bead
def "main gen-survivor" [
  task_id: string
  dimension: string
  cmd: string
  --expect_exit: int = 0
  --severity: string = "MAJOR"
  --title: string = ""
  --stdout: string = ""
  --stderr: string = ""
  --actual_exit: int = -1
] {
  let bb = load-blackboard
  let task = get-task $bb $task_id
  if $task.status != "IN_PROGRESS" {
    error make {msg: $"GATE BLOCKED gen-survivor: status is '($task.status)', expected 'IN_PROGRESS'"}
  }
  let gen_active = if "gen_active" in $task { $task.gen_active } else { false }
  if not $gen_active {
    error make {msg: "GATE BLOCKED gen-survivor: no active generation — call gen-start first"}
  }
  if ($dimension | str trim | str length) == 0 {
    error make {msg: "GATE BLOCKED gen-survivor: dimension cannot be empty"}
  }
  let gen = $task.generation
  if $gen == 0 {
    error make {msg: "GATE BLOCKED gen-survivor: generation is 0 — call gen-start first"}
  }
  let finding_n = ($task.findings | length) + 1
  let finding_id = $"GEN-($gen)-($finding_n)"

  # 1. Lock regression in done_when (permanent, append-only)
  let check = {
    cmd: $cmd
    expect_exit: $expect_exit
    dimension: $dimension
    generation: $gen
    severity: $severity
    finding_id: $finding_id
    added_at: (now-timestamp)
  }
  let new_done = ($task.done_when | append $check)

  # 2. Record finding with full context
  let finding_title = if $title != "" { $title } else { $"($dimension): ($cmd)" }
  let finding = {
    id: $finding_id
    generation: $gen
    dimension: $dimension
    severity: $severity
    title: $finding_title
    cmd: $cmd
    expect_exit: $expect_exit
    actual_exit: $actual_exit
    stdout: $stdout
    stderr: $stderr
    found_at: (now-timestamp)
  }
  let new_findings = ($task.findings | append $finding)

  # 3. Update landscape (arithmetic, deterministic)
  let landscape = $task.landscape
  let dim_data = if $dimension in $landscape {
    $landscape | get $dimension
  } else {
    { tests_run: 0, survivors: 0, zero_gens: 0, last_survivor_gen: -1 }
  }
  let dim_data2 = ($dim_data
    | upsert tests_run ($dim_data.tests_run + 1)
    | upsert survivors ($dim_data.survivors + 1)
    | upsert zero_gens 0
    | upsert last_survivor_gen $gen)
  let landscape2 = ($landscape | upsert $dimension $dim_data2)

  let task2 = ($task
    | upsert done_when $new_done
    | upsert findings $new_findings
    | upsert landscape $landscape2
    | upsert survivors_total ($task.survivors_total + 1)
    | upsert zero_survivor_gens 0)
  let bb2 = set-task $bb $task_id $task2
  save-blackboard $bb2

  # 4. Print finding report
  print $"[($finding_id)] ($severity): ($finding_title)"
  print "═══════════════════════════════════════════════"
  print $"  Generation:    ($gen)"
  print $"  Dimension:     ($dimension)"
  print $"  Command:       ($cmd)"
  print $"  Expected Exit: ($expect_exit)"
  print $"  Actual Exit:   ($actual_exit)"
  if $stdout != "" { print $"  Stdout:        ($stdout | str substring 0..200)" }
  if $stderr != "" { print $"  Stderr:        ($stderr | str substring 0..200)" }
  print $"  done_when:     LOCKED"
  print "═══════════════════════════════════════════════"

  # 5. File bead IMMEDIATELY (never deferred — Rule #10)
  let priority = (severity-to-priority $severity)
  let bead_title = $"[Red Queen] ($severity): ($finding_title)"
  print $"FILING BEAD: ($bead_title) [priority=($priority)]"
  let bead_result = (do { ^bd create --title $bead_title --type bug $"--priority=($priority)" } | complete)
  if $bead_result.exit_code == 0 {
    print $"  BEAD FILED: ($bead_result.stdout | str trim)"
    # Track bead in blackboard
    let bb3 = load-blackboard
    let task3 = get-task $bb3 $task_id
    let new_beads = ($task3.beads_filed | append {
      finding_id: $finding_id
      bead_output: ($bead_result.stdout | str trim)
      filed_at: (now-timestamp)
    })
    let task4 = ($task3 | upsert beads_filed $new_beads)
    let bb4 = set-task $bb3 $task_id $task4
    save-blackboard $bb4
  } else {
    print $"  BEAD FAILED: ($bead_result.stderr | str trim)"
    print "  WARNING: Survivor recorded but bead filing failed. Manual follow-up needed."
  }
}

# Record a discard (test passed, no bug) — update landscape tests_run only
def "main gen-discard" [
  task_id: string
  dimension: string
] {
  let bb = load-blackboard
  let task = get-task $bb $task_id
  if $task.status != "IN_PROGRESS" {
    error make {msg: $"GATE BLOCKED gen-discard: status is '($task.status)', expected 'IN_PROGRESS'"}
  }
  let gen_active = if "gen_active" in $task { $task.gen_active } else { false }
  if not $gen_active {
    error make {msg: "GATE BLOCKED gen-discard: no active generation — call gen-start first"}
  }
  if ($dimension | str trim | str length) == 0 {
    error make {msg: "GATE BLOCKED gen-discard: dimension cannot be empty"}
  }

  let landscape = $task.landscape
  let dim_data = if $dimension in $landscape {
    $landscape | get $dimension
  } else {
    { tests_run: 0, survivors: 0, zero_gens: 0, last_survivor_gen: -1 }
  }
  let dim_data2 = ($dim_data | upsert tests_run ($dim_data.tests_run + 1))
  let landscape2 = ($landscape | upsert $dimension $dim_data2)

  let task2 = ($task | upsert landscape $landscape2)
  let bb2 = set-task $bb $task_id $task2
  save-blackboard $bb2
  let tr = $dim_data2.tests_run
  print $"DISCARD in ($dimension) tests_run=($tr)"
}

# End generation — track zero-survivor streaks for equilibrium detection
def "main gen-end" [task_id: string --survivors_this_gen: int = 0] {
  if $survivors_this_gen < 0 {
    error make {msg: $"GATE BLOCKED gen-end: survivors_this_gen cannot be negative \(got ($survivors_this_gen)\)"}
  }
  let bb = load-blackboard
  let task = get-task $bb $task_id
  if $task.status != "IN_PROGRESS" {
    error make {msg: $"GATE BLOCKED gen-end: status is '($task.status)', expected 'IN_PROGRESS'"}
  }
  let gen_active = if "gen_active" in $task { $task.gen_active } else { false }
  if not $gen_active {
    error make {msg: $"GATE BLOCKED gen-end: no active generation — call gen-start first"}
  }

  let landscape = $task.landscape
  let current_gen = $task.generation
  mut updated_landscape = $landscape

  # Per-dimension zero_gens tracking:
  # gen-survivor sets last_survivor_gen = current gen for dims that had survivors.
  # At gen-end, increment zero_gens for all dims where last_survivor_gen != current gen.
  for dim in ($landscape | columns) {
    let d = ($landscape | get $dim)
    let last_sg = if "last_survivor_gen" in $d { $d.last_survivor_gen } else { -1 }
    if $last_sg == $current_gen {
      # This dim had a survivor this gen — reset zero_gens to 0
      $updated_landscape = ($updated_landscape | upsert $dim ($d | upsert zero_gens 0))
    } else {
      # No survivor this gen — increment zero_gens
      $updated_landscape = ($updated_landscape | upsert $dim ($d | upsert zero_gens ($d.zero_gens + 1)))
    }
  }

  let zero_sg = if $survivors_this_gen == 0 {
    $task.zero_survivor_gens + 1
  } else {
    0
  }

  let task2 = ($task | upsert landscape $updated_landscape | upsert zero_survivor_gens $zero_sg | upsert gen_active false)
  let bb2 = set-task $bb $task_id $task2
  save-blackboard $bb2

  # DRQ anti-stagnation: reawaken dormant dimensions periodically
  let gen_num = $task2.generation
  if ($gen_num mod 5) == 0 and $gen_num > 0 {
    mut reawakened = []
    mut rl = $updated_landscape
    for dim in ($updated_landscape | columns) {
      let d = ($updated_landscape | get $dim)
      if (should-reawaken $d.zero_gens $gen_num) {
        $rl = ($rl | upsert $dim ($d | upsert zero_gens 0))
        $reawakened = ($reawakened | append $dim)
      }
    }
    if ($reawakened | length) > 0 {
      let task3 = ($task2 | upsert landscape $rl)
      let bb3 = set-task $bb $task_id $task3
      save-blackboard $bb3
      print "╔═══════════════════════════════════════════════╗"
      print "║  ANTI-STAGNATION: Dimensions reawakened!      ║"
      print "╚═══════════════════════════════════════════════╝"
      for r in $reawakened {
        print $"  REAWAKENED: ($r) — the Queen never truly rests"
      }
      # Reawaken overrides equilibrium message — dimensions are active again
      print $"Generation ($gen_num) ended: ($survivors_this_gen) survivors, zero-streak=($zero_sg) [dims reawakened — equilibrium suppressed]"
      return
    }
  }

  if $zero_sg >= 3 {
    print "╔═══════════════════════════════════════════════╗"
    print $"║  EQUILIBRIUM: ($zero_sg) consecutive zero-survivor gens  ║"
    print "╚═══════════════════════════════════════════════╝"
  } else if $zero_sg >= 2 {
    print $"Generation ($gen_num) ended: ($survivors_this_gen) survivors, zero-streak=($zero_sg) [need 3 for equilibrium]"
  } else {
    print $"Generation ($gen_num) ended: ($survivors_this_gen) survivors, zero-streak=($zero_sg)"
  }
}

# Check if equilibrium reached (deterministic: 2+ consecutive zero-survivor gens)
def "main equilibrium" [task_id: string] {
  let bb = load-blackboard
  let task = get-task $bb $task_id

  let all_exhausted = if ($task.landscape | columns | length) == 0 {
    false
  } else {
    let exhausted_count = ($task.landscape | columns | each {|dim|
      let d = ($task.landscape | get $dim)
      if $d.zero_gens >= 2 { 1 } else { 0 }
    } | math sum)
    $exhausted_count == ($task.landscape | columns | length)
  }

  # DRQ: Equilibrium requires 3 consecutive zero-survivor gens (was 2)
  # AND all dimensions must be exhausted. The codebase must PROVE resilience.
  if $task.zero_survivor_gens >= 3 and $all_exhausted {
    print "EQUILIBRIUM: YES — Crown defended through sustained resistance"
    print $"  Global zero-survivor streak: ($task.zero_survivor_gens)"
    print $"  All dimensions exhausted: ($all_exhausted)"
    exit 0
  } else {
    print "EQUILIBRIUM: NO — The Red Queen demands more"
    print $"  Global zero-survivor streak: ($task.zero_survivor_gens) [need 3]"
    print $"  All dimensions exhausted: ($all_exhausted)"
    if $task.zero_survivor_gens >= 2 and (not $all_exhausted) {
      print "  WARNING: Streak is strong but dimensions remain active — keep attacking"
    }
    exit 1
  }
}

# Show landscape fitness scores (all arithmetic, no AI)
def "main landscape" [task_id: string] {
  let bb = load-blackboard
  let task = get-task $bb $task_id
  let crown = (compute-crown-status $task)

  print ""
  print "THE RED QUEEN'S LANDSCAPE"
  print "═══════════════════════════════════════════════════════════════"
  print $"Champion:    ($task.champion)"
  print $"Generation:  ($task.generation)"
  print $"Survivors:   ($task.survivors_total)"
  print $"Lineage:     ($task.done_when | length) checks"
  print $"Beads Filed: ($task.beads_filed | length)"
  print $"Crown:       ($crown)"
  print ""

  let header_dim = ("Dimension" | fill -w 25)
  let header_tests = ("Tests" | fill -w 8)
  let header_surv = ("Survivors" | fill -w 12)
  let header_fit = ("Fitness" | fill -w 10)
  print $"($header_dim)($header_tests)($header_surv)($header_fit)Status"
  let sep = ("─" | fill -c "─" -w 67)
  print $sep

  let landscape = $task.landscape
  if ($landscape | columns | length) == 0 {
    print "  (no dimensions tested yet)"
  } else {
    for dim in ($landscape | columns) {
      let d = ($landscape | get $dim)
      let fitness = (compute-fitness $d.tests_run $d.survivors)
      let status = (dimension-status $fitness $d.zero_gens)
      let col_dim = ($dim | fill -w 25)
      let col_tests = ($d.tests_run | into string | fill -w 8)
      let col_surv = ($d.survivors | into string | fill -w 12)
      let col_fit = ($fitness | into string | fill -w 10)
      print $"($col_dim)($col_tests)($col_surv)($col_fit)($status)"
    }
  }
  print ""
}

# Regress — add test to done_when with champion/candidate verification
# Without --force: verifies test fails on champion, passes on candidate
def "main regress" [
  task_id: string
  cmd: string
  --expect_exit: int = 0
  --dimension: string = "regression"
  --severity: string = "MAJOR"
  --force # Skip champion/candidate verification
] {
  let bb = load-blackboard
  let task = get-task $bb $task_id
  if $task.status != "IN_PROGRESS" {
    error make {msg: $"GATE BLOCKED regress: status is '($task.status)', expected 'IN_PROGRESS'"}
  }

  if not $force {
    # Step 1: Run on current code — should FAIL (this is a known bug)
    print "Verifying regression: running on current code, expecting failure..."
    let champion_result = (run-shell-cmd $cmd)
    if $champion_result.exit_code == $expect_exit {
      let ec = $champion_result.exit_code
      let msg = $"Regression verification failed: command already passes on current code, exit=($ec). Use --force to override."
      error make {msg: $msg}
    }
    let champ_ec = $champion_result.exit_code
    print $"  Champion exits ($champ_ec) — confirmed failing"
  }

  # Lock it into done_when
  let check = {
    cmd: $cmd
    expect_exit: $expect_exit
    dimension: $dimension
    generation: $task.generation
    severity: $severity
    regression: true
    added_at: (now-timestamp)
  }
  let new_done = ($task.done_when | append $check)
  let task2 = ($task | upsert done_when $new_done)
  let bb2 = set-task $bb $task_id $task2
  save-blackboard $bb2
  print $"REGRESSION LOCKED: ($cmd) [expect_exit=($expect_exit)]"
}

# Submit for review (IN_PROGRESS → READY_FOR_REVIEW)
def "main coder-submit" [
  task_id: string
  agent_id: string
] {
  let bb = load-blackboard
  let task = get-task $bb $task_id
  assert-can-submit $task
  if $task.agent_id != $agent_id {
    error make {msg: $"GATE BLOCKED coder-submit: agent '($agent_id)' does not match claimed agent '($task.agent_id)'"}
  }
  let gen_active = if "gen_active" in $task { $task.gen_active } else { false }
  if $gen_active {
    error make {msg: "GATE BLOCKED coder-submit: generation is still active — call gen-end first"}
  }

  # Record commit SHA if in a git repo
  let sha_result = (do { ^git rev-parse HEAD } | complete)
  let sha = if $sha_result.exit_code == 0 { $sha_result.stdout | str trim } else { null }

  let task2 = ($task | upsert status "READY_FOR_REVIEW" | upsert commit_sha $sha)
  let bb2 = set-task $bb $task_id $task2
  save-blackboard $bb2
  print $"Task '($task_id)' submitted for review [sha=($sha)]"
}

# Validate — run ALL done_when checks (THE RATCHET)
# This is the core evolutionary mechanism. Every survivor becomes a permanent check.
# Exit code comparison only. No AI judgment.
def "main validate" [task_id: string] {
  let bb = load-blackboard
  let task = get-task $bb $task_id
  let checks = $task.done_when

  if ($checks | length) == 0 {
    error make {msg: "GATE BLOCKED validate: no done_when checks exist — the Red Queen demands at least one test before validation"}
  }

  print ""
  let num_checks = ($checks | length)
  print $"VALIDATION: Running ($num_checks) checks — the ratchet"
  print "═══════════════════════════════════════════════════════════════"

  mut all_pass = true
  mut failed_list = []
  mut pass_count = 0

  for check in $checks {
    let result = (run-shell-cmd $check.cmd)
    let passed = ($result.exit_code == $check.expect_exit)
    let finding_tag = if "finding_id" in $check { $" [($check.finding_id)]" } else { "" }
    if $passed {
      $pass_count = $pass_count + 1
      print $"  PASS($finding_tag): ($check.cmd)"
    } else {
      $all_pass = false
      $failed_list = ($failed_list | append {
        cmd: $check.cmd
        expected: $check.expect_exit
        actual: $result.exit_code
        dimension: $check.dimension
        severity: $check.severity
      })
      print $"  FAIL($finding_tag): ($check.cmd) [expected=($check.expect_exit) got=($result.exit_code)]"
    }
  }

  print ""
  print $"Results: ($pass_count)/($checks | length) passed"

  # Store validation results (deterministic)
  let bb2 = load-blackboard
  let task3 = (get-task $bb2 $task_id
    | upsert validation_results {
        all_pass: $all_pass
        passed: $pass_count
        total: ($checks | length)
        failed: $failed_list
        validated_at: (now-timestamp)
      })
  let bb3 = set-task $bb2 $task_id $task3
  save-blackboard $bb3

  if $all_pass {
    print "ALL CHECKS PASS — ratchet holds"
  } else {
    print ""
    let fc = ($failed_list | length)
    print $"RATCHET BROKEN: ($fc) checks failed"
    for f in $failed_list {
      print $"  ($f.severity) [($f.dimension)]: ($f.cmd)"
    }
    exit 1
  }
}

# Approve task (READY_FOR_REVIEW → APPROVED)
def "main approve" [task_id: string] {
  let bb = load-blackboard
  let task = get-task $bb $task_id
  assert-can-review $task

  if not $task.validation_results.all_pass {
    error make {msg: "Cannot approve: validation has failures — ratchet broken"}
  }

  let task2 = ($task | upsert status "APPROVED" | upsert review_decision "APPROVED")
  let bb2 = set-task $bb $task_id $task2
  save-blackboard $bb2
  print $"Task '($task_id)' APPROVED"
}

# Reject task (READY_FOR_REVIEW → IN_PROGRESS)
def "main reject" [task_id: string --reason: string = ""] {
  let bb = load-blackboard
  let task = get-task $bb $task_id
  assert-can-review $task

  let task2 = ($task | upsert status "IN_PROGRESS" | upsert review_decision $"REJECTED: ($reason)" | upsert validation_results null)
  let bb2 = set-task $bb $task_id $task2
  save-blackboard $bb2
  print $"Task '($task_id)' REJECTED: ($reason) [validation_results cleared — must re-validate]"
}

# Merge task (APPROVED → MERGED)
def "main merge" [task_id: string] {
  let bb = load-blackboard
  let task = get-task $bb $task_id
  assert-can-merge $task

  let task2 = ($task | upsert status "MERGED")
  let bb2 = set-task $bb $task_id $task2
  save-blackboard $bb2
  print $"Task '($task_id)' MERGED"
}

# Assert no test weakening — check changed files don't touch tests/
def "main assert-no-test-weakening" [--allow-tests] {
  if $allow_tests { return }
  # Try git first, then jj
  let changed = (do { ^git diff --name-only HEAD } | complete)
  if $changed.exit_code == 0 {
    let files = ($changed.stdout | lines | where {|l| ($l | str length) > 0})
    assert-no-test-weakening $files
    print "No test weakening detected"
    return
  }
  # Try jj
  let jj_changed = (do { ^jj diff --name-only } | complete)
  if $jj_changed.exit_code == 0 {
    let files = ($jj_changed.stdout | lines | where {|l| ($l | str length) > 0})
    assert-no-test-weakening $files
    print "No test weakening detected (jj)"
    return
  }
  print "Not in a git or jj repo — skipping test weakening check"
}

# Show task state
def "main show" [--task: string = ""] {
  let bb = load-blackboard
  if $task == "" {
    if "tasks" in $bb {
      for t in ($bb.tasks | columns) {
        let td = ($bb.tasks | get $t)
        # Guard against corrupted/incomplete task records
        let has_required = ("status" in $td) and ("generation" in $td) and ("survivors_total" in $td) and ("done_when" in $td) and ("beads_filed" in $td)
        if not $has_required {
          print $"($t): CORRUPTED — missing required fields. Use 'reset' to start fresh."
        } else {
          let crown = (compute-crown-status $td)
          print $"($t): status=($td.status) gen=($td.generation) survivors=($td.survivors_total) lineage=($td.done_when | length) beads=($td.beads_filed | length) crown=($crown)"
        }
      }
    } else {
      print "No tasks"
    }
  } else {
    let td = get-task $bb $task
    print ($td | to yaml)
  }
}

# Show findings for a task
def "main findings" [task_id: string --severity: string = ""] {
  let bb = load-blackboard
  let task = get-task $bb $task_id
  let findings = if $severity != "" {
    $task.findings | where {|f| $f.severity == $severity}
  } else {
    $task.findings
  }

  print $"FINDINGS: ($findings | length) total"
  print "═══════════════════════════════════════════════════════════════"
  for f in $findings {
    print $"[($f.id)] ($f.severity): ($f.title)"
    print $"  Gen: ($f.generation)  Dim: ($f.dimension)  Cmd: ($f.cmd)"
    if $f.actual_exit != -1 { print $"  Exit: expected=($f.expect_exit) actual=($f.actual_exit)" }
    print ""
  }
}

# Show lineage (all done_when entries)
def "main lineage" [task_id: string] {
  let bb = load-blackboard
  let task = get-task $bb $task_id

  print "PERMANENT LINEAGE (done_when entries)"
  print "═══════════════════════════════════════════════════════════════"
  print $"Total: ($task.done_when | length) checks"
  print ""

  for check in $task.done_when {
    let tag = if "finding_id" in $check { $check.finding_id } else { "initial" }
    let reg = if "regression" in $check and $check.regression { " [REGRESSION]" } else { "" }
    print $"  [($tag)] ($check.severity) gen=($check.generation) dim=($check.dimension)($reg)"
    print $"    cmd: ($check.cmd)"
    print $"    expect_exit: ($check.expect_exit)"
    print ""
  }
}

# Full verdict — computed entirely from blackboard state
def "main verdict" [task_id: string] {
  let bb = load-blackboard
  let task = get-task $bb $task_id
  let crown = (compute-crown-status $task)

  # Count by severity
  let critical = ($task.findings | where {|f| $f.severity == "CRITICAL"} | length)
  let major = ($task.findings | where {|f| $f.severity == "MAJOR"} | length)
  let minor = ($task.findings | where {|f| $f.severity == "MINOR"} | length)
  let observation = ($task.findings | where {|f| $f.severity == "OBSERVATION"} | length)

  print ""
  print "THE RED QUEEN'S VERDICT"
  print "═══════════════════════════════════════════════════════════════"
  print ""
  print $"Champion:    ($task.champion)"
  print $"Generations: ($task.generation)"
  print $"Lineage:     ($task.done_when | length) permanent checks"
  let st = $task.survivors_total
  print $"Survivors:   ($st) — CRITICAL=($critical) MAJOR=($major) MINOR=($minor) OBS=($observation)"
  print $"Beads Filed: ($task.beads_filed | length)"
  print $"Final:       ($crown)"
  print ""

  # Landscape table
  print "FITNESS LANDSCAPE"
  print "═══════════════════════════════════════════════════════════════"
  let header_dim = ("Dimension" | fill -w 25)
  let header_tests = ("Tests" | fill -w 8)
  let header_surv = ("Survivors" | fill -w 12)
  let header_fit = ("Fitness" | fill -w 10)
  print $"($header_dim)($header_tests)($header_surv)($header_fit)Status"
  let sep = ("─" | fill -c "─" -w 67)
  print $sep

  let landscape = $task.landscape
  if ($landscape | columns | length) > 0 {
    for dim in ($landscape | columns) {
      let d = ($landscape | get $dim)
      let fitness = (compute-fitness $d.tests_run $d.survivors)
      let status = (dimension-status $fitness $d.zero_gens)
      let col_dim = ($dim | fill -w 25)
      let col_tests = ($d.tests_run | into string | fill -w 8)
      let col_surv = ($d.survivors | into string | fill -w 12)
      let col_fit = ($fitness | into string | fill -w 10)
      print $"($col_dim)($col_tests)($col_surv)($col_fit)($status)"
    }
  }
  print ""

  # Findings summary
  if ($task.findings | length) > 0 {
    print "FINDINGS"
    print "═══════════════════════════════════════════════════════════════"
    for f in $task.findings {
      print $"  [($f.id)] ($f.severity): ($f.title)"
    }
    print ""
  }

  # Validation status
  if $task.validation_results != null {
    print "VALIDATION"
    print "═══════════════════════════════════════════════════════════════"
    print $"All checks pass: ($task.validation_results.all_pass)"
    print $"Passed: ($task.validation_results.passed)/($task.validation_results.total)"
    if ($task.validation_results.failed | length) > 0 {
      print "Failed checks:"
      for f in $task.validation_results.failed {
        print $"  ($f.severity) [($f.dimension)]: ($f.cmd)"
      }
    }
    print ""
  }

  # Beads filed
  if ($task.beads_filed | length) > 0 {
    print "BEADS FILED"
    print "═══════════════════════════════════════════════════════════════"
    for b in $task.beads_filed {
      print $"  ($b.finding_id): ($b.bead_output)"
    }
    print ""
  }

  print "═══════════════════════════════════════════════════════════════"
}

# Export blackboard as JSON (for CI/CD integration)
def "main export-json" [task_id: string] {
  let bb = load-blackboard
  let task = get-task $bb $task_id
  $task | to json
}

# Allocation advisor — deterministic rules for next generation
def "main allocate" [task_id: string] {
  let bb = load-blackboard
  let task = get-task $bb $task_id

  print "ALLOCATION ADVICE (deterministic rules)"
  print "═══════════════════════════════════════════════════════════════"
  print ""

  let landscape = $task.landscape
  if ($landscape | columns | length) == 0 {
    print "No landscape data — start with broad exploration"
    return
  }

  let gen = $task.generation
  let multiplier = (escalation-multiplier $gen)
  print $"  Escalation multiplier: ($multiplier)x [gen ($gen)]"
  print ""

  for dim in ($landscape | columns) {
    let d = ($landscape | get $dim)
    let fitness = (compute-fitness $d.tests_run $d.survivors)
    let lethality = (compute-lethality $task.findings $dim)
    let reawaken = (should-reawaken $d.zero_gens $gen)

    let base_alloc = if $d.zero_gens >= 3 and (not $reawaken) {
      0
    } else if $reawaken {
      3  # reawakened — probe hard
    } else if $fitness > 0.7 {
      6  # hemorrhaging — maximum assault
    } else if $fitness > 0.5 {
      5  # high pressure — heavy challengers
    } else if $fitness > 0.3 {
      4  # contested — sustained pressure
    } else if $fitness > 0.1 {
      3  # probing — keep pushing
    } else if $fitness == 0.0 and $d.tests_run > 0 {
      2  # cooling — double-tap, never single
    } else {
      3  # default — aggressive baseline
    }

    # Apply escalation multiplier
    let alloc = if $base_alloc == 0 { 0 } else {
      [($base_alloc * $multiplier | math round | into int) 2] | math max
    }

    let status = (dimension-status $fitness $d.zero_gens)
    let reawaken_tag = if $reawaken { " [REAWAKENED]" } else { "" }
    let label = if $alloc == 0 { "SKIP (exhausted)" } else { $"($alloc) challengers" }
    print $"  ($dim | fill -w 20) fit=($fitness | into string | fill -w 6) leth=($lethality | into string | fill -w 6) ($status | fill -w 15) -> ($label)($reawaken_tag)"
  }
  print ""
}

# ── DRQ Coevolution Commands ──────────────────────────────────────────────────

# Carnage report — how much damage has been inflicted across all dimensions
def "main carnage" [task_id: string] {
  let bb = load-blackboard
  let task = get-task $bb $task_id

  print ""
  print "THE RED QUEEN'S CARNAGE REPORT"
  print "═══════════════════════════════════════════════════════════════"
  print $"Champion:    ($task.champion)"
  print $"Generation:  ($task.generation)"
  let esc = (escalation-multiplier $task.generation)
  print $"Escalation:  ($esc)x"
  print ""

  let total_findings = ($task.findings | length)
  let critical = ($task.findings | where {|f| $f.severity == "CRITICAL"} | length)
  let major = ($task.findings | where {|f| $f.severity == "MAJOR"} | length)
  let minor = ($task.findings | where {|f| $f.severity == "MINOR"} | length)
  let total_tests = if ($task.landscape | columns | length) > 0 {
    $task.landscape | columns | each {|dim| ($task.landscape | get $dim).tests_run } | math sum
  } else { 0 }
  let kill_rate = if $total_tests > 0 {
    ($total_findings / $total_tests) | math round --precision 3
  } else { 0.0 }

  print $"Total Attacks:   ($total_tests)"
  print $"Total Kills:     ($total_findings)"
  let kill_pct = ($kill_rate * 100 | math round --precision 1)
  print $"Kill Rate:       ($kill_rate) [($kill_pct)%]"
  print $"  CRITICAL:      ($critical)"
  print $"  MAJOR:         ($major)"
  print $"  MINOR:         ($minor)"
  print $"Beads Filed:     ($task.beads_filed | length)"
  print ""

  # Per-dimension lethality
  if ($task.landscape | columns | length) > 0 {
    let h_dim = ("Dimension" | fill -w 20)
    let h_att = ("Attacks" | fill -w 10)
    let h_kills = ("Kills" | fill -w 10)
    let h_leth = ("Lethality" | fill -w 12)
    print $"($h_dim)($h_att)($h_kills)($h_leth)Status"
    let sep = ("─" | fill -c "─" -w 67)
    print $sep

    for dim in ($task.landscape | columns) {
      let d = ($task.landscape | get $dim)
      let fitness = (compute-fitness $d.tests_run $d.survivors)
      let lethality = (compute-lethality $task.findings $dim)
      let status = (dimension-status $fitness $d.zero_gens)
      let col_dim = ($dim | fill -w 20)
      let col_att = ($d.tests_run | into string | fill -w 10)
      let col_kills = ($d.survivors | into string | fill -w 10)
      let col_leth = ($lethality | into string | fill -w 12)
      print $"($col_dim)($col_att)($col_kills)($col_leth)($status)"
    }
  }
  print ""

  # Threat assessment
  if $kill_rate > 0.5 {
    print "THREAT LEVEL: CRITICAL — codebase is hemorrhaging"
    print "  The code cannot defend itself. Every other attack draws blood."
  } else if $kill_rate > 0.3 {
    print "THREAT LEVEL: HIGH — significant vulnerabilities remain"
    print "  The code is wounded. Sustained pressure will break it further."
  } else if $kill_rate > 0.1 {
    print "THREAT LEVEL: MODERATE — defenses hold but gaps exist"
    print "  Targeted attacks on weak dimensions can still find blood."
  } else if $total_tests > 0 {
    print "THREAT LEVEL: LOW — codebase is defending well"
    print "  But the Queen never stops. Dormant dimensions will reawaken."
  } else {
    print "THREAT LEVEL: UNKNOWN — no attacks launched yet"
  }
  print ""
}

# Lineage replay — run ALL done_when checks and report which generation each came from
# This is the DRQ "defeat ALL predecessors" mechanism
def "main lineage-replay" [task_id: string] {
  let bb = load-blackboard
  let task = get-task $bb $task_id
  let checks = $task.done_when

  if ($checks | length) == 0 {
    print "No lineage to replay"
    return
  }

  print ""
  print "LINEAGE REPLAY — Every predecessor must be defeated"
  print "═══════════════════════════════════════════════════════════════"
  print $"Total lineage: ($checks | length) warriors from ($task.generation) generations"
  print ""

  mut gen_results = {}
  mut total_pass = 0
  mut total_fail = 0

  for check in $checks {
    let result = (run-shell-cmd $check.cmd)
    let passed = ($result.exit_code == $check.expect_exit)
    let gen = $check.generation
    let gen_key = ($gen | into string)

    # Track per-generation results
    let prev = if $gen_key in $gen_results {
      $gen_results | get $gen_key
    } else {
      { passed: 0, failed: 0 }
    }

    if $passed {
      $total_pass = $total_pass + 1
      $gen_results = ($gen_results | upsert $gen_key { passed: ($prev.passed + 1), failed: $prev.failed })
      print $"  DEFEATED [gen ($gen)] ($check.dimension): ($check.cmd)"
    } else {
      $total_fail = $total_fail + 1
      $gen_results = ($gen_results | upsert $gen_key { passed: $prev.passed, failed: ($prev.failed + 1) })
      print $"  SURVIVED [gen ($gen)] ($check.dimension): ($check.cmd) [expected=($check.expect_exit) got=($result.exit_code)]"
    }
  }

  print ""
  print "PER-GENERATION SCORECARD"
  print "═══════════════════════════════════════════════════════════════"
  for gen_key in ($gen_results | columns | sort) {
    let r = ($gen_results | get $gen_key)
    let total = $r.passed + $r.failed
    let verdict = if $r.failed == 0 { "ALL DEFEATED" } else { $"($r.failed) SURVIVORS REMAIN" }
    print $"  Gen ($gen_key): ($r.passed)/($total) defeated — ($verdict)"
  }
  print ""
  print $"TOTAL: ($total_pass)/($total_pass + $total_fail) predecessors defeated"
  if $total_fail > 0 {
    print $"LINEAGE BROKEN: ($total_fail) predecessors still standing — code must evolve further"
  } else {
    print "LINEAGE INTACT: All predecessors defeated — the current code survives"
  }
  print ""
}

# Escalate — auto-promote severity for dimensions with consecutive survivors
def "main escalate" [task_id: string] {
  let bb = load-blackboard
  let task = get-task $bb $task_id

  print ""
  print "SEVERITY ESCALATION CHECK"
  print "═══════════════════════════════════════════════════════════════"

  let landscape = $task.landscape
  if ($landscape | columns | length) == 0 {
    print "No dimensions to check"
    return
  }

  for dim in ($landscape | columns) {
    let d = ($landscape | get $dim)
    # Count consecutive survivors (recent findings in this dimension)
    let dim_findings = ($task.findings | where {|f| $f.dimension == $dim})
    let recent = ($dim_findings | last 3)
    let consecutive = ($recent | length)
    let current_sev = if ($dim_findings | length) > 0 {
      ($dim_findings | last).severity
    } else {
      "MINOR"
    }
    let escalated = (escalate-severity $current_sev $consecutive)
    if $escalated != $current_sev {
      print $"  ($dim): ($current_sev) -> ($escalated) \(($consecutive) consecutive survivors\)"
    } else {
      print $"  ($dim): ($current_sev) \(no escalation, ($consecutive) recent\)"
    }
  }
  print ""
}

# ── Main Entry ────────────────────────────────────────────────────────────────

def main [] {
  print "liza-advanced.nu — Deterministic state machine for Red Queen QA"
  print ""
  print "State Machine:"
  print "  UNCLAIMED -> claim -> IN_PROGRESS -> coder-submit -> READY_FOR_REVIEW"
  print "  -> validate -> approve/reject -> APPROVED -> merge -> MERGED"
  print ""
  print "Evolution Commands:"
  print "  init                                  Initialize blackboard"
  print "  reset                                 Reset blackboard (destructive)"
  print "  task-add <id> [--spec_ref] [--champion]  Add a task"
  print "  task-add-check <id> <cmd>             Lock done_when check (ratchet)"
  print "  claim <id> <agent>                    Claim task (UNCLAIMED->IN_PROGRESS)"
  print "  gen-start <id>                        Start new generation"
  print "  gen-survivor <id> <dim> <cmd>         Record survivor + file bead"
  print "  gen-discard <id> <dim>                Record discard"
  print "  gen-end <id> [--survivors_this_gen N]  End generation (track equilibrium)"
  print "  equilibrium <id>                      Check if equilibrium reached"
  print ""
  print "Regression & Validation:"
  print "  regress <id> <cmd> [--force]          Lock regression test"
  print "  validate <id>                         Run ALL done_when (the ratchet)"
  print "  assert-no-test-weakening              Check no test files modified"
  print ""
  print "Gates (State Transitions):"
  print "  coder-submit <id> <agent>             Submit for review"
  print "  approve <id>                          Approve task"
  print "  reject <id> [--reason]                Reject task"
  print "  merge <id>                            Merge task"
  print ""
  print "DRQ Coevolution:"
  print "  carnage <id>                          Kill rate + lethality per dimension"
  print "  lineage-replay <id>                   Replay ALL predecessors (defeat check)"
  print "  escalate <id>                         Auto-promote severity for hot dimensions"
  print ""
  print "Inspection:"
  print "  show [--task <id>]                    Show task state"
  print "  landscape <id>                        Fitness landscape + crown status"
  print "  findings <id> [--severity S]          List findings"
  print "  lineage <id>                          Show permanent done_when entries"
  print "  verdict <id>                          Full Red Queen verdict"
  print "  allocate <id>                         Next-gen allocation advice (escalating)"
  print "  export-json <id>                      Export task as JSON"
}
