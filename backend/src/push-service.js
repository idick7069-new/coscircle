import { applicationDefault, cert, initializeApp } from 'firebase-admin/app';
import { getMessaging } from 'firebase-admin/messaging';

let firebaseApp;
let firebaseInitAttempted = false;

function getFirebaseApp() {
  if (firebaseApp) return firebaseApp;
  if (firebaseInitAttempted) return null;
  firebaseInitAttempted = true;

  try {
    const serviceAccountJson = process.env.FIREBASE_SERVICE_ACCOUNT_JSON;
    const credential = serviceAccountJson
      ? cert(JSON.parse(serviceAccountJson))
      : applicationDefault();
    firebaseApp = initializeApp({
      credential,
      projectId: process.env.FIREBASE_PROJECT_ID || 'coscircle',
    });
    return firebaseApp;
  } catch (error) {
    console.warn('[push] Firebase Admin is not configured', {
      message: error?.message,
    });
    return null;
  }
}

export async function sendRecognitionPush({ tokens, requestId, eventId, requesterName }) {
  const app = getFirebaseApp();
  const activeTokens = [...new Set(tokens.map((token) => String(token).trim()))].filter(
    Boolean,
  );
  if (!app || activeTokens.length === 0) {
    return { successCount: 0, failureCount: activeTokens.length, invalidTokens: [] };
  }

  const messages = activeTokens.map((token) => ({
    token,
    notification: {
      title: '有人想認親',
      body: `${requesterName || '有同好'} 想在現場找你認親`,
    },
    data: {
      type: 'recognition_request',
      requestId: String(requestId),
      eventId: String(eventId),
    },
    android: {
      priority: 'high',
      notification: {
        channelId: 'recognition_requests',
        priority: 'high',
      },
    },
  }));

  const response = await getMessaging(app).sendEach(messages);
  const invalidTokens = response.responses
    .map((item, index) => {
      const code = item.error?.code;
      return code === 'messaging/registration-token-not-registered' ||
        code === 'messaging/invalid-registration-token'
        ? activeTokens[index]
        : null;
    })
    .filter(Boolean);

  return {
    successCount: response.successCount,
    failureCount: response.failureCount,
    invalidTokens,
  };
}
