# CLAUDE.md

не используй /codebase-memory-reference СТРОГО !!! НИКОГДА !!!

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

YouTube video downloading and management pipeline with FTP sync to a mobile device. All scripts are in Bash/Python, run on Ubuntu (MSI Raider laptop with NVIDIA GPU).

## Key Scripts

- `youtube_download_01.sh` — Main download script. Two-phase: (1) scans channels from `_channels.txt` for new videos, (2) downloads in batches via yt-dlp with rate-limiting. Uses `--cookies-from-browser firefox` and download archive `_download_archive.txt`.
- `copy_to_Folder3.sh` — Syncs downloaded videos to Android device via FTP (lftp). Finds files newer than N days, sanitizes filenames for FAT/exFAT, copies with size verification.
- `transcribe.sh` / `transcribe1.sh` — Transcription via Whisper. `transcribe1.sh` is the newer version using whisper-asr-webservice Docker container with GPU, supports `--force` and `--format=` flags.
- `get_cookies.py` — Extracts YouTube cookies from Firefox profile's SQLite DB into Netscape format.

## Data Files

- `_channels.txt` — List of YouTube channel URLs (one per line, `#` comments)
- `_download_archive.txt` — yt-dlp archive of already-downloaded video IDs
- Videos are organized into subdirectories by channel name

## Dependencies

- `yt-dlp` (installed at `/home/uadmin/.local/bin/yt-dlp`)
- `ffmpeg`
- `lftp` (for FTP sync)
- `docker` (for Whisper transcription)
- Firefox (for cookie extraction)

## Common Commands

```bash
# Download new videos from all channels
./youtube_download_01.sh

# Sync videos to mobile device
./copy_to_Folder3.sh

# Transcribe a video
./transcribe1.sh /path/to/video.mp4
./transcribe1.sh --force --format=flac /path/to/video.mp4
```
