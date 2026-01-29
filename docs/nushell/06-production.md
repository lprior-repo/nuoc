# Production Patterns: Monitoring & Deployment

**Previous:** [Performance](./05-performance.md) | **Next:** [Reference](./07-reference.md)

---

## Health Checks

### Basic Health Check

```nu
def health_check []: nothing -> record {
  let checks = [
    {
      name: "disk_space"
      check: { (sys disks | where mount == "/" | first | get free) > 1GB }
      message: "Sufficient disk space"
    }
    {
      name: "memory"
      check: { (sys mem | get used) < ((sys mem | get total) * 0.9) }
      message: "Memory usage OK"
    }
  ]

  let results = ($checks | each { |c|
    try {
      let passed = (do $c.check)
      {name: $c.name, status: "pass", message: $c.message}
    } catch { |e|
      {name: $c.name, status: "fail", message: $e.msg}
    }
  })

  {
    overall: (if ($results | where status == "fail" | length) == 0 {"healthy"} else {"unhealthy"})
    checks: $results
    timestamp: (date now | format date "%Y-%m-%d %H:%M:%S")
  }
}
```

---

## Logging

### Structured Logging

```nu
export const LOG_LEVELS = {
  DEBUG: 0, INFO: 1, WARN: 2, ERROR: 3
}

export def log [level: string, message: string, --data: record] {
  let current = (get_config "log_level" | default "info")
  let level_val = ($LOG_LEVELS | get ($level | str upcase))
  let current_val = ($LOG_LEVELS | get ($current | str upcase))

  if $level_val >= $current_val {
    {
      timestamp: (date now | format date "%Y-%m-%d %H:%M:%S")
      level: ($level | str upcase)
      message: $message
      data: ($data | default {})
    } | to json | print
  }
}
```

### Log with Masking

```nu
def log_masked [level: string, message: string, --sensitive: list<string>] {
  mut masked = $message
  if $sensitive != null {
    for key in $sensitive {
      $masked = ($masked | str replace -a $key "***MASKED***")
    }
  }
  log $level $masked
}
```

---

## Configuration Management

### Environment-Specific Config

```nu
def load_config [env: string]: nothing -> record {
  let base = (open "config/base.toml")
  let env_file = $"config/($env).toml"

  if ($env_file | path exists) {
    $base | merge (open $env_file)
  } else {
    log "warn" $"No config for ($env), using base"
    $base
  }
}
```

### Secure Secrets

```nu
def load_secrets [path: string]: nothing -> record {
  # Check permissions
  let perms = (ls -l $path | first | get permissions)
  if not ($perms | str starts-with "-rw-------") {
    error make { msg: "Insecure permissions on secrets" }
  }

  open $path
}
```

---

## Graceful Shutdown

```nu
def graceful_shutdown []: nothing -> nothing {
  log "info" "Shutting down..."

  # Save state
  save_current_state

  # Close connections
  close_connections

  # Cleanup temp files
  cleanup_temp

  log "info" "Shutdown complete"
  exit 0
}
```

---

## Production Checklist

### Code Quality
- [ ] Type signatures on all functions
- [ ] Error handling explicit and comprehensive
- [ ] Input validation performed
- [ ] Pure functions (no hidden side effects)
- [ ] Documented with examples

### Testing
- [ ] Unit tests (happy path + errors)
- [ ] Integration tests (end-to-end)
- [ ] Property tests (invariants)
- [ ] Performance benchmarks
- [ ] Tests run in CI

### Observability
- [ ] Structured logging
- [ ] Health checks
- [ ] Metrics collection
- [ ] Error tracking
- [ ] Performance monitoring

### Security
- [ ] Input validation and sanitization
- [ ] Secure secret management
- [ ] File access controls
- [ ] Audit logging
- [ ] Least privilege

### Deployment
- [ ] Config externalized
- [ ] Environment-specific configs
- [ ] Graceful shutdown
- [ ] Rollback procedures
- [ ] Database migrations

---

## Production Script Template

```nu
#!/usr/bin/env nu

# Configuration
const CONFIG = load_config "production"
const LOG_LEVEL = "info"

# Main
def main [input_file: string, --dry-run (-n)] {
  log "info" $"Processing: ($input_file)"

  if $dry_run {
    log "info" "DRY RUN - skipping execution"
    return
  }

  # Process
  let data = (open $input_file)
  let result = (process_data $data)

  # Output
  $result | save output.json
  log "info" "Complete"
}

# Error handling
try {
  main ...args
} catch { |e|
  log "error" $"Fatal: ($e.msg)"
  exit 1
}
```

---

## Next Steps

**For examples:** [Reference](./07-reference.md)

**Back to:** [Index](./INDEX.md)
