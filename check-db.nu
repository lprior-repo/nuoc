#!/usr/bin/env nu
use oc-engine.nu *

rm -rf .oc-workflow
db-init

let tables = (sqlite3 $DB_PATH "SELECT name FROM sqlite_master WHERE type='table';" | from ssv)
print "All tables:"
print $tables
print "Column names:"
print ($tables | columns)
