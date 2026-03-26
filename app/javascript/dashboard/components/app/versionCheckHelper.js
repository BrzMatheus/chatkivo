import semver from 'semver';

const UPDATE_NOTIFICATIONS_ENABLED = false;

export const hasAnUpdateAvailable = (latestVersion, currentVersion) => {
  if (!UPDATE_NOTIFICATIONS_ENABLED) {
    return false;
  }

  if (!semver.valid(latestVersion)) {
    return false;
  }

  return semver.lt(currentVersion, latestVersion);
};
