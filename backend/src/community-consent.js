import {requireLegalAcceptance} from './legal-consent.js';

const contentMutations = [
  ['PUT', /^\/api\/me$/],
  ['POST', /^\/api\/uploads\/image$/],
  ['POST', /^\/api\/works$/],
  ['POST', /^\/api\/circles$/],
  ['PUT', /^\/api\/circles\/[^/]+$/],
  ['POST', /^\/api\/friend-invites\/[^/]+$/],
  ['POST', /^\/api\/events\/submissions$/],
  ['POST', /^\/api\/events\/[^/]+\/bookings$/],
  ['POST', /^\/api\/events\/[^/]+\/meetups$/],
  ['PUT', /^\/api\/events\/[^/]+\/meetups\/[^/]+$/],
  ['PUT', /^\/api\/events\/[^/]+\/location(?:\/coordinates)?$/],
  ['POST', /^\/api\/recognitions\/[^/]+\/respond$/],
];

export function requiresCommunityConsent(method, path) {
  const normalized = path.toLowerCase().replace(/\/+$/, '') || '/';
  return contentMutations.some(([verb, pattern]) => method === verb && pattern.test(normalized));
}

export function communityConsentGuard(service) {
  const requireConsent = requireLegalAcceptance(service);
  return (req, res, next) => requiresCommunityConsent(req.method, req.path)
    ? requireConsent(req, res, next) : next();
}
