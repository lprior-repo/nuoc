# Error Handling & Validation

**Previous:** [Type System](./02-types.md) | **Next:** [Performance](./05-performance.md)

---

## Safe Navigation

### Optional Access

```nu
# Returns null if path doesn't exist
$data.missing_field?

# Chain with default
$data?.key1?.key2 | default "fallback"

# Safe record access
$config.database?.port? | default 5432
```

### Get with Default

```nu
# -i flag ignores errors
$data | get -i missing_key | default "value"
```

---

## Try/Catch

### Basic Error Handling

```nu
try { risky_operation } catch { |e|
  print -e $"Error: ($e.msg)"
}
```

### Specific Error Handling

```nu
try { risky } catch { |e|
  if ($e.msg =~ "specific") {
    handle_specific
  } else {
    error make $e  # Re-throw
  }
}
```

### Try Chain

```nu
# Chain operations, use first success
try { step1 }
| try { step2 }
| try { step3 }
catch { default_value }
```

---

## Explicit Errors

### Error with Context

```nu
error make {
  msg: "Operation failed"
  label: {
    text: $"invalid value: ($val)"
    span: (metadata $val).span
  }
  help: "Expected positive integer"
}
```

### Validation Errors

```nu
def validate_age [age: int]: nothing -> bool {
  if $age < 0 or $age > 150 {
    error make {
      msg: "Invalid age"
      label: { text: $"Age must be 0-150, got ($age)" }
    }
  }
  true
}
```

---

## Input Validation

### Record Validation

```nu
def validate_record [r: record]: nothing -> record {
  # Check required fields
  let required = ["name", "email", "age"]
  let missing = ($required | where { |f| not ($f in ($r | columns)) })

  if ($missing | length) > 0 {
    error make {
      msg: "Invalid record"
      label: { text: $"Missing: ($missing | str join ', ')" }
    }
  }

  # Validate field types
  if ($r.age? | default 0) < 0 {
    error make { msg: "Age must be positive" }
  }

  $r
}
```

### Path Validation

```nu
def validate_path [path: string]: nothing -> string {
  # Prevent directory traversal
  if ($path | str contains "..") {
    error make { msg: "Directory traversal detected" }
  }

  # Check allowed directories
  let allowed = ["/data", "/uploads", "/tmp"]
  let abs_path = ($path | path expand)

  let is_allowed = ($allowed | any { |dir|
    ($abs_path | str starts-with ($dir | path expand))
  })

  if not $is_allowed {
    error make { msg: "Access denied: path outside allowed dirs" }
  }

  $abs_path
}
```

---

## Result Type Pattern

```nu
def safe_divide [a: float, b: float]: nothing -> record {
  if $b == 0 {
    {err: "Division by zero"}
  } else {
    {ok: ($a / $b)}
  }
}

# Usage
let result = safe_divide 10 2
if ($result | columns | "ok" in $in) {
  $result.ok  # Success
} else {
  print -e $result.err  # Error
}
```

---

## External Command Errors

### Complete Pattern

```nu
def safe_external [cmd: closure]: nothing -> record {
  let result = (complete $cmd)

  if $result.exit_code == 0 {
    { success: true, output: $result.stdout }
  } else {
    {
      success: false,
      error: $result.stderr,
      exit_code: $result.exit_code
    }
  }
}

# Usage
let result = safe_external { ^git status }
if $result.success {
  $result.output | from json
} else {
  error make { msg: $"Git failed: ($result.error)" }
}
```

### Retry Pattern

```nu
def run_with_retry [cmd: closure, max_attempts: int = 3]: nothing -> record {
  mut attempts = 0

  while $attempts < $max_attempts {
    let result = (complete $cmd)

    if $result.exit_code == 0 {
      return { success: true, output: $result.stdout }
    }

    $attempts = $attempts + 1
    sleep 1sec
  }

  { success: false, error: "Max retries exceeded" }
}
```

---

## Best Practices

### Do's

- ✅ Use explicit types for validation
- ✅ Provide clear error messages with context
- ✅ Use safe navigation (`?`) for optional data
- ✅ Handle errors at boundaries (external commands, I/O)
- ✅ Log errors before re-raising

### Don'ts

- ❌ Swallow errors silently (`catch { null }`)
- ❌ Use string parsing for structured data
- ❌ Return strings for errors (use error records)
- ❌ Ignore exit codes from external commands

---

## Next Steps

**For performance:** [Performance](./05-performance.md)

**For deployment:** [Production Patterns](./06-production.md) > Monitoring
