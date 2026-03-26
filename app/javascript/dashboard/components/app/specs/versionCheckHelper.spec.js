import { hasAnUpdateAvailable } from '../versionCheckHelper';

describe('#hasAnUpdateAvailable', () => {
  it('returns false if latest version is invalid', () => {
    expect(hasAnUpdateAvailable('invalid', '1.0.0')).toBe(false);
    expect(hasAnUpdateAvailable(null, '1.0.0')).toBe(false);
    expect(hasAnUpdateAvailable(undefined, '1.0.0')).toBe(false);
    expect(hasAnUpdateAvailable('', '1.0.0')).toBe(false);
  });

  it('returns false even when a newer version exists', () => {
    expect(hasAnUpdateAvailable('1.1.0', '1.0.0')).toBe(false);
    expect(hasAnUpdateAvailable('0.1.0', '1.0.0')).toBe(false);
  });
});
