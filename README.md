# audio-transcription

An automated audio transcription tool that monitors directories for audio files and converts them to text using OpenAI's Whisper API. Features automatic FLAC metadata repair, speaker diarization support, and clean file management.

## Quick Start (New Machine Setup)

### 1. Install Dependencies
```bash
# Ubuntu/Debian/Mint
sudo apt update && sudo apt install -y curl jq ffmpeg git

# macOS (with Homebrew)
brew install curl jq ffmpeg git

# Verify installation
curl --version && jq --version && ffmpeg -version
```

### 2. Get OpenAI API Key
1. Go to [OpenAI API Keys](https://platform.openai.com/api-keys)
2. Create a new API key
3. Copy the key (starts with `sk-proj-...`)

### 3. Download and Setup
```bash
# Clone or download the project
git clone https://github.com/claremont-computer-network/audio-transcription.git
cd audio-transcription

# Make script executable
chmod +x scripts/transcribe.sh

# Create configuration file
cat > .env << 'EOF'
OPENAI_API_KEY=sk-proj-your-key-here
AUDIO_DIR=/home/$(whoami)/audio-transcription/audio/recordings
CHECK_INTERVAL=60
WHISPER_MODEL=whisper-1
ENABLE_DIARIZATION=false
AUTO_FIX_AUDIO=true
EOF

# Replace with your actual API key
nano .env  # or vim .env
```

### 4. Create Directory Structure
```bash
mkdir -p audio/recordings
mkdir -p transcripts  # optional output directory
```

### 5. Test with Sample Audio
```bash
# Copy your audio file to the monitored directory
cp /path/to/your/audio.flac audio/recordings/

# Run the transcription (Ctrl+C to stop)
./scripts/transcribe.sh
```

### 6. Expected Output
You'll see files created in the project directory:
```
your-audio.txt                    # Plain text transcript
your-audio_transcript_meta.json  # Full API response with metadata
```

---

## Complete Configuration Guide

### Environment Variables (.env file)

| Variable | Description | Default | Example |
|----------|-------------|---------|---------|
| `OPENAI_API_KEY` | Your OpenAI API key (**required**) | - | `sk-proj-abc123...` |
| `AUDIO_DIR` | Directory to monitor for audio files | `./audio/recordings` | `/home/user/audio` |
| `CHECK_INTERVAL` | Seconds between directory scans | `60` | `30` |
| `WHISPER_MODEL` | OpenAI model to use | `whisper-1` | `gpt-4o-transcribe` |
| `ENABLE_DIARIZATION` | Enable speaker separation | `false` | `true` |
| `AUTO_FIX_AUDIO` | Auto-fix FLAC metadata issues | `true` | `false` |

### Supported Audio Formats
- **FLAC** (recommended - auto-repaired if corrupted)
- **WAV** (high compatibility)
- **MP3, MP4, M4A** (compressed formats)
- **WEBM, MPEG, MPGA** (additional formats)

### Model Comparison
| Model | Features | Max Length | Use Case |
|-------|----------|------------|----------|
| `whisper-1` | Standard transcription, timestamps | 25 MB | General purpose, reliable |
| `gpt-4o-transcribe` | Higher quality, prompting | 25 MB | Better accuracy |
| `gpt-4o-transcribe-diarize` | Speaker separation | 25 MB | Multi-speaker meetings |

---

## How to Use

### Basic Operation
1. **Start monitoring:**
   ```bash
   cd audio-transcription
   ./scripts/transcribe.sh
   ```

2. **Add audio files:**
   ```bash
   # Copy files to monitored directory
   cp recording.flac audio/recordings/
   
   # Files are processed automatically
   # Watch the terminal for progress
   ```

3. **Stop monitoring:**
   ```bash
   # Press Ctrl+C in terminal
   # Temp files are automatically cleaned up
   ```

### What Happens Automatically
- ✅ **Detects** new audio files every 60 seconds
- ✅ **Checks** FLAC files for corrupted metadata
- ✅ **Fixes** duration issues automatically 
- ✅ **Transcribes** using OpenAI Whisper API
- ✅ **Saves** transcript and metadata files
- ✅ **Cleans up** temporary files
- ✅ **Skips** already processed files

### Output Files
For each `recording.flac`, you get:
```
recording.txt                    # Clean transcript text
recording_transcript_meta.json  # Full API response with timestamps
```

---

## Speaker Diarization Setup

### Enable Speaker Separation
1. **Edit configuration:**
   ```bash
   nano .env
   # Change: ENABLE_DIARIZATION=true
   ```

2. **Requirements:**
   - Audio must be longer than 30 seconds
   - Uses `gpt-4o-transcribe-diarize` model automatically
   - Costs slightly more per minute

3. **Output format with speakers:**
   ```
   [Speaker 0] Hello, how are you today?
   [Speaker 1] I'm doing well, thank you.
   [Speaker 0] That's great to hear.
   ```

---

---

## 5. Usage

### Basic Workflow

1. **Start the monitor:**
   ```bash
   cd /path/to/audio-transcription
   ./scripts/transcribe.sh
   ```

2. **Add audio files:**
   ```bash
   # Copy audio files to the monitored directory
   cp recording.flac audio/recordings/
   ```

3. **Monitor output:**
   The script will automatically:
   - Detect new audio files
   - Send them to OpenAI's API
   - Save transcripts in the current directory
   - Display progress with emojis and status messages

### Output Files

For each audio file `recording.flac`, the script creates:

```
recording.txt                    # Plain text transcript
recording_transcript_meta.json  # Full API response with timestamps
```

### Directory Structure

```
audio-transcription/
├── .env                        # Configuration
├── scripts/
│   └── transcribe.sh          # Main script
├── audio/
│   └── recordings/            # Input audio files
├── recording1.txt             # Transcript output
├── recording1_meta.json      # Metadata output  
├── recording2.txt
└── recording2_meta.json
```

### Running with Custom Output Directory

To save transcripts to a specific directory:

```bash
# Set OUTPUT_DIR in .env
echo "OUTPUT_DIR=/path/to/transcripts" >> .env

# Or set temporarily
OUTPUT_DIR=/path/to/transcripts ./scripts/transcribe.sh
```

---

## 6. Speaker Diarization

### Enable Diarization
Set in `.env`:
```bash
ENABLE_DIARIZATION=true
```

### Requirements
- Audio must be > 30 seconds for diarization
- Uses `gpt-4o-transcribe-diarize` model automatically
- Adds `chunking_strategy=auto` parameter

### Output Format
With diarization enabled, transcripts include speaker labels:
```
[Speaker 0] Hello, how are you today?
[Speaker 1] I'm doing well, thank you for asking.
[Speaker 0] That's great to hear.
```

---

## Troubleshooting

### ❌ Common Setup Issues

**"Command not found" errors:**
```bash
# Install missing dependencies
sudo apt update && sudo apt install -y curl jq ffmpeg

# Verify installation
which curl jq ffmpeg
```

**"Permission denied" on script:**
```bash
chmod +x scripts/transcribe.sh
```

**"API key required" error:**
```bash
# Check your .env file has the correct key
cat .env | grep OPENAI_API_KEY
# Should show: OPENAI_API_KEY=sk-proj-...
```

### ⚠️ Audio Processing Issues

**"Audio duration too long" error:**
- **Cause:** Corrupted FLAC metadata (shows 39,997 seconds instead of actual duration)
- **Solution:** Script auto-fixes this with `AUTO_FIX_AUDIO=true` (default)
- **Manual fix:** `ffmpeg -i corrupted.flac -c:a flac fixed.flac`

**"No files found" message:**
```bash
# Check directory path is correct
ls -la audio/recordings/

# Verify file format is supported
file audio/recordings/your-file.flac
```

**Script stuck or slow:**
- Check internet connection (needs API access)
- Reduce `CHECK_INTERVAL` in .env for faster scanning
- Large files take longer to upload and process

### 🔧 Advanced Troubleshooting

**View detailed progress:**
```bash
./scripts/transcribe.sh | tee transcription.log
```

**Test with minimal setup:**
```bash
# Create test audio file
ffmpeg -f lavfi -i "sine=frequency=1000:duration=5" test.wav
cp test.wav audio/recordings/
./scripts/transcribe.sh
```

**Check API quota:**
- Visit [OpenAI Usage Dashboard](https://platform.openai.com/usage)
- Verify you have available credits
- Check rate limits aren't exceeded

---

## File Management & Performance

### Directory Structure
```
audio-transcription/
├── .env                          # Your configuration
├── scripts/transcribe.sh         # Main script  
├── audio/recordings/             # Input audio files
├── .temp_audio/                  # Temporary files (auto-cleaned)
├── your-file.txt                # Output transcripts
├── your-file_transcript_meta.json # Output metadata
└── README.md                     # This file
```

### API Costs & Optimization
- **Pricing:** $0.006 per minute of audio
- **Example:** 1 hour = $0.36
- **File limit:** 25 MB per file  
- **Tip:** Use compressed formats when possible
- **Monitor:** Check [OpenAI Usage Dashboard](https://platform.openai.com/usage)

### Batch Processing
```bash
# Process multiple files at once
cp /path/to/multiple/*.flac audio/recordings/
./scripts/transcribe.sh
# Processes all files sequentially
```