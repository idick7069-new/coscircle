export function agePublicUpdate(value) {
  if (value === undefined) return null; // Old clients must preserve the saved choice.
  if (typeof value !== 'boolean') {
    const error = new Error('invalid_age_public');
    error.status = 400;
    error.code = 'invalid_age_public';
    throw error;
  }
  return value ? 1 : 0;
}

export function publicProfileAge(profile) {
  const agePublic = profile.agePublic == null || profile.agePublic === true || profile.agePublic === 1;
  return {...profile, agePublic, age: agePublic ? profile.age : ''};
}
