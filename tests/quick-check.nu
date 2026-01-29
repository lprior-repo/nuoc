#!/usr/bin/env nu
# Quick validation: Format and lint check for Nushell code

use std testing

print "Running quick validation..."

# List of source files to check
let source_files = [
  "oc-agent.nu"
  "oc-engine.nu"
  "oc-orchestrate.nu"
  "oc-tdd15.nu"
]

print "Checking Nushell files..."

# Collect results
let results = ($source_files | each {|file|
  let expanded = ($file | path expand)
  if ($expanded | path exists) {
    try {
      # Try to parse file
      nu -n -c $"source ($file)"
      { file: $file, status: "ok" }
    } catch {|e|
      { file: $file, status: "fail", error: ($e | get msg? | default 'parse error') }
    }
  } else {
    { file: $file, status: "skip", error: "not found" }
  }
})

# Print results
for result in $results {
  match $result.status {
    "ok" => { print $"  [ok] ($result.file)" }
    "fail" => { print $"  [fail] ($result.file): ($result.error)" }
    "skip" => { print $"  [skip] ($result.file)" }
  }
}

# Count results
let passed = ($results | where status == "ok" | length)
let failed = ($results | where status == "fail" | length)
let skipped = ($results | where status == "skip" | length)

print ""
print $"Passed: ($passed)"
print $"Failed: ($failed)"
print $"Skipped: ($skipped)"

if $failed > 0 {
  exit 1
}
