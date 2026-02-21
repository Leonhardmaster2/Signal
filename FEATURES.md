# Trace - Feature Documentation

## Table of Contents
- [Recording Capabilities](#recording-capabilities)
- [Transcription Features](#transcription-features)
- [AI Features](#ai-features)
- [Premium Tiers](#premium-tiers)
- [Export & Sharing](#export--sharing)
- [iCloud Backup](#icloud-backup)
- [Settings & Customization](#settings--customization)
- [Advanced Features](#advanced-features)

---

## Recording Capabilities

### Audio Recording
- **Studio-Quality Audio**: 44kHz mono recording in AAC format
- **Real-time Visualization**: Live waveform display with amplitude metering
- **Recording Controls**:
  - Pause/Resume functionality
  - Background recording support
  - Live Activity widget on Lock Screen
  - Recovery checkpoints for unexpected terminations
- **Audio Session Management**: Handles interruptions and route changes

### Recording Annotations
- **Mark System**: Flag important moments during recording with timestamps
- **Meeting Notes**: Add text notes while recording
- **Image Attachments**: Capture photos or add from library as visual notes
- **Speaker Management**: Automatic speaker identification with custom naming

### Recording Management
- Edit recording titles
- Star/favorite important recordings
- Archive old recordings
- Delete with confirmation
- Full amplitude history for waveform replay
- Duration tracking and formatted display

---

## Transcription Features

### Cloud Transcription (ElevenLabs Scribe API)
- Full speech-to-text with word-level timestamps
- **Speaker Diarization**: Automatic speaker separation and identification
- **Speaker Customization**: Rename speakers (speaker_0 → "John", etc.)
- Automatic language detection
- Segment-by-segment breakdown with timestamps
- Full transcript text generation

### On-Device Transcription
- **Privacy-First**: Local transcription using Apple Speech Framework
- **No Data Transmission**: Everything stays on your device
- Available with Standard+ subscription or Privacy Pack purchase
- Automatic fallback to cloud if unavailable
- Multi-language support

### Smart Transcription System
- **Auto-routing**: Intelligently selects cloud vs on-device based on settings
- **Silence Trimming**: Pre-processes audio to remove silent parts (Standard+ only)
- **Speed Optimization**: 1.5x faster cloud transcription
- **Audio Compression**: Reduces upload size to 16kHz
- **Progress Tracking**: Real-time transcription progress updates
- **Cancellation Support**: Stop transcription mid-process

### Transcription Limits by Tier
| Tier | Monthly Limit |
|------|--------------|
| Free | 15 minutes |
| Standard | 12 hours |
| Pro | 36 hours |

---

## AI Features

### Summarization (Google Gemini 2.5 Flash Lite)

#### Summary Components
- **One-Liner**: Max 20-word capture of core outcome
- **Context**: 2-4 sentences with key discussion points
- **On-Device Option**: Privacy-focused local summarization (Standard+/Privacy Pack)
- **Multi-Language**: Summaries in transcript language

#### Smart Action Extraction
Automatically extracts:
- **Action Items**: Task, assignee, status, timestamp
- **Emails**: Recipient, subject, body suggestions, timestamp
- **Reminders**: Title, due date, timestamp
- **Calendar Events**: Title, date/time, duration, timestamp
- **Key Sources**: 3-5 important moments with descriptions and timestamps

#### Context-Aware Summarization
- Includes user-provided meeting notes
- Current date for relative date interpretation
- User usage profile for tailored prompts
- Speaker names integrated into context

### Audio Search & Chat (Pro Tier Only)

#### Ask Your Audio
- **Natural Language Q&A**: Chat with AI about your recordings
- **Conversational Interface**: Multi-turn conversation support
- **Tappable Citations**: [MM:SS] timestamp links in responses
- **Markdown Formatting**: Bold text, bullet points, numbered lists
- **Persistent History**: Conversations saved per recording

#### Features
- Navigate directly to transcript segments from chat
- Suggested starter questions
- Copy message functionality
- Delete conversation history with confirmation
- Instant keyboard dismissal
- Floating glass-styled input bar

---

## Premium Tiers

### Free Tier - Forever
✓ Unlimited recordings
✓ 15 min/month transcription
✓ 44kHz recording quality
✓ Unlimited storage
✓ Note-taking & archiving
✗ No AI analysis

### Standard Tier
**Monthly / Yearly Plans Available**

✓ 12 hours/month transcription
✓ AI summarization with Deep Dive
✓ On-device transcription (privacy-focused)
✓ On-device summarization
✓ Speaker identification
✓ 2-hour max file upload
✓ PDF/Markdown export
✓ Unlimited recording history

### Pro Tier
**Monthly / Yearly Plans Available**

✓ 36 hours/month transcription
✓ **Audio Search** (Ask Your Audio)
✓ Priority processing (faster AI)
✓ Unlimited file upload size
✓ Everything in Standard

### Privacy Pack - One-Time Purchase
**$3.00** - 2 hours of transcription
✓ On-device transcription & summarization access
✓ Credits never expire
✓ No subscription required

---

## Export & Sharing

### Markdown Export (Standard+ Only)
- Complete recording metadata (title, date, duration, language)
- Full summary section (one-liner, context, actions)
- Speaker-labeled transcript with timestamps
- Meeting notes section
- Formatted for easy sharing

### PDF Export (Standard+ Only)
- Professional formatted documents
- **Trace branding**: Logo header and footer
- Multi-page support with pagination
- Summary and action items
- Full transcript with speaker separation
- Meeting notes
- Page numbers and branding

### Share Sheet
- Native iOS share functionality
- Platform-aware (iPad/Mac popover support)
- Multiple export format support

---

## iCloud Backup

### Automatic Backup
- **iCloud Drive Integration**: Backup all recordings automatically
- **Note Images**: Visual attachments backed up separately
- **JSON Manifests**: Complete metadata preservation
- **Sign in with Apple**: Secure authentication

### Backup Features
- Manual "Backup Now" trigger
- Real-time sync progress tracking
- Last backup date display
- Per-recording or full backup options
- Conflict resolution (uses most recent modification)

### Restore Functionality
- Restore recordings from iCloud
- Complete metadata restoration
- Audio file and image recovery
- Duplicate detection

---

## Settings & Customization

### Appearance
- **Dark Mode**: Full dark theme
- **Light Mode**: Optimized light theme with reduced glass frosting
- **System**: Follow device setting

### Recording Settings
- Recording quality selection
- Haptic feedback toggle
- Auto-transcribe new recordings

### Transcription Settings
- Enable on-device transcription (when available)
- Automatic language detection toggle
- Preferred transcription language
- **14+ Language Support**: English, French, German, Spanish, and more

### AI Settings
- Enable on-device summarization (when available)
- Usage profile customization (Professional, Student, Freelancer, etc.)

### iCloud Settings
- Apple account status
- Manual backup trigger with progress
- Restore from iCloud
- Last backup timestamp

### Data Management
- Delete all recordings (with confirmation)
- Storage usage information
- Export/restore functionality

---

## Advanced Features

### Audio Processing
- **Silence Trimming**: Automatic silence detection and removal
- **Speed Optimization**: 1.5x faster transcription processing
- **Segment Mapping**: Timestamp remapping for edited audio
- **RMS Energy Analysis**: Statistical silence detection
- Configurable silence thresholds

### Live Activities
- Lock Screen recording widget
- Real-time timer display
- Pause/resume status
- Dynamic island support

### App Shortcuts
- "Start Recording" shortcut
- "View Latest Recording" shortcut
- "Import Audio File" shortcut
- Notification-triggered actions

### Adaptive Layouts
- **iPhone**: Compact tabbed layout (Summary, Transcript, Notes, Audio)
- **iPad/Mac**: Side-by-side panels with split view
- Responsive design with size classes

### Transcript Management
- **Edit Segments**: Modify transcript text inline
- **Speaker Renaming**: Custom speaker name interface
- **Delete Transcript**: Remove and re-transcribe
- **Regeneration**: Full text updates on edit

### Audio Player
- Mini waveform with scrubbing
- Play/pause controls
- 15-second forward skip
- Progress display with timestamps
- **Synchronized Playback**: Tap transcript segment to play

### Onboarding Experience
- **Welcome Screen**: Animated app introduction
- **Language Selection**: Choose from 14+ languages
- **Usage Profile**: Tailored experience (Professional, Student, etc.)
- **Feature Showcase**: Customized based on usage type
- **Quick Tips**: 4-step tutorial on core workflow
- **Notification Permission**: Optional notification setup

### Chat Interface Enhancements
- **Glass-styled Messages**: Frosted glass bubble design
- **Floating Input Bar**: Elevated, modern input design
- **Keyboard Dismissal**: Tap anywhere or swipe down
- **Delete Confirmation**: Prevent accidental conversation deletion
- **Markdown Support**: Bold text, formatting preserved

---

## Technical Specifications

### APIs & Integrations
- **ElevenLabs Scribe API**: Cloud transcription with diarization
- **Google Gemini 2.5 Flash Lite**: Summarization and chat
- **Apple Speech Framework**: On-device transcription
- **Apple Intelligence**: On-device summarization (when available)
- **StoreKit 2**: In-app purchases and subscriptions
- **ActivityKit**: Live Activities support
- **EventKit**: Calendar event creation

### Data Models
- **SwiftData**: Recording persistence
- **JSON Files**: Chat history (separate from core data)
- **iCloud Documents**: Backup storage

### Architecture
- **Service-Oriented**: Modular service layer
- **Observable State**: Reactive SwiftUI patterns
- **Async/Await**: Modern concurrency
- **Feature Gating**: Tier-based access control

---

## Usage Limits Summary

| Feature | Free | Standard | Pro |
|---------|------|----------|-----|
| Recording | Unlimited | Unlimited | Unlimited |
| Transcription/month | 15 min | 12 hours | 36 hours |
| AI Summarization | ✗ | ✓ | ✓ |
| Speaker ID | ✗ | ✓ | ✓ |
| On-Device Features | ✗ | ✓* | ✓* |
| Audio Upload | ✗ | 2h max | Unlimited |
| Export (PDF/MD) | ✗ | ✓ | ✓ |
| Audio Search (Chat) | ✗ | ✗ | ✓ |
| Priority Processing | ✗ | ✗ | ✓ |
| Recording History | 50 limit | Unlimited | Unlimited |

\* On-device features also available via Privacy Pack one-time purchase

---

## Recent Improvements

### Light Mode Enhancements
- Theme-aware "RECORD" button text (visible in light mode)
- Theme-aware import audio icon
- Reduced glass frosting opacity in light mode
- Optimized for better visibility

### Chat Interface Polish
- Glass card styling for message bubbles
- Floating input bar with shadow effect
- Instant keyboard collapse on tap
- Swipe-down keyboard dismissal
- Delete conversation confirmation dialog
- Removed duplicate menu button

### Markdown Rendering
- Full support for `**bold**` text
- Proper timestamp underlining `[MM:SS]`
- Tappable citation links

### Onboarding Flow
- New welcome screen with animated logo
- Quick tips page with notification permission
- Smooth page transitions
- Usage profile-based feature pages

---

**Last Updated**: February 2026
**Version**: Current Release
**Platform**: iOS, iPadOS, macOS (Catalyst)
