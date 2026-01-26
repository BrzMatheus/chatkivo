import { required, minLength } from '@vuelidate/validators';

const LABEL_TITLE_REGEX = /^[\p{L}\p{N}][\p{L}\p{N}_\- ]*[\p{L}\p{N}_-]?$/u;

export const validLabelCharacters = (str = '') => {
  if (!str) return false;
  if (str !== str.trim()) return false;
  return LABEL_TITLE_REGEX.test(str);
};

export const getLabelTitleErrorMessage = validation => {
  let errorMessage = '';
  if (!validation.title.$error) {
    errorMessage = '';
  } else if (!validation.title.required) {
    errorMessage = 'LABEL_MGMT.FORM.NAME.REQUIRED_ERROR';
  } else if (!validation.title.minLength) {
    errorMessage = 'LABEL_MGMT.FORM.NAME.MINIMUM_LENGTH_ERROR';
  } else if (!validation.title.validLabelCharacters) {
    errorMessage = 'LABEL_MGMT.FORM.NAME.VALID_ERROR';
  }
  return errorMessage;
};

export default {
  title: {
    required,
    minLength: minLength(2),
    validLabelCharacters,
  },
  description: {},
  color: {
    required,
  },
  showOnSidebar: {},
};
