export const DASHBOARD_APPEARANCE_SETTING_KEYS = {
  PRIMARY_COLOR: 'dashboard_primary_color',
  BACKGROUND_COLOR_LIGHT: 'dashboard_background_color_light',
  BACKGROUND_COLOR_DARK: 'dashboard_background_color_dark',
};

export const DEFAULT_DASHBOARD_APPEARANCE = {
  [DASHBOARD_APPEARANCE_SETTING_KEYS.PRIMARY_COLOR]: '#2781F6',
  [DASHBOARD_APPEARANCE_SETTING_KEYS.BACKGROUND_COLOR_LIGHT]: '#F7F7F7',
  [DASHBOARD_APPEARANCE_SETTING_KEYS.BACKGROUND_COLOR_DARK]: '#1C1D20',
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
  const primaryColor = normalizeHexColor(
    settings?.[DASHBOARD_APPEARANCE_SETTING_KEYS.PRIMARY_COLOR]
  );
  const backgroundColorKey = document.body?.classList.contains('dark')
    ? DASHBOARD_APPEARANCE_SETTING_KEYS.BACKGROUND_COLOR_DARK
    : DASHBOARD_APPEARANCE_SETTING_KEYS.BACKGROUND_COLOR_LIGHT;
  const backgroundColor = normalizeHexColor(settings?.[backgroundColorKey]);

  if (primaryColor) {
    target.style.setProperty('--brand-color', hexToRgbTriplet(primaryColor));
  } else {
    target.style.removeProperty('--brand-color');
  }

  if (backgroundColor) {
    target.style.setProperty(
      '--background-color',
      hexToRgbTriplet(backgroundColor)
    );
  } else {
    target.style.removeProperty('--background-color');
  }
};
