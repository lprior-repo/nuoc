# Type System & Testing

**Previous:** [Functional Patterns](./01-functional.md) | **Next:** [Error Handling](./04-errors.md)

---

## Type System

### Type Signatures

**Always specify types:**

```nu
def name [param: type]: input_type -> output_type {
  body
}
```

**Examples:**

```nu
def process [x: int]: nothing -> int { $x * 2 }

def calculate_total [items: list<record>]: nothing -> float {
  $items | each { |item| $item.price * $item.quantity } | math sum
}

def api_get [endpoint: string]: nothing -> record {
  http get $"https://api.example.com/($endpoint)"
}
```

**Benefits:**
- Documents function contracts
- Runtime type checking (v0.102+)
- Parse-time verification
- Better error messages

### Runtime Checking

```nu
def cool_int_print []: int -> nothing {
  print $"my cool int is ($in)"
}

1 | cool_int_print      # Works
"string" | cool_int_print  # Throws: input_type_mismatch
```

### Error Propagation

```nu
# Errors in pipeline are thrown immediately
try { risky_command } catch { |e|
  print -e $"Error: ($e)"
}

# External commands: check explicitly
let result = (complete { ^external_cmd })
if $result.exit_code == 0 {
  $result.stdout | from json
} else {
  error make { msg: $"Failed: ($result.stderr)" }
}
```

---

## Testing

### Unit Tests

### Assertions

```nu
def assert_equal [actual: any, expected: any, message: string] {
  if $actual != $expected {
    error make {
      msg: $"Assertion failed: ($message)",
      label: { text: $"Expected ($expected), got ($actual)" }
    }
  }
}

def assert_type [value: any, expected_type: string] {
  let actual = ($value | describe)
  if $actual != $expected_type {
    error make {
      msg: "Type assertion failed",
      label: { text: $"Expected ($expected_type), got ($actual)" }
    }
  }
}
```

### Test Pattern

```nu
export def test_add [] {
  assert_equal (add 2 3) 5 "Basic addition"
  assert_equal (add -1 1) 0 "With negatives"
  assert_type (add 1 2) "int"
  print "✓ All tests passed"
}

export def run_tests [] {
  [test_add test_subtract test_multiply]
  | each { |test|
    try { do $test; {test: $test, status: "PASS"} }
    catch { |e| {test: $test, status: "FAIL", error: $e.msg} }
  }
  | where status == "FAIL"
}
```

### Property Testing

```nu
# Property: map preserves length
def prop_map_length [f: closure] {
  let original = [1 2 3 4 5]
  let mapped = ($original | each $f)
  assert_equal ($mapped | length) ($original | length) "Map preserves length"
}

# Property: filter then map == map then filter
def prop_filter_map_commute [pred: closure, mapper: closure] {
  let data = [1 2 3 4 5]
  let r1 = ($data | where $pred | each $mapper)
  let r2 = ($data | each $mapper | where $pred)
  assert_equal $r1 $r2 "Filter-map commutes"
}
```

### Integration Tests

```nu
def test_api_integration [] {
  let test_data = {name: "test", value: 123}
  let response = (http post http://localhost:8080/api/test $test_data)

  assert_equal $response.status 200 "Expected 200"
  assert_type $response.body.id "int"

  # Cleanup
  http delete $"http://localhost:8080/api/test/($response.body.id)"
}
```

---

## Quick Reference

### Type Checklist

- [ ] All functions have type signatures
- [ ] Parameters have explicit types
- [ ] Return type specified
- [ ] Use `list<T>` and `table<col: type>` for structured types

### Test Checklist

- [ ] Unit tests for happy path
- [ ] Unit tests for error cases
- [ ] Integration tests for external deps
- [ ] Property tests for invariants
- [ ] Run tests in CI

---

## Next Steps

**For error handling:** [Error Handling](./04-errors.md)

**For examples:** [Reference](./07-reference.md) > Testing Examples
