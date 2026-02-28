# Next Steps - Required Actions

## ⚠️ Build Error: Firebase SDK Not Installed

The code is ready, but the Firebase iOS SDK needs to be added to your Xcode project.

---

## Step 1: Add Firebase iOS SDK via Swift Package Manager (5 minutes)

### In Xcode:

1. **File** → **Add Package Dependencies...**

2. **Enter URL:** `https://github.com/firebase/firebase-ios-sdk`

3. **Dependency Rule:** Select "Up to Next Major Version" with version **10.20.0** or later

4. **Add to Target:** Select **Signal** (your main app target)

5. **Select Products to Add:**
   - ✅ **FirebaseAuth** (required)
   - ✅ **FirebaseCore** (required)
   - ✅ **FirebaseFunctions** (required)
   - ⬜ FirebaseFirestore (optional - for reading usage logs in-app)
   - ⬜ FirebaseAnalytics (optional)

6. Click **Add Package**

7. Wait for Xcode to download and integrate the packages (~2-3 minutes)

---

## Step 2: Download GoogleService-Info.plist from Firebase Console (3 minutes)

### In Firebase Console:

1. Go to [Firebase Console](https://console.firebase.google.com)

2. Select your project (or create a new one)

3. Click the **⚙️ gear icon** → **Project Settings**

4. Scroll down to **Your apps** section

5. Click **iOS** (or **Add app** if you haven't registered the iOS app yet)

6. **Register app:**
   - **Bundle ID:** `com.Proceduralabs.Signal` (from your Xcode project)
   - **App nickname:** Signal (or Trace)
   - **App Store ID:** (optional, skip for now)
   - Click **Register app**

7. **Download `GoogleService-Info.plist`:**
   - Click **Download GoogleService-Info.plist**
   - Save to your computer

8. **Add to Xcode:**
   - Drag `GoogleService-Info.plist` into Xcode (in the Signal folder)
   - ✅ Check "Copy items if needed"
   - ✅ Check target: **Signal**
   - Click **Finish**

---

## Step 3: Enable Sign in with Apple in Firebase Console (5 minutes)

### In Firebase Console:

1. Go to **Authentication** → **Sign-in method**

2. Click **Apple** sign-in provider

3. Click **Enable**

4. **Configure Apple Sign-In:**
   - **Service ID:** (get from Apple Developer Console)
   - **Team ID:** (get from Apple Developer Console - 10-character ID)
   - **Key ID:** (get from Apple Developer Console)
   - **Private Key:** (upload `.p8` file from Apple Developer Console)

   **OR** for simpler setup (no server configuration):
   - Just enable it with default settings
   - Apple Sign-In will work for basic authentication

5. Click **Save**

---

## Step 4: Enable Firestore Database (3 minutes)

### In Firebase Console:

1. Go to **Firestore Database**

2. Click **Create database**

3. **Start mode:** Select **Production mode**

4. **Location:** Select **us-central (Iowa)** (same region as Cloud Functions)

5. Click **Enable**

6. **Set Security Rules:**
   - Go to **Rules** tab
   - Replace with:

   ```javascript
   rules_version = '2';
   service cloud.firestore {
     match /databases/{database}/documents {
       match /usage_logs/{document} {
         allow read: if request.auth != null && request.auth.uid == resource.data.userId;
         allow write: if false; // Only Cloud Functions can write
       }
     }
   }
   ```

7. Click **Publish**

---

## Step 5: Upgrade to Blaze Plan (Required for Cloud Functions)

### In Firebase Console:

1. Click **Upgrade** button (top of dashboard)

2. Select **Blaze (Pay as you go)** plan

3. **Why required:** Cloud Functions need to make outbound API calls to ElevenLabs and Gemini

4. **Set budget alerts:**
   - Go to Google Cloud Console → Billing
   - Create budget: $50/month
   - Set alerts at 50%, 90%, 100%

5. **Don't worry about costs:**
   - First 2M function invocations are FREE
   - You'll only pay for ElevenLabs/Gemini API usage (same as before)
   - Firebase overhead is minimal (~$1-2/month for moderate usage)

---

## Step 6: Deploy Firebase Cloud Functions (10 minutes)

### In Terminal:

```bash
# 1. Install Firebase CLI (if not already installed)
npm install -g firebase-tools

# 2. Login to Firebase
firebase login

# 3. Navigate to firebase directory
cd /Users/leonhardmeingast/Documents/Projects/ComputerScienceIA/App/Signal/firebase

# 4. Initialize Firebase (select your project when prompted)
firebase init functions
# Select: TypeScript, Yes to ESLint, Yes to install dependencies

# 5. Install dependencies
cd functions
npm install

# 6. Set API key secrets (CRITICAL!)
cd ..
firebase functions:secrets:set ELEVENLABS_API_KEY
# Paste: YOUR_ELEVENLABS_API_KEY_HERE

firebase functions:secrets:set GEMINI_API_KEY
# Paste: YOUR_GEMINI_API_KEY_HERE

# 7. Grant secret access (MUST DO!)
firebase functions:secrets:access ELEVENLABS_API_KEY
firebase functions:secrets:access GEMINI_API_KEY

# 8. Build and deploy
cd functions
npm run build
cd ..
firebase deploy --only functions

# 9. Verify deployment
firebase functions:list
# You should see:
# - processAudio (us-central1)
# - generateText (us-central1)
```

---

## Step 7: Delete Secrets.plist (CRITICAL SECURITY STEP!)

```bash
# Navigate to project root
cd /Users/leonhardmeingast/Documents/Projects/ComputerScienceIA/App/Signal

# Delete the file
rm Signal/Secrets.plist

# Remove from git tracking
git rm Signal/Secrets.plist

# Add to .gitignore
echo "Signal/Secrets.plist" >> .gitignore

# Commit the security fix
git add .
git commit -m "Security: Remove API keys from client, migrate to Firebase backend proxy"
```

---

## Step 8: Build & Test in Xcode (10 minutes)

### In Xcode:

1. **Clean Build Folder:**
   - Product → Clean Build Folder (Shift + Cmd + K)

2. **Build the project:**
   - Product → Build (Cmd + B)
   - Should build successfully now (no errors)

3. **Run the app:**
   - Select a simulator or device
   - Click Run (Cmd + R)

4. **Test Sign-In:**
   - Go to Settings
   - Tap "Sign in with Apple"
   - Complete Apple Sign-In flow
   - You should see "Signed in as [Your Name]"

5. **Test Transcription:**
   - Record a short audio clip (10-15 seconds)
   - Transcribe it
   - Check Xcode console for:
     ```
     ☁️ [Firebase] Starting audio processing...
     ✅ [Firebase] Audio processing completed
     ```

6. **Test Summarization:**
   - Generate summary for the transcription
   - Check Xcode console for:
     ```
     ☁️ [Firebase] Starting text generation...
     ✅ [Firebase] Text generation completed
     ```

7. **Verify Usage Logging:**
   - Go to Firebase Console → Firestore Database
   - Check `usage_logs` collection
   - You should see documents with:
     - userId
     - requestType ("STT" or "Gemini")
     - timestamp
     - deviceModel, appVersion, iosVersion

---

## Step 9: Optional - Update Settings UI

Currently, SettingsView.swift still shows API key input fields. Since keys are now server-side, you can:

**Option A:** Remove the API key settings entirely (recommended)

**Option B:** Keep them but show "Using secure backend proxy" instead

**Option C:** Show sign-in status and usage statistics from Firestore

---

## Step 10: Final Security Verification

```bash
# Verify API keys are NOT in the app binary
cd /Users/leonhardmeingast/Documents/Projects/ComputerScienceIA/App/Signal

# Build the app for release
xcodebuild -scheme Signal -configuration Release -archivePath build/Signal.xcarchive archive

# Check if API keys are in binary (should return NOTHING)
strings build/Signal.xcarchive/Products/Applications/Signal.app/Signal | grep -i "YOUR_ELEVENLABS_API_KEY_HERE"
strings build/Signal.xcarchive/Products/Applications/Signal.app/Signal | grep -i "YOUR_GEMINI_API_KEY_HERE"

# If no output = SUCCESS! Keys are not in the app.
```

---

## Troubleshooting

### Issue: "Unable to find module dependency: 'FirebaseCore'"
**Solution:** Add Firebase SDK via Swift Package Manager (see Step 1)

### Issue: "GoogleService-Info.plist not found"
**Solution:** Download from Firebase Console and add to Xcode (see Step 2)

### Issue: "User must be authenticated to call this function"
**Solution:** User needs to sign in with Apple before using transcription/summarization

### Issue: "ElevenLabs API key not configured"
**Solution:** Set secrets in Firebase (see Step 6, commands 6-7)

### Issue: Build succeeds but app crashes on launch
**Solution:** Verify `GoogleService-Info.plist` is added to the **Signal** target (not just the project)

---

## Completion Checklist

- [ ] Firebase iOS SDK added via Swift Package Manager
- [ ] GoogleService-Info.plist downloaded and added to Xcode
- [ ] Apple Sign-In enabled in Firebase Console
- [ ] Firestore database created with security rules
- [ ] Upgraded to Blaze plan
- [ ] Firebase CLI installed and logged in
- [ ] Firebase Functions initialized
- [ ] API key secrets set (ELEVENLABS_API_KEY, GEMINI_API_KEY)
- [ ] Secret access granted
- [ ] Cloud Functions deployed successfully
- [ ] Secrets.plist deleted from project
- [ ] App builds without errors
- [ ] User can sign in with Apple
- [ ] Transcription works via Firebase
- [ ] Summarization works via Firebase
- [ ] Usage logs appear in Firestore
- [ ] API keys verified NOT in app binary

---

## Estimated Total Time: 45-60 minutes

Most of this is waiting for downloads and deployments. The actual hands-on work is about 20-30 minutes.

---

## When You're Done

You'll have:
- ✅ Secure, production-ready backend architecture
- ✅ API keys safely stored server-side
- ✅ User authentication required for all AI features
- ✅ Automatic usage tracking and cost monitoring
- ✅ Scalable infrastructure that can handle thousands of users
- ✅ Peace of mind that your API keys cannot be extracted from the app

**Ready to deploy to the App Store!** 🚀
