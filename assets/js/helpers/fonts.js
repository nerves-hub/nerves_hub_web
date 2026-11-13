// Runs `callback` once the web fonts named by `fonts` (CSS `font` shorthands,
// such as `bold 14px "JetBrains Mono", monospace`) have loaded.
//
// Text drawn on a canvas, as xterm and chart.js do, uses whatever has loaded
// at the moment it is drawn, and xterm sizes its cells from the font it has
// when it opens. So anything that starts before the font arrives keeps the
// fallback. The font is usually loaded already, because mono text elsewhere on
// the page asked for it, and then `callback` runs straight away. If a font
// fails to load, `callback` still runs, with the fallback.
export const whenFontsLoaded = (fonts, callback) => {
  if (fonts.every(font => document.fonts.check(font))) {
    callback()
  } else {
    Promise.all(fonts.map(font => document.fonts.load(font)))
      .catch(() => {})
      .then(callback)
  }
}
