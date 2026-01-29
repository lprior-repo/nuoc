# Performance Optimization

**Previous:** [Error Handling](./04-errors.md) | **Next:** [Production Patterns](./06-production.md)

---

## Streaming vs Collecting

### Stream (Memory Efficient)

```nu
# Process incrementally, constant memory
open huge.csv | where status == "active" | first 10

# Streaming aggregation
$stream | reduce { |it, acc| $acc + $it }
```

### Collect (When Needed)

```nu
# Multiple passes required
let data = (fetch_data | collect)
$data | analyze
$data | report
```

**Rule:** Stream by default, collect only when necessary.

---

## Parallel Processing

### par-each

```nu
# CPU-bound tasks
$items | par-each { |item| expensive_transform $item }

# With ordering preserved
$items
| enumerate
| par-each { |x| {index: $x.index, result: (process $x.item)} }
| sort-by index
| get result
```

**Use when:** Operations take >100ms per item and are CPU-bound.

**Avoid:** Simple operations (overhead > benefit).

---

## Memory Efficiency

### Batch I/O

```nu
# Process in chunks to avoid memory spike
$ids | chunks 10 | each { |batch|
  fetch_batch $batch
} | flatten
```

### Constant Memory Patterns

```nu
# Good: Stream processing
open large.log | lines | where $it =~ "ERROR" | first 100

# Bad: Collect all
let all = (open large.log | lines)
$all | where $it =~ "ERROR" | first 100
```

---

## Performance Patterns

### Early Exit

```nu
# Stop as soon as you have enough
open huge.csv | where condition | first 100  # Only processes 100 rows
```

### Avoid Unnecessary Parsing

```nu
# Bad: Parse to text, then back
ps | to text | lines | each { str split " " }

# Good: Use structured data
ps | select pid name cpu
```

### Choose Right Aggregation

```nu
# Count only
$list | length

# Unique only
$list | uniq

# Sum only
$list | math sum

# Don't: collect then aggregate
```

---

## Profiling

### Timing Operations

```nu
def profile [name: string, op: closure]: any -> any {
  let start = (date now)
  let result = ($in | do $op)
  let duration = ((date now) - $start)

  print $"PROFILE ($name): ($duration)"
  $result
}

# Usage
$data | profile "filtering" { where active }
| profile "transform" { each transform }
```

### Benchmarking

```nu
def benchmark [iterations: int, op: closure] {
  let start = (date now)

  for i in 1..$iterations {
    do $op
  }

  let duration = ((date now) - $start)
  let avg = ($duration / $iterations)

  {
    total_iterations: $iterations
    total_duration: $duration
    avg_duration: $avg
  }
}
```

---

## Common Optimizations

### Use Built-ins

```nu
# Fast: Built-in
$list | math sum

# Slow: Manual reduce
$list | reduce { |it, acc| $acc + $it }
```

### Avoid Intermediate Collections

```nu
# Good: Single pass
$data | where cond | each transform | select cols

# Bad: Multiple passes
let filtered = ($data | where cond)
let transformed = ($filtered | each transform)
$transformed | select cols
```

### Choose Right Data Structure

```nu
# Lookup: record is O(1)
$record | get key

# Search: list is O(n)
$list | where { |x| $x == value }
```

---

## Performance Checklist

- [ ] Streaming used for large datasets
- [ ] `par-each` only for expensive CPU-bound operations
- [ ] Early exit with `first N` when possible
- [ ] Batch I/O operations
- [ ] Profile before optimizing
- [ ] Built-ins preferred over manual implementation
- [ ] Appropriate data structures chosen

---

## Next Steps

**For production deployment:** [Production Patterns](./06-production.md)

**For examples:** [Reference](./07-reference.md) > Performance Examples
