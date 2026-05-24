export const DASHBOARD_APPEARANCE_SETTING_KEYS = {
  PRIMARY_COLOR: 'dashboard_primary_color',
  BACKGROUND_COLOR_LIGHT: 'dashboard_background_color_light',
  BACKGROUND_COLOR_DARK: 'dashboard_background_color_dark',
  AGENT_MESSAGE_BUBBLE_COLOR: 'dashboard_agent_message_bubble_color',
};

export const DEFAULT_DASHBOARD_APPEARANCE = {
  [DASHBOARD_APPEARANCE_SETTING_KEYS.PRIMARY_COLOR]: '#2781F6',
  [DASHBOARD_APPEARANCE_SETTING_KEYS.BACKGROUND_COLOR_LIGHT]: '#F7F7F7',
  [DASHBOARD_APPEARANCE_SETTING_KEYS.BACKGROUND_COLOR_DARK]: '#1C1D20',
  [DASHBOARD_APPEARANCE_SETTING_KEYS.AGENT_MESSAGE_BUBBLE_COLOR]: '#0F3966',
};

const HEX_COLOR_REGEX = /^#(?:[0-9a-f]{3}|[0-9a-f]{6})$/i;

const normalizeHexColor = color => {
  const value = color?.toString().trim();
  if (!value || !HEX_COLOR_REGEX.test(value)) return '';

  if (value.length === 4) {
    return `#${value[1]}${value[1]}${value[2]}${value[2]}${value[3]}${value[3]}`.toUpperCase();
  }

  return value.toUpperCase();
};

const hexToRgbTriplet = hexColor => {
  const normalizedColor = normalizeHexColor(hexColor);
  if (!normalizedColor) return '';

  const value = normalizedColor.slice(1);
  return [0, 2, 4]
    .map(start => parseInt(value.slice(start, start + 2), 16))
    .join(' ');
};

const hexToRgbChannels = hexColor =>
  hexToRgbTriplet(hexColor)
    .split(' ')
    .filter(Boolean)
    .map(channel => Number(channel));

const mixRgbChannel = (channel, targetChannel, colorWeight) =>
  Math.round(channel * colorWeight + targetChannel * (1 - colorWeight));

const mixRgbTriplet = (rgbChannels, targetChannel, colorWeight) => {
  return rgbChannels
    .map(channel => mixRgbChannel(channel, targetChannel, colorWeight))
    .join(' ');
};

const LIGHT_PRIMARY_TONE_CONFIG = {
  '--blue-3': [255, 0.08],
  '--blue-4': [255, 0.15],
  '--blue-5': [255, 0.22],
  '--blue-6': [255, 0.3],
  '--blue-7': [255, 0.42],
  '--blue-8': [255, 0.6],
  '--blue-9': [255, 1],
  '--blue-10': [0, 0.92],
  '--blue-11': [0, 0.85],
  '--text-blue': [0, 0.85],
  '--solid-blue': [255, 0.15],
  '--border-blue-strong': [0, 0.55],
};

const DARK_PRIMARY_TONE_CONFIG = {
  '--blue-3': [0, 0.25],
  '--blue-4': [0, 0.35],
  '--blue-5': [0, 0.42],
  '--blue-6': [0, 0.5],
  '--blue-7': [0, 0.58],
  '--blue-8': [0, 0.7],
  '--blue-9': [0, 1],
  '--blue-10': [255, 0.9],
  '--blue-11': [255, 0.55],
  '--text-blue': [255, 0.55],
  '--solid-blue': [0, 0.4],
  '--border-blue-strong': [255, 0.75],
};

const themedPrimaryVariableNames = [
  '--brand-color',
  '--border-blue',
  ...Object.keys(LIGHT_PRIMARY_TONE_CONFIG),
];

const getThemedPrimaryColors = (rgbChannels, isDarkMode) => {
  const toneConfig = isDarkMode
    ? DARK_PRIMARY_TONE_CONFIG
    : LIGHT_PRIMARY_TONE_CONFIG;

  return Object.entries(toneConfig).reduce(
    (result, [variableName, [targetChannel, colorWeight]]) => {
      result[variableName] = mixRgbTriplet(
        rgbChannels,
        targetChannel,
        colorWeight
      );
      return result;
    },
    {}
  );
};

export const getDashboardAppearanceSettings = settings => {
  return Object.entries(DEFAULT_DASHBOARD_APPEARANCE).reduce(
    (result, [key, defaultValue]) => {
      result[key] = normalizeHexColor(settings?.[key]) || defaultValue;
      return result;
    },
    {}
  );
};

export const applyDashboardAppearance = settings => {
  if (typeof document === 'undefined') return;

  const target = document.body || document.documentElement;
  const isDarkMode = document.body?.classList.contains('dark');
  const primaryColor = normalizeHexColor(
    settings?.[DASHBOARD_APPEARANCE_SETTING_KEYS.PRIMARY_COLOR]
  );
  const backgroundColorKey = isDarkMode
    ? DASHBOARD_APPEARANCE_SETTING_KEYS.BACKGROUND_COLOR_DARK
    : DASHBOARD_APPEARANCE_SETTING_KEYS.BACKGROUND_COLOR_LIGHT;
  const backgroundColor = normalizeHexColor(settings?.[backgroundColorKey]);
  const agentMessageBubbleColor = normalizeHexColor(
    settings?.[DASHBOARD_APPEARANCE_SETTING_KEYS.AGENT_MESSAGE_BUBBLE_COLOR]
  );

  if (primaryColor) {
    const primaryRgbTriplet = hexToRgbTriplet(primaryColor);
    const primaryRgbChannels = hexToRgbChannels(primaryColor);
    const themedPrimaryColors = getThemedPrimaryColors(
      primaryRgbChannels,
      isDarkMode
    );

    target.style.setProperty('--brand-color', primaryRgbTriplet);
    Object.entries(themedPrimaryColors).forEach(([variableName, color]) => {
      target.style.setProperty(variableName, color);
    });
    target.style.setProperty('--border-blue', `${primaryRgbTriplet}, 0.5`);
  } else {
    themedPrimaryVariableNames.forEach(variableName => {
      target.style.removeProperty(variableName);
    });
  }

  if (backgroundColor) {
    target.style.setProperty(
      '--background-color',
      hexToRgbTriplet(backgroundColor)
    );
  } else {
    target.style.removeProperty('--background-color');
  }

  if (agentMessageBubbleColor) {
    target.style.setProperty(
      '--agent-message-bubble-color',
      hexToRgbTriplet(agentMessageBubbleColor)
    );
  } else {
    target.style.removeProperty('--agent-message-bubble-color');
  }
};
