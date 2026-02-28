import {setGlobalOptions} from "firebase-functions";
import * as functions from "firebase-functions/v2";
import * as admin from "firebase-admin";

// Initialize Firebase Admin
admin.initializeApp();
const db = admin.firestore();

// Global options for cost control
setGlobalOptions({maxInstances: 10});

// MARK: - Types

interface ProcessAudioRequest {
  audioBase64: string;
  fileName: string;
  diarize: boolean;
  deviceModel: string;
  appVersion: string;
  iosVersion: string;
}

interface ProcessAudioResponse {
  language_code?: string;
  language_probability?: number;
  text: string;
  words?: Array<{
    text: string;
    start: number;
    end: number;
    type: string;
    speaker_id?: string;
  }>;
}

interface GenerateTextRequest {
  prompt: string;
  temperature: number;
  maxOutputTokens: number;
  responseMimeType: string;
  deviceModel: string;
  appVersion: string;
  iosVersion: string;
}

interface GenerateTextResponse {
  candidates?: Array<{
    content?: {
      parts?: Array<{
        text?: string;
      }>;
    };
  }>;
}

// MARK: - Helper Functions

/**
 * Verify Firebase Auth token and return user ID
 * @param {functions.https.CallableRequest} context - Request context
 * @return {Promise<string>} User ID
 */
async function verifyAuth(
  context: functions.https.CallableRequest
): Promise<string> {
  if (!context.auth) {
    throw new functions.https.HttpsError(
      "unauthenticated",
      "User must be authenticated to call this function"
    );
  }
  return context.auth.uid;
}

/**
 * Log usage to Firestore
 * @param {string} userId - User ID
 * @param {string} requestType - Type of request (STT or Gemini)
 * @param {object} metadata - Usage metadata
 */
async function logUsage(
  userId: string,
  requestType: "STT" | "Gemini",
  metadata: {
    audioSize?: number;
    audioDuration?: number;
    inputTokens?: number;
    outputTokens?: number;
    deviceModel: string;
    appVersion: string;
    iosVersion: string;
  }
): Promise<void> {
  await db.collection("usage_logs").add({
    userId,
    requestType,
    timestamp: admin.firestore.FieldValue.serverTimestamp(),
    ...metadata,
  });
}

/**
 * Estimate audio duration from base64 size
 * @param {string} base64String - Base64 encoded audio
 * @return {number} Estimated duration in seconds
 */
function estimateAudioDuration(base64String: string): number {
  const sizeInBytes = (base64String.length * 3) / 4;
  const sizeInKB = sizeInBytes / 1024;
  // Rough estimate: 1 minute of M4A ≈ 1MB at 128kbps
  const estimatedMinutes = sizeInKB / 1024;
  return estimatedMinutes * 60; // Convert to seconds
}

/**
 * Estimate token count from text
 * @param {string} text - Text to estimate tokens for
 * @return {number} Estimated token count
 */
function estimateTokens(text: string): number {
  return Math.ceil(text.length / 4);
}

// MARK: - Cloud Functions

/**
 * Process audio file using ElevenLabs Scribe API
 * Securely proxies requests and logs usage
 */
export const processAudio = functions.https.onCall(
  {
    region: "us-central1",
    maxInstances: 10,
    timeoutSeconds: 540, // 9 minutes for large audio files
    memory: "512MiB",
  },
  async (request): Promise<ProcessAudioResponse> => {
    // Verify authentication
    const userId = await verifyAuth(request);

    // Validate request data
    const data = request.data as ProcessAudioRequest;
    if (!data.audioBase64 || !data.fileName) {
      throw new functions.https.HttpsError(
        "invalid-argument",
        "Missing required fields: audioBase64, fileName"
      );
    }

    // Get ElevenLabs API key from environment secrets
    const elevenLabsApiKey = process.env.ELEVENLABS_API_KEY;
    if (!elevenLabsApiKey) {
      throw new functions.https.HttpsError(
        "failed-precondition",
        "ElevenLabs API key not configured"
      );
    }

    try {
      // Convert base64 to buffer
      const audioBuffer = Buffer.from(data.audioBase64, "base64");

      // Build multipart form data
      const boundary = `----Boundary${Date.now()}`;
      const formData: Buffer[] = [];

      // Add form fields
      const addField = (name: string, value: string) => {
        formData.push(Buffer.from(`--${boundary}\r\n`));
        formData.push(
          Buffer.from(`Content-Disposition: form-data; name="${name}"\r\n\r\n`)
        );
        formData.push(Buffer.from(`${value}\r\n`));
      };

      addField("model_id", "scribe_v2");
      addField("diarize", data.diarize ? "true" : "false");
      addField("timestamps_granularity", "word");
      addField("tag_audio_events", "false");

      // Add audio file
      formData.push(Buffer.from(`--${boundary}\r\n`));
      formData.push(
        Buffer.from(
          "Content-Disposition: form-data; name=\"file\"; " +
          `filename="${data.fileName}"\r\n`
        )
      );
      formData.push(Buffer.from("Content-Type: audio/mp4\r\n\r\n"));
      formData.push(audioBuffer);
      formData.push(Buffer.from(`\r\n--${boundary}--\r\n`));

      const body = Buffer.concat(formData);

      // Call ElevenLabs API
      const response = await fetch(
        "https://api.elevenlabs.io/v1/speech-to-text",
        {
          method: "POST",
          headers: {
            "xi-api-key": elevenLabsApiKey,
            "Content-Type": `multipart/form-data; boundary=${boundary}`,
          },
          body,
        }
      );

      if (!response.ok) {
        const errorText = await response.text();
        throw new Error(
          `ElevenLabs API error (${response.status}): ${errorText}`
        );
      }

      const result = (await response.json()) as ProcessAudioResponse;

      // Log usage to Firestore
      const estimatedDuration = estimateAudioDuration(data.audioBase64);
      await logUsage(userId, "STT", {
        audioSize: audioBuffer.length,
        audioDuration: estimatedDuration,
        deviceModel: data.deviceModel,
        appVersion: data.appVersion,
        iosVersion: data.iosVersion,
      });

      return result;
    } catch (error) {
      console.error("Error processing audio:", error);
      throw new functions.https.HttpsError(
        "internal",
        error instanceof Error ? error.message : "Unknown error occurred"
      );
    }
  }
);

/**
 * Generate text using Google Gemini API
 * Securely proxies requests and logs usage
 */
export const generateText = functions.https.onCall(
  {
    region: "us-central1",
    maxInstances: 10,
    timeoutSeconds: 120,
    memory: "256MiB",
  },
  async (request): Promise<GenerateTextResponse> => {
    // Verify authentication
    const userId = await verifyAuth(request);

    // Validate request data
    const data = request.data as GenerateTextRequest;
    if (!data.prompt) {
      throw new functions.https.HttpsError(
        "invalid-argument",
        "Missing required field: prompt"
      );
    }

    // Get Gemini API key from environment secrets
    const geminiApiKey = process.env.GEMINI_API_KEY;
    if (!geminiApiKey) {
      throw new functions.https.HttpsError(
        "failed-precondition",
        "Gemini API key not configured"
      );
    }

    try {
      // Build request payload
      const requestBody = {
        contents: [
          {
            parts: [
              {
                text: data.prompt,
              },
            ],
          },
        ],
        generationConfig: {
          temperature: data.temperature || 0.3,
          maxOutputTokens: data.maxOutputTokens || 2048,
          responseMimeType: data.responseMimeType || "application/json",
        },
      };

      // Call Gemini API
      const response = await fetch(
        "https://generativelanguage.googleapis.com/v1beta/models/" +
        `gemini-2.5-flash-lite:generateContent?key=${geminiApiKey}`,
        {
          method: "POST",
          headers: {
            "Content-Type": "application/json",
          },
          body: JSON.stringify(requestBody),
        }
      );

      if (!response.ok) {
        const errorText = await response.text();
        throw new Error(`Gemini API error (${response.status}): ${errorText}`);
      }

      const result = (await response.json()) as GenerateTextResponse;

      // Estimate token usage
      const inputTokens = estimateTokens(data.prompt);
      const outputText =
        result.candidates?.[0]?.content?.parts?.[0]?.text || "";
      const outputTokens = estimateTokens(outputText);

      // Log usage to Firestore
      await logUsage(userId, "Gemini", {
        inputTokens,
        outputTokens,
        deviceModel: data.deviceModel,
        appVersion: data.appVersion,
        iosVersion: data.iosVersion,
      });

      return result;
    } catch (error) {
      console.error("Error generating text:", error);
      throw new functions.https.HttpsError(
        "internal",
        error instanceof Error ? error.message : "Unknown error occurred"
      );
    }
  }
);
