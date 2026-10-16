function fail(code, status = 401) {
  throw Object.assign(new Error(code), {code, status});
}

export async function fetchLineProfile(accessToken, {
  channelId = process.env.LINE_LOGIN_CHANNEL_ID,
  fetcher = fetch,
} = {}) {
  if (!channelId || !/^\d+$/.test(channelId)) fail('line_login_not_configured', 503);
  if (typeof accessToken !== 'string' || accessToken.length < 12 || accessToken.length > 4096) {
    fail('invalid_social_token');
  }
  const request = async (url, options) => {
    try { return await fetcher(url, options); }
    catch { fail('line_login_unavailable', 503); }
  };
  const readJson = async (response) => {
    try { return await response.json(); }
    catch { fail('line_login_unavailable', 503); }
  };
  const verification = new URL('https://api.line.me/oauth2/v2.1/verify');
  verification.searchParams.set('access_token', accessToken);
  const verified = await request(verification, {signal: AbortSignal.timeout(4000)});
  if (!verified.ok) fail(verified.status >= 500 || verified.status === 429
    ? 'line_login_unavailable' : 'invalid_social_token', verified.status >= 500 || verified.status === 429 ? 503 : 401);
  const token = await readJson(verified);
  if (String(token.client_id) !== channelId || !Number.isFinite(token.expires_in) || token.expires_in <= 0 ||
      !String(token.scope ?? '').split(' ').includes('profile')) fail('invalid_social_token');
  const response = await request('https://api.line.me/v2/profile', {
    headers: {Authorization: `Bearer ${accessToken}`}, signal: AbortSignal.timeout(4000),
  });
  if (!response.ok) fail(response.status >= 500 || response.status === 429
    ? 'line_login_unavailable' : 'invalid_social_token', response.status >= 500 || response.status === 429 ? 503 : 401);
  const profile = await readJson(response);
  if (typeof profile.userId !== 'string' || !profile.userId) fail('invalid_social_token');
  return {id: profile.userId, email: null,
    nickname: String(profile.displayName || 'LINE 使用者').slice(0, 80),
    avatarUrl: typeof profile.pictureUrl === 'string' && profile.pictureUrl.startsWith('https://') ? profile.pictureUrl : ''};
}
