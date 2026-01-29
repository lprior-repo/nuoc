#!/usr/bin/env nu
# oc-server.nu — NUOC HTTP Server
# Exposes awakeable resolution and other workflow operations via HTTP

use oc-engine.nu *

const SERVER_PORT = 4097
const SERVER_HOST = "http://localhost"

# Start the HTTP server
export def "main start" [--port: int = 4097] {
  print $"Starting NUOC HTTP server on port ($port)..."

  # Use Python's http.server for a simple HTTP server
  # Start it in the background and capture the PID
  let server_pid = (python3 $"scripts/oc-http-server.py ($port)" &)

  print $"[ok] NUOC HTTP server started on port ($port)"
  print $"     PID: ($server_pid)"
  print $"     Endpoint: http://localhost:($port)/awakeables/{{id}}/resolve"

  # Return PID for later use
  $server_pid
}

# Stop the HTTP server
export def "main stop" [pid: int] {
  try {
    ^kill $pid
    print $"[ok] NUOC HTTP server stopped (PID: ($pid))"
  } catch {|e|
    print $"[warn] Failed to stop server: ($e | get msg? | default 'unknown error')"
  }
}

# Health check
export def "main health" [--port: int = 4097] {
  try {
    http get $"($SERVER_HOST):($port)/health"
  } catch {
    { status: "error", message: "server not responding" }
  }
}
