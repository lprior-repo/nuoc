#!/usr/bin/env python3
import json
import sqlite3
import sys
from http.server import HTTPServer, BaseHTTPRequestHandler
from urllib.parse import urlparse, parse_qs
import subprocess
import os

# Configuration
PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 4097
DB_PATH = ".oc-workflow/journal.db"


class AwakeableHandler(BaseHTTPRequestHandler):
    def _set_headers(self, status_code=200, content_type="application/json"):
        self.send_response(status_code)
        self.send_header("Content-type", content_type)
        self.end_headers()

    def _send_json_response(self, data, status_code=200):
        self._set_headers(status_code)
        self.wfile.write(json.dumps(data).encode("utf-8"))

    def _send_error(self, message, status_code=400):
        self._send_json_response({"success": False, "error": message}, status_code)

    def _send_success(self, data=None):
        response = {"success": True}
        if data:
            response.update(data)
        self._send_json_response(response)

    def do_GET(self):
        parsed = urlparse(self.path)

        if parsed.path == "/health":
            self._send_success({"status": "ok", "message": "NUOC server is running"})
        else:
            self._send_error("Not found", 404)

    def do_POST(self):
        parsed = urlparse(self.path)
        path_parts = parsed.path.strip("/").split("/")

        # Route: /awakeables/{id}/resolve
        if (
            len(path_parts) == 4
            and path_parts[0] == "awakeables"
            and path_parts[2] == "resolve"
        ):
            awakeable_id = path_parts[1]
            self._handle_resolve_awakeable(awakeable_id)
        else:
            self._send_error("Not found", 404)

    def _handle_resolve_awakeable(self, awakeable_id):
        try:
            # Read request body
            content_length = int(self.headers.get("Content-Length", 0))
            body = self.rfile.read(content_length)

            # Parse JSON payload
            try:
                payload = json.loads(body.decode("utf-8")) if content_length > 0 else {}
            except json.JSONDecodeError:
                self._send_error("Invalid JSON payload")
                return

            # Validate awakeable_id
            if not awakeable_id or not isinstance(awakeable_id, str):
                self._send_error("Invalid awakeable ID")
                return

            # Check if awakeable exists and is pending
            conn = sqlite3.connect(DB_PATH)
            cursor = conn.cursor()
            cursor.execute(
                "SELECT job_id, task_name, status FROM awakeables WHERE id = ?",
                (awakeable_id,),
            )
            result = cursor.fetchone()
            conn.close()

            if not result:
                self._send_error(f"Awakeable not found: {awakeable_id}", 404)
                return

            job_id, task_name, status = result

            if status != "PENDING":
                self._send_error(
                    f"Awakeable not pending (status: {status}): {awakeable_id}", 409
                )
                return

            # Serialize payload to JSON for storage
            payload_json = json.dumps(payload)

            # Update awakeable: mark RESOLVED, store payload, set timestamp
            conn = sqlite3.connect(DB_PATH)
            cursor = conn.cursor()
            cursor.execute(
                """UPDATE awakeables 
                   SET status = 'RESOLVED', payload = ?, resolved_at = datetime('now')
                   WHERE id = ?""",
                (payload_json, awakeable_id),
            )

            # Wake the suspended task
            cursor.execute(
                "UPDATE tasks SET status = 'pending' WHERE job_id = ? AND name = ?",
                (job_id, task_name),
            )
            conn.commit()
            conn.close()

            # Log event (would need to call Nushell for this, but we'll do it directly here)
            self._log_event(
                job_id,
                task_name,
                "task.StateChange",
                "suspended",
                "pending",
                f"awakeable {awakeable_id} resolved",
            )

            self._send_success(
                {
                    "awakeable_id": awakeable_id,
                    "payload": payload,
                    "message": "Awakeable resolved successfully",
                }
            )

        except Exception as e:
            print(f"Error resolving awakeable: {e}", file=sys.stderr)
            self._send_error(f"Internal server error: {str(e)}", 500)

    def _log_event(self, job_id, task_name, event_type, old_state, new_state, payload):
        try:
            conn = sqlite3.connect(DB_PATH)
            cursor = conn.cursor()
            cursor.execute(
                """INSERT INTO events (job_id, task_name, event_type, old_state, new_state, payload)
                   VALUES (?, ?, ?, ?, ?, ?)""",
                (job_id, task_name, event_type, old_state, new_state, payload),
            )
            conn.commit()
            conn.close()
        except Exception as e:
            print(f"Error logging event: {e}", file=sys.stderr)

    def log_message(self, format, *args):
        # Suppress default logging
        pass


def run_server():
    server_address = ("", PORT)
    httpd = HTTPServer(server_address, AwakeableHandler)
    print(f"NUOC HTTP server listening on port {PORT}")
    print(f"Database: {os.path.abspath(DB_PATH)}")
    try:
        httpd.serve_forever()
    except KeyboardInterrupt:
        print("\nShutting down server...")
        httpd.shutdown()


if __name__ == "__main__":
    run_server()
