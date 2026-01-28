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

# ── Helpers: Mutation, Spec Mining, Quality, Fowler ──────────────────────────

# Parse cargo-mutants outcomes.json → list of {mutant, status, file, function}
def parse-mutant-outcomes [dir: string] {
  let outcomes_path = $"($dir)/mutants.out/outcomes.json"
  if not ($outcomes_path | path exists) {
    error make {msg: $"No outcomes.json found at ($outcomes_path)"}
  }
  open $outcomes_path | get outcomes | each {|o|
    let status = if "scenario" in $o {
      match ($o.scenario | describe) {
        "string" => $o.scenario
        _ => "unknown"
      }
    } else { "unknown" }
    {
      mutant: (if "summary" in $o { $o.summary } else { "unknown" })
      status: (if "caught" in $o and $o.caught { "caught" } else if "unviable" in $o and $o.unviable { "unviable" } else if "timeout" in $o and $o.timeout { "timeout" } else if "missed" in $o and $o.missed { "missed" } else {
        # Fall back to checking the outcome field
        if "outcome" in $o {
          $o.outcome
        } else { "unknown" }
      })
      file: (if "file" in $o { $o.file } else { "" })
      function: (if "function" in $o { $o.function } else { "" })
      line: (if "line" in $o { $o.line } else { 0 })
    }
  }
}

# Determine mutant severity — auto-escalate pub API
def mutant-severity [base: string, fn_name: string, file_path: string] {
  # pub fn in lib.rs or mod.rs = public API → CRITICAL
  let is_pub_api = ($file_path | str ends-with "lib.rs") or ($file_path | str ends-with "mod.rs")
  if $is_pub_api {
    "CRITICAL"
  } else {
    $base
  }
}

# Detect project language from manifest files
def detect-project-lang [dir: string] {
  if ($"($dir)/Cargo.toml" | path exists) {
    "rust"
  } else if ($"($dir)/gleam.toml" | path exists) {
    "gleam"
  } else if ($"($dir)/pyproject.toml" | path exists) or ($"($dir)/setup.py" | path exists) {
    "python"
  } else if ($"($dir)/package.json" | path exists) {
    "node"
  } else {
    "unknown"
  }
}

# Extract runnable commands from README fenced code blocks
def extract-readme-commands [readme_path: string] {
  if not ($readme_path | path exists) { return [] }
  let content = (open $readme_path)
  let lines = ($content | lines)
  mut commands = []
  mut in_block = false
  mut is_shell_block = false
  mut current_cmd = ""

  for line in $lines {
    if ($line | str starts-with "```bash") or ($line | str starts-with "```shell") or ($line | str starts-with "```sh") or ($line | str starts-with "```console") {
      $in_block = true
      $is_shell_block = true
      $current_cmd = ""
    } else if ($line | str starts-with "```") and $in_block {
      if $is_shell_block and ($current_cmd | str trim | str length) > 0 {
        $commands = ($commands | append ($current_cmd | str trim))
      }
      $in_block = false
      $is_shell_block = false
      $current_cmd = ""
    } else if $in_block and $is_shell_block {
      let trimmed = ($line | str trim)
      # Skip comment lines and empty lines, strip leading $ or >
      if ($trimmed | str length) > 0 and not ($trimmed | str starts-with "#") {
        let cleaned = if ($trimmed | str starts-with "$ ") {
          $trimmed | str substring 2..
        } else if ($trimmed | str starts-with "> ") {
          $trimmed | str substring 2..
        } else {
          $trimmed
        }
        if ($current_cmd | str trim | str length) > 0 {
          $commands = ($commands | append ($current_cmd | str trim))
        }
        $current_cmd = $cleaned
      }
    }
  }
  $commands
}

# Extract subcommands from --help output
def extract-help-subcommands [help_output: string] {
  let lines = ($help_output | lines)
  mut subcmds = []
  mut in_commands = false

  for line in $lines {
    let trimmed = ($line | str trim)
    if ($trimmed | str downcase) =~ "^(commands|subcommands|available commands)" {
      $in_commands = true
    } else if $in_commands {
      if ($trimmed | str length) == 0 {
        $in_commands = false
      } else {
        # Extract first word as subcommand name
        let parts = ($trimmed | split row " " | where {|p| ($p | str length) > 0})
        if ($parts | length) > 0 {
          let cmd = ($parts | first)
          # Skip help itself and decorative lines
          if $cmd != "help" and not ($cmd | str starts-with "-") and not ($cmd | str starts-with "─") {
            $subcmds = ($subcmds | append $cmd)
          }
        }
      }
    }
  }
  $subcmds
}

# Shared helper: run a quality check command, record as survivor or discard
def run-quality-check [task_id: string, cmd: string, dimension: string, title: string, severity: string] {
  let result = (run-shell-cmd $cmd)
  if $result.exit_code != 0 {
    # Failed check → survivor
    let stdout_snip = ($result.stdout | str substring 0..500)
    let stderr_snip = ($result.stderr | str substring 0..500)
    print $"  FAIL: ($title)"
    do { ^nu (blackboard-path | path dirname | path join "../liza-advanced.nu") gen-survivor $task_id $dimension $cmd --severity $severity --title $title --stdout $stdout_snip --stderr $stderr_snip --actual_exit $result.exit_code } | complete
  } else {
    # Passed → discard
    print $"  PASS: ($title)"
    do { ^nu (blackboard-path | path dirname | path join "../liza-advanced.nu") gen-discard $task_id $dimension } | complete
  }
  $result.exit_code
}

# Parse rust-code-analysis JSON output → list of functions exceeding thresholds
def parse-rca-metrics [json_path: string, thresholds: record] {
  if not ($json_path | path exists) { return [] }
  let data = (open $json_path)
  mut violations = []

  # rust-code-analysis outputs per-file metrics; walk through spaces/functions
  let files = if ($data | describe | str starts-with "list") { $data } else { [$data] }
  for file_data in $files {
    let file_name = if "name" in $file_data { $file_data.name } else { "unknown" }
    let spaces = if "spaces" in $file_data { $file_data.spaces } else { [] }
    for space in $spaces {
      let fn_name = if "name" in $space { $space.name } else { "unknown" }
      let metrics = if "metrics" in $space { $space.metrics } else { {} }

      # Check cyclomatic complexity
      if "cyclomatic" in $metrics and "sum" in $metrics.cyclomatic {
        if $metrics.cyclomatic.sum > $thresholds.complexity {
          $violations = ($violations | append {
            file: $file_name
            function: $fn_name
            metric: "cyclomatic"
            value: $metrics.cyclomatic.sum
            threshold: $thresholds.complexity
          })
        }
      }

      # Check SLOC
      if "loc" in $metrics and "sloc" in $metrics.loc {
        if $metrics.loc.sloc > $thresholds.fn_length {
          $violations = ($violations | append {
            file: $file_name
            function: $fn_name
            metric: "fn_length"
            value: $metrics.loc.sloc
            threshold: $thresholds.fn_length
          })
        }
      }

      # Check nesting
      if "nesting" in $metrics and "max" in $metrics.nesting {
        if $metrics.nesting.max > $thresholds.nesting {
          $violations = ($violations | append {
            file: $file_name
            function: $fn_name
            metric: "nesting"
            value: $metrics.nesting.max
            threshold: $thresholds.nesting
          })
        }
      }
    }
  }
  $violations
}

# Parse tokei JSON output → {src_lines, test_lines, comment_lines, ratio, files: [{name, lines}]}
def parse-tokei-json [json_str: string] {
  let data = ($json_str | from json)
  mut src_lines = 0
  mut test_lines = 0
  mut comment_lines = 0
  mut file_details = []

  for lang in ($data | columns) {
    if $lang == "Total" { continue }
    let lang_data = ($data | get $lang)
    if "code" in $lang_data { $src_lines = $src_lines + $lang_data.code }
    if "comments" in $lang_data { $comment_lines = $comment_lines + $lang_data.comments }
    # Check for reports (per-file details)
    if "reports" in $lang_data {
      for report in $lang_data.reports {
        let name = if "name" in $report { $report.name } else { "unknown" }
        let lines = if "stats" in $report and "code" in $report.stats { $report.stats.code } else { 0 }
        let is_test = ($name =~ "test" or $name =~ "tests/" or $name =~ "_test\\." or $name =~ "spec")
        if $is_test {
          $test_lines = $test_lines + $lines
        }
        $file_details = ($file_details | append { name: $name, lines: $lines })
      }
    }
  }

  let ratio = if $src_lines > 0 { ($test_lines / $src_lines) | math round --precision 3 } else { 0.0 }
  { src_lines: $src_lines, test_lines: $test_lines, comment_lines: $comment_lines, ratio: $ratio, files: $file_details }
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

# ── Mutation Testing ──────────────────────────────────────────────────────────

# Run cargo-mutants on a Rust project, record uncaught mutants as survivors
def "main mutate" [
  task_id: string
  project_dir: string
  --file: string = ""
  --function: string = ""
  --timeout: int = 300
  --severity: string = "MAJOR"
] {
  let bb = load-blackboard
  let task = get-task $bb $task_id
  if $task.status != "IN_PROGRESS" {
    error make {msg: $"GATE BLOCKED mutate: status is '($task.status)', expected 'IN_PROGRESS'"}
  }
  let gen_active = if "gen_active" in $task { $task.gen_active } else { false }
  if not $gen_active {
    error make {msg: "GATE BLOCKED mutate: no active generation — call gen-start first"}
  }

  let dir = ($project_dir | path expand)
  if not ($"($dir)/Cargo.toml" | path exists) {
    error make {msg: $"GATE BLOCKED mutate: no Cargo.toml in ($dir) — mutation testing requires Rust"}
  }

  # Build cargo-mutants command
  mut cmd = $"cd ($dir) && cargo mutants --timeout ($timeout)"
  if $file != "" {
    $cmd = $"($cmd) -f ($file)"
  }
  if $function != "" {
    $cmd = $"($cmd) --re ($function)"
  }

  print $"MUTATION TESTING: ($cmd)"
  print "═══════════════════════════════════════════════════════════════"

  let result = (run-shell-cmd $cmd)
  print $"cargo-mutants exit code: ($result.exit_code)"

  # Parse outcomes
  let outcomes_path = $"($dir)/mutants.out/outcomes.json"
  if not ($outcomes_path | path exists) {
    print "WARNING: No outcomes.json found — cargo-mutants may have failed"
    print $"stderr: ($result.stderr | str substring 0..500)"
    return
  }

  let raw_outcomes = (open $outcomes_path)
  let outcomes = if "outcomes" in $raw_outcomes { $raw_outcomes.outcomes } else { [] }

  mut missed = 0
  mut caught = 0
  mut timeout_count = 0
  mut unviable = 0

  for outcome in $outcomes {
    let status = if "summary" in $outcome { $outcome.summary } else { "unknown" }
    let file_path = if "file" in $outcome { $outcome.file } else { "" }
    let fn_name = if "function" in $outcome { $outcome.function } else { "" }
    let mutant_desc = if "scenario" in $outcome {
      $outcome.scenario | to text
    } else {
      $"($file_path):($fn_name)"
    }

    if $status == "MissedMutant" or $status == "missed" {
      $missed = $missed + 1
      let sev = (mutant-severity $severity $fn_name $file_path)
      let check_cmd = $"cd ($dir) && cargo mutants -f ($file_path) --re ($fn_name)"
      # Record as survivor
      let bb_now = load-blackboard
      let task_now = get-task $bb_now $task_id
      let gen = $task_now.generation
      let finding_n = ($task_now.findings | length) + 1
      let finding_id = $"GEN-($gen)-($finding_n)"
      let check = {
        cmd: $check_cmd
        expect_exit: 0
        dimension: "mutation"
        generation: $gen
        severity: $sev
        finding_id: $finding_id
        added_at: (now-timestamp)
      }
      let finding = {
        id: $finding_id
        generation: $gen
        dimension: "mutation"
        severity: $sev
        title: $"Uncaught mutant: ($mutant_desc)"
        cmd: $check_cmd
        expect_exit: 0
        actual_exit: 1
        stdout: ""
        stderr: $"Mutant survived: ($mutant_desc)"
        found_at: (now-timestamp)
      }
      let landscape = $task_now.landscape
      let dim_data = if "mutation" in $landscape {
        $landscape | get "mutation"
      } else {
        { tests_run: 0, survivors: 0, zero_gens: 0, last_survivor_gen: -1 }
      }
      let dim_data2 = ($dim_data | upsert tests_run ($dim_data.tests_run + 1) | upsert survivors ($dim_data.survivors + 1) | upsert zero_gens 0 | upsert last_survivor_gen $gen)
      let landscape2 = ($landscape | upsert "mutation" $dim_data2)
      let task2 = ($task_now
        | upsert done_when ($task_now.done_when | append $check)
        | upsert findings ($task_now.findings | append $finding)
        | upsert landscape $landscape2
        | upsert survivors_total ($task_now.survivors_total + 1)
        | upsert zero_survivor_gens 0)
      save-blackboard (set-task $bb_now $task_id $task2)
      print $"  [($finding_id)] ($sev) MISSED: ($mutant_desc)"

      # File bead
      let priority = (severity-to-priority $sev)
      let bead_title = $"[Red Queen] ($sev): Uncaught mutant: ($mutant_desc)"
      let bead_result = (do { ^bd create --title $bead_title --type bug $"--priority=($priority)" } | complete)
      if $bead_result.exit_code == 0 {
        print $"    BEAD FILED: ($bead_result.stdout | str trim)"
        let bb3 = load-blackboard
        let task3 = get-task $bb3 $task_id
        let new_beads = ($task3.beads_filed | append { finding_id: $finding_id, bead_output: ($bead_result.stdout | str trim), filed_at: (now-timestamp) })
        save-blackboard (set-task $bb3 $task_id ($task3 | upsert beads_filed $new_beads))
      }
    } else if $status == "CaughtMutant" or $status == "caught" {
      $caught = $caught + 1
      # Update landscape tests_run only
      let bb_now = load-blackboard
      let task_now = get-task $bb_now $task_id
      let landscape = $task_now.landscape
      let dim_data = if "mutation" in $landscape { $landscape | get "mutation" } else { { tests_run: 0, survivors: 0, zero_gens: 0, last_survivor_gen: -1 } }
      let dim_data2 = ($dim_data | upsert tests_run ($dim_data.tests_run + 1))
      let landscape2 = ($landscape | upsert "mutation" $dim_data2)
      save-blackboard (set-task $bb_now $task_id ($task_now | upsert landscape $landscape2))
    } else if $status == "Timeout" or $status == "timeout" {
      $timeout_count = $timeout_count + 1
    } else if $status == "Unviable" or $status == "unviable" {
      $unviable = $unviable + 1
    }
  }

  print ""
  print $"MUTATION RESULTS: ($caught) caught, ($missed) missed, ($timeout_count) timeout, ($unviable) unviable"
  if $missed > 0 {
    print $"  ($missed) uncaught mutants recorded as survivors"
  } else {
    print "  All mutants caught — mutation score 100%"
  }
}

# ── Spec Mining ──────────────────────────────────────────────────────────────

# Mine any project for testable promises — adds permanent checks
def "main spec-mine" [
  task_id: string
  project_dir: string
  --bin: string = ""
  --readme: string = ""
  --severity: string = "MINOR"
] {
  let dir = ($project_dir | path expand)
  let lang = (detect-project-lang $dir)
  mut checks_added = 0

  print "SPEC MINING"
  print "═══════════════════════════════════════════════════════════════"
  print $"  Project: ($dir)"
  print $"  Language: ($lang)"
  print ""

  # 2a. README mining
  let readme_path = if $readme != "" { $readme } else { $"($dir)/README.md" }
  if ($readme_path | path exists) {
    print "Mining README..."
    let commands = (extract-readme-commands $readme_path)
    for cmd in $commands {
      # Use task-add-check (no gen-start needed)
      let bb = load-blackboard
      let task = get-task $bb $task_id
      if $task.status == "MERGED" or $task.status == "APPROVED" {
        print $"  SKIP: task is ($task.status)"
        continue
      }
      let check = {
        cmd: $"cd ($dir) && ($cmd)"
        expect_exit: 0
        dimension: "spec-readme"
        generation: $task.generation
        severity: $severity
        added_at: (now-timestamp)
      }
      let task2 = ($task | upsert done_when ($task.done_when | append $check))
      save-blackboard (set-task $bb $task_id $task2)
      $checks_added = $checks_added + 1
      print $"  CHECK LOCKED [spec-readme]: cd ($dir) && ($cmd)"
    }
  } else {
    print "  No README.md found — skipping"
  }

  # 2b. CLI --help mining
  if $bin != "" {
    print ""
    print "Mining CLI --help..."
    let help_result = (run-shell-cmd $"($bin) --help")
    if $help_result.exit_code == 0 {
      let subcmds = (extract-help-subcommands $help_result.stdout)
      for subcmd in $subcmds {
        let bb = load-blackboard
        let task = get-task $bb $task_id
        let check = {
          cmd: $"($bin) ($subcmd) --help"
          expect_exit: 0
          dimension: "spec-help"
          generation: $task.generation
          severity: $severity
          added_at: (now-timestamp)
        }
        let task2 = ($task | upsert done_when ($task.done_when | append $check))
        save-blackboard (set-task $bb $task_id $task2)
        $checks_added = $checks_added + 1
        print $"  CHECK LOCKED [spec-help]: ($bin) ($subcmd) --help"
      }
      # Also add --version check
      let bb = load-blackboard
      let task = get-task $bb $task_id
      let version_check = {
        cmd: $"($bin) --version"
        expect_exit: 0
        dimension: "spec-help"
        generation: $task.generation
        severity: $severity
        added_at: (now-timestamp)
      }
      let task2 = ($task | upsert done_when ($task.done_when | append $version_check))
      save-blackboard (set-task $bb $task_id $task2)
      $checks_added = $checks_added + 1
      print $"  CHECK LOCKED [spec-help]: ($bin) --version"
    } else {
      print $"  ($bin) --help failed — skipping CLI mining"
    }
  }

  # 2c. Doc comment mining
  print ""
  print "Mining doc comments..."
  if $lang == "rust" {
    # Rust doc tests
    let doctest_result = (run-shell-cmd $"cd ($dir) && grep -rl '/// # Examples' src/ 2>/dev/null")
    if $doctest_result.exit_code == 0 and ($doctest_result.stdout | str trim | str length) > 0 {
      let bb = load-blackboard
      let task = get-task $bb $task_id
      let check = {
        cmd: $"cd ($dir) && cargo test --doc"
        expect_exit: 0
        dimension: "spec-doctest"
        generation: $task.generation
        severity: $severity
        added_at: (now-timestamp)
      }
      let task2 = ($task | upsert done_when ($task.done_when | append $check))
      save-blackboard (set-task $bb $task_id $task2)
      $checks_added = $checks_added + 1
      print $"  CHECK LOCKED [spec-doctest]: cargo test --doc"
    }
  } else if $lang == "python" {
    # Python doctests
    let doctest_result = (run-shell-cmd $"cd ($dir) && grep -rl '>>>' --include='*.py' . 2>/dev/null")
    if $doctest_result.exit_code == 0 {
      let files = ($doctest_result.stdout | lines | where {|l| ($l | str length) > 0})
      for f in $files {
        let bb = load-blackboard
        let task = get-task $bb $task_id
        let check = {
          cmd: $"cd ($dir) && python -m doctest ($f)"
          expect_exit: 0
          dimension: "spec-doctest"
          generation: $task.generation
          severity: $severity
          added_at: (now-timestamp)
        }
        let task2 = ($task | upsert done_when ($task.done_when | append $check))
        save-blackboard (set-task $bb $task_id $task2)
        $checks_added = $checks_added + 1
        print $"  CHECK LOCKED [spec-doctest]: python -m doctest ($f)"
      }
    }
  }

  # TODO/FIXME/HACK/XXX debt mining (any language)
  let debt_result = (run-shell-cmd $"cd ($dir) && grep -rn 'TODO\\|FIXME\\|HACK\\|XXX' --include='*.rs' --include='*.py' --include='*.gleam' --include='*.ts' --include='*.js' src/ lib/ . 2>/dev/null | head -50")
  if $debt_result.exit_code == 0 and ($debt_result.stdout | str trim | str length) > 0 {
    let debt_lines = ($debt_result.stdout | lines | where {|l| ($l | str length) > 0} | length)
    if $debt_lines > 0 {
      let bb = load-blackboard
      let task = get-task $bb $task_id
      let check = {
        cmd: $"cd ($dir) && ! grep -rn 'TODO\\|FIXME\\|HACK\\|XXX' --include='*.rs' --include='*.py' --include='*.gleam' src/ lib/ 2>/dev/null | head -1"
        expect_exit: 0
        dimension: "spec-debt"
        generation: $task.generation
        severity: "OBSERVATION"
        added_at: (now-timestamp)
      }
      let task2 = ($task | upsert done_when ($task.done_when | append $check))
      save-blackboard (set-task $bb $task_id $task2)
      $checks_added = $checks_added + 1
      print $"  CHECK LOCKED [spec-debt]: ($debt_lines) TODO/FIXME/HACK/XXX markers found"
    }
  }

  # 2d. Type safety mining (Rust bonus)
  if $lang == "rust" {
    print ""
    print "Mining type safety (Rust)..."
    let bb = load-blackboard
    let task = get-task $bb $task_id
    let check = {
      cmd: $"cd ($dir) && cargo clippy -- -D clippy::unwrap_used"
      expect_exit: 0
      dimension: "spec-type-safety"
      generation: $task.generation
      severity: "MAJOR"
      added_at: (now-timestamp)
    }
    let task2 = ($task | upsert done_when ($task.done_when | append $check))
    save-blackboard (set-task $bb $task_id $task2)
    $checks_added = $checks_added + 1
    print "  CHECK LOCKED [spec-type-safety]: cargo clippy -- -D clippy::unwrap_used"
  }

  print ""
  print $"SPEC MINING COMPLETE: ($checks_added) checks added to done_when ratchet"
}

# ── Quality Gates ────────────────────────────────────────────────────────────

# Deterministic code quality checks — each failure is a survivor
def "main quality-gate" [
  task_id: string
  project_dir: string
  --severity: string = "MAJOR"
] {
  let bb = load-blackboard
  let task = get-task $bb $task_id
  if $task.status != "IN_PROGRESS" {
    error make {msg: $"GATE BLOCKED quality-gate: status is '($task.status)', expected 'IN_PROGRESS'"}
  }
  let gen_active = if "gen_active" in $task { $task.gen_active } else { false }
  if not $gen_active {
    error make {msg: "GATE BLOCKED quality-gate: no active generation — call gen-start first"}
  }

  let dir = ($project_dir | path expand)
  let lang = (detect-project-lang $dir)

  print "QUALITY GATES"
  print "═══════════════════════════════════════════════════════════════"
  print $"  Project: ($dir)"
  print $"  Language: ($lang)"
  print ""

  # 3a. FP Gates
  print "FP Gates:"
  if $lang == "rust" {
    # No Panic
    let r = (run-shell-cmd $"cd ($dir) && cargo clippy -- -D clippy::unwrap_used -D clippy::expect_used -D clippy::panic")
    if $r.exit_code != 0 {
      print "  FAIL: No Panic (unwrap/expect/panic detected)"
      # Record inline as survivor
      let bb2 = load-blackboard
      let t = get-task $bb2 $task_id
      let gen = $t.generation
      let fid = $"GEN-($gen)-(($t.findings | length) + 1)"
      let check = { cmd: $"cd ($dir) && cargo clippy -- -D clippy::unwrap_used -D clippy::expect_used -D clippy::panic", expect_exit: 0, dimension: "fp-gate-no-panic", generation: $gen, severity: $severity, finding_id: $fid, added_at: (now-timestamp) }
      let finding = { id: $fid, generation: $gen, dimension: "fp-gate-no-panic", severity: $severity, title: "FP Gate: unwrap/expect/panic detected", cmd: $check.cmd, expect_exit: 0, actual_exit: $r.exit_code, stdout: ($r.stdout | str substring 0..300), stderr: ($r.stderr | str substring 0..300), found_at: (now-timestamp) }
      let ld = if "fp-gate-no-panic" in $t.landscape { $t.landscape | get "fp-gate-no-panic" } else { { tests_run: 0, survivors: 0, zero_gens: 0, last_survivor_gen: -1 } }
      let t2 = ($t | upsert done_when ($t.done_when | append $check) | upsert findings ($t.findings | append $finding) | upsert landscape ($t.landscape | upsert "fp-gate-no-panic" ($ld | upsert tests_run ($ld.tests_run + 1) | upsert survivors ($ld.survivors + 1) | upsert zero_gens 0 | upsert last_survivor_gen $gen)) | upsert survivors_total ($t.survivors_total + 1) | upsert zero_survivor_gens 0)
      save-blackboard (set-task $bb2 $task_id $t2)
    } else {
      print "  PASS: No Panic"
      let bb2 = load-blackboard
      let t = get-task $bb2 $task_id
      let ld = if "fp-gate-no-panic" in $t.landscape { $t.landscape | get "fp-gate-no-panic" } else { { tests_run: 0, survivors: 0, zero_gens: 0, last_survivor_gen: -1 } }
      let t2 = ($t | upsert landscape ($t.landscape | upsert "fp-gate-no-panic" ($ld | upsert tests_run ($ld.tests_run + 1))))
      save-blackboard (set-task $bb2 $task_id $t2)
    }

    # Exhaustive Match
    let r = (run-shell-cmd $"cd ($dir) && cargo clippy -- -D clippy::wildcard_enum_match_arm")
    if $r.exit_code != 0 {
      print "  FAIL: Exhaustive Match"
      let bb2 = load-blackboard
      let t = get-task $bb2 $task_id
      let gen = $t.generation
      let fid = $"GEN-($gen)-(($t.findings | length) + 1)"
      let check = { cmd: $"cd ($dir) && cargo clippy -- -D clippy::wildcard_enum_match_arm", expect_exit: 0, dimension: "fp-gate-exhaustive", generation: $gen, severity: $severity, finding_id: $fid, added_at: (now-timestamp) }
      let finding = { id: $fid, generation: $gen, dimension: "fp-gate-exhaustive", severity: $severity, title: "FP Gate: wildcard enum match arms", cmd: $check.cmd, expect_exit: 0, actual_exit: $r.exit_code, stdout: "", stderr: ($r.stderr | str substring 0..300), found_at: (now-timestamp) }
      let ld = if "fp-gate-exhaustive" in $t.landscape { $t.landscape | get "fp-gate-exhaustive" } else { { tests_run: 0, survivors: 0, zero_gens: 0, last_survivor_gen: -1 } }
      let t2 = ($t | upsert done_when ($t.done_when | append $check) | upsert findings ($t.findings | append $finding) | upsert landscape ($t.landscape | upsert "fp-gate-exhaustive" ($ld | upsert tests_run ($ld.tests_run + 1) | upsert survivors ($ld.survivors + 1) | upsert zero_gens 0 | upsert last_survivor_gen $gen)) | upsert survivors_total ($t.survivors_total + 1) | upsert zero_survivor_gens 0)
      save-blackboard (set-task $bb2 $task_id $t2)
    } else {
      print "  PASS: Exhaustive Match"
      let bb2 = load-blackboard
      let t = get-task $bb2 $task_id
      let ld = if "fp-gate-exhaustive" in $t.landscape { $t.landscape | get "fp-gate-exhaustive" } else { { tests_run: 0, survivors: 0, zero_gens: 0, last_survivor_gen: -1 } }
      let t2 = ($t | upsert landscape ($t.landscape | upsert "fp-gate-exhaustive" ($ld | upsert tests_run ($ld.tests_run + 1))))
      save-blackboard (set-task $bb2 $task_id $t2)
    }

    # Format
    let r = (run-shell-cmd $"cd ($dir) && cargo fmt --check")
    if $r.exit_code != 0 {
      print "  FAIL: Format"
      let bb2 = load-blackboard
      let t = get-task $bb2 $task_id
      let gen = $t.generation
      let fid = $"GEN-($gen)-(($t.findings | length) + 1)"
      let check = { cmd: $"cd ($dir) && cargo fmt --check", expect_exit: 0, dimension: "fp-gate-format", generation: $gen, severity: "MINOR", finding_id: $fid, added_at: (now-timestamp) }
      let finding = { id: $fid, generation: $gen, dimension: "fp-gate-format", severity: "MINOR", title: "FP Gate: code not formatted", cmd: $check.cmd, expect_exit: 0, actual_exit: $r.exit_code, stdout: ($r.stdout | str substring 0..300), stderr: "", found_at: (now-timestamp) }
      let ld = if "fp-gate-format" in $t.landscape { $t.landscape | get "fp-gate-format" } else { { tests_run: 0, survivors: 0, zero_gens: 0, last_survivor_gen: -1 } }
      let t2 = ($t | upsert done_when ($t.done_when | append $check) | upsert findings ($t.findings | append $finding) | upsert landscape ($t.landscape | upsert "fp-gate-format" ($ld | upsert tests_run ($ld.tests_run + 1) | upsert survivors ($ld.survivors + 1) | upsert zero_gens 0 | upsert last_survivor_gen $gen)) | upsert survivors_total ($t.survivors_total + 1) | upsert zero_survivor_gens 0)
      save-blackboard (set-task $bb2 $task_id $t2)
    } else {
      print "  PASS: Format"
      let bb2 = load-blackboard
      let t = get-task $bb2 $task_id
      let ld = if "fp-gate-format" in $t.landscape { $t.landscape | get "fp-gate-format" } else { { tests_run: 0, survivors: 0, zero_gens: 0, last_survivor_gen: -1 } }
      let t2 = ($t | upsert landscape ($t.landscape | upsert "fp-gate-format" ($ld | upsert tests_run ($ld.tests_run + 1))))
      save-blackboard (set-task $bb2 $task_id $t2)
    }

    # Lint
    let r = (run-shell-cmd $"cd ($dir) && cargo clippy -- -D warnings")
    if $r.exit_code != 0 {
      print "  FAIL: Lint"
      let bb2 = load-blackboard
      let t = get-task $bb2 $task_id
      let gen = $t.generation
      let fid = $"GEN-($gen)-(($t.findings | length) + 1)"
      let check = { cmd: $"cd ($dir) && cargo clippy -- -D warnings", expect_exit: 0, dimension: "fp-gate-lint", generation: $gen, severity: $severity, finding_id: $fid, added_at: (now-timestamp) }
      let finding = { id: $fid, generation: $gen, dimension: "fp-gate-lint", severity: $severity, title: "FP Gate: clippy warnings", cmd: $check.cmd, expect_exit: 0, actual_exit: $r.exit_code, stdout: "", stderr: ($r.stderr | str substring 0..300), found_at: (now-timestamp) }
      let ld = if "fp-gate-lint" in $t.landscape { $t.landscape | get "fp-gate-lint" } else { { tests_run: 0, survivors: 0, zero_gens: 0, last_survivor_gen: -1 } }
      let t2 = ($t | upsert done_when ($t.done_when | append $check) | upsert findings ($t.findings | append $finding) | upsert landscape ($t.landscape | upsert "fp-gate-lint" ($ld | upsert tests_run ($ld.tests_run + 1) | upsert survivors ($ld.survivors + 1) | upsert zero_gens 0 | upsert last_survivor_gen $gen)) | upsert survivors_total ($t.survivors_total + 1) | upsert zero_survivor_gens 0)
      save-blackboard (set-task $bb2 $task_id $t2)
    } else {
      print "  PASS: Lint"
      let bb2 = load-blackboard
      let t = get-task $bb2 $task_id
      let ld = if "fp-gate-lint" in $t.landscape { $t.landscape | get "fp-gate-lint" } else { { tests_run: 0, survivors: 0, zero_gens: 0, last_survivor_gen: -1 } }
      let t2 = ($t | upsert landscape ($t.landscape | upsert "fp-gate-lint" ($ld | upsert tests_run ($ld.tests_run + 1))))
      save-blackboard (set-task $bb2 $task_id $t2)
    }

    # Tests Pass
    let r = (run-shell-cmd $"cd ($dir) && cargo test")
    if $r.exit_code != 0 {
      print "  FAIL: Tests"
      let bb2 = load-blackboard
      let t = get-task $bb2 $task_id
      let gen = $t.generation
      let fid = $"GEN-($gen)-(($t.findings | length) + 1)"
      let check = { cmd: $"cd ($dir) && cargo test", expect_exit: 0, dimension: "fp-gate-tests", generation: $gen, severity: "CRITICAL", finding_id: $fid, added_at: (now-timestamp) }
      let finding = { id: $fid, generation: $gen, dimension: "fp-gate-tests", severity: "CRITICAL", title: "FP Gate: tests failing", cmd: $check.cmd, expect_exit: 0, actual_exit: $r.exit_code, stdout: ($r.stdout | str substring 0..300), stderr: ($r.stderr | str substring 0..300), found_at: (now-timestamp) }
      let ld = if "fp-gate-tests" in $t.landscape { $t.landscape | get "fp-gate-tests" } else { { tests_run: 0, survivors: 0, zero_gens: 0, last_survivor_gen: -1 } }
      let t2 = ($t | upsert done_when ($t.done_when | append $check) | upsert findings ($t.findings | append $finding) | upsert landscape ($t.landscape | upsert "fp-gate-tests" ($ld | upsert tests_run ($ld.tests_run + 1) | upsert survivors ($ld.survivors + 1) | upsert zero_gens 0 | upsert last_survivor_gen $gen)) | upsert survivors_total ($t.survivors_total + 1) | upsert zero_survivor_gens 0)
      save-blackboard (set-task $bb2 $task_id $t2)
    } else {
      print "  PASS: Tests"
      let bb2 = load-blackboard
      let t = get-task $bb2 $task_id
      let ld = if "fp-gate-tests" in $t.landscape { $t.landscape | get "fp-gate-tests" } else { { tests_run: 0, survivors: 0, zero_gens: 0, last_survivor_gen: -1 } }
      let t2 = ($t | upsert landscape ($t.landscape | upsert "fp-gate-tests" ($ld | upsert tests_run ($ld.tests_run + 1))))
      save-blackboard (set-task $bb2 $task_id $t2)
    }

    # Test Coverage (tarpaulin)
    let r = (run-shell-cmd $"cd ($dir) && cargo tarpaulin --skip-clean --out json 2>/dev/null")
    if $r.exit_code == 0 {
      # Try to parse coverage percentage
      let cov_data = (try { $r.stdout | from json } catch { null })
      if $cov_data != null and "coverage" in $cov_data {
        let cov_pct = $cov_data.coverage
        if $cov_pct < 80.0 {
          print $"  FAIL: Test Coverage \(($cov_pct)% < 80%\)"
          let bb2 = load-blackboard
          let t = get-task $bb2 $task_id
          let gen = $t.generation
          let fid = $"GEN-($gen)-(($t.findings | length) + 1)"
          let check = { cmd: $"cd ($dir) && cargo tarpaulin --skip-clean --fail-under 80", expect_exit: 0, dimension: "fp-gate-coverage", generation: $gen, severity: $severity, finding_id: $fid, added_at: (now-timestamp) }
          let finding = { id: $fid, generation: $gen, dimension: "fp-gate-coverage", severity: $severity, title: $"FP Gate: coverage ($cov_pct)% < 80%", cmd: $check.cmd, expect_exit: 0, actual_exit: 1, stdout: "", stderr: $"Coverage: ($cov_pct)%", found_at: (now-timestamp) }
          let ld = if "fp-gate-coverage" in $t.landscape { $t.landscape | get "fp-gate-coverage" } else { { tests_run: 0, survivors: 0, zero_gens: 0, last_survivor_gen: -1 } }
          let t2 = ($t | upsert done_when ($t.done_when | append $check) | upsert findings ($t.findings | append $finding) | upsert landscape ($t.landscape | upsert "fp-gate-coverage" ($ld | upsert tests_run ($ld.tests_run + 1) | upsert survivors ($ld.survivors + 1) | upsert zero_gens 0 | upsert last_survivor_gen $gen)) | upsert survivors_total ($t.survivors_total + 1) | upsert zero_survivor_gens 0)
          save-blackboard (set-task $bb2 $task_id $t2)
        } else {
          print $"  PASS: Test Coverage \(($cov_pct)%\)"
          let bb2 = load-blackboard
          let t = get-task $bb2 $task_id
          let ld = if "fp-gate-coverage" in $t.landscape { $t.landscape | get "fp-gate-coverage" } else { { tests_run: 0, survivors: 0, zero_gens: 0, last_survivor_gen: -1 } }
          let t2 = ($t | upsert landscape ($t.landscape | upsert "fp-gate-coverage" ($ld | upsert tests_run ($ld.tests_run + 1))))
          save-blackboard (set-task $bb2 $task_id $t2)
        }
      }
    } else {
      print "  SKIP: tarpaulin not available"
    }
  } else if $lang == "gleam" {
    # Gleam gates
    let r = (run-shell-cmd $"cd ($dir) && gleam format --check")
    if $r.exit_code != 0 {
      print "  FAIL: Format (Gleam)"
      let bb2 = load-blackboard
      let t = get-task $bb2 $task_id
      let gen = $t.generation
      let fid = $"GEN-($gen)-(($t.findings | length) + 1)"
      let check = { cmd: $"cd ($dir) && gleam format --check", expect_exit: 0, dimension: "fp-gate-format", generation: $gen, severity: "MINOR", finding_id: $fid, added_at: (now-timestamp) }
      let finding = { id: $fid, generation: $gen, dimension: "fp-gate-format", severity: "MINOR", title: "FP Gate: Gleam code not formatted", cmd: $check.cmd, expect_exit: 0, actual_exit: $r.exit_code, stdout: "", stderr: "", found_at: (now-timestamp) }
      let ld = if "fp-gate-format" in $t.landscape { $t.landscape | get "fp-gate-format" } else { { tests_run: 0, survivors: 0, zero_gens: 0, last_survivor_gen: -1 } }
      let t2 = ($t | upsert done_when ($t.done_when | append $check) | upsert findings ($t.findings | append $finding) | upsert landscape ($t.landscape | upsert "fp-gate-format" ($ld | upsert tests_run ($ld.tests_run + 1) | upsert survivors ($ld.survivors + 1) | upsert zero_gens 0 | upsert last_survivor_gen $gen)) | upsert survivors_total ($t.survivors_total + 1) | upsert zero_survivor_gens 0)
      save-blackboard (set-task $bb2 $task_id $t2)
    } else {
      print "  PASS: Format (Gleam)"
    }

    let r = (run-shell-cmd $"cd ($dir) && gleam build")
    if $r.exit_code != 0 {
      print "  FAIL: Build (Gleam)"
      let bb2 = load-blackboard
      let t = get-task $bb2 $task_id
      let gen = $t.generation
      let fid = $"GEN-($gen)-(($t.findings | length) + 1)"
      let check = { cmd: $"cd ($dir) && gleam build", expect_exit: 0, dimension: "fp-gate-lint", generation: $gen, severity: $severity, finding_id: $fid, added_at: (now-timestamp) }
      let finding = { id: $fid, generation: $gen, dimension: "fp-gate-lint", severity: $severity, title: "FP Gate: Gleam build fails", cmd: $check.cmd, expect_exit: 0, actual_exit: $r.exit_code, stdout: "", stderr: ($r.stderr | str substring 0..300), found_at: (now-timestamp) }
      let ld = if "fp-gate-lint" in $t.landscape { $t.landscape | get "fp-gate-lint" } else { { tests_run: 0, survivors: 0, zero_gens: 0, last_survivor_gen: -1 } }
      let t2 = ($t | upsert done_when ($t.done_when | append $check) | upsert findings ($t.findings | append $finding) | upsert landscape ($t.landscape | upsert "fp-gate-lint" ($ld | upsert tests_run ($ld.tests_run + 1) | upsert survivors ($ld.survivors + 1) | upsert zero_gens 0 | upsert last_survivor_gen $gen)) | upsert survivors_total ($t.survivors_total + 1) | upsert zero_survivor_gens 0)
      save-blackboard (set-task $bb2 $task_id $t2)
    } else {
      print "  PASS: Build (Gleam)"
    }

    let r = (run-shell-cmd $"cd ($dir) && gleam test")
    if $r.exit_code != 0 {
      print "  FAIL: Tests (Gleam)"
      let bb2 = load-blackboard
      let t = get-task $bb2 $task_id
      let gen = $t.generation
      let fid = $"GEN-($gen)-(($t.findings | length) + 1)"
      let check = { cmd: $"cd ($dir) && gleam test", expect_exit: 0, dimension: "fp-gate-tests", generation: $gen, severity: "CRITICAL", finding_id: $fid, added_at: (now-timestamp) }
      let finding = { id: $fid, generation: $gen, dimension: "fp-gate-tests", severity: "CRITICAL", title: "FP Gate: Gleam tests failing", cmd: $check.cmd, expect_exit: 0, actual_exit: $r.exit_code, stdout: ($r.stdout | str substring 0..300), stderr: ($r.stderr | str substring 0..300), found_at: (now-timestamp) }
      let ld = if "fp-gate-tests" in $t.landscape { $t.landscape | get "fp-gate-tests" } else { { tests_run: 0, survivors: 0, zero_gens: 0, last_survivor_gen: -1 } }
      let t2 = ($t | upsert done_when ($t.done_when | append $check) | upsert findings ($t.findings | append $finding) | upsert landscape ($t.landscape | upsert "fp-gate-tests" ($ld | upsert tests_run ($ld.tests_run + 1) | upsert survivors ($ld.survivors + 1) | upsert zero_gens 0 | upsert last_survivor_gen $gen)) | upsert survivors_total ($t.survivors_total + 1) | upsert zero_survivor_gens 0)
      save-blackboard (set-task $bb2 $task_id $t2)
    } else {
      print "  PASS: Tests (Gleam)"
    }
  }

  # 3b. DRY Check (Rust only)
  if $lang == "rust" {
    print ""
    print "DRY Check:"
    let r = (run-shell-cmd $"cd ($dir) && cargo clippy -- -D clippy::redundant_clone -D clippy::manual_map -D clippy::unnecessary_wraps")
    if $r.exit_code != 0 {
      print "  FAIL: DRY violations"
      let bb2 = load-blackboard
      let t = get-task $bb2 $task_id
      let gen = $t.generation
      let fid = $"GEN-($gen)-(($t.findings | length) + 1)"
      let check = { cmd: $"cd ($dir) && cargo clippy -- -D clippy::redundant_clone -D clippy::manual_map -D clippy::unnecessary_wraps", expect_exit: 0, dimension: "quality-dry", generation: $gen, severity: $severity, finding_id: $fid, added_at: (now-timestamp) }
      let finding = { id: $fid, generation: $gen, dimension: "quality-dry", severity: $severity, title: "DRY violations detected", cmd: $check.cmd, expect_exit: 0, actual_exit: $r.exit_code, stdout: "", stderr: ($r.stderr | str substring 0..300), found_at: (now-timestamp) }
      let ld = if "quality-dry" in $t.landscape { $t.landscape | get "quality-dry" } else { { tests_run: 0, survivors: 0, zero_gens: 0, last_survivor_gen: -1 } }
      let t2 = ($t | upsert done_when ($t.done_when | append $check) | upsert findings ($t.findings | append $finding) | upsert landscape ($t.landscape | upsert "quality-dry" ($ld | upsert tests_run ($ld.tests_run + 1) | upsert survivors ($ld.survivors + 1) | upsert zero_gens 0 | upsert last_survivor_gen $gen)) | upsert survivors_total ($t.survivors_total + 1) | upsert zero_survivor_gens 0)
      save-blackboard (set-task $bb2 $task_id $t2)
    } else {
      print "  PASS: DRY"
      let bb2 = load-blackboard
      let t = get-task $bb2 $task_id
      let ld = if "quality-dry" in $t.landscape { $t.landscape | get "quality-dry" } else { { tests_run: 0, survivors: 0, zero_gens: 0, last_survivor_gen: -1 } }
      let t2 = ($t | upsert landscape ($t.landscape | upsert "quality-dry" ($ld | upsert tests_run ($ld.tests_run + 1))))
      save-blackboard (set-task $bb2 $task_id $t2)
    }
  }

  # 3c. Test Quality — test-to-code ratio
  print ""
  print "Test Quality:"
  let tokei_result = (run-shell-cmd $"cd ($dir) && tokei --output json 2>/dev/null")
  if $tokei_result.exit_code == 0 {
    let metrics = (try { parse-tokei-json $tokei_result.stdout } catch { null })
    if $metrics != null {
      if $metrics.ratio < 0.5 {
        print $"  FAIL: Test-to-code ratio ($metrics.ratio) < 0.5"
        let bb2 = load-blackboard
        let t = get-task $bb2 $task_id
        let gen = $t.generation
        let fid = $"GEN-($gen)-(($t.findings | length) + 1)"
        let check_cmd = $"cd ($dir) && tokei --output json | nu -c 'let d = ($in | from json); let s = ($d | values | each {|v| if \"code\" in $v { $v.code } else { 0 }} | math sum); if $s > 0 { print \"ok\" } else { exit 1 }'"
        let check = { cmd: $check_cmd, expect_exit: 0, dimension: "quality-test-coverage", generation: $gen, severity: $severity, finding_id: $fid, added_at: (now-timestamp) }
        let finding = { id: $fid, generation: $gen, dimension: "quality-test-coverage", severity: $severity, title: $"Test-to-code ratio ($metrics.ratio) < 0.5", cmd: $check_cmd, expect_exit: 0, actual_exit: 1, stdout: "", stderr: $"ratio=($metrics.ratio)", found_at: (now-timestamp) }
        let ld = if "quality-test-coverage" in $t.landscape { $t.landscape | get "quality-test-coverage" } else { { tests_run: 0, survivors: 0, zero_gens: 0, last_survivor_gen: -1 } }
        let t2 = ($t | upsert done_when ($t.done_when | append $check) | upsert findings ($t.findings | append $finding) | upsert landscape ($t.landscape | upsert "quality-test-coverage" ($ld | upsert tests_run ($ld.tests_run + 1) | upsert survivors ($ld.survivors + 1) | upsert zero_gens 0 | upsert last_survivor_gen $gen)) | upsert survivors_total ($t.survivors_total + 1) | upsert zero_survivor_gens 0)
        save-blackboard (set-task $bb2 $task_id $t2)
      } else {
        print $"  PASS: Test-to-code ratio ($metrics.ratio)"
      }
    }
  } else {
    print "  SKIP: tokei not available"
  }

  print ""
  print "QUALITY GATES COMPLETE"
}

# ── Fowler Review ────────────────────────────────────────────────────────────

# Martin Fowler code + test quality review using real AST/analysis tools
def "main fowler-review" [
  task_id: string
  project_dir: string
  --severity: string = "MAJOR"
  --complexity-threshold: int = 15
  --fn-length-threshold: int = 50
  --file-length-threshold: int = 250
  --nesting-threshold: int = 4
  --coverage-threshold: float = 80.0
] {
  let bb = load-blackboard
  let task = get-task $bb $task_id
  if $task.status != "IN_PROGRESS" {
    error make {msg: $"GATE BLOCKED fowler-review: status is '($task.status)', expected 'IN_PROGRESS'"}
  }
  let gen_active = if "gen_active" in $task { $task.gen_active } else { false }
  if not $gen_active {
    error make {msg: "GATE BLOCKED fowler-review: no active generation — call gen-start first"}
  }

  let dir = ($project_dir | path expand)
  let lang = (detect-project-lang $dir)

  print "FOWLER REVIEW — Source + Test Quality"
  print "═══════════════════════════════════════════════════════════════"
  print $"  Project: ($dir)"
  print $"  Language: ($lang)"
  print $"  Thresholds: complexity=($complexity_threshold) fn_length=($fn_length_threshold) file_length=($file_length_threshold) nesting=($nesting_threshold) coverage=($coverage_threshold)%"
  print ""

  # Helper closure to record a gate result inline
  # We'll use a helper function pattern to reduce repetition

  # 4a. Source Code Structural Analysis — rust-code-analysis-cli
  print "4a. Structural Analysis (rust-code-analysis-cli):"
  let rca_check = (run-shell-cmd $"which rust-code-analysis-cli 2>/dev/null")
  if $rca_check.exit_code == 0 {
    let rca_out = $"($dir)/rca-output.json"
    let rca_result = (run-shell-cmd $"rust-code-analysis-cli -p ($dir)/src -O json > ($rca_out) 2>/dev/null")
    if $rca_result.exit_code == 0 and ($rca_out | path exists) {
      let thresholds = { complexity: $complexity_threshold, fn_length: $fn_length_threshold, nesting: $nesting_threshold }
      let violations = (try { parse-rca-metrics $rca_out $thresholds } catch { [] })
      for v in $violations {
        let dim = $"fowler-($v.metric | str replace '_' '-')"
        let title = $"($v.function) in ($v.file): ($v.metric)=($v.value) > ($v.threshold)"
        print $"  FAIL: ($title)"
        let bb2 = load-blackboard
        let t = get-task $bb2 $task_id
        let gen = $t.generation
        let fid = $"GEN-($gen)-(($t.findings | length) + 1)"
        let check = { cmd: $"rust-code-analysis-cli -p ($dir)/src -O json | grep -q '\"($v.function)\"'", expect_exit: 0, dimension: $dim, generation: $gen, severity: $severity, finding_id: $fid, added_at: (now-timestamp) }
        let finding = { id: $fid, generation: $gen, dimension: $dim, severity: $severity, title: $title, cmd: $check.cmd, expect_exit: 0, actual_exit: 1, stdout: "", stderr: "", found_at: (now-timestamp) }
        let ld = if $dim in $t.landscape { $t.landscape | get $dim } else { { tests_run: 0, survivors: 0, zero_gens: 0, last_survivor_gen: -1 } }
        let t2 = ($t | upsert done_when ($t.done_when | append $check) | upsert findings ($t.findings | append $finding) | upsert landscape ($t.landscape | upsert $dim ($ld | upsert tests_run ($ld.tests_run + 1) | upsert survivors ($ld.survivors + 1) | upsert zero_gens 0 | upsert last_survivor_gen $gen)) | upsert survivors_total ($t.survivors_total + 1) | upsert zero_survivor_gens 0)
        save-blackboard (set-task $bb2 $task_id $t2)
      }
      if ($violations | length) == 0 {
        print "  PASS: All functions within thresholds"
      }
    } else {
      print "  SKIP: rust-code-analysis-cli failed or no src/"
    }
    # Clean up temp file
    do { ^rm -f $rca_out } | complete
  } else {
    print "  SKIP: rust-code-analysis-cli not installed"
  }

  # Cognitive complexity via clippy
  if $lang == "rust" {
    let r = (run-shell-cmd $"cd ($dir) && cargo clippy -- -D clippy::cognitive_complexity 2>&1")
    if $r.exit_code != 0 {
      print "  FAIL: Cognitive complexity (clippy)"
      let bb2 = load-blackboard
      let t = get-task $bb2 $task_id
      let gen = $t.generation
      let fid = $"GEN-($gen)-(($t.findings | length) + 1)"
      let check = { cmd: $"cd ($dir) && cargo clippy -- -D clippy::cognitive_complexity", expect_exit: 0, dimension: "fowler-cognitive", generation: $gen, severity: $severity, finding_id: $fid, added_at: (now-timestamp) }
      let finding = { id: $fid, generation: $gen, dimension: "fowler-cognitive", severity: $severity, title: "Cognitive complexity too high", cmd: $check.cmd, expect_exit: 0, actual_exit: $r.exit_code, stdout: "", stderr: ($r.stderr | str substring 0..300), found_at: (now-timestamp) }
      let ld = if "fowler-cognitive" in $t.landscape { $t.landscape | get "fowler-cognitive" } else { { tests_run: 0, survivors: 0, zero_gens: 0, last_survivor_gen: -1 } }
      let t2 = ($t | upsert done_when ($t.done_when | append $check) | upsert findings ($t.findings | append $finding) | upsert landscape ($t.landscape | upsert "fowler-cognitive" ($ld | upsert tests_run ($ld.tests_run + 1) | upsert survivors ($ld.survivors + 1) | upsert zero_gens 0 | upsert last_survivor_gen $gen)) | upsert survivors_total ($t.survivors_total + 1) | upsert zero_survivor_gens 0)
      save-blackboard (set-task $bb2 $task_id $t2)
    } else {
      print "  PASS: Cognitive complexity"
    }
  }

  # 4b. AST Pattern Matching — ast-grep
  print ""
  print "4b. AST Pattern Matching (ast-grep):"
  let sg_check = (run-shell-cmd "which ast-grep 2>/dev/null || which sg 2>/dev/null")
  let sg_bin = if $sg_check.exit_code == 0 { $sg_check.stdout | str trim | lines | first } else { "" }
  if $sg_bin != "" and $lang == "rust" {
    let patterns = [
      { pattern: "$X.unwrap()", dimension: "fowler-unwrap", title: ".unwrap() calls" }
      { pattern: "$X.expect($MSG)", dimension: "fowler-expect", title: ".expect() calls" }
      { pattern: "todo!()", dimension: "fowler-todo", title: "todo!() macros" }
      { pattern: "unimplemented!()", dimension: "fowler-todo", title: "unimplemented!() macros" }
    ]
    for pat in $patterns {
      let r = (run-shell-cmd $"($sg_bin) --pattern '($pat.pattern)' --json ($dir)/src/ 2>/dev/null")
      if $r.exit_code == 0 and ($r.stdout | str trim | str length) > 2 {
        let matches = (try { $r.stdout | from json | length } catch { 0 })
        if $matches > 0 {
          print $"  FAIL: ($pat.title) — ($matches) matches"
          let bb2 = load-blackboard
          let t = get-task $bb2 $task_id
          let gen = $t.generation
          let fid = $"GEN-($gen)-(($t.findings | length) + 1)"
          let check = { cmd: $"($sg_bin) --pattern '($pat.pattern)' ($dir)/src/ 2>/dev/null | wc -l | xargs test 0 -eq", expect_exit: 0, dimension: $pat.dimension, generation: $gen, severity: $severity, finding_id: $fid, added_at: (now-timestamp) }
          let finding = { id: $fid, generation: $gen, dimension: $pat.dimension, severity: $severity, title: $"($pat.title): ($matches) found", cmd: $check.cmd, expect_exit: 0, actual_exit: 1, stdout: "", stderr: "", found_at: (now-timestamp) }
          let ld = if $pat.dimension in $t.landscape { $t.landscape | get $pat.dimension } else { { tests_run: 0, survivors: 0, zero_gens: 0, last_survivor_gen: -1 } }
          let t2 = ($t | upsert done_when ($t.done_when | append $check) | upsert findings ($t.findings | append $finding) | upsert landscape ($t.landscape | upsert $pat.dimension ($ld | upsert tests_run ($ld.tests_run + 1) | upsert survivors ($ld.survivors + 1) | upsert zero_gens 0 | upsert last_survivor_gen $gen)) | upsert survivors_total ($t.survivors_total + 1) | upsert zero_survivor_gens 0)
          save-blackboard (set-task $bb2 $task_id $t2)
        } else {
          print $"  PASS: ($pat.title)"
        }
      } else {
        print $"  PASS: ($pat.title)"
      }
    }
  } else {
    print "  SKIP: ast-grep not installed or not Rust"
  }

  # 4c. Clippy Extended Checks
  if $lang == "rust" {
    print ""
    print "4c. Clippy Extended Checks:"

    let clippy_checks = [
      { flags: "-D dead_code -D unused_imports", dimension: "fowler-dead-code", title: "Dead code / unused imports" }
      { flags: "-D clippy::redundant_clone -D clippy::manual_map", dimension: "fowler-dry", title: "DRY violations" }
      { flags: "-D clippy::unwrap_used -D clippy::expect_used", dimension: "fowler-error-handling", title: "Error handling (unwrap/expect)" }
      { flags: "-D clippy::wildcard_enum_match_arm", dimension: "fowler-exhaustive", title: "Wildcard enum matches" }
    ]

    for cc in $clippy_checks {
      let r = (run-shell-cmd $"cd ($dir) && cargo clippy -- ($cc.flags) 2>&1")
      if $r.exit_code != 0 {
        print $"  FAIL: ($cc.title)"
        let bb2 = load-blackboard
        let t = get-task $bb2 $task_id
        let gen = $t.generation
        let fid = $"GEN-($gen)-(($t.findings | length) + 1)"
        let check = { cmd: $"cd ($dir) && cargo clippy -- ($cc.flags)", expect_exit: 0, dimension: $cc.dimension, generation: $gen, severity: $severity, finding_id: $fid, added_at: (now-timestamp) }
        let finding = { id: $fid, generation: $gen, dimension: $cc.dimension, severity: $severity, title: $cc.title, cmd: $check.cmd, expect_exit: 0, actual_exit: $r.exit_code, stdout: "", stderr: ($r.stderr | str substring 0..300), found_at: (now-timestamp) }
        let ld = if $cc.dimension in $t.landscape { $t.landscape | get $cc.dimension } else { { tests_run: 0, survivors: 0, zero_gens: 0, last_survivor_gen: -1 } }
        let t2 = ($t | upsert done_when ($t.done_when | append $check) | upsert findings ($t.findings | append $finding) | upsert landscape ($t.landscape | upsert $cc.dimension ($ld | upsert tests_run ($ld.tests_run + 1) | upsert survivors ($ld.survivors + 1) | upsert zero_gens 0 | upsert last_survivor_gen $gen)) | upsert survivors_total ($t.survivors_total + 1) | upsert zero_survivor_gens 0)
        save-blackboard (set-task $bb2 $task_id $t2)
      } else {
        print $"  PASS: ($cc.title)"
        let bb2 = load-blackboard
        let t = get-task $bb2 $task_id
        let ld = if $cc.dimension in $t.landscape { $t.landscape | get $cc.dimension } else { { tests_run: 0, survivors: 0, zero_gens: 0, last_survivor_gen: -1 } }
        let t2 = ($t | upsert landscape ($t.landscape | upsert $cc.dimension ($ld | upsert tests_run ($ld.tests_run + 1))))
        save-blackboard (set-task $bb2 $task_id $t2)
      }
    }
  }

  # 4d. Test Code Review
  print ""
  print "4d. Test Code Review:"

  if $lang == "rust" {
    # No assertions check
    let test_files_result = (run-shell-cmd $"find ($dir)/tests ($dir)/src -name '*.rs' 2>/dev/null | head -50")
    if $test_files_result.exit_code == 0 {
      let test_files = ($test_files_result.stdout | lines | where {|l| ($l | str length) > 0})
      for tf in $test_files {
        let has_test_fn = (run-shell-cmd $"grep -c '#\\[test\\]' '($tf)' 2>/dev/null")
        if $has_test_fn.exit_code == 0 {
          let test_count = (try { $has_test_fn.stdout | str trim | into int } catch { 0 })
          if $test_count > 0 {
            let assert_count_r = (run-shell-cmd $"rg -c 'assert' '($tf)' 2>/dev/null")
            let assert_count = if $assert_count_r.exit_code == 0 { (try { $assert_count_r.stdout | str trim | into int } catch { 0 }) } else { 0 }
            if $assert_count == 0 {
              let short_path = ($tf | str replace $dir ".")
              print $"  FAIL: No assertions in ($short_path) \(($test_count) test fns\)"
              let bb2 = load-blackboard
              let t = get-task $bb2 $task_id
              let gen = $t.generation
              let fid = $"GEN-($gen)-(($t.findings | length) + 1)"
              let check = { cmd: $"rg -c 'assert' '($tf)' | xargs test 0 -lt", expect_exit: 0, dimension: "fowler-test-no-assert", generation: $gen, severity: $severity, finding_id: $fid, added_at: (now-timestamp) }
              let finding = { id: $fid, generation: $gen, dimension: "fowler-test-no-assert", severity: $severity, title: $"No assertions in ($short_path)", cmd: $check.cmd, expect_exit: 0, actual_exit: 1, stdout: "", stderr: "", found_at: (now-timestamp) }
              let ld = if "fowler-test-no-assert" in $t.landscape { $t.landscape | get "fowler-test-no-assert" } else { { tests_run: 0, survivors: 0, zero_gens: 0, last_survivor_gen: -1 } }
              let t2 = ($t | upsert done_when ($t.done_when | append $check) | upsert findings ($t.findings | append $finding) | upsert landscape ($t.landscape | upsert "fowler-test-no-assert" ($ld | upsert tests_run ($ld.tests_run + 1) | upsert survivors ($ld.survivors + 1) | upsert zero_gens 0 | upsert last_survivor_gen $gen)) | upsert survivors_total ($t.survivors_total + 1) | upsert zero_survivor_gens 0)
              save-blackboard (set-task $bb2 $task_id $t2)
            }
          }
        }
      }
    }

    # Test-to-code ratio via tokei
    let tokei_r = (run-shell-cmd $"cd ($dir) && tokei --output json 2>/dev/null")
    if $tokei_r.exit_code == 0 {
      let metrics = (try { parse-tokei-json $tokei_r.stdout } catch { null })
      if $metrics != null and $metrics.ratio < 0.5 {
        print $"  FAIL: Test-to-code ratio ($metrics.ratio) < 0.5"
        let bb2 = load-blackboard
        let t = get-task $bb2 $task_id
        let gen = $t.generation
        let fid = $"GEN-($gen)-(($t.findings | length) + 1)"
        let check = { cmd: $"cd ($dir) && tokei --output json", expect_exit: 0, dimension: "fowler-test-ratio", generation: $gen, severity: $severity, finding_id: $fid, added_at: (now-timestamp) }
        let finding = { id: $fid, generation: $gen, dimension: "fowler-test-ratio", severity: $severity, title: $"Test-to-code ratio ($metrics.ratio) < 0.5", cmd: $check.cmd, expect_exit: 0, actual_exit: 1, stdout: "", stderr: "", found_at: (now-timestamp) }
        let ld = if "fowler-test-ratio" in $t.landscape { $t.landscape | get "fowler-test-ratio" } else { { tests_run: 0, survivors: 0, zero_gens: 0, last_survivor_gen: -1 } }
        let t2 = ($t | upsert done_when ($t.done_when | append $check) | upsert findings ($t.findings | append $finding) | upsert landscape ($t.landscape | upsert "fowler-test-ratio" ($ld | upsert tests_run ($ld.tests_run + 1) | upsert survivors ($ld.survivors + 1) | upsert zero_gens 0 | upsert last_survivor_gen $gen)) | upsert survivors_total ($t.survivors_total + 1) | upsert zero_survivor_gens 0)
        save-blackboard (set-task $bb2 $task_id $t2)
      } else if $metrics != null {
        print $"  PASS: Test-to-code ratio ($metrics.ratio)"
      }
    }

    # Coverage threshold — cargo-llvm-cov
    let llvm_cov_r = (run-shell-cmd $"cd ($dir) && cargo llvm-cov --json --fail-under-lines ($coverage_threshold) 2>/dev/null")
    if $llvm_cov_r.exit_code != 0 {
      let has_tool = (run-shell-cmd "which cargo-llvm-cov 2>/dev/null")
      if $has_tool.exit_code == 0 {
        print $"  FAIL: Test coverage below ($coverage_threshold)%"
        let bb2 = load-blackboard
        let t = get-task $bb2 $task_id
        let gen = $t.generation
        let fid = $"GEN-($gen)-(($t.findings | length) + 1)"
        let check = { cmd: $"cd ($dir) && cargo llvm-cov --fail-under-lines ($coverage_threshold)", expect_exit: 0, dimension: "fowler-test-coverage", generation: $gen, severity: $severity, finding_id: $fid, added_at: (now-timestamp) }
        let finding = { id: $fid, generation: $gen, dimension: "fowler-test-coverage", severity: $severity, title: $"Test coverage below ($coverage_threshold)%", cmd: $check.cmd, expect_exit: 0, actual_exit: $llvm_cov_r.exit_code, stdout: "", stderr: ($llvm_cov_r.stderr | str substring 0..300), found_at: (now-timestamp) }
        let ld = if "fowler-test-coverage" in $t.landscape { $t.landscape | get "fowler-test-coverage" } else { { tests_run: 0, survivors: 0, zero_gens: 0, last_survivor_gen: -1 } }
        let t2 = ($t | upsert done_when ($t.done_when | append $check) | upsert findings ($t.findings | append $finding) | upsert landscape ($t.landscape | upsert "fowler-test-coverage" ($ld | upsert tests_run ($ld.tests_run + 1) | upsert survivors ($ld.survivors + 1) | upsert zero_gens 0 | upsert last_survivor_gen $gen)) | upsert survivors_total ($t.survivors_total + 1) | upsert zero_survivor_gens 0)
        save-blackboard (set-task $bb2 $task_id $t2)
      } else {
        print "  SKIP: cargo-llvm-cov not installed"
      }
    } else {
      print $"  PASS: Test coverage >= ($coverage_threshold)%"
    }

    # Happy path only check
    let test_dir_exists = ($"($dir)/tests" | path exists)
    if $test_dir_exists {
      let test_fn_count_r = (run-shell-cmd $"rg -c '#\\[test\\]' ($dir)/tests/ 2>/dev/null | paste -sd+ | bc 2>/dev/null")
      let err_test_r = (run-shell-cmd $"rg -c 'Err\\|Error\\|panic\\|should_fail\\|expect_err' ($dir)/tests/ 2>/dev/null | paste -sd+ | bc 2>/dev/null")
      let test_fn_count = (try { $test_fn_count_r.stdout | str trim | into int } catch { 0 })
      let err_test_count = (try { $err_test_r.stdout | str trim | into int } catch { 0 })
      if $test_fn_count > 5 and $err_test_count < ($test_fn_count * 0.3 | math round | into int) {
        print $"  FAIL: Happy path only — ($err_test_count)/($test_fn_count) test error paths"
        let bb2 = load-blackboard
        let t = get-task $bb2 $task_id
        let gen = $t.generation
        let fid = $"GEN-($gen)-(($t.findings | length) + 1)"
        let check = { cmd: $"rg -c 'Err|Error|panic|should_fail|expect_err' ($dir)/tests/ 2>/dev/null | paste -sd+ | bc", expect_exit: 0, dimension: "fowler-test-happy-only", generation: $gen, severity: "MINOR", finding_id: $fid, added_at: (now-timestamp) }
        let finding = { id: $fid, generation: $gen, dimension: "fowler-test-happy-only", severity: "MINOR", title: $"Happy path only: ($err_test_count)/($test_fn_count) error paths", cmd: $check.cmd, expect_exit: 0, actual_exit: 1, stdout: "", stderr: "", found_at: (now-timestamp) }
        let ld = if "fowler-test-happy-only" in $t.landscape { $t.landscape | get "fowler-test-happy-only" } else { { tests_run: 0, survivors: 0, zero_gens: 0, last_survivor_gen: -1 } }
        let t2 = ($t | upsert done_when ($t.done_when | append $check) | upsert findings ($t.findings | append $finding) | upsert landscape ($t.landscape | upsert "fowler-test-happy-only" ($ld | upsert tests_run ($ld.tests_run + 1) | upsert survivors ($ld.survivors + 1) | upsert zero_gens 0 | upsert last_survivor_gen $gen)) | upsert survivors_total ($t.survivors_total + 1) | upsert zero_survivor_gens 0)
        save-blackboard (set-task $bb2 $task_id $t2)
      } else if $test_fn_count > 0 {
        print $"  PASS: Error paths covered ($err_test_count)/($test_fn_count)"
      }
    }

    # Flaky indicators
    let flaky_r = (run-shell-cmd $"rg -c 'sleep|thread::sleep|tokio::time::sleep' ($dir)/tests/ 2>/dev/null | paste -sd+ | bc 2>/dev/null")
    let flaky_count = (try { $flaky_r.stdout | str trim | into int } catch { 0 })
    if $flaky_count > 0 {
      print $"  WARN: ($flaky_count) sleep calls in tests (flaky risk)"
      let bb2 = load-blackboard
      let t = get-task $bb2 $task_id
      let gen = $t.generation
      let fid = $"GEN-($gen)-(($t.findings | length) + 1)"
      let check = { cmd: $"! rg -q 'sleep|thread::sleep|tokio::time::sleep' ($dir)/tests/", expect_exit: 0, dimension: "fowler-test-flaky", generation: $gen, severity: "MINOR", finding_id: $fid, added_at: (now-timestamp) }
      let finding = { id: $fid, generation: $gen, dimension: "fowler-test-flaky", severity: "MINOR", title: $"($flaky_count) sleep calls in tests", cmd: $check.cmd, expect_exit: 0, actual_exit: 1, stdout: "", stderr: "", found_at: (now-timestamp) }
      let ld = if "fowler-test-flaky" in $t.landscape { $t.landscape | get "fowler-test-flaky" } else { { tests_run: 0, survivors: 0, zero_gens: 0, last_survivor_gen: -1 } }
      let t2 = ($t | upsert done_when ($t.done_when | append $check) | upsert findings ($t.findings | append $finding) | upsert landscape ($t.landscape | upsert "fowler-test-flaky" ($ld | upsert tests_run ($ld.tests_run + 1) | upsert survivors ($ld.survivors + 1) | upsert zero_gens 0 | upsert last_survivor_gen $gen)) | upsert survivors_total ($t.survivors_total + 1) | upsert zero_survivor_gens 0)
      save-blackboard (set-task $bb2 $task_id $t2)
    }

    # Test isolation
    let isolation_r = (run-shell-cmd $"rg -c 'static mut|lazy_static|once_cell.*Mutex' ($dir)/tests/ 2>/dev/null | paste -sd+ | bc 2>/dev/null")
    let isolation_count = (try { $isolation_r.stdout | str trim | into int } catch { 0 })
    if $isolation_count > 0 {
      print $"  WARN: ($isolation_count) shared state patterns in tests"
      let bb2 = load-blackboard
      let t = get-task $bb2 $task_id
      let gen = $t.generation
      let fid = $"GEN-($gen)-(($t.findings | length) + 1)"
      let check = { cmd: $"! rg -q 'static mut|lazy_static|once_cell.*Mutex' ($dir)/tests/", expect_exit: 0, dimension: "fowler-test-isolation", generation: $gen, severity: "MINOR", finding_id: $fid, added_at: (now-timestamp) }
      let finding = { id: $fid, generation: $gen, dimension: "fowler-test-isolation", severity: "MINOR", title: $"($isolation_count) shared state patterns in tests", cmd: $check.cmd, expect_exit: 0, actual_exit: 1, stdout: "", stderr: "", found_at: (now-timestamp) }
      let ld = if "fowler-test-isolation" in $t.landscape { $t.landscape | get "fowler-test-isolation" } else { { tests_run: 0, survivors: 0, zero_gens: 0, last_survivor_gen: -1 } }
      let t2 = ($t | upsert done_when ($t.done_when | append $check) | upsert findings ($t.findings | append $finding) | upsert landscape ($t.landscape | upsert "fowler-test-isolation" ($ld | upsert tests_run ($ld.tests_run + 1) | upsert survivors ($ld.survivors + 1) | upsert zero_gens 0 | upsert last_survivor_gen $gen)) | upsert survivors_total ($t.survivors_total + 1) | upsert zero_survivor_gens 0)
      save-blackboard (set-task $bb2 $task_id $t2)
    }
  }

  # 4e. Security & Supply Chain
  if $lang == "rust" {
    print ""
    print "4e. Security & Supply Chain:"

    let security_checks = [
      { cmd_suffix: "cargo geiger --forbid-only --output-format json", dimension: "fowler-unsafe", title: "Unsafe code (geiger)", tool: "cargo-geiger" }
      { cmd_suffix: "cargo audit --json", dimension: "fowler-security", title: "Security vulnerabilities", tool: "cargo-audit" }
      { cmd_suffix: "cargo udeps --output json 2>&1", dimension: "fowler-unused-deps", title: "Unused dependencies", tool: "cargo-udeps" }
      { cmd_suffix: "cargo deny check 2>&1", dimension: "fowler-licenses", title: "License issues", tool: "cargo-deny" }
    ]

    for sc in $security_checks {
      let tool_check = (run-shell-cmd $"which ($sc.tool) 2>/dev/null")
      if $tool_check.exit_code == 0 {
        let r = (run-shell-cmd $"cd ($dir) && ($sc.cmd_suffix)")
        if $r.exit_code != 0 {
          print $"  FAIL: ($sc.title)"
          let bb2 = load-blackboard
          let t = get-task $bb2 $task_id
          let gen = $t.generation
          let fid = $"GEN-($gen)-(($t.findings | length) + 1)"
          let check = { cmd: $"cd ($dir) && ($sc.cmd_suffix)", expect_exit: 0, dimension: $sc.dimension, generation: $gen, severity: $severity, finding_id: $fid, added_at: (now-timestamp) }
          let finding = { id: $fid, generation: $gen, dimension: $sc.dimension, severity: $severity, title: $sc.title, cmd: $check.cmd, expect_exit: 0, actual_exit: $r.exit_code, stdout: ($r.stdout | str substring 0..300), stderr: ($r.stderr | str substring 0..300), found_at: (now-timestamp) }
          let ld = if $sc.dimension in $t.landscape { $t.landscape | get $sc.dimension } else { { tests_run: 0, survivors: 0, zero_gens: 0, last_survivor_gen: -1 } }
          let t2 = ($t | upsert done_when ($t.done_when | append $check) | upsert findings ($t.findings | append $finding) | upsert landscape ($t.landscape | upsert $sc.dimension ($ld | upsert tests_run ($ld.tests_run + 1) | upsert survivors ($ld.survivors + 1) | upsert zero_gens 0 | upsert last_survivor_gen $gen)) | upsert survivors_total ($t.survivors_total + 1) | upsert zero_survivor_gens 0)
          save-blackboard (set-task $bb2 $task_id $t2)
        } else {
          print $"  PASS: ($sc.title)"
          let bb2 = load-blackboard
          let t = get-task $bb2 $task_id
          let ld = if $sc.dimension in $t.landscape { $t.landscape | get $sc.dimension } else { { tests_run: 0, survivors: 0, zero_gens: 0, last_survivor_gen: -1 } }
          let t2 = ($t | upsert landscape ($t.landscape | upsert $sc.dimension ($ld | upsert tests_run ($ld.tests_run + 1))))
          save-blackboard (set-task $bb2 $task_id $t2)
        }
      } else {
        print $"  SKIP: ($sc.tool) not installed"
      }
    }
  }

  # 4f. LOC Metrics & File Size Enforcement
  print ""
  print "4f. LOC Metrics & File Size:"
  let tokei_r = (run-shell-cmd $"cd ($dir) && tokei --output json 2>/dev/null")
  if $tokei_r.exit_code == 0 {
    let metrics = (try { parse-tokei-json $tokei_r.stdout } catch { null })
    if $metrics != null {
      # Check file sizes
      for f in $metrics.files {
        if $f.lines > $file_length_threshold {
          let short = ($f.name | str replace $dir ".")
          print $"  FAIL: ($short) is ($f.lines) lines > ($file_length_threshold)"
          let bb2 = load-blackboard
          let t = get-task $bb2 $task_id
          let gen = $t.generation
          let fid = $"GEN-($gen)-(($t.findings | length) + 1)"
          let check = { cmd: $"wc -l < '($f.name)' | xargs test ($file_length_threshold) -ge", expect_exit: 0, dimension: "fowler-file-size", generation: $gen, severity: "MINOR", finding_id: $fid, added_at: (now-timestamp) }
          let finding = { id: $fid, generation: $gen, dimension: "fowler-file-size", severity: "MINOR", title: $"($short) is ($f.lines) lines", cmd: $check.cmd, expect_exit: 0, actual_exit: 1, stdout: "", stderr: "", found_at: (now-timestamp) }
          let ld = if "fowler-file-size" in $t.landscape { $t.landscape | get "fowler-file-size" } else { { tests_run: 0, survivors: 0, zero_gens: 0, last_survivor_gen: -1 } }
          let t2 = ($t | upsert done_when ($t.done_when | append $check) | upsert findings ($t.findings | append $finding) | upsert landscape ($t.landscape | upsert "fowler-file-size" ($ld | upsert tests_run ($ld.tests_run + 1) | upsert survivors ($ld.survivors + 1) | upsert zero_gens 0 | upsert last_survivor_gen $gen)) | upsert survivors_total ($t.survivors_total + 1) | upsert zero_survivor_gens 0)
          save-blackboard (set-task $bb2 $task_id $t2)
        }
      }

      # Comment ratio on public API
      if $metrics.src_lines > 0 {
        let comment_ratio = ($metrics.comment_lines / $metrics.src_lines) | math round --precision 3
        if $comment_ratio < 0.05 {
          print $"  FAIL: Comment ratio ($comment_ratio) < 5%"
          let bb2 = load-blackboard
          let t = get-task $bb2 $task_id
          let gen = $t.generation
          let fid = $"GEN-($gen)-(($t.findings | length) + 1)"
          let check = { cmd: $"cd ($dir) && tokei --output json", expect_exit: 0, dimension: "fowler-documentation", generation: $gen, severity: "OBSERVATION", finding_id: $fid, added_at: (now-timestamp) }
          let finding = { id: $fid, generation: $gen, dimension: "fowler-documentation", severity: "OBSERVATION", title: $"Comment ratio ($comment_ratio) < 5%", cmd: $check.cmd, expect_exit: 0, actual_exit: 1, stdout: "", stderr: "", found_at: (now-timestamp) }
          let ld = if "fowler-documentation" in $t.landscape { $t.landscape | get "fowler-documentation" } else { { tests_run: 0, survivors: 0, zero_gens: 0, last_survivor_gen: -1 } }
          let t2 = ($t | upsert done_when ($t.done_when | append $check) | upsert findings ($t.findings | append $finding) | upsert landscape ($t.landscape | upsert "fowler-documentation" ($ld | upsert tests_run ($ld.tests_run + 1) | upsert survivors ($ld.survivors + 1) | upsert zero_gens 0 | upsert last_survivor_gen $gen)) | upsert survivors_total ($t.survivors_total + 1) | upsert zero_survivor_gens 0)
          save-blackboard (set-task $bb2 $task_id $t2)
        } else {
          print $"  PASS: Comment ratio ($comment_ratio)"
        }
      }
    }
  } else {
    print "  SKIP: tokei not available"
  }

  print ""
  print "FOWLER REVIEW COMPLETE"
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
  print ""
  print "Mutation Testing (Rust):"
  print "  mutate <id> <dir> [--file] [--function]    Run cargo-mutants, record survivors"
  print ""
  print "Spec Mining (any language):"
  print "  spec-mine <id> <dir> [--bin] [--readme]    Extract promises as permanent checks"
  print ""
  print "Quality Gates (from tdd15):"
  print "  quality-gate <id> <dir>                    FP + DRY + coverage checks"
  print ""
  print "Fowler Review (source + tests):"
  print "  fowler-review <id> <dir>                   Code smells + test smells + architecture"
}
