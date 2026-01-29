#!/usr/bin/env nu
# Tests for oc-tdd15.nu - TDD15 Phase Definitions

use std testing

print "Testing oc-tdd15.nu..."

# Import the module
use ../oc-tdd15.nu *

# Test: PHASES_COMPLEX constant
def test-phases-complex [] {
  assert equal ($PHASES_COMPLEX | length) 16
  assert equal $PHASES.0 0
  assert equal $PHASES_COMPLEX.15 15
}

# Test: PHASES_MEDIUM constant
def test-phases-medium [] {
  let expected = [0 1 2 4 5 6 7 9 11 15]
  assert equal $PHASES_MEDIUM $expected
}

# Test: PHASES_SIMPLE constant
def test-phases-simple [] {
  let expected = [0 4 5 6 14 15]
  assert equal $PHASES_SIMPLE $expected
}

# Test: tdd15-route for complex complexity
def test-tdd15-route-complex [] {
  let route = (tdd15-route "complex")
  assert equal $route $PHASES_COMPLEX
}

# Test: tdd15-route for medium complexity
def test-tdd15-route-medium [] {
  let route = (tdd15-route "medium")
  assert equal $route $PHASES_MEDIUM
}

# Test: tdd15-route for simple complexity
def test-tdd15-route-simple [] {
  let route = (tdd15-route "simple")
  assert equal $route $PHASES_SIMPLE
}

# Test: tdd15-route for unknown complexity (defaults to simple)
def test-tdd15-route-unknown [] {
  let route = (tdd15-route "unknown")
  assert equal $route $PHASES_SIMPLE
}

# Test: tdd15-route case insensitive
def test-tdd15-route-case-insensitive [] {
  let route1 = (tdd15-route "COMPLEX")
  let route2 = (tdd15-route "High")
  let route3 = (tdd15-route "Low")
  
  assert equal $route1 $PHASES_COMPLEX
  assert equal $route2 $PHASES_MEDIUM
  assert equal $route3 $PHASES_SIMPLE
}

# Test: tdd15-job creates correct structure
def test-tdd15-job-structure [] {
  let job = (tdd15-job "test-bead")
  
  assert equal $job.name "tdd15-test-bead"
  assert equal $job.position 0
  assert equal $job.inputs.bead_id "test-bead"
  assert ($job.tasks | is-not-empty)
  assert ($job.defaults | is-not-empty)
}

# Test: tdd15-job includes triage task
def test-tdd15-job-has-triage [] {
  let job = (tdd15-job "test-bead")
  let triage_task = ($job.tasks | where name == "triage" | first)
  
  assert ($triage_task | is-not-empty)
  assert equal $triage_task.name "triage"
  assert equal $triage_task.var "triage"
  assert equal $triage_task.run "phase-0-triage"
}

# Test: tdd15-job includes red phase
def test-tdd15-job-has-red [] {
  let job = (tdd15-job "test-bead")
  let red_task = ($job.tasks | where name == "red" | first)
  
  assert ($red_task | is-not-empty)
  assert equal $red_task.name "red"
  assert equal $red_task.var "red"
  assert equal $red_task.run "phase-4-red"
}

# Test: tdd15-job includes green phase
def test-tdd15-job-has-green [] {
  let job = (tdd15-job "test-bead")
  let green_task = ($job.tasks | where name == "green" | first)
  
  assert ($green_task | is-not-empty)
  assert equal $green_task.name "green"
  assert equal $green_task.var "green"
  assert equal $green_task.run "phase-5-green"
}

# Test: tdd15-job includes refactor phase
def test-tdd15-job-has-refactor [] {
  let job = (tdd15-job "test-bead")
  let refactor_task = ($job.tasks | where name == "refactor" | first)
  
  assert ($refactor_task | is-not-empty)
  assert equal $refactor_task.name "refactor"
  assert equal $refactor_task.var "refactor"
  assert equal $refactor_task.run "phase-6-refactor"
}

# Test: tdd15-job with position parameter
def test-tdd15-job-position [] {
  let job = (tdd15-job "test-bead" --position 5)
  
  assert equal $job.position 5
}

print "[ok] oc-tdd15.nu tests completed"
