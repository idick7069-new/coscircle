ALTER TABLE users ADD COLUMN onboarding_completed BOOLEAN NOT NULL DEFAULT FALSE;
UPDATE users SET onboarding_completed = TRUE
 WHERE profile_roles_json IS NOT NULL AND profile_roles_json <> '[]' AND nickname <> '';
