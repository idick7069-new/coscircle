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

export async function sendRecognitionPush({ tokens, requestId, eventId, dayIndex, requesterName }) {
  return sendEventPush({
    tokens,
    notification: {title: '有人想認親', body: `${requesterName || '有同好'} 想在現場找你認親`},
    data: {type: 'recognition_request', requestId, eventId, dayIndex},
  });
}

export async function sendRecognitionReplyPush({tokens, requestId, eventId, dayIndex, responderName, status}) {
  return sendEventPush({
    tokens,
    notification: {title: '認親有回覆', body: `${responderName || '同好'}：${status === 'accepted' ? '快來' : '當前不方便'}`},
    data: {type: 'recognition_response', requestId, eventId, dayIndex, status},
  });
}

export async function sendMeetupPush({tokens, meetupId, eventId, dayIndex, creatorName}) {
  return sendEventPush({
    tokens,
    notification: {title: '新的集合', body: `${creatorName || '小圈圈同好'} 建立了集合地點`},
    data: {type: 'meetup_created', meetupId, eventId, dayIndex},
  });
}

async function sendEventPush({tokens, notification, data}) {
  const app = getFirebaseApp();
  const activeTokens = [...new Set(tokens.map((token) => String(token).trim()))].filter(
    Boolean,
  );
  if (!app || activeTokens.length === 0) {
    return { successCount: 0, failureCount: activeTokens.length, invalidTokens: [] };
  }

  const messages = activeTokens.map((token) => ({
    token,
    notification,
    data: Object.fromEntries(Object.entries(data).map(([key, value]) => [key, String(value)])),
    android: {
      priority: 'high',
      notification: {
        channelId: 'recognition_requests',
        priority: 'high',
      },
    },
  }));

  return sendPushBatches(messages, getMessaging(app));
}

export async function sendPushBatches(messages, messaging) {
  const result = {successCount: 0, failureCount: 0, invalidTokens: []};
  for (let offset = 0; offset < messages.length; offset += 500) {
    const batch = messages.slice(offset, offset + 500);
    try {
      const response = await messaging.sendEach(batch);
      result.successCount += response.successCount;
      result.failureCount += response.failureCount;
      response.responses.forEach((item, index) => {
        if (['messaging/registration-token-not-registered', 'messaging/invalid-registration-token']
          .includes(item.error?.code)) {
          result.invalidTokens.push(batch[index].token);
        }
      });
    } catch {
      result.failureCount += batch.length;
    }
  }
  return result;
}
