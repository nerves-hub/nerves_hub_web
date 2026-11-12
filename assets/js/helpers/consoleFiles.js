import semver from "semver"

// Whether a device's console can be sent a file, from the console version it
// joined with (the channel's "metadata" message). Consoles before 2.0.0 can't
// take one. A device that sent no version, or one that isn't semver, is given
// the benefit of the doubt: refusing a drop it could take is worse than
// sending one it ignores.
export const acceptsFiles = version => {
  const parsed = semver.valid(semver.coerce(version))

  return parsed === null || semver.gte(parsed, "2.0.0")
}
