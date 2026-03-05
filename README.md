# 🤟 PolyVoice — Real-time Accessibility Call Translator

> **Break every communication barrier.** PolyVoice enables real-time calls between Deaf, Blind, and hearing users with automatic translation between Speech, Text, and Sign Language.

---

## The Problem

600M+ people worldwide are Deaf or Hard of Hearing. 43M+ are blind. There is **no widely available real-time calling system** that translates between voice and sign language. This creates isolation, dependency on interpreters, and exclusion from everyday communication.

## Our Solution

PolyVoice is a mobile calling app that acts as a **live translation bridge**:

```
🗣️ Hearing/Blind User speaks
    → Speech-to-Text (real-time)
    → 📱 Deaf User sees live captions

🤟 Deaf User signs with camera
    → Sign Language AI → Text
    → Text-to-Speech
    → 🔊 Hearing/Blind User hears response
```

**One app. Any user. Zero barriers.**

---

## Demo Flow

### Scenario: Blind User ↔ Deaf User

1. **Blind user** speaks normally into the phone
2. App transcribes speech to text in real-time
3. **Deaf user** sees live captions on screen
4. Deaf user responds using sign language (camera) or quick phrases
5. App converts signs → text → voice
6. **Blind user** hears the response spoken aloud

---

## Tech Stack

| Layer        | Technology                                   |
|-------------|----------------------------------------------|
| **Mobile**   | Flutter (iOS + Android)                      |
| **Calling**  | Twilio Programmable Video (WebRTC)           |
| **STT**      | Platform-native Speech-to-Text               |
| **TTS**      | Platform-native Text-to-Speech               |
| **Sign AI**  | Google ML Kit + MediaPipe Hand Landmarks     |
| **Backend**  | Node.js + Express                            |
| **Auth**     | JWT + bcrypt                                 |
| **Database** | SQLite (zero-config, hackathon-ready)        |

---

## Architecture

```
┌─────────────────────────────────────────────┐
│                FLUTTER APP                   │
│  ┌──────────┐  ┌──────────┐  ┌───────────┐ │
│  │  Camera   │  │   Mic    │  │  Speaker  │ │
│  └────┬─────┘  └────┬─────┘  └─────▲─────┘ │
│       │              │              │        │
│  ┌────▼─────┐  ┌────▼─────┐  ┌─────┴─────┐ │
│  │ ML Kit   │  │   STT    │  │   TTS     │ │
│  │ Sign AI  │  │ Service  │  │  Service  │ │
│  └────┬─────┘  └────┬─────┘  └─────▲─────┘ │
│       │              │              │        │
│       └──────┐  ┌────┘    ┌─────────┘        │
│              ▼  ▼         │                  │
│         ┌──────────┐  ┌───┴──────┐           │
│         │   TEXT    │──│ Twilio   │           │
│         │  Bridge   │  │  Video   │           │
│         └──────────┘  └──────────┘           │
└───────────────┬─────────────┬───────────────┘
                │             │
        ┌───────▼───────┐    │ (WebRTC)
        │  Node.js API  │    │
        │  ┌──────────┐ │    │
        │  │  Auth     │ │    │
        │  │  Calls    │ │    │
        │  │  Tokens   │ │    │
        │  └──────────┘ │    │
        │  ┌──────────┐ │    │
        │  │  SQLite   │ │    │
        │  └──────────┘ │    │
        └───────────────┘    │
                             │
                    ┌────────▼────────┐
                    │  Twilio Cloud   │
                    │  Video Rooms    │
                    └─────────────────┘
```

---

## Quick Start (5 minutes)

### Prerequisites

- **Node.js** 18+ installed
- **Flutter** 3.16+ installed
- **Android Studio** or **Xcode** with an emulator/device
- **Twilio account** (free trial works)

### 1. Clone & Setup Backend

```bash
git clone <repo-url>
cd polyvoice/backend

# Install dependencies
npm install

# Configure environment
cp .env.example .env
```

Edit `.env` with your Twilio credentials:

```env
PORT=3000
JWT_SECRET=pick-any-strong-secret-here

# From https://console.twilio.com
TWILIO_ACCOUNT_SID=ACxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
TWILIO_AUTH_TOKEN=your_auth_token

# Create API Key at: Console → Account → API Keys
TWILIO_API_KEY_SID=SKxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
TWILIO_API_KEY_SECRET=your_api_key_secret
```

Start the server:

```bash
npm start
```

You should see:

```
╔══════════════════════════════════════════╗
║   🤟 PolyVoice API Server               ║
║   Running on http://0.0.0.0:3000        ║
╚══════════════════════════════════════════╝
```

### 2. Setup Flutter App

```bash
cd ../flutter_app

# Get dependencies
flutter pub get
```

#### Configure Backend URL

Edit `lib/config/app_config.dart`:

```dart
// Android Emulator:
static const String baseUrl = 'http://10.0.2.2:3000';

// iOS Simulator:
static const String baseUrl = 'http://localhost:3000';

// Physical Device (use your computer's IP):
static const String baseUrl = 'http://192.168.1.XXX:3000';
```

#### Android Setup

1. Open `android/app/build.gradle` and set:
   ```gradle
   defaultConfig {
       minSdkVersion 24
       targetSdkVersion 34
   }
   ```

2. Add permissions from `android_permissions.xml` to your `AndroidManifest.xml`

#### iOS Setup (if applicable)

Add to `ios/Runner/Info.plist`:
```xml
<key>NSCameraUsageDescription</key>
<string>Camera is needed for sign language detection</string>
<key>NSMicrophoneUsageDescription</key>
<string>Microphone is needed for voice calls</string>
<key>NSSpeechRecognitionUsageDescription</key>
<string>Speech recognition converts voice to text</string>
```

### 3. Run

```bash
# Terminal 1 — Backend
cd backend && npm start

# Terminal 2 — Flutter
cd flutter_app && flutter run
```

---

## How to Get Twilio Credentials

1. Go to [console.twilio.com](https://console.twilio.com)
2. Copy your **Account SID** and **Auth Token** from the dashboard
3. Go to **Account → API Keys** → Create a new API Key
4. Copy the **SID** and **Secret**
5. Paste all four values into your `.env` file

---

## Hackathon Demo Script

### Setup (2 phones or 1 phone + 1 emulator)

1. **Device A** — Register as "Alice" with role **Blind**
2. **Device B** — Register as "Bob" with role **Deaf**

### Demo Flow

1. **Alice** (Blind) taps "Call" on Bob's contact card
2. **Bob** (Deaf) sees incoming call → accepts
3. **Alice** speaks: *"Hi Bob, how are you today?"*
4. **Bob** sees live captions appear in real-time on screen
5. **Bob** taps quick phrase "I'm doing great, thank you!"
   (or uses camera to sign letters)
6. **Alice** hears the TTS voice read Bob's response
7. Conversation continues seamlessly

### What to Highlight for Judges

- **Real-time STT** — words appear as they're spoken
- **Role-adaptive UI** — different experience for Deaf vs Blind vs Hearing
- **Twilio Video** — production-grade WebRTC calling
- **Sign Language AI** — MediaPipe hand landmarks → ASL classification
- **Quick Phrases** — reliable fallback for communication
- **Zero-interpreter dependency** — complete independence

---

## Project Structure

```
polyvoice/
├── backend/
│   ├── server.js            # Express API (auth, calls, Twilio tokens)
│   ├── package.json
│   ├── .env.example
│   └── polyvoice.db         # SQLite (auto-created)
│
├── flutter_app/
│   ├── lib/
│   │   ├── main.dart                    # App entry + providers
│   │   ├── config/
│   │   │   ├── app_config.dart          # URLs, constants
│   │   │   └── theme.dart               # Dark theme, role colors
│   │   ├── models/
│   │   │   └── user_model.dart          # User + Call models
│   │   ├── services/
│   │   │   ├── auth_service.dart        # JWT auth, user management
│   │   │   ├── call_service.dart        # Twilio Video rooms
│   │   │   ├── speech_service.dart      # STT + TTS
│   │   │   └── sign_language_service.dart  # ML Kit hand detection
│   │   └── screens/
│   │       ├── splash_screen.dart       # Animated splash + auth check
│   │       ├── auth_screen.dart         # Login/register + role selection
│   │       ├── home_screen.dart         # Contacts + incoming calls
│   │       └── call_screen.dart         # THE MAIN EVENT
│   ├── pubspec.yaml
│   └── android_permissions.xml          # Required Android permissions
│
├── .gitignore
└── README.md
```

---

## API Endpoints

| Method   | Endpoint                    | Description              | Auth |
|----------|-----------------------------|--------------------------|------|
| `POST`   | `/api/auth/register`        | Create account           | No   |
| `POST`   | `/api/auth/login`           | Login                    | No   |
| `GET`    | `/api/auth/me`              | Get current user         | Yes  |
| `GET`    | `/api/users`                | List all contacts        | Yes  |
| `PATCH`  | `/api/users/status`         | Update online status     | Yes  |
| `POST`   | `/api/twilio/token`         | Generate Video token     | Yes  |
| `POST`   | `/api/calls/initiate`       | Start a call             | Yes  |
| `POST`   | `/api/calls/:id/accept`     | Accept incoming call     | Yes  |
| `POST`   | `/api/calls/:id/end`        | End a call               | Yes  |
| `GET`    | `/api/calls/pending`        | Check for incoming calls | Yes  |

---

## Sign Language Detection

The ASL detection pipeline works in three stages:

1. **Hand Landmark Detection** — ML Kit Pose Detection extracts wrist, thumb, index, and pinky positions from camera frames
2. **Geometric Classification** — Rule-based analysis of finger positions, angles, and distances maps to ASL letters
3. **Stability Buffer** — Requires 60%+ consistency over 8 frames before confirming a letter (prevents flickering)

Currently recognizes: **A, B, D, I, L, S, V, Y** with high confidence. For the full 26-letter alphabet, integrate a trained TFLite CNN model.

**Quick Phrases** provide reliable communication for the demo regardless of model accuracy.

---

## Troubleshooting

| Issue | Fix |
|-------|-----|
| `Network error` on login | Check `baseUrl` in `app_config.dart` matches your backend IP |
| Camera permission denied | Go to device Settings → App → PolyVoice → Permissions |
| `minSdkVersion` error | Set `minSdkVersion 24` in `android/app/build.gradle` |
| Twilio token error | Verify all 4 Twilio values in `.env` are correct |
| STT not working | Ensure microphone permission granted + device has Google STT |
| Backend crash on start | Run `npm install` and check Node.js version (18+ required) |

---

## Future Roadmap

- [ ] Full 26-letter ASL recognition (TFLite CNN model)
- [ ] Video rendering of remote participant
- [ ] Sign language avatar (3D animated hands from text)
- [ ] Multi-language sign support (BSL, RSL, ISL)
- [ ] Group calls
- [ ] Offline sign recognition
- [ ] Chat history persistence
- [ ] Push notifications for incoming calls

---

## Team

Built with ❤️ for accessibility at [Hackathon Name]

---

## License

MIT
