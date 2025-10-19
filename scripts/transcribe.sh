#!/usr/bin/env bash
# audio-telemetry: transcribe FLAC files using Whisper API with speaker diarization

# Temporarily disable strict mode for debugging
set -uo pipefail
# set -e  # Commented out to prevent silent exits

# Load environment variables from .env file
if [[ -f "$(dirname "$0")/../.env" ]]; then
  source "$(dirname "$0")/../.env"
  echo "✓ Loaded .env file"
else
  echo "⚠ No .env file found at $(dirname "$0")/../.env"
fi

# Configuration - Use .env values or defaults
AUDIO_DIR=${AUDIO_DIR:-"$(dirname "$0")/../audio/recordings"}
OUTPUT_DIR=${OUTPUT_DIR:-"$(pwd)"}  # Save to current directory
API_KEY=${OPENAI_API_KEY:-""}
CHECK_INTERVAL=${CHECK_INTERVAL:-60}  # seconds between checks
WHISPER_MODEL=${WHISPER_MODEL:-"whisper-1"}  # Use .env value
ENABLE_DIARIZATION=${ENABLE_DIARIZATION:-false}  # Use .env value
AUTO_FIX_AUDIO=${AUTO_FIX_AUDIO:-true}  # Auto-fix corrupted metadata

# Validate API key
if [[ -z "$API_KEY" ]]; then
  echo "ERROR: OpenAI API key required. Set OPENAI_API_KEY in .env file." >&2
  exit 1
fi

echo "== audio-telemetry transcription =="
echo "Audio dir:     $AUDIO_DIR"
echo "Output dir:    $OUTPUT_DIR"
echo "Check interval: ${CHECK_INTERVAL}s"
echo "Model:         $WHISPER_MODEL"
echo "Diarization:   $ENABLE_DIARIZATION"
echo "Auto-fix audio: $AUTO_FIX_AUDIO"
echo "API Key:       ${API_KEY:0:8}..." # Show first 8 chars only
echo

# Check if audio directory exists
if [[ ! -d "$AUDIO_DIR" ]]; then
  echo "ERROR: Audio directory does not exist: $AUDIO_DIR" >&2
  exit 1
fi

# Create temp directory for processed audio (cleaned up on exit)
TEMP_DIR="${OUTPUT_DIR}/.temp_audio"
mkdir -p "$TEMP_DIR"

# Show what files we found
echo "Scanning for audio files in: $AUDIO_DIR"
audio_files=($(find "$AUDIO_DIR" -name "*.flac" -o -name "*.wav" -type f))
echo "Found ${#audio_files[@]} audio file(s):"
for file in "${audio_files[@]}"; do
  echo "  - $(basename "$file") ($(stat -c%s "$file" 2>/dev/null || stat -f%z "$file" 2>/dev/null) bytes)"
done
echo

# Function to check and fix audio metadata
fix_audio_metadata() {
  local input_file="$1"
  local output_file="$2"
  
  echo "   🔧 Checking audio metadata..."
  
  # Check if ffprobe can read the duration properly
  local duration
  duration=$(ffprobe -v quiet -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$input_file" 2>/dev/null || echo "")
  
  if [[ -z "$duration" || "$duration" == "N/A" ]]; then
    echo "   ⚠ Corrupted metadata detected, fixing..."
    # Re-encode to fix metadata while preserving quality
    if ffmpeg -i "$input_file" -c:a flac -compression_level 8 "$output_file" >/dev/null 2>&1; then
      echo "   ✅ Metadata fixed ($(ffprobe -v quiet -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$output_file" 2>/dev/null || echo "unknown")s)"
      return 0
    else
      echo "   ❌ Failed to fix metadata" >&2
      return 1
    fi
  else
    echo "   ✅ Metadata looks good (${duration}s)"
    # Just copy the file if metadata is fine
    cp "$input_file" "$output_file"
    return 0
  fi
}

# Function to detect if audio file contains meaningful speech
detect_speech() {
  local audio_file="$1"
  
  echo "   🔊 Analyzing audio content..."
  
  # Get audio duration first - handle errors gracefully
  local duration
  duration=$(ffprobe -v quiet -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 "$audio_file" 2>/dev/null || echo "0")
  
  # Skip very short files (less than 2 seconds) - use awk for portability
  if [[ -n "$duration" && "$duration" != "0" ]]; then
    local is_short=$(awk -v dur="$duration" 'BEGIN { print (dur < 2) }')
    if [[ "$is_short" == "1" ]]; then
      echo "   ⏩ Audio too short (${duration}s) - likely not meaningful speech"
      return 1  # Return 1 means "skip this file"
    fi
  fi
  
  # Method 1: Use volumedetect to check overall audio levels
  local volume_output
  volume_output=$(ffmpeg -i "$audio_file" -af "volumedetect" -f null - 2>&1 || true)
  
  if [[ -n "$volume_output" ]]; then
    local mean_volume=$(echo "$volume_output" | grep "mean_volume" | sed 's/.*mean_volume: \([-0-9.]*\) dB.*/\1/' || echo "")
    local max_volume=$(echo "$volume_output" | grep "max_volume" | sed 's/.*max_volume: \([-0-9.]*\) dB.*/\1/' || echo "")
    
    if [[ -n "$mean_volume" || -n "$max_volume" ]]; then
      echo "   📊 Audio stats: duration=${duration}s, mean_volume=${mean_volume}dB, max_volume=${max_volume}dB"
    fi
    
    # Skip if audio is very quiet (likely silence or background noise only)
    if [[ -n "$mean_volume" && "$mean_volume" != "" ]]; then
      local is_quiet=$(awk -v vol="$mean_volume" 'BEGIN { print (vol < -50) }')
      if [[ "$is_quiet" == "1" ]]; then
        echo "   🔇 Audio appears to be mostly silence (mean volume: ${mean_volume}dB < -50dB)"
        return 1
      fi
    fi
    
    if [[ -n "$max_volume" && "$max_volume" != "" ]]; then
      local is_very_quiet=$(awk -v vol="$max_volume" 'BEGIN { print (vol < -35) }')
      if [[ "$is_very_quiet" == "1" ]]; then
        echo "   🔇 Audio appears very quiet (max volume: ${max_volume}dB < -35dB)"
        return 1
      fi
    fi
  fi
  
  # Method 2: Detect percentage of silence - handle errors gracefully
  if command -v awk >/dev/null 2>&1; then
    local silence_output
    silence_output=$(ffmpeg -i "$audio_file" -af "silencedetect=noise=-40dB:duration=1" -f null - 2>&1 || true)
    
    if [[ -n "$silence_output" ]]; then
      local silence_duration
      silence_duration=$(echo "$silence_output" | grep "silence_duration" | sed 's/.*silence_duration: \([0-9.]*\).*/\1/' | awk '{sum+=$1} END {print sum+0}' || echo "0")
      
      if [[ -n "$duration" && -n "$silence_duration" && "$duration" != "0" && "$silence_duration" != "0" ]]; then
        local silence_percentage
        silence_percentage=$(awk -v sil="$silence_duration" -v dur="$duration" 'BEGIN { printf "%.2f", (sil / dur) * 100 }')
        
        echo "   📈 Silence analysis: ${silence_duration}s of ${duration}s is silent (${silence_percentage}%)"
        
        # Skip if more than 80% is silence
        local is_mostly_silent=$(awk -v pct="$silence_percentage" 'BEGIN { print (pct > 80) }')
        if [[ "$is_mostly_silent" == "1" ]]; then
          echo "   🔇 Audio is mostly silent (${silence_percentage}% > 80%)"
          return 1
        fi
      fi
    fi
  fi
  
  echo "   ✅ Audio contains speech - proceeding with transcription"
  return 0  # Return 0 means "process this file"
}

# Function to transcribe a single file
transcribe_file() {
  local audio_file="$1"
  local base_name="$(basename "${audio_file%.*}")"
  local transcript_file="${OUTPUT_DIR}/${base_name}.txt"
  local metadata_file="${OUTPUT_DIR}/${base_name}_transcript_meta.json"
  
  echo "📁 Processing: $(basename "$audio_file")"
  echo "   Output: $transcript_file"
  
  # Skip if transcript already exists
  if [[ -f "$transcript_file" ]]; then
    echo "   ⏭ Transcript already exists, skipping"
    return 0
  fi
  
  # Check if audio contains meaningful speech
  if ! detect_speech "$audio_file"; then
    echo "   🔇 Skipping silent/empty audio - saving API costs"
    # Create placeholder transcript to mark as processed
    echo "[SILENT AUDIO - NO SPEECH DETECTED]" > "$transcript_file" || true
    echo "   📝 Created placeholder transcript for silent audio"
    return 0
  fi
  
  echo "   🎤 Starting transcription..."
  
  # Prepare audio file for API
  local processed_audio="$audio_file"
  local temp_audio="${TEMP_DIR}/${base_name}_processed.flac"
  local cleanup_temp=false
  
  if [[ "$AUTO_FIX_AUDIO" == "true" && "${audio_file,,}" == *.flac ]]; then
    if fix_audio_metadata "$audio_file" "$temp_audio"; then
      processed_audio="$temp_audio"
      cleanup_temp=true
      echo "   📁 Using processed audio file"
    else
      echo "   ⚠ Using original file despite metadata issues"
    fi
  fi
  
  # Prepare curl command based on diarization setting
  local curl_args=(
    -X POST
    -H "Authorization: Bearer $API_KEY"
    -H "Content-Type: multipart/form-data"
    -F "file=@$processed_audio"
  )
  
  if [[ "$ENABLE_DIARIZATION" == "true" ]]; then
    echo "   🎭 Using diarization model: gpt-4o-transcribe-diarize"
    curl_args+=(
      -F "model=gpt-4o-transcribe-diarize"
      -F "response_format=diarized_json"
      -F "chunking_strategy=auto"
    )
  else
    echo "   🎙 Using standard transcription model: $WHISPER_MODEL"
    curl_args+=(
      -F "model=$WHISPER_MODEL"
      -F "response_format=verbose_json"
    )
    
    # Only add timestamp granularities for whisper-1
    if [[ "$WHISPER_MODEL" == "whisper-1" ]]; then
      curl_args+=(
        -F "timestamp_granularities[]=word"
        -F "timestamp_granularities[]=segment"
      )
    fi
  fi
  
  # Make API request
  echo "   🌐 Sending to OpenAI API..."
  local response
  response=$(curl -s "${curl_args[@]}" "https://api.openai.com/v1/audio/transcriptions")
  
  echo "   📥 Response received (${#response} chars)"
  
  # Clean up temp file immediately after API call
  if [[ "$cleanup_temp" == "true" && -f "$temp_audio" ]]; then
    rm -f "$temp_audio"
    echo "   🧹 Cleaned up temporary audio file"
  fi
  
  # Check for API errors
  if echo "$response" | jq -e '.error' >/dev/null 2>&1; then
    echo "   ❌ API Error: $(echo "$response" | jq -r '.error.message')" >&2
    echo "   Full response: $response" >&2
    return 1
  fi
  
  # Extract transcript text based on response format
  local transcript_text
  if [[ "$ENABLE_DIARIZATION" == "true" ]]; then
    # For diarized_json format, extract text with speaker labels
    if echo "$response" | jq -e '.segments' >/dev/null 2>&1; then
      # Create formatted transcript with speaker labels
      transcript_text=$(echo "$response" | jq -r '.segments[] | "[Speaker \(.speaker // "Unknown")] \(.text)"' | paste -sd ' ')
    else
      # Fallback to plain text if segments not available
      transcript_text=$(echo "$response" | jq -r '.text // .transcript // ""')
    fi
  else
    # For verbose_json format
    transcript_text=$(echo "$response" | jq -r '.text')
  fi
  
  # Check if we got text
  if [[ -z "$transcript_text" || "$transcript_text" == "null" ]]; then
    echo "   ❌ No text content in response" >&2
    echo "   Response: $response" >&2
    return 1
  fi
  
  # Save transcript text
  echo "$transcript_text" > "$transcript_file"
  
  # Save full metadata response
  echo "$response" | jq '.' > "$metadata_file"
  
  echo "   ✅ Success! Files saved:"
  echo "      📄 $(basename "$transcript_file")"
  echo "      📋 $(basename "$metadata_file")"
  echo "   📝 Preview: ${transcript_text:0:100}..."
  echo
}

# Function to process all unprocessed files
process_files() {
  local processed_count=0
  local skipped_count=0
  local error_count=0
  local total_files=0
  
  echo "🔍 Checking for unprocessed files..."
  
  # First, collect all audio files into an array using a more reliable method
  echo "   📋 Scanning audio directory: $AUDIO_DIR"
  local all_files=()
  
  # Use mapfile (readarray) which is more reliable than while loops
  echo "   🔧 DEBUG: About to run find command..."
  find "$AUDIO_DIR" \( -name "*.flac" -o -name "*.wav" \) -type f | head -5
  echo "   🔧 DEBUG: Find command completed, running mapfile..."
  
  mapfile -t all_files < <(find "$AUDIO_DIR" \( -name "*.flac" -o -name "*.wav" \) -type f | sort)
  local mapfile_result=$?
  echo "   🔧 DEBUG: mapfile exit code: $mapfile_result"
  
  total_files=${#all_files[@]}
  echo "   🔧 DEBUG: Array populated with $total_files files"
  
  for audio_file in "${all_files[@]}"; do
    echo "      Found: $(basename "$audio_file")"
  done
  
  echo "   📊 Total audio files found: $total_files"
  echo "   🔧 DEBUG: About to check if total_files is zero..."
  
  if [[ $total_files -eq 0 ]]; then
    echo "   ⚠ No audio files found in $AUDIO_DIR"
    echo "💤 No files to process"
    echo "=========================="
    return
  fi
  
  echo
  echo "   🔧 DEBUG: Starting file processing loop..."
  
  # Process each file individually with better error handling
  local file_num=1
  echo "   🔧 DEBUG: About to iterate through ${#all_files[@]} files..."
  for audio_file in "${all_files[@]}"; do
    echo "   🔧 DEBUG: Processing array element $file_num: '$audio_file'"
    local base_name="$(basename "${audio_file%.*}")"
    local transcript_file="${OUTPUT_DIR}/${base_name}.txt"
    
    echo "🔎 Processing file $file_num of $total_files"
    echo "   File: $(basename "$audio_file")"
    echo "   Looking for existing transcript: $transcript_file"
    
    if [[ -f "$transcript_file" ]]; then
      echo "   ⏭ Transcript already exists, skipping"
      ((skipped_count++))
    else
      echo "   ✅ No existing transcript found - will process"
      
      # Try to transcribe with explicit error handling
      if transcribe_file "$audio_file"; then
        echo "   🎉 Successfully transcribed: $(basename "$audio_file")"
        ((processed_count++))
      else
        echo "   💥 Failed to transcribe: $(basename "$audio_file")"
        ((error_count++))
        echo "   🔄 Continuing with next file despite error..."
      fi
      
      # Small delay to avoid rate limiting
      if [[ $file_num -lt $total_files ]]; then
        echo "   ⏱ Waiting 2 seconds before next file..."
        sleep 2
      fi
    fi
    
    echo "   ---"
    ((file_num++))
  done
  
  echo "📊 FINAL SUMMARY:"
  echo "   📁 Total files found: $total_files"
  echo "   ✅ Successfully processed: $processed_count"
  echo "   ⏭ Skipped (already done): $skipped_count"
  echo "   ❌ Errors encountered: $error_count"
  
  if [[ $processed_count -gt 0 ]]; then
    echo "🎉 Successfully processed $processed_count new files this round!"
  elif [[ $total_files -gt 0 && $skipped_count -eq $total_files ]]; then
    echo "✨ All files already processed - nothing new to do"
  else
    echo "💤 No new files were processed"
  fi
  echo "=========================="
}

# Cleanup function
cleanup() {
  echo "🧹 Cleaning up temporary files..."
  if [[ -d "$TEMP_DIR" ]]; then
    rm -rf "$TEMP_DIR"
    echo "   ✅ Removed temporary directory: $TEMP_DIR"
  fi
  echo "� Stopping transcription monitor..."
  exit 0
}

# Main loop
echo "� Starting transcription monitoring..."
echo "Press Ctrl+C to stop"
echo

trap cleanup INT

while true; do
  process_files
  sleep "$CHECK_INTERVAL"
done