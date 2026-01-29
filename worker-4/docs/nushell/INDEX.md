# Nushell Production Guide - Progressive Disclosure

**Quick Links:**
- [Foundation](./00-foundation.md) - Start here if new to Nushell
- [Functional Patterns](./01-functional.md) - Map/filter/reduce, composition
- [Type System](./02-types.md) - Type signatures, runtime checking
- [Testing](./03-testing.md) - Unit tests, property testing
- [Error Handling](./04-errors.md) - Try/catch, validation, safe navigation
- [Performance](./05-performance.md) - Streaming, parallel, optimization
- [Production Patterns](./06-production.md) - Monitoring, deployment, checklists
- [Reference](./07-reference.md) - Style guide, anti-patterns, examples

**Learning Paths:**

```
Beginner:        00 → 01 → 02
Script Writer:    00 → 02 → 03 → 04
Production Dev:  00 → 01 → 02 → 03 → 04 → 05 → 06
Performance:     00 → 01 → 05
```

**By Goal:**

| You want to... | Read this |
|----------------|-----------|
| Learn Nushell basics | [Foundation](./00-foundation.md) |
| Write idiomatic code | [Functional Patterns](./01-functional.md) |
| Add type safety | [Type System](./02-types.md) |
| Test your code | [Testing](./03-testing.md) |
| Handle errors | [Error Handling](./04-errors.md) |
| Optimize performance | [Performance](./05-performance.md) |
| Deploy to production | [Production Patterns](./06-production.md) |
| See real examples | [Reference](./07-reference.md) |

**Cheat Sheet:**

```nu
# Pipeline variable
ls | where $in.size > 1mb

# Safe navigation
$data.field? | default "fallback"

# Type signature
def process [x: int]: nothing -> int { $x * 2 }

# Error handling
try { risky } catch { |e| handle $e }

# Streaming (memory efficient)
open huge | lines | first 10

# Parallel (CPU intensive)
$items | par-each { expensive_op }
```

**Quick Navigation:**

- **I'm new** → Start with [Foundation](./00-foundation.md)
- **I know basics, want patterns** → [Functional Patterns](./01-functional.md)
- **I have a bug** → [Error Handling](./04-errors.md) > Debugging
- **My code is slow** → [Performance](./05-performance.md)
- **I'm deploying** → [Production Patterns](./06-production.md)
- **Show me examples** → [Reference](./07-reference.md) > Real-World Examples
