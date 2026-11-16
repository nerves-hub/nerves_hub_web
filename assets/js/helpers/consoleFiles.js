// Whether a device's console can be sent a file, from the console version it
// joined with (the channel's "metadata" message). Consoles before 2.0.0 can't
// take one. A device that sent no version, or one with no number in it, is
// given the benefit of the doubt: refusing a drop it could take is worse than
// sending one it ignores.
//
// Only the major version matters, read as `semver.coerce` would: the first
// run of digits. No `semver` import, so the unit tests run without an npm
// install, as CI runs them.
export const acceptsFiles = (version) => {
  const major = String(version ?? "").match(/\d+/)

  return major === null || Number(major[0]) >= 2
}
