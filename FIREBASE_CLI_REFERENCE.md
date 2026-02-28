# Firebase CLI Quick Reference

## Essential Commands for Setup & Deployment

### 1. Initial Setup

```bash
# Install Firebase CLI globally
npm install -g firebase-tools

# Login to Firebase
firebase login

# Initialize Firebase in your project
cd /Users/leonhardmeingast/Documents/Projects/ComputerScienceIA/App/Signal/firebase
firebase init functions
# Select: TypeScript, ESLint, Install dependencies
```

### 2. Set API Key Secrets

**CRITICAL: These commands must be run before deploying functions**

```bash
# Navigate to firebase directory
cd /Users/leonhardmeingast/Documents/Projects/ComputerScienceIA/App/Signal/firebase

# Set ElevenLabs API key (paste when prompted)
firebase functions:secrets:set ELEVENLABS_API_KEY
# Enter your ElevenLabs API key when prompted

# Set Gemini API key (paste when prompted)
firebase functions:secrets:set GEMINI_API_KEY
# Enter your Gemini API key when prompted

# Grant access to secrets (MUST DO THIS!)
firebase functions:secrets:access ELEVENLABS_API_KEY
firebase functions:secrets:access GEMINI_API_KEY
```

### 3. Install Dependencies

```bash
cd functions
npm install
```

### 4. Deploy Cloud Functions

```bash
# Build TypeScript
npm run build

# Deploy to Firebase
firebase deploy --only functions

# Expected output:
# ✔ functions[us-central1-processAudio] Successful create operation.
# ✔ functions[us-central1-generateText] Successful create operation.
```

### 5. Verify Deployment

```bash
# List all deployed functions
firebase functions:list

# View real-time logs
firebase functions:log

# View logs for specific function
firebase functions:log --only processAudio
```

### 6. Monitor & Debug

```bash
# Watch logs in real-time
firebase functions:log --follow

# View logs from last hour
firebase functions:log --since 1h

# View logs with specific severity
firebase functions:log --severity error
```

### 7. Update Functions

```bash
# After making code changes
cd functions
npm run build
firebase deploy --only functions

# Deploy specific function only
firebase deploy --only functions:processAudio
```

### 8. Manage Secrets

```bash
# List all secrets
firebase functions:secrets:list

# Update a secret
firebase functions:secrets:set ELEVENLABS_API_KEY
# (Enter new value when prompted)

# Delete a secret
firebase functions:secrets:destroy ELEVENLABS_API_KEY
```

### 9. Local Testing (Optional)

```bash
# Start Firebase emulators
cd functions
npm run serve

# Emulators run at:
# - Functions: http://localhost:5001
# - Firestore: http://localhost:8080
```

### 10. Troubleshooting

```bash
# Check Firebase project info
firebase projects:list
firebase use

# Switch to different project
firebase use <project-id>

# Clear Firebase cache
firebase logout
firebase login

# Re-deploy with force flag
firebase deploy --only functions --force
```

---

## Important Notes

1. **Always deploy from the `firebase` directory**, not the root project directory
2. **Secrets must be set BEFORE deploying** functions that use them
3. **Grant secret access** with `firebase functions:secrets:access` after setting secrets
4. **Upgrade to Blaze plan** (Pay-as-you-go) - required for external API calls
5. **Monitor costs** in Firebase Console → Usage and Billing

---

## One-Time Setup Checklist

- [ ] Install Firebase CLI: `npm install -g firebase-tools`
- [ ] Login: `firebase login`
- [ ] Initialize: `firebase init functions`
- [ ] Install dependencies: `cd functions && npm install`
- [ ] Set ElevenLabs secret: `firebase functions:secrets:set ELEVENLABS_API_KEY`
- [ ] Set Gemini secret: `firebase functions:secrets:set GEMINI_API_KEY`
- [ ] Grant secret access: `firebase functions:secrets:access ELEVENLABS_API_KEY`
- [ ] Grant secret access: `firebase functions:secrets:access GEMINI_API_KEY`
- [ ] Build: `npm run build`
- [ ] Deploy: `firebase deploy --only functions`
- [ ] Verify: `firebase functions:list`
- [ ] Test in iOS app

---

## Regular Deployment Workflow

```bash
# 1. Navigate to functions directory
cd /Users/leonhardmeingast/Documents/Projects/ComputerScienceIA/App/Signal/firebase/functions

# 2. Make code changes in src/index.ts

# 3. Build TypeScript
npm run build

# 4. Deploy to Firebase
cd ..
firebase deploy --only functions

# 5. Monitor logs
firebase functions:log --follow
```

---

## Cost Monitoring

```bash
# View function invocation stats
firebase functions:list

# Check quotas and usage
# Go to: https://console.firebase.google.com/project/_/usage

# Set budget alerts in Google Cloud Console
# Go to: https://console.cloud.google.com/billing
```

---

## Emergency Rollback

```bash
# Delete specific function
firebase functions:delete processAudio
firebase functions:delete generateText

# Redeploy previous version
git checkout HEAD~1 firebase/functions/src/index.ts
cd firebase/functions
npm run build
cd ..
firebase deploy --only functions
```

---

## Support Resources

- Firebase CLI Docs: https://firebase.google.com/docs/cli
- Cloud Functions Docs: https://firebase.google.com/docs/functions
- Secret Manager: https://firebase.google.com/docs/functions/config-env
