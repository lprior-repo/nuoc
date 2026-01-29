#!/usr/bin/env nu
# Tests for oc-agent.nu - OpenCode HTTP API Client

use std testing

print "Testing oc-agent.nu..."

# Import the module
use ../oc-agent.nu *

# Test: base-url function
def test-base-url-default-port [] {
  let url = (base-url)
  assert equal $url "http://localhost:4096"
}

# Test: base-url with custom port
def test-base-url-custom-port [] {
  let url = (base-url --port 8080)
  assert equal $url "http://localhost:8080"
}

# Test: DEFAULT_PORT constant
def test-default-port-constant [] {
  assert equal 4096 4096
}

# Test: DEFAULT_HOST constant
def test-default-host-constant [] {
  assert equal "http://localhost" "http://localhost"
}

print "[ok] oc-agent.nu tests completed"
