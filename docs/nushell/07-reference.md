# Reference: Examples, Patterns, Anti-Patterns

**Previous:** [Production Patterns](./06-production.md) | **Back to:** [Index](./INDEX.md)

---

## Style Guide

### Naming

```nu
# Commands: snake_case
def process_data []
def fetch_user []

# Parameters: snake_case
[file_path: string, max_items: int]

# Constants: SCREAMING_SNAKE_CASE
const MAX_RETRIES = 3

# Private: underscore prefix
def _internal_helper [] { }
```

### Formatting

```nu
# Indent: 2 spaces
# Line length: ~100 chars
# Pipeline breaks: indent continuations
$data
| where condition
| each { |x| transform $x }
| sort-by value
```

---

## Anti-Patterns

### ❌ 1. Mutation

**Bad:**
```nu
mut total = 0
for x in $list {
  $total = $total + $x
}
```

**Good:**
```nu
$list | reduce { |it, acc| $acc + $it }
```

---

### ❌ 2. Text Parsing

**Bad:**
```nu
ps | to text | lines | each { str split " " }
```

**Good:**
```nu
ps | select pid name cpu | where cpu > 50
```

---

### ❌ 3. Premature Collection

**Bad:**
```nu
let all = (open huge | lines | collect)
$all | first 10
```

**Good:**
```nu
open huge | lines | first 10
```

---

### ❌ 4. Missing Types

**Bad:**
```nu
def process [x] { $x * 2 }
```

**Good:**
```nu
def process [x: int]: nothing -> int { $x * 2 }
```

---

### ❌ 5. Side Effects

**Bad:**
```nu
def process [] {
  save output.txt
  "done"
}
```

**Good:**
```nu
def process_and_save [path: string]: any -> string {
  let result = process
  $result | save $path
  $result
}
```

---

### ❌ 6. Error Swallowing

**Bad:**
```nu
try { risky } catch { null }
```

**Good:**
```nu
try { risky } catch { |e|
  log "error" $e.msg
  default_value
}
```

---

### ❌ 7. No Error Handling

**Bad:**
```nu
def risky [input: string]: nothing -> string {
  ^external_command $input | str trim
}
```

**Good:**
```nu
def safe_risky [input: string]: nothing -> record {
  try {
    let result = (^external_command $input | str trim)
    {ok: $result}
  } catch { |e|
    {err: $e.msg}
  }
}
```

---

## Real-World Examples

### Log Analysis

```nu
def analyze_logs [path: string]: nothing -> table {
  open $path
  | lines
  | each { |line|
    $line | parse '{ip} [{timestamp}] "{method} {path} {protocol}" {status} {size}'
    | first
  }
  | where status >= 400
  | group-by status
  | transpose status count
  | sort-by count -r
}
```

### API Client

```nu
const API_BASE = "https://api.example.com/"

def api_get [endpoint: string]: nothing -> record {
  http get $"($API_BASE)/($endpoint)"
    --headers [Authorization $"Bearer ($env.API_TOKEN)"]
  | if ($in.status? | default 0) >= 400 {
    error make {msg: $"API error: ($in.status)"}
  } else {
    $in
  }
  | get data
}
```

### Data Pipeline

```nu
def extract [source: string]: nothing -> list {
  open $source | from csv
}

def transform []: list -> list {
  each { |row|
    $row
    | insert full_name $"($row.first) ($row.last)"
    | insert age_group (if $row.age < 18 {"minor"} else {"adult"})
    | reject first last
  }
}

def validate []: list -> list {
  where { |row|
    ($row.email? | default "" | str length) > 0
    and ($row.age? | default 0) > 0
  }
}

def run_pipeline [source: string, dest: string]: nothing -> nothing {
  extract $source
  | transform
  | validate
  | to json
  | save $dest
}
```

### Build System

```nu
def "main build" [--release] {
  let mode = if $release {"release"} else {"debug"}
  print $"Building in ($mode)..."

  ^cargo build (if $release {["--release"]} else {[]})

  if $env.LAST_EXIT_CODE != 0 {
    error make {msg: "Build failed"}
  }
}

def "main test" [] {
  ^cargo test
}

def "main clean" [] {
  rm -rf target/
}

def main [] {
  print "Usage: main.nu <build|test|clean> [--release]"
}
```

---

## Quick Reference

### Pipeline

```nu
$data | where cond | each transform | sort-by col
```

### Error Handling

```nu
try { risky } catch { |e| handle $e }
```

### Types

```nu
def func [x: int]: nothing -> string { ... }
```

### Validation

```nu
$data | get -i key | default "fallback"
```

### Performance

```nu
open huge | lines | first 10  # Stream
$items | par-each { expensive }  # Parallel
```

---

## Complete Documentation Index

- [Index](./INDEX.md) - Navigation
- [Foundation](./00-foundation.md) - Core philosophy and syntax
- [Functional Patterns](./01-functional.md) - Map/filter/reduce
- [Type System](./02-types.md) - Type signatures and testing
- [Error Handling](./04-errors.md) - Validation and errors
- [Performance](./05-performance.md) - Optimization
- [Production Patterns](./06-production.md) - Monitoring and deployment

**External:**
- [Nushell Book](https://www.nushell.sh/book/)
- [Command Reference](https://www.nushell.sh/commands/)
- [AGENTS.md](../../AGENTS.md) - Project guidelines
