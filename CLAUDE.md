# NUOC - Core Agent Guidelines

## Build/Test Commands

**ALWAYS use Moon:**
```bash
moon run :test     # All tests
moon run :check    # Type check
moon run :quick    # Format + lint
moon run :ci       # Full CI
```

**NEVER use cargo/nu directly.**

## Idiomatic Nushell

**Official docs: https://www.nushell.sh/book/**

**Key patterns:**
```nu
# Function with types
export def func_name [param: string]: nothing -> record {
  { key: "value" }
}

# Pipeline
list | where status == "PENDING" | each {|x| transform($x)}

# Error handling
try { risky_op } catch {|e|
  { status: "FAILED", error: ($e | get msg? | default "unknown") }
}

# Safe access
$record.field? | default "fallback"
```

## Model Usage

**Use Moon (Haiku) for all code generation** - 60-70% faster, perfect for Nushell.

## Writing Beads

```bash
bd create --title="[Category] verb what" --type=task|bug|feature --priority=0-4
```

**Examples:**
- `[SQL] Parameterize job queries` --type=bug --priority=0
- `[Workflow] Add checkpoint retry` --type=feature --priority=1

**Priority:** 0=critical, 1=high, 2=medium, 3=low, 4=backlog

## Core Rules

1. Use Moon (Haiku) for code
2. Consult nushell.sh for idioms
3. No comments - self-documenting code
4. Immutability preferred
5. Use `par-each` for parallel tasks
6. Return structured error records
7. Always escape SQL inputs
8. NEVER skip git push - work incomplete until pushed

## Session End

MANDATORY:
```bash
bd sync
git push
git status  # MUST show "up to date"
```
