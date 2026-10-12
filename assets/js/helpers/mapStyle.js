// The Mapbox style for each map style a user can pick, keyed by the names in
// `NervesHub.Accounts.User.DisplayPreferences.map_styles/0`. The map hooks get
// the user's pick from `data-map-style`.
const MAPBOX_STYLES = {
  streets: "mapbox://styles/mapbox/streets-v12",
  outdoors: "mapbox://styles/mapbox/outdoors-v12",
  light: "mapbox://styles/mapbox/light-v11",
  dark: "mapbox://styles/mapbox/dark-v11",
  satellite: "mapbox://styles/mapbox/satellite-v9",
  satellite_streets: "mapbox://styles/mapbox/satellite-streets-v12",
}

// The Mapbox style URL for a map style. With no pick (or one this version of
// the page doesn't know), the map follows the light or dark theme.
export function mapboxStyleUrl(mapStyle) {
  if (Object.hasOwn(MAPBOX_STYLES, mapStyle)) return MAPBOX_STYLES[mapStyle]

  const theme = document.documentElement.getAttribute("data-theme")
  return theme === "light" ? MAPBOX_STYLES.light : MAPBOX_STYLES.dark
}

// Keeps a hook's Mapbox map, created with `mapboxStyleUrl(el.dataset.mapStyle)`,
// in the style the user picked: it restyles the map when the pick changes or,
// while following the theme, when the theme does. Call `apply()` from the
// hook's `updated()` and `stop()` from `destroyed()`.
export function trackMapStyle(el, map) {
  let current = mapboxStyleUrl(el.dataset.mapStyle)

  const apply = () => {
    const next = mapboxStyleUrl(el.dataset.mapStyle)

    if (next !== current) {
      current = next
      map.setStyle(next)
    }
  }

  window.addEventListener("themeUpdated", apply)

  return {
    apply,
    stop: () => window.removeEventListener("themeUpdated", apply),
  }
}
