#!/bin/bash
# Acceptance tests for nuoc-37v: [TUI-01] Set up Rust project with ratatui and crossterm

set -e

echo "Running acceptance tests for nuoc-37v..."

# Test 1: Cargo.toml exists with dependencies
echo "Test 1: Checking Cargo.toml has ratatui and crossterm dependencies..."
if grep -q "ratatui" Cargo.toml && grep -q "crossterm" Cargo.toml; then
    echo "✓ Cargo.toml contains ratatui and crossterm dependencies"
else
    echo "✗ Cargo.toml missing required dependencies"
    exit 1
fi

# Test 2: Basic main.rs with terminal setup
echo "Test 2: Checking main.rs has terminal setup..."
if grep -q "enable_raw_mode" src/main.rs && grep -q "Terminal" src/main.rs; then
    echo "✓ main.rs contains terminal setup code"
else
    echo "✗ main.rs missing terminal setup"
    exit 1
fi

# Test 3: Event loop skeleton
echo "Test 3: Checking main.rs has event loop..."
if grep -q "event::poll" src/main.rs && grep -q "Event::Key" src/main.rs; then
    echo "✓ main.rs contains event loop skeleton"
else
    echo "✗ main.rs missing event loop"
    exit 1
fi

# Test 4: cargo build succeeds
echo "Test 4: Building project..."
if cargo build --quiet 2>&1; then
    echo "✓ cargo build succeeds"
else
    echo "✗ cargo build failed"
    exit 1
fi

# Test 5: Terminal enters raw mode (code inspection)
echo "Test 5: Checking raw mode terminal setup..."
if grep -q "enable_raw_mode" src/main.rs && grep -q "disable_raw_mode" src/main.rs; then
    echo "✓ Terminal enters raw mode"
else
    echo "✗ Missing raw mode setup"
    exit 1
fi

# Test 6: Clean exit on 'q'
echo "Test 6: Checking exit on 'q' key..."
if grep -q "KeyCode::Char('q')" src/main.rs; then
    echo "✓ Clean exit on 'q' implemented"
else
    echo "✗ Missing 'q' key exit handler"
    exit 1
fi

echo ""
echo "All acceptance tests passed! ✓"
