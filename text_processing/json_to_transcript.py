#!/usr/bin/env python3
"""
Convert transcript JSON files to a clean text format.

Takes JSON files with segments and creates a readable transcript with:
[Speaker, timestamp] what they said

Usage:
    python json_to_transcript.py file1.json file2.json ...
    
Or pipe filenames from collect_json.py:
    python collect_json.py ./text "2025-10-18 23:40:00" "2025-10-19 01:30:00" | xargs python json_to_transcript.py

Output format:
[A, 00:00] something, is that good for you?
[B, 00:02] Yeah, I mean I like it. I think it's a lot better than that to be honest.
[A, 00:05] Yeah, yeah.
"""

import sys
import json
from pathlib import Path
from datetime import datetime, timedelta
import re

def format_timestamp(seconds):
    """Convert seconds to MM:SS format"""
    minutes = int(seconds // 60)
    secs = int(seconds % 60)
    return f"{minutes:02d}:{secs:02d}"

def extract_file_timestamp(filename):
    """Extract timestamp from filename like 20251018_234813_transcript_meta.json"""
    pattern = re.compile(r"(\d{8})_(\d{6})")
    match = pattern.search(filename)
    if match:
        date_part = match.group(1)  # YYYYMMDD
        time_part = match.group(2)  # HHMMSS
        ts_str = date_part + time_part
        return datetime.strptime(ts_str, "%Y%m%d%H%M%S")
    return None

def process_json_file(file_path):
    """Process a single JSON transcript file"""
    try:
        with open(file_path, 'r', encoding='utf-8') as f:
            data = json.load(f)
        
        # Extract base timestamp from filename
        file_timestamp = extract_file_timestamp(file_path.name)
        
        print(f"\n=== {file_path.name} ===")
        if file_timestamp:
            print(f"File created: {file_timestamp.strftime('%Y-%m-%d %H:%M:%S')}")
        print()
        
        # Check if we have segments (the new format) or fall back to text
        segments = data.get('segments', [])
        
        if segments:
            # Process segments with speaker diarization
            for segment in segments:
                if segment.get('type') == 'transcript.text.segment':
                    speaker = segment.get('speaker', 'Unknown')
                    text = segment.get('text', '').strip()
                    start_time = segment.get('start', 0)
                    
                    # Skip empty segments
                    if not text:
                        continue
                    
                    # Format timestamp relative to start of recording
                    timestamp = format_timestamp(start_time)
                    
                    print(f"[{speaker}, {timestamp}] {text}")
        else:
            # Fall back to plain text if no segments
            text = data.get('text', '')
            if text:
                print(f"[Unknown, 00:00] {text}")
    
    except json.JSONDecodeError as e:
        print(f"Error parsing JSON in {file_path}: {e}", file=sys.stderr)
    except FileNotFoundError:
        print(f"File not found: {file_path}", file=sys.stderr)
    except Exception as e:
        print(f"Error processing {file_path}: {e}", file=sys.stderr)

def main():
    """Main function"""
    if len(sys.argv) < 2:
        print("Usage: python json_to_transcript.py file1.json file2.json ...", file=sys.stderr)
        print("Or pipe from collect_json.py:", file=sys.stderr)
        print("  python collect_json.py ./text 'start' 'end' | xargs python json_to_transcript.py", file=sys.stderr)
        sys.exit(1)
    
    # Process each file
    for file_arg in sys.argv[1:]:
        file_path = Path(file_arg)
        
        # Handle both relative and absolute paths
        if not file_path.exists():
            # Try treating as filename in current directory
            file_path = Path.cwd() / file_arg
        
        if file_path.exists() and file_path.suffix.lower() == '.json':
            process_json_file(file_path)
        else:
            print(f"Skipping non-existent or non-JSON file: {file_arg}", file=sys.stderr)

if __name__ == "__main__":
    main()