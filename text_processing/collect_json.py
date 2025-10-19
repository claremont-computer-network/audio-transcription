#!/usr/bin/env python3
"""
List transcript JSON files whose filenames contain timestamps of the form %Y%m%d_%H%M%S
within a given time interval.

Usage:
    python list_jsons_by_time.py /path/to/dir "2025-10-18 23:40:00" "2025-10-19 01:30:00"
"""

import sys
from pathlib import Path
from datetime import datetime
import re

if len(sys.argv) != 4:
    print("Usage: python collect_json.py DIR START_DATETIME END_DATETIME", file=sys.stderr)
    print("Example: python collect_json.py ./text '2025-10-18 23:40:00' '2025-10-19 01:30:00'", file=sys.stderr)
    sys.exit(1)

directory = Path(sys.argv[1])

# Check if directory exists
if not directory.exists():
    print(f"Directory does not exist: {directory}", file=sys.stderr)
    sys.exit(1)

# Parse datetimes with error handling
try:
    start = datetime.strptime(sys.argv[2], "%Y-%m-%d %H:%M:%S")
    end = datetime.strptime(sys.argv[3], "%Y-%m-%d %H:%M:%S")
except ValueError as e:
    print(f"Error parsing datetime: {e}", file=sys.stderr)
    sys.exit(1)

pattern = re.compile(r"(\d{8})_(\d{6})")  # matches 20251018_234813

matches = []
for file in directory.glob("*.json"):
    m = pattern.search(file.name)
    if not m:
        continue
    ts_str = m.group(1) + m.group(2)
    try:
        ts = datetime.strptime(ts_str, "%Y%m%d%H%M%S")
    except ValueError:
        continue
    if start <= ts <= end:
        matches.append((ts, file.resolve()))

# sort chronologically
matches.sort(key=lambda x: x[0])

for _, f in matches:
    print(f)
