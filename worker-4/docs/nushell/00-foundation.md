# Foundation: Nushell Core Philosophy

**Previous:** [Index](./INDEX.md) | **Next:** [Functional Patterns](./01-functional.md)

---

## Core Principles

1. **Everything is structured data** - Tables, records, lists (not text)
2. **Functional-first** - Immutable, pure functions, composition
3. **Type safety** - Explicit types prevent errors
4. **Streaming** - Process incrementally, avoid collecting
5. **Quality through design** - Testable, observable, maintainable

---

## Essential Syntax

### Pipeline Variable

```nu
# Simple: use $in
ls | where $in.size > 1mb

# Complex: use explicit parameters
ls | each { |file| $file.name | str upcase }
```

### Subexpressions

```nu
# Required when command output needed as argument
cd (ls | where type == dir | first | get name)

# Nested
mkdir $"backup_(date now | format date '%Y%m%d')"
```

### Ranges

```nu
1..5    # [1, 2, 3, 4, 5] inclusive
1..<5   # [1, 2, 3, 4] exclusive

for x in 1..10 { print $x }
```

### Cell Paths

```nu
$data.user.name              # Nested access
$data.missing?               # Returns null (not error)
$data | get $field_name      # Dynamic access
```

### Safe Navigation

```nu
# Optional access with default
$config.database?.port? | default 5432

# Error with context
error make {
  msg: "Operation failed"
  label: { text: $"invalid value: ($val)" }
}
```

---

## Data Manipulation

### Records

```nu
$record | insert key value          # Add key
$record | update key { |old| ... }   # Transform key
$record | merge $other              # Combine
$record | reject key1 key2          # Remove keys
```

### Tables

```nu
$table | select col1 col2           # Project columns
$table | where condition           # Filter rows
$table | update col { ... }         # Transform column
$table | group-by category         # Aggregate
$table | flatten                   # Unnest
```

### Lists

```nu
$list | append value                # Add to end
$list | prepend value              # Add to start
$list | uniq                       # Remove duplicates
$list | chunks 10                  # Batch
```

### Aggregations

```nu
$numbers | math sum
$numbers | math avg
$list | length
$table | uniq-by column
```

---

## Anti-Patterns to Avoid

### ❌ Bad: Mutation

```nu
mut total = 0
for x in $list { $total = $total + $x }
```

### ✓ Good: Reduction

```nu
$list | reduce { |it, acc| $acc + $it }
```

### ❌ Bad: Text Parsing

```nu
ps | to text | lines | each { str split " " }
```

### ✓ Good: Structured Data

```nu
ps | select pid name cpu | where cpu > 50
```

---

## Next Steps

**For functional patterns:** [Functional Patterns](./01-functional.md)

**For type safety:** [Type System](./02-types.md)

**For examples:** [Reference](./07-reference.md) > Real-World Examples
