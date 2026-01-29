# Functional Programming Patterns

**Previous:** [Foundation](./00-foundation.md) | **Next:** [Type System](./02-types.md)

---

## Core Concepts

### Immutability

```nu
# Transform, don't mutate
let filtered = $data | where active
let doubled = $list | each { |x| $x * 2 }
```

### Pure Functions

```nu
# Given same inputs → same outputs, no side effects
def calculate_total [items: list]: nothing -> int {
  $items | each { |x| $x.price * $x.quantity } | math sum
}
```

### Function Composition

```nu
# Pipeline = composition
data | transform | normalize | validate

# Named composition
def process []: any -> any {
  validate | transform | normalize
}
```

---

## Map/Filter/Reduce

### Map (Transform)

```nu
# Transform each element
$list | each { |x| $x * 2 }

# Update column
$table | update col { |row| $row.col * 2 }
```

### Filter (Where)

```nu
# Filter by predicate
$list | where { |x| $x > 10 }

# Filter table rows
$table | where status == "active"
```

### Reduce (Aggregate)

```nu
# Sum with reduce
$list | reduce { |it, acc| $acc + $it }

# With explicit initial
$list | reduce -f 0 { |it, acc| $acc + $it }

# Scan (all intermediate values)
$list | iter scan 0 { |it, acc| $acc + $it }
```

---

## Advanced Patterns

### Partition

```nu
# Split by predicate
$list | partition { |x| $x mod 2 == 0 }
# Returns: {true: evens, false: odds}
```

### Group By

```nu
# Group by field
$table | group-by category

# Group by computed key
$table | group-by { |row| $row.date | format date '%Y-%m' }
```

### Window/Chunks

```nu
# Sliding windows
$list | window 3  # [[1,2,3] [2,3,4] [3,4,5]]

# Non-overlapping chunks
$list | chunks 10  # Batch processing
```

### Transducers

```nu
# Compose before collecting (efficient)
$huge
| where condition
| each transform
| first 100  # Single pass, constant memory
```

---

## Functional Compositions

### Partial Application

```nu
# Fix arguments to create specialized function
def multiply [x: int, y: int]: nothing -> int { $x * $y }
def double []: int -> int { multiply $in 2 }

# Closures capture environment
let threshold = 100
$data | where { |x| $x.value > $threshold }
```

### Higher-Order Functions

```nu
# Function that takes function
def map_transform [transform: closure]: list -> list {
  $in | each $transform
}

# Use it
$data | map_transform { |x| $x * 2 }
```

---

## Streaming vs Collecting

### Stream (Memory Efficient)

```nu
# Process incrementally, early exit
open huge.csv | where status == "active" | first 10

# Streaming aggregation
$stream | reduce { |it, acc| $acc + $it }  # Constant memory
```

### Collect (When Needed)

```nu
# Multiple passes required
let data = (fetch_data | collect)
$data | analyze
$data | report
```

---

## Common Patterns

### Validation Pipeline

```nu
def validate_user [user: record]: nothing -> record {
  # Check required fields
  if not (["name" "email"] | all { |f| $f in ($user | columns) }) {
    error make { msg: "Missing required fields" }
  }

  # Validate ranges
  if $user.age < 0 or $user.age > 150 {
    error make { msg: "Invalid age" }
  }

  $user
}
```

### Safe Navigation Chain

```nu
# Maybe chain
$data
| get -i key1
| get -i key2
| default "fallback"

# Try chain
try { step1 }
| try { step2 }
catch { default_value }
```

---

## Next Steps

**For type safety:** [Type System](./02-types.md)

**For testing:** [Testing](./03-testing.md)

**For examples:** [Reference](./07-reference.md) > Data Pipeline Example
