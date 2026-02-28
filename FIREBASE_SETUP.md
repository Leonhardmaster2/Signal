# Firebase Backend Proxy Setup Guide

This guide provides complete instructions for setting up Firebase Cloud Functions as a secure backend proxy for ElevenLabs and Gemini APIs.

## Overview

The architecture uses Firebase Cloud Functions to:
- ✅ **Secure API Keys**: Store API keys server-side in Firebase Environment Secrets
- ✅ **Authenticate Users**: Verify Firebase Auth tokens before processing requests
- ✅ **Log Usage**: Track API usage in Cloud Firestore for cost monitoring
- ✅ **Proxy Requests**: Forward requests to ElevenLabs and Gemini APIs securely

## Prerequisites

1. **Firebase CLI** installed globally:
   ```bash
   npm install -g firebase-tools
   ```

2. **Node.js 18+** installed (for Cloud Functions)

3. **Firebase Project** created at [console.firebase.google.com](https://console.firebase.google.com)

4. **Xcode 15+** with Swift 5.9+

---

## Part 1: Firebase Console Setup

### 1.1 Enable Firebase Services

1. Go to [Firebase Console](https://console.firebase.google.com)
2. Select your project (or create a new one)
3. Enable the following services:

   **Authentication:**
   - Go to **Authentication** → **Sign-in method**
   - Enable **Apple** sign-in provider
   - Configure Service ID and Team ID (from Apple Developer)

   **Cloud Firestore:**
   - Go to **Firestore Database** → **Create database**
   - Start in **Production mode**
   - Choose a location (e.g., `us-central1`)

   **Cloud Functions:**
   - Upgrade to **Blaze (Pay as you go)** plan (required for outbound API calls)

### 1.2 Configure Firestore Security Rules

In the Firebase Console → **Firestore Database** → **Rules**, add:

```javascript
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    // Only allow authenticated users to read their own usage logs
    match /usage_logs/{document} {
      allow read: if request.auth != null && request.auth.uid == resource.data.userId;
      allow write: if false; // Only Cloud Functions can write
    }
  }
}
```

### 1.3 Download Firebase Configuration

1. Go to **Project Settings** → **General**
2. Under **Your apps**, select **iOS**
3. Download `GoogleService-Info.plist`
4. Add it to your Xcode project (drag into Xcode, check "Copy items if needed")

---

## Part 2: Deploy Firebase Cloud Functions

### 2.1 Initialize Firebase Functions

In your project directory:

```bash
# Navigate to your project root
cd /Users/leonhardmeingast/Documents/Projects/ComputerScienceIA/App/Signal

# Create Firebase directory
mkdir -p firebase
cd firebase

# Login to Firebase (if not already logged in)
firebase login

# Initialize Firebase (select your project)
firebase init functions

# During initialization:
# - Select "TypeScript"
# - Choose "Yes" for ESLint
# - Choose "Yes" to install dependencies
```

### 2.2 Install Dependencies

```bash
cd functions
npm install firebase-admin firebase-functions node-fetch@2
npm install --save-dev @types/node-fetch
```

### 2.3 Copy Cloud Functions Code

Replace `functions/src/index.ts` with the code provided in the previous section (see Cloud Functions code above).

### 2.4 Update package.json

Ensure your `functions/package.json` includes:

```json
{
  "name": "functions",
  "scripts": {
    "build": "tsc",
    "serve": "npm run build && firebase emulators:start --only functions",
    "deploy": "firebase deploy --only functions",
    "logs": "firebase functions:log"
  },
  "engines": {
    "node": "18"
  },
  "main": "lib/index.js",
  "dependencies": {
    "firebase-admin": "^12.0.0",
    "firebase-functions": "^5.0.0",
    "node-fetch": "^2.7.0"
  },
  "devDependencies": {
    "@types/node-fetch": "^2.6.2",
    "typescript": "^5.3.0"
  }
}
```

### 2.5 Set API Key Secrets

Store your API keys securely in Firebase Environment Secrets:

```bash
# Set ElevenLabs API key
firebase functions:secrets:set ELEVENLABS_API_KEY
# When prompted, paste your ElevenLabs API key: YOUR_ELEVENLABS_API_KEY_HERE

# Set Gemini API key
firebase functions:secrets:set GEMINI_API_KEY
# When prompted, paste your Gemini API key: YOUR_GEMINI_API_KEY_HERE
```

**Important:** After setting secrets, you MUST grant Cloud Functions access:

```bash
# Grant the Cloud Functions service account access to Secret Manager
firebase functions:secrets:access ELEVENLABS_API_KEY
firebase functions:secrets:access GEMINI_API_KEY
```

### 2.6 Deploy Functions

```bash
# Build and deploy
npm run build
firebase deploy --only functions

# You should see output like:
# ✔ functions[us-central1-processAudio] Successful create operation.
# ✔ functions[us-central1-generateText] Successful create operation.
```

### 2.7 Verify Deployment

```bash
# List deployed functions
firebase functions:list

# View function logs
firebase functions:log
```

---

## Part 3: iOS App Configuration

### 3.1 Install Firebase iOS SDK

Add Firebase to your Xcode project using Swift Package Manager:

1. In Xcode: **File** → **Add Package Dependencies**
2. Enter URL: `https://github.com/firebase/firebase-ios-sdk`
3. Select version: **10.20.0** or later
4. Add these packages:
   - `FirebaseAuth`
   - `FirebaseCore`
   - `FirebaseFunctions`
   - `FirebaseFirestore` (optional, for usage logs UI)

### 3.2 Add GoogleService-Info.plist

1. Download `GoogleService-Info.plist` from Firebase Console (if not done already)
2. Drag it into Xcode project (ensure it's in the **Signal** target)
3. Check "Copy items if needed"

### 3.3 Configure App Capabilities

In Xcode → **Signing & Capabilities**:

1. Add **Sign in with Apple** capability
2. Verify **Push Notifications** is enabled (for Firebase Cloud Messaging, optional)

### 3.4 Update Info.plist

Add the following to `Info.plist`:

```xml
<key>CFBundleURLTypes</key>
<array>
    <dict>
        <key>CFBundleURLSchemes</key>
        <array>
            <string>com.googleusercontent.apps.YOUR-REVERSED-CLIENT-ID</string>
        </array>
    </dict>
</array>
```

Replace `YOUR-REVERSED-CLIENT-ID` with the value from `GoogleService-Info.plist`.

### 3.5 Initialize Firebase in App

The `FirebaseService.swift` file has already been added to your project. It automatically initializes Firebase on first access.

---

## Part 4: Remove API Keys from Client

### 4.1 Delete Secrets.plist (IMPORTANT!)

```bash
# Remove the file containing API keys
rm /Users/leonhardmeingast/Documents/Projects/ComputerScienceIA/App/Signal/Signal/Secrets.plist

# Also remove it from git tracking
git rm Signal/Secrets.plist

# Add to .gitignore to prevent accidental commits
echo "Signal/Secrets.plist" >> .gitignore
```

### 4.2 Remove API Key Settings from Settings UI

Update `SettingsView.swift` to remove the API key input fields (they're no longer needed since keys are server-side).

### 4.3 Clear UserDefaults (Optional)

If users have API keys stored in UserDefaults from previous versions:

```swift
// Add this to a migration function or app startup
UserDefaults.standard.removeObject(forKey: "elevenLabsAPIKey")
UserDefaults.standard.removeObject(forKey: "geminiAPIKey")
```

---

## Part 5: Testing

### 5.1 Test Firebase Functions Locally (Optional)

```bash
cd firebase/functions

# Start Firebase emulators
npm run serve

# The Functions emulator will run at http://localhost:5001
```

To use the emulator in iOS:
```swift
// In FirebaseService.swift init(), uncomment:
#if DEBUG
functions.useEmulator(withHost: "localhost", port: 5001)
#endif
```

### 5.2 Test Authentication

1. Run the app in Xcode
2. Go to Settings → Sign in with Apple
3. Complete Sign in with Apple flow
4. Verify you see "Signed in as [Name]"

### 5.3 Test Transcription

1. Record a short audio clip
2. Transcribe it (should use Firebase Cloud Function)
3. Check Xcode console for:
   ```
   ☁️ [Firebase] Starting audio processing...
   ✅ [Firebase] Audio processing completed
   ```

### 5.4 Test Summarization

1. After transcribing, generate a summary
2. Check Xcode console for:
   ```
   ☁️ [Firebase] Starting text generation...
   ✅ [Firebase] Text generation completed
   ```

### 5.5 Verify Usage Logging

In Firebase Console → Firestore Database:

1. Check the `usage_logs` collection
2. You should see documents with:
   - `userId`: Firebase UID
   - `requestType`: "STT" or "Gemini"
   - `timestamp`: Server timestamp
   - `deviceModel`, `appVersion`, `iosVersion`
   - Cost metrics (audioSize, inputTokens, etc.)

---

## Part 6: Monitoring & Debugging

### 6.1 View Function Logs

```bash
# Real-time logs
firebase functions:log --only processAudio,generateText

# Logs from the last 1 hour
firebase functions:log --since 1h
```

### 6.2 Monitor Usage in Firebase Console

- **Functions Dashboard**: View invocations, execution time, errors
- **Firestore**: Query `usage_logs` collection for cost tracking
- **Authentication**: Monitor active users

### 6.3 Common Issues

**Issue: "unauthenticated" error**
- Solution: Ensure user is signed in with Apple before making API calls
- Check: `FirebaseService.shared.isAuthenticated` returns `true`

**Issue: "failed-precondition" error**
- Solution: API keys not set in Firebase secrets
- Run: `firebase functions:secrets:set ELEVENLABS_API_KEY` and `firebase functions:secrets:set GEMINI_API_KEY`

**Issue: Function timeout**
- Solution: Large audio files may exceed default timeout (60s)
- The `processAudio` function is already configured with 540s (9 min) timeout

**Issue: "permission-denied" in Firestore**
- Solution: Update Firestore security rules (see Part 1.2)

---

## Part 7: Cost Optimization

### 7.1 Monitor Costs

Track your costs in:
- [Firebase Console → Usage and Billing](https://console.firebase.google.com/project/_/usage)
- [Google Cloud Console → Billing](https://console.cloud.google.com/billing)

### 7.2 Set Budget Alerts

1. Go to Google Cloud Console → Billing
2. Create a budget alert (e.g., $50/month)
3. Set email notifications

### 7.3 Optimize Cloud Functions

The functions are already optimized with:
- **Regional deployment** (`us-central1`) - faster and cheaper
- **Right-sized memory** (256MiB for text, 512MiB for audio)
- **Appropriate timeouts** (120s for text, 540s for audio)
- **Max instances limit** (10) - prevents runaway costs

---

## Security Best Practices

✅ **API Keys are server-side only** - Never exposed to client
✅ **Firebase Auth verification** - All requests require valid user token
✅ **Firestore security rules** - Users can only read their own usage logs
✅ **Environment secrets** - API keys stored in Firebase Secret Manager
✅ **HTTPS only** - All Cloud Functions use HTTPS with TLS
✅ **Nonce verification** - Apple Sign-In uses SHA256 nonce for security

---

## Rollback Plan

If you need to rollback to the old implementation:

1. Restore `Secrets.plist` from git history
2. Revert changes to `TranscriptionService.swift` and `SummarizationService.swift`
3. Comment out Firebase initialization in `FirebaseService.swift`

---

## Support

- **Firebase Documentation**: https://firebase.google.com/docs
- **Cloud Functions**: https://firebase.google.com/docs/functions
- **Firebase Auth**: https://firebase.google.com/docs/auth
- **Firestore**: https://firebase.google.com/docs/firestore

---

## Next Steps

1. ✅ Deploy Cloud Functions
2. ✅ Set API key secrets
3. ✅ Delete `Secrets.plist`
4. ✅ Test authentication flow
5. ✅ Test transcription and summarization
6. ✅ Monitor usage logs in Firestore
7. 🚀 Deploy to TestFlight/App Store

Your app is now secure with backend API proxying! 🎉
