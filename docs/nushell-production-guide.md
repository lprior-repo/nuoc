# Production-Ready Nushell Development Guide

**Metadata:**
- **Title:** Production-Ready Nushell: Functional Programming, Type Safety & Testing
- **Description:** Complete guide emphasizing functional programming, type safety, testing, and reliability patterns for building maintainable Nushell scripts
- **Target Version:** 0.106+
- **Tags:** nushell, production, functional-programming, type-safety, testing, reliability
- **Author:** Community Documentation
- **Last Updated:** 2025-01-29
- **Related:** [Nushell Core Concepts](./nushell-core-concepts.md), [Idiomatic Nushell](https://www.nushell.sh/book/)

---

## Concept Dependency Graph (DAG)

This guide is organized as a directed acyclic graph. Follow numbered paths for optimal learning:

```
┌─────────────────────────────────────────────────────────────────┐
│                    FOUNDATION (Start Here)                      │
├─────────────────────────────────────────────────────────────────┤
│ 1. Core Philosophy → Essential Syntax → Data Manipulation      │
│    [Everything is structured data]    [Pipeline variable $in]   │
└─────────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────────┐
│                   FUNCTIONAL PATTERNS                          │
├─────────────────────────────────────────────────────────────────┤
│ 2. Advanced Functional → Higher-Order Functions → Composition  │
│    [Fold patterns, recursion]    [each, where, reduce]         │
└─────────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────────┐
│                      TYPE SYSTEM & TESTING                     │
├─────────────────────────────────────────────────────────────────┤
│ 3. Type Signatures → Unit Testing → Property Testing           │
│    [Runtime checking]          [Assertions, integration]       │
└─────────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────────┐
│                    PRODUCTION PATTERNS                          │
├─────────────────────────────────────────────────────────────────┤
│ 4. Error Handling → Performance → Monitoring → Deployment      │
│    [Try/catch, explicit errors]  [Streaming, parallel]         │
└─────────────────────────────────────────────────────────────────┘
```

**Recommended Learning Paths:**
- **Quick Start:** 1 → 2 → 3 (Foundation → Functional → Types)
- **Production Ready:** 1 → 2 → 3 → 4 (Complete path)
- **Debugging Focus:** 1 → 3.8 (Debugging Techniques)
- **Performance Focus:** 1 → 2 → 3.7 (Performance Optimization)

---

## Table of Contents

### Foundation Path
1. [Core Philosophy](#1-core-philosophy)
2. [Essential Syntax](#2-essential-syntax)
3. [Data Manipulation](#3-data-manipulation)

### Functional Patterns Path
4. [Advanced Functional Patterns](#4-advanced-functional-patterns)
5. [Functional Programming Principles](#5-functional-programming-principles)
6. [Map/Filter/Reduce](#6-map-filter-reduce)
7. [Advanced Streaming](#7-advanced-streaming)

### Type System & Testing Path
8. [Type System](#8-type-system)
9. [Testing & Quality](#9-testing-quality)

### Production Patterns Path
10. [Idiomatic Patterns](#10-idiomatic-patterns)
11. [Error Handling Patterns](#11-error-handling-patterns)
12. [Performance Optimization](#12-performance-optimization)
13. [Scripting Best Practices](#13-scripting-best-practices)
14. [Monitoring & Observability](#14-monitoring-observability)
15. [Debugging Techniques](#15-debugging-techniques)

### Advanced Topics
16. [Dataframe Integration](#16-dataframe-integration)
17. [Plugin System](#17-plugin-system)
18. [Advanced External Commands](#18-advanced-external-commands)

### Reference
19. [Style Guide](#19-style-guide)
20. [Anti-Patterns](#20-anti-patterns)
21. [Real-World Examples](#21-real-world-examples)
22. [Production Checklist](#22-production-checklist)

---

## 1. Core Philosophy

### Core Principles

**"Everything is structured data"**
- Tables, records, lists - not text
- Never parse text when structured alternatives exist
- All commands return typed data structures

**Functional-first:**
- Immutable by default
- Pure functions (no side effects)
- Composition over mutation
- Declarative over imperative

**Type safety:**
- Explicit types prevent errors
- Runtime and parse-time checking
- Type signatures document contracts

**Streaming:**
- Process data incrementally
- Avoid collecting entire datasets unnecessarily

**Quality through design:**
- Testable code
- Maintainable architecture
- Observable behavior

### Production Principles

1. **Fail fast** with clear errors
2. **Test thoroughly** at all levels
3. **Handle edge cases** explicitly
4. **Design for observability**
5. **Optimize for maintainability** over cleverness
6. **Build composable**, reusable components
7. **Document contracts** through type signatures

---

## 2. Essential Syntax

### Pipeline Variable `$in`

Refers to pipeline input, available in blocks and closures.

**Usage:**
```nu
# Simple expression
ls | where $in.size > 1mb

# Explicit parameters (preferred for complex logic)
ls | each { |file| $file.name | str upcase }
```

**Guideline:** Use `$in` for simple expressions, explicit parameters for complex logic.

### Subexpressions `$()`

Evaluates expression and substitutes result.

**Required when command output needed as argument:**
```nu
cd (ls | where type == dir | first | get name)

mkdir $"backup_(date now | format date '%Y%m%d')"

# Nested subexpressions
touch $"file_($env.USER)_((date now | format date '%H%M')).txt"
```

### String Interpolation `$"..."`

```nu
$"Hello ($name), total: ($items | length)"

# Any expression in parentheses
$"Result: (2 + 2 * 10)"

# With formatting
$"Price: ($price | format number -d 2)"
```

### Ranges

```nu
1..5    # [1, 2, 3, 4, 5] (inclusive)
1..<5   # [1, 2, 3, 4] (exclusive)

# Use cases
for x in 1..10 { print $x }
seq 1 100 | each { |x| $x * 2 }
[0 1 2 3] | range 1..2
```

### Cell Paths

```nu
# Nested access
$data.user.name
$data."field with spaces".value

# Optional access (returns null instead of error)
$data.missing?

# Dynamic access
$data | get $field_name
```

### Spread and Rest

```nu
# Spread list elements
[1 2 ...$more 5]

# Capture remaining arguments in parameters
def func [first, ...rest] {
  # $rest is a list of all remaining args
}
```

### Safe Navigation

```nu
# Optional access with default
$config.database?.port? | default 5432

# Try-catch chains
try { step1 } | try { step2 } catch { default_value }

# Error with context
error make {
  msg: "Operation failed"
  label: {
    text: $"invalid value: ($val)"
    span: (metadata $val).span
  }
  help: "Expected positive integer"
}
```

---

## 3. Data Manipulation

### Record Operations

```nu
# Insert new key
$record | insert key value

# Update existing key (transform value)
$record | update key { |old| $old.value * 2 }

# Insert or update
$record | upsert key value

# Combine records (right side wins conflicts)
$record1 | merge $record2

# Remove keys
$record | reject key1 key2

# Rename field
$record | rename old_key new_key
```

### Table Operations

```nu
# Project columns
$table | select col1 col2

# Remove columns
$table | reject col1

# Filter rows
$table | where condition

# Transform column
$table | update col { |row| $row.col * 2 }

# Add computed column
$table | insert new_col { |row| $row.col1 + $row.col2 }

# Group by column
$table | group-by category

# Swap rows and columns
$table | transpose

# Unnest nested structures
$table | flatten
```

### List Operations

```nu
# Add to end
$list | append value

# Add to start
$list | prepend value

# Flatten nested lists
$list | flatten

# Convert list to table
$list | wrap column_name

# Pair elements: [[1 a] [2 b] [3 c]]
$list1 | zip $list2

# Sliding windows: [[1 2 3] [2 3 4] [3 4 5]]
$list | window 3

# Non-overlapping chunks: [[1 2] [3 4] [5]]
$list | chunks 2

# Split into N sublists
$list | partition 2
```

### Aggregations

```nu
# Math operations
$numbers | math sum
$numbers | math avg
$numbers | math min
$numbers | math max
$numbers | math median

# Count elements
$list | length

# Remove duplicates
$list | uniq

# Deduplicate by field
$table | uniq-by column
```

### Functional Transformations

```nu
# Complex pipeline
$sales
| where amount > 900
| group-by region
| transpose region data
| insert total { |row| $row.data | math sum }
| sort-by total -r

# Compose transformations
def pipeline_transform []: list -> list {
  $in
  | validate_data
  | normalize_fields
  | enrich_with_metadata
  | filter_active_records
}
```

---

## 4. Advanced Functional Patterns

### Fold Patterns

```nu
# Basic reduce (fold from first element)
$list | reduce { |it, acc| $acc + $it }

# Reduce with explicit initial
$list | reduce -f 0 { |it, acc| $acc + $it }

# Scan (returns all intermediate values)
$list | iter scan 0 { |it, acc| $acc + $it }

# Build structure
[name age city]
| reduce -f {} { |key, acc| $acc | insert $key null }
```

### Partition and Group

```nu
# Partition by predicate (returns {true: evens, false: odds})
$list | partition { |x| $x mod 2 == 0 }

# Group by computed key
$table | group-by { |row| $row.date | format date '%Y-%m' }

# Split on condition
$list | split list { |x| $x == separator }
```

### Traversals

```nu
# Nested each
$nested | each { |outer|
  $outer | each { |inner| process $inner }
} | flatten

# Flatten with depth
$deeply_nested | flatten --all

# Recursive walk
def walk []: any -> list {
  if ($in | describe | str starts-with 'record') {
    $in | values | each { walk } | flatten
  } else {
    [$in]
  }
}
```

### Function Composition

```nu
# Manual composition
def pipe [f: closure, g: closure]: any -> any {
  $in | do $f | do $g
}

# Chain functions
def process []: any -> any {
  validate | transform | normalize | enrich
}

# Higher-order function
def apply_twice [f: closure]: any -> any {
  $in | do $f | do $f
}
```

### Lazy and Infinite Sequences

```nu
# Infinite counter
generate { |x| { out: $x, next: ($x + 1) } } 0 | take 100

# Fibonacci sequence
generate { |s| {
  out: $s.0,
  next: [$s.1, ($s.0 + $s.1)]
} } [0, 1] | take 20

# Prime numbers generator
def primes []: nothing -> list {
  generate { |state| {
    out: $state.current,
    next: {
      current: (next_prime $state.current),
      seen: ($state.seen | append $state.current)
    }
  } } { current: 2, seen: [] }
}
```

### Monadic Chains

```nu
# Maybe chain (safe navigation)
$data
| get -i key1
| get -i key2
| default "fallback"

# Try chain (error handling)
try { step1 }
| try { step2 }
catch { default_value }

# Result pattern
def safe_divide [a: float, b: float]: nothing -> record {
  if $b == 0 {
    {err: "Division by zero"}
  } else {
    {ok: ($a / $b)}
  }
}
```

---

## 5. Functional Programming Principles

### Immutability

All variables immutable by default. Once assigned, values cannot be changed.

**Benefits:**
- Predictable behavior
- Easier reasoning
- Thread-safe
- No side effects from variable changes

**Pattern:** Transform data through pipelines creating new values:
```nu
let filtered = $data | where active
```

### Pure Functions

Given same inputs, always return same outputs without side effects.

**Example:**
```nu
def calculate_total [items: list]: nothing -> int {
  $items | each { |x| $x.price * $x.quantity } | math sum
}
```

**Benefits:**
- Testable in isolation
- Composable
- Cacheable
- Parallelizable
- Easier to understand

### Higher-Order Functions

Functions that take or return other functions.

**Built-ins:**
```nu
# Apply function to each element
ls | each { |file| $file.size / 1mb }

# Filter using predicate
$list | where { |x| $x.age > 18 }

# Fold/accumulate
[1 2 3 4] | reduce { |it, acc| $acc + $it }

# Check predicates
[1 2 3] | all { |x| $x > 0 }
```

**Custom:**
```nu
def map_transform [transform: closure]: list -> list {
  $in | each $transform
}
```

### Function Composition

Build complex operations by composing simple functions.

**Pipelines as composition:**
```nu
data | f | g | h  # Equivalent to: h(g(f(data)))
```

**Example:**
```nu
def normalize_name []: string -> string {
  str trim | str downcase | str replace -a " " "_"
}

"  John Doe  " | normalize_name  # "john_doe"
```

### Declarative Style

Express **what** to compute, not **how**.

**Imperative (bad):**
```nu
mut sum = 0
for item in $list {
  $sum = $sum + $item.value
}
```

**Declarative (good):**
```nu
$list | each { |x| $x.value } | math sum
```

**Benefits:**
- More readable
- Less error-prone
- Easier to optimize
- Clearer intent

### Lazy Evaluation

Streaming and lazy evaluation for efficiency. Data processed incrementally.

**Streaming commands:**
- `lines`
- `each` (when streaming)
- `chunks`
- `generate`

**Example:**
```nu
# Only processes until 10 matches found
open huge_file.log | lines | where $it =~ "ERROR" | first 10
```

### Recursion

Use for naturally recursive problems.

```nu
def factorial [n: int]: nothing -> int {
  if $n <= 1 { 1 } else { $n * (factorial ($n - 1)) }
}
```

**Pattern:** Define base case first, then recursive case. Prefer `reduce` for accumulation when possible.

---

## 6. Map/Filter/Reduce

### Core Trinity

```nu
# Map: transform each element
$list | each { |x| $x * 2 }

# Filter: select elements
$list | where { |x| $x > 10 }

# Reduce: aggregate to single value
$list | reduce { |it, acc| $acc + $it }

# Combined
$data | where active | each { |x| $x.value } | reduce { |it, acc| $acc + $it }
```

### Partial Application

Create specialized functions from general ones by fixing arguments.

```nu
def multiply [x: int, y: int]: nothing -> int {
  $x * $y
}

def double []: int -> int {
  multiply $in 2
}

# Closures capture environment
let threshold = 100
$data | where { |x| $x.value > $threshold }
```

### Function Pipelines

Chain functions where output of one is input to next.

```nu
def sanitize []: string -> string {
  str trim | str downcase
}

def validate []: string -> bool {
  str length | $in > 0
}

$input | sanitize | validate
```

### Currying via Closures

```nu
def make_adder [x: int]: nothing -> closure {
  { |y| $x + $y }
}

let add_five = make_adder 5
10 | do $add_five  # 15
```

---

## 7. Advanced Streaming

### Streaming Principle

Leverage streaming commands for large datasets. Process incrementally without collecting everything in memory.

```nu
# Streams data - constant memory
open huge_file.log | lines | where $it =~ "ERROR" | first 10
```

### Transducers

Compose transformations without creating intermediate collections.

```nu
# Efficient - single pass
$huge_list
| where condition
| each transform
| select columns
| take 100
```

### Closures

Use for flexible data transformation.

```nu
# Simple transformation
ls | each { |file| {
  name: $file.name,
  size_mb: ($file.size / 1mb)
} }

# Stateful map
let counter = 0
$data | each { |x|
  $counter = $counter + 1
  {id: $counter, value: $x}
}
```

### Algebraic Data Types

Use records and tagged unions. Pattern match with `match`.

```nu
def handle_result [r: record]: nothing -> any {
  match $r.type {
    "ok" => $r.value,
    "err" => (error make {msg: $r.error}),
    _ => null
  }
}
```

---

## 8. Type System

### Runtime Type Checking

Introduced in v0.102.0. Commands verify pipeline input types match declared types at runtime.

```nu
def cool-int-print []: int -> nothing {
  print $"my cool int is ($in)"
}

1 | cool-int-print      # Works
"string" | cool-int-print  # Throws: nu::parser::input_type_mismatch
```

### Type Signatures

Always specify input and output types in custom commands.

```nu
def name [args]: input_type -> output_type {
  body
}
```

**Benefits:**
- Documents function contracts
- Enables compile-time verification
- Catches errors early

**Structural typing:**
```nu
value [{a: 123} {a: 456}] is subtype of table<a: int>
```

**Production example:**
```nu
def calculate_total [items: list<record>]: nothing -> float {
  $items | each { |item| $item.price * $item.quantity } | math sum
}
```

### Error Propagation

Error values passed as pipeline input are immediately thrown.

```nu
# Use try/catch for error handling
try { risky_command } catch { |e|
  print -e $"Error: ($e)"
}
```

**External commands:** Errors don't automatically propagate - use `do -c` or explicit error checking.

---

## 9. Testing & Quality

### Unit Test Framework

```nu
def assert_equal [actual: any, expected: any, message: string]: nothing -> nothing {
  if $actual != $expected {
    error make {
      msg: $"Assertion failed: ($message)",
      label: {
        text: $"Expected ($expected), got ($actual)",
        span: (metadata $actual).span
      }
    }
  }
}

def assert_type [value: any, expected_type: string]: nothing -> nothing {
  let actual_type = ($value | describe)
  if $actual_type != $expected_type {
    error make {
      msg: "Type assertion failed",
      label: {
        text: $"Expected ($expected_type), got ($actual_type)",
        span: (metadata $value).span
      }
    }
  }
}
```

### Unit Test Pattern

```nu
export def test_add [] {
  assert_equal (add 2 3) 5 "Basic addition"
  assert_equal (add -1 1) 0 "Addition with negatives"
  assert_equal (add 0 0) 0 "Addition of zeros"
  assert_type (add 1 2) "int"
  print "✓ All math tests passed"
}

export def run_tests [] {
  [test_add test_subtract test_multiply]
  | each { |test_name|
    try {
      do $test_name
      {test: $test_name, status: "PASS"}
    } catch { |e|
      {test: $test_name, status: "FAIL", error: $e.msg}
    }
  }
  | where status == "FAIL"
}
```

### Property Testing

```nu
# Property: map then length equals original length
def prop_map_length [f: closure] {
  let original = [1 2 3 4 5]
  let mapped = ($original | each $f)
  assert_equal ($mapped | length) ($original | length) "Map preserves length"
}

# Property: filter then map === map then filter
def prop_filter_map_commute [pred: closure, mapper: closure] {
  let data = [1 2 3 4 5]
  let result1 = ($data | where $pred | each $mapper)
  let result2 = ($data | each $mapper | where $pred)
  assert_equal $result1 $result2 "Filter-map commutativity"
}
```

### Integration Patterns

```nu
def test_api_integration [] {
  let test_data = {name: "test", value: 123}
  let response = (http post http://localhost:8080/api/test $test_data)

  assert_equal $response.status 200 "Expected 200 status"
  assert_type $response.body.id "int"

  http delete $"http://localhost:8080/api/test/($response.body.id)"
}
```

### Assert Patterns

```nu
# Equal
assert_equal $actual $expected "values should match"

# Contains
assert ($list | any { |x| $x == $value }) "list should contain value"

# Type
assert_type $value "int"

# Range
assert ($value > 0 and $value < 100) "should be in range 1-99"
```

---

## 10. Idiomatic Patterns

### Data Validation

```nu
def validate_record [r: record]: nothing -> bool {
  ($r | columns | all { |c| $c in [name age email] })
  and ($r.age? | default 0 | $in > 0)
}

def in_range [min: number, max: number]: number -> bool {
  $in >= $min and $in <= $max
}

def validate_file_path [path: string]: nothing -> string {
  if ($path | str contains "..") {
    error make { msg: "Invalid file path: directory traversal detected" }
  }

  let allowed_dirs = ["/data", "/uploads", "/tmp"]
  let absolute_path = ($path | path expand)

  let is_allowed = ($allowed_dirs | any { |dir|
    ($absolute_path | str starts-with ($dir | path expand))
  })

  if not $is_allowed {
    error make { msg: "Access denied: path outside allowed directories" }
  }

  $absolute_path
}
```

### Error Handling Patterns

```nu
# Try-catch specific
try { risky } catch { |e|
  if ($e.msg =~ "specific") {
    handle_specific
  } else {
    error make $e
  }
}

# Error context
error make {
  msg: "Operation failed"
  label: {
    text: $"invalid value: ($val)"
    span: (metadata $val).span
  }
  help: "Expected positive integer"
}

# Result type
def safe_operation []: any -> record {
  try {
    {ok: (dangerous_op)}
  } catch { |e|
    {err: $e.msg}
  }
}
```

### Performance Patterns

```nu
# Streaming vs collecting

# Good: streams, early exit
open large.json | each { process } | where condition | first 10

# Bad: collects everything first
let all = (open large.json | each { process })
$all | where condition | first 10

# Parallel processing
$items | par-each { expensive_operation }

# Batch processing
$large_list | chunks 100 | each { |batch| process_batch $batch }
```

### File Operations

```nu
# Read structured
open config.json  # Parses automatically

# Read raw
open --raw file.txt

# Write structured
$data | save output.json  # Serializes automatically

# Atomic write
$data | save --force atomic.tmp
mv atomic.tmp atomic.json
```

### Environment Handling

```nu
# Load env file
open .env | from env | load-env

# Temporary env var
with-env {TEMP_VAR: "value"} { command }

# Modify caller's env
export def-env activate [] {
  $env.PATH = ($env.PATH | prepend "./bin")
}

# Secure env
def get_secure_env [key: string]: nothing -> string {
  let value = ($env | get -i $key)
  if $value == null {
    error make { msg: $"Required environment variable not set: ($key)" }
  }
  $value | str replace -a '\n' '' | str replace -a '\r' ''
}
```

---

## 11. Error Handling Patterns

### Safe Navigation

```nu
# Optional access with defaults
$data
| get -i key1
| get -i key2
| default "fallback"

# Try chain
try { step1 }
| try { step2 }
catch { default_value }

# Safe wrapper
def safe_divide [a: float, b: float]: nothing -> record {
  if $b == 0 {
    {err: "Division by zero"}
  } else {
    {ok: ($a / $b)}
  }
}
```

### Explicit Error Handling

```nu
def process_user [user: record]: nothing -> record {
  # Validate required fields
  let required_fields = ["name", "email", "age"]
  let missing_fields = ($required_fields | where { |field|
    not ($field in ($user | columns))
  })

  if ($missing_fields | length) > 0 {
    error make {
      msg: "Invalid user data"
      label: {
        text: $"Missing fields: ($missing_fields | str join ', ')"
      }
    }
  }

  # Validate ranges
  if $user.age < 0 or $user.age > 150 {
    error make {
      msg: "Invalid age"
      label: {
        text: $"Age must be between 0 and 150, got ($user.age)"
      }
    }
  }

  $user
}
```

---

## 12. Performance Optimization

### When to Collect

**Stream:**
- Large datasets
- Early exit needed
- Memory constrained

**Collect:**
- Need multiple passes
- Random access
- Data fits in memory

```nu
# Stream: constant memory
open huge.csv | where status == "active" | first 100

# Collect: multiple passes
let data = (fetch_data | collect)
$data | analyze
$data | report
```

### Parallel Processing

```nu
# CPU-bound tasks
$items | par-each { |item|
  expensive_transform $item
}

# With ordering preserved
$items
| enumerate
| par-each { |x|
  {
    index: $x.index,
    result: (process $x.item)
  }
}
| sort-by index
| get result
```

### Memory Efficiency

```nu
# Avoid unnecessary collection
open large | lines | each { process }  # Good
let all = (open large | lines | collect)  # Bad

# Streaming aggregations
$stream | reduce { |it, acc| $acc + $it }  # Constant memory

# Batch I/O
$ids | chunks 10 | each { |batch|
  fetch_batch $batch
} | flatten
```

---

## 13. Scripting Best Practices

### Module Organization

```nu
# lib/config.nu
export const APP_CONFIG = {
  api_base_url: "https://api.example.com/"
  timeout_seconds: 30
  retry_count: 3
  log_level: "info"
}

export def get_config [key: string]: nothing -> any {
  $APP_CONFIG
  | get -i $key
  | default (error make { msg: $"Configuration key not found: ($key)" })
}

# lib/http_client.nu
use lib.nu [get_config]

export def api_request [
  method: string,
  endpoint: string,
  --data: record,
  --headers: list = []
]: nothing -> record {
  let base_url = (get_config "api_base_url")
  let timeout = (get_config "timeout_seconds")

  try {
    http $method $"($base_url)/($endpoint)"
      --headers $headers
      --timeout $"($timeout)sec"
  } catch { |e|
    error make { msg: $"API request failed: ($e.msg)" }
  }
}
```

### Configuration Management

```nu
const CONFIG = {
  api_url: "https://api.example.com/"
  timeout: 30sec
  retry_count: 3
}

def get_config [key: string]: nothing -> any {
  $CONFIG
  | get -i $key
  | default (error make {msg: $"Config key not found: ($key)"})
}

# Environment-specific
def load_environment_config [env: string]: nothing -> record {
  let base_config = (open "config/base.toml")
  let env_config_file = $"config/($env).toml"

  if ($env_config_file | path exists) {
    let env_config = (open $env_config_file)
    $base_config | merge $env_config
  } else {
    log "warn" $"No environment-specific config found for ($env)"
    $base_config
  }
}
```

### Command Flags

```nu
def deploy [
  environment: string,
  --force (-f),
  --dry-run (-d),
  --verbose (-v)
]: nothing -> nothing {
  if $verbose {
    print $"Deploying to ($environment)"
  }

  if not $force and not $dry_run {
    let confirm = (input "Proceed? (y/n): ")
    if $confirm != "y" { return }
  }

  if $dry_run {
    print "DRY RUN: Would deploy..."
    return
  }

  # Actual deployment
}
```

### Main with Subcommands

```nu
def "main process" [
  input_file: string,
  --output (-o): string = "output.json",
  --dry-run (-n),
  --verbose (-v)
]: nothing -> nothing {
  if $verbose {
    print $"Processing file: ($input_file)"
  }

  let users = try { open $input_file } catch {
    error make { msg: $"Failed to load input file: ($input_file)" }
  }

  if $dry_run {
    print $"Would process ($users | length) users"
    return
  }

  let results = (process_user_batch $users)
  $results | to json | save $output
}

def "main deploy" [
  environment: string,
  --force (-f),
  --rollback: string
]: nothing -> nothing {
  if $rollback != null {
    print $"Rolling back to version: ($rollback)"
    return
  }

  print $"Deploying to ($environment)..."
}

def main [] {
  print "Usage: main.nu <process|deploy|test> [options]"
}
```

### Secret Management

```nu
def load_secrets [config_file: string]: nothing -> record {
  if not ($config_file | path exists) {
    error make { msg: $"Secrets file not found: ($config_file)" }
  }

  let permissions = (ls -l $config_file | first | get permissions)
  if not ($permissions | str starts-with "-rw-------") {
    error make { msg: "Secrets file has insecure permissions" }
  }

  open $config_file
}

def log_with_mask [
  level: string,
  message: string,
  --sensitive: list<string>
]: nothing -> nothing {
  mut masked_message = $message

  if $sensitive != null {
    for key in $sensitive {
      $masked_message = ($masked_message | str replace -a $key "***MASKED***")
    }
  }

  log $level $masked_message
}
```

---

## 14. Monitoring & Observability

### Health Checks

```nu
def health_check []: nothing -> record {
  let checks = [
    {
      name: "disk_space"
      check: { (sys disks | where mount == "/" | first | get free) > 1GB }
      message: "Sufficient disk space available"
    }
    {
      name: "memory_usage"
      check: { (sys mem | get used) < ((sys mem | get total) * 0.9) }
      message: "Memory usage within limits"
    }
    {
      name: "config_valid"
      check: { validate_config }
      message: "Configuration is valid"
    }
  ]

  let results = ($checks | each { |check|
    try {
      let passed = (do $check.check)
      {
        name: $check.name
        status: "pass"
        message: $check.message
      }
    } catch { |e|
      {
        name: $check.name
        status: "fail"
        message: $e.msg
      }
    }
  })

  let failed_checks = ($results | where status == "fail")

  {
    overall_status: (if ($failed_checks | length) == 0 { "healthy" } else { "unhealthy" })
    checks: $results
    timestamp: (date now | format date "%Y-%m-%d %H:%M:%S")
  }
}
```

### Graceful Shutdown

```nu
def graceful_shutdown []: nothing -> nothing {
  log "info" "Received shutdown signal, cleaning up..."

  # Close open connections
  # Save current state
  # Clean up temporary files

  log "info" "Shutdown complete"
  exit 0
}
```

### Feature Flags

```nu
def is_feature_enabled [feature: string]: nothing -> bool {
  let features = (get_config "features" | default {})
  $features | get -i $feature | default false
}
```

---

## 15. Debugging Techniques

### Debug Commands

```nu
$data | debug      # Print debug representation
$data | describe   # Get type information
$value | metadata  # Get source span for errors
view source command_name  # See command definition
```

### Pipeline Debugging

```nu
# Tap pattern
def tap [label: string]: any -> any {
  print $"DEBUG ($label): ($in | to json)"
  $in
}

# Usage
$data
| tap "initial_data"
| where active == true
| tap "after_filter"
| each { |item| { ...$item, processed: true } }
| tap "after_transform"

# Performance profiling
def profile_operation [name: string, operation: closure]: any -> any {
  let start = (date now)
  let result = ($in | do $operation)
  let duration = ((date now) - $start)

  print $"PROFILE ($name): ($duration)"
  $result
}
```

### Logging Framework

```nu
export const LOG_LEVELS = {
  DEBUG: 0
  INFO: 1
  WARN: 2
  ERROR: 3
}

export def log [
  level: string,
  message: string,
  --data: record
]: nothing -> nothing {
  let current_level = (get_config "log_level" | default "info")
  let level_value = ($LOG_LEVELS | get ($level | str upcase))
  let current_level_value = ($LOG_LEVELS | get ($current_level | str upcase))

  if $level_value >= $current_level_value {
    let timestamp = (date now | format date "%Y-%m-%d %H:%M:%S")
    let log_entry = {
      timestamp: $timestamp
      level: ($level | str upcase)
      message: $message
      data: ($data | default {})
    }

    $log_entry | to json | print
  }
}
```

---

## 16. Dataframe Integration

### Introduction

For high-performance data analysis on large datasets, Nushell integrates with Polars DataFrame library. DataFrame operations are **lazy by default** - they build optimized query plans and only execute when explicitly told to.

### Loading Data

```nu
# Load from file
dfr open data.csv

# Convert from stream
$table | dfr into-df
```

### Core Operations

```nu
# Column projection
dfr select colA colB

# Row filtering
dfr filter ($it | get colA | dfr is-greater 100)

# Add computed column
dfr with-column "new_col" ($it | get colA | dfr multiply 2)

# Group and aggregate
dfr group-by "category"
| dfr agg ($it | get "values" | dfr sum)
```

### Lazy Execution

Most `dfr` operations build a LazyFrame plan. No computation until `dfr collect`.

```nu
dfr open $file
| dfr filter ($it | get "amount" | dfr is-greater 0)
| dfr with-column "profit_margin" ($it | get "amount" | dfr multiply 0.15)
| dfr group-by "region"
| dfr agg [
  ($it | get "amount" | dfr sum | dfr as "total_sales")
  ($it | get "profit_margin" | dfr sum | dfr as "total_profit")
  ($it | get "id" | dfr count | dfr as "transaction_count")
]
| dfr collect
| sort-by total_sales -r
```

---

## 17. Plugin System

### Overview

Nushell can be extended with plugins - external executables that communicate via standard protocol. Write custom commands in Rust, Python, Go, and use seamlessly within the shell.

### Registration

```nu
# Register plugin
register path/to/nu_plugin_example

# Plugin is now available
ls | my-command --flag value | where size > 10kb
```

### Development (Rust)

```rust
use nu_plugin::*;

struct MyPlugin;

impl Plugin for MyPlugin {
  fn commands(&self) -> Vec<Box<dyn PluginCommand<PluginState>>> {
    vec![Box::new(MyCommand)]
  }
}
```

---

## 18. Advanced External Commands

### Capturing Streams

```nu
let result = (complete { ^git status })
if $result.exit_code != 0 {
  print -e $result.stderr
}
```

### Parsing Binary Output

```nu
let icon_bytes = (^cat icon.ico | do --capture-binary)
$icon_bytes | bytes at 6 | into int
```

### Error Handling

```nu
let result = (complete { ^dangerous_command })
if $result.exit_code == 0 {
  $result.stdout | from json
} else {
  error make { msg: $"Command failed: ($result.stderr)" }
}
```

### Retry Patterns

```nu
def run_with_retry [
  cmd: closure,
  max_attempts: int = 3
]: nothing -> record {
  mut attempts = 0

  while $attempts < $max_attempts {
    let result = (complete $cmd)
    if $result.exit_code == 0 {
      return {
        success: true,
        output: $result.stdout,
        attempts: ($attempts + 1)
      }
    }
    $attempts = $attempts + 1
    sleep 1sec
  }

  { success: false, final_error: "Max retries exceeded" }
}
```

---

## 19. Style Guide

### Naming

```nu
# Commands: snake_case
def process_data []
def fetch_user []

# Parameters: snake_case
[file_path: string, max_items: int]

# Constants: SCREAMING_SNAKE_CASE
const MAX_RETRIES = 3

# Private: prefix with underscore
def _internal_helper [] { }
```

### Formatting

```nu
# Indentation: 2 spaces
# Line length: under 100 characters
# Pipeline breaks: indent continuations
$data | where condition | each { |x|
  transform $x
} | sort-by value
```

### Comments

```nu
# Header: brief description
# Body: explain why, not what
```

### Documentation

```nu
# Always document function contracts through type signatures
# Include examples
# Use meaningful names as documentation
```

---

## 20. Anti-Patterns

### ❌ Mutation Attempts

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

### ❌ Text Parsing

**Bad:**
```nu
ps | to text | lines | each { str split " " }
```

**Good:**
```nu
ps | select pid name cpu | where cpu > 50
```

### ❌ Premature Collection

**Bad:**
```nu
let all = (open huge | lines | collect)
$all | first 10
```

**Good:**
```nu
open huge | lines | first 10
```

### ❌ Missing Types

**Bad:**
```nu
def process [x] { $x * 2 }
```

**Good:**
```nu
def process [x: int]: nothing -> int { $x * 2 }
```

### ❌ Side Effects

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

### ❌ Error Swallowing

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

## 21. Real-World Examples

### Log Analysis

```nu
def analyze_logs [path: string]: nothing -> table {
  open $path
  | lines
  | each { |line|
    let parts = ($line | parse '{ip} - - [{timestamp}] "{method} {path} {protocol}" {status} {size}')
    $parts | first
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

def list_users []: nothing -> list {
  api_get "users"
}

def get_user [id: int]: nothing -> record {
  api_get $"users/($id)"
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
    | insert full_name $"($row.first_name) ($row.last_name)"
    | insert age_group (if $row.age < 18 { "minor" } else { "adult" })
    | reject first_name last_name
  }
}

def validate []: list -> list {
  where { |row|
    ($row.email? | default "" | str length) > 0
    and ($row.age? | default 0) > 0
  }
}

def load [dest: string]: list -> nothing {
  to json | save $dest
}

def run_pipeline [source: string, dest: string]: nothing -> nothing {
  extract $source
  | transform
  | validate
  | load $dest
}
```

### Build System

```nu
def "main build" [--release] {
  let mode = if $release { "release" } else { "debug" }
  print $"Building in ($mode) mode..."

  ^cargo build (if $release { ["--release"] } else { [] })

  if $env.LAST_EXIT_CODE != 0 {
    error make {msg: "Build failed"}
  }

  print "Build successful!"
}

def "main test" [] {
  print "Running tests..."
  ^cargo test
}

def "main clean" [] {
  print "Cleaning build artifacts..."
  rm -rf target/
}

def main [] {
  print "Usage: build.nu <build|test|clean> [--release]"
}
```

---

## 22. Production Checklist

### Code Quality

- [ ] All functions have type signatures
- [ ] Error handling is explicit and comprehensive
- [ ] Input validation is performed
- [ ] Functions are pure (no hidden side effects)
- [ ] Code is documented with clear examples
- [ ] Performance characteristics are understood

### Testing

- [ ] Unit tests cover happy path and error cases
- [ ] Integration tests verify end-to-end functionality
- [ ] Property-based tests check invariants
- [ ] Performance benchmarks establish baselines
- [ ] Tests run in CI/CD pipeline

### Observability

- [ ] Structured logging with appropriate levels
- [ ] Health checks for system dependencies
- [ ] Metrics collection for key operations
- [ ] Error tracking and alerting
- [ ] Performance monitoring and profiling

### Security

- [ ] Input validation and sanitization
- [ ] Secure secret management
- [ ] File system access controls
- [ ] Audit logging for sensitive operations
- [ ] Principle of least privilege

### Deployment

- [ ] Configuration externalized and environment-specific
- [ ] Graceful shutdown handling
- [ ] Rolling deployment support
- [ ] Rollback procedures documented
- [ ] Database migration strategies

### Maintenance

- [ ] Clear module organization and dependencies
- [ ] Version control best practices
- [ ] Change documentation and release notes
- [ ] Dependency management and updates
- [ ] Code review processes
- [ ] Technical debt tracking

---

## Where to Look Next

### Based on Your Goal

**If you want to:**
- **Learn Nushell basics**: Start with [Nushell Core Concepts](./nushell-core-concepts.md) Sections 1-3
- **Write production scripts**: Read this guide's Sections 1-9, then 13-15
- **Optimize performance**: Study Sections 7, 12, and Anti-Patterns
- **Build robust systems**: Follow Sections 9-14, then 22 (checklist)
- **Integrate with tools**: See Sections 16-18 (Dataframe, Plugins, External commands)
- **Debug issues**: Go directly to Section 15 (Debugging Techniques)

### Related Documentation

- **[Nushell Book](https://www.nushell.sh/book/)** - Official documentation
- **[Command Reference](https://www.nushell.sh/commands/)** - Complete command listing
- **[AGENTS.md](../AGENTS.md)** - Agent guidelines with idiomatic patterns
- **[zjj Deep Dive](../zjj-deep-dive.md)** - Workspace isolation with zjj

### Learning Path Recommendations

**Beginner (New to Nushell):**
1. Read [Nushell Core Concepts](./nushell-core-concepts.md) Sections 1-4
2. Practice with one-liners in REPL
3. Study Essential Syntax (Section 2 of this guide)
4. Build small scripts with Data Manipulation (Section 3)

**Intermediate (Comfortable with basics):**
1. Master Functional Patterns (Sections 4-7)
2. Learn Type System (Section 8)
3. Write unit tests (Section 9)
4. Study real-world examples (Section 21)

**Advanced (Building production systems):**
1. Implement error handling (Section 11)
2. Optimize performance (Section 12)
3. Add monitoring (Section 14)
4. Follow production checklist (Section 22)

---

## Summary

### Key Principles

- **Structured data first**: Tables, records, lists - not text
- **Functional composition**: Pure functions, immutability, pipelines
- **Type safety**: Explicit types, runtime checking
- **Quality through design**: Testing, error handling, observability

### Production Mindset

- Simple is better than complex
- Explicit is better than implicit
- Readable trumps clever
- Test thoroughly
- Document clearly
- Profile before optimizing

### Critical Patterns

- Map/filter/reduce for transformation
- Function composition via pipelines
- Streaming for large datasets
- Pure functions for reliability
- Explicit types for safety
- Monadic chains for error handling

---

**Navigation:** [Documentation Index](./INDEX.md) | [Nushell Core Concepts](./nushell-core-concepts.md) | [AGENTS.md](../AGENTS.md)
