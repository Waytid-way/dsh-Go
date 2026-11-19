import { isDeepStrictEqual } from 'node:util';

const manifestFields = ['name', 'version', 'dependencies', 'optionalDependencies', 'peerDependencies',
  'peerDependenciesMeta', 'bundledDependencies', 'bundleDependencies', 'os', 'cpu', 'libc', 'engines',
  'dsh', 'scripts', 'gypfile', 'type', 'main', 'module', 'exports', 'imports', 'bin'];

function normalizedBin(value, packageName) {
  const path = value => value.replace(/^\.\//, '');
  if (typeof value === 'string') {
    const command = packageName.slice(packageName.lastIndexOf('/') + 1);
    return [[command, path(value)]];
  }
  if (value !== null && typeof value === 'object' && !Array.isArray(value)) {
    return Object.keys(value).sort().map(command => {
      const target = value[command];
      return [command, typeof target === 'string' ? path(target) : target];
    });
  }
  return value;
}

/** Name the first drift between the registry lock and the extracted archive. */
export function manifestMismatch(locked, archive) {
  for (const field of manifestFields) {
    const expected = field === 'bin' ? normalizedBin(locked.bin, locked.name) : locked[field];
    const actual = field === 'bin' ? normalizedBin(archive.bin, locked.name) : archive[field];
    if (!isDeepStrictEqual(expected, actual)) return field;
  }
  return null;
}
