const plugin = require("tailwindcss/plugin")
const fs = require("fs")
const path = require("path")

module.exports = plugin(function ({ matchComponents, theme }) {
  let iconsDir = path.join(__dirname, "../../deps/lucide/icons")
  let values = {}
  // A line icon draws its stroke at 1/16 of its size, and never under 1px:
  // 1px at 16px, 1.25px at 20px, whatever its source. On Lucide's 24 grid
  // that is 1.5, the default here. --bold is for a selected nav item and for
  // icons under 16px (size-3, size-3.5); --thin keeps an icon of 32px or
  // more from drawing a 2px+ line.
  let weights = [
    ["", "1.5"],
    ["--bold", "2"],
    ["--thin", "0.8"],
  ]

  weights.forEach(([suffix, weight]) => {
    fs.readdirSync(iconsDir).forEach((file) => {
      if (file.endsWith(".svg")) {
        let name = path.basename(file, ".svg") + suffix
        values[name] = {
          name,
          fullPath: path.join(iconsDir, file),
          weight: weight,
        }
      }
    })
  })

  matchComponents(
    {
      lucide: ({ name, fullPath, weight }) => {
        let content = fs
          .readFileSync(fullPath)
          .toString()
          .replace(/\r?\n|\r/g, "")

        if (weight !== "") {
          content = content.replace(
            /stroke-width="2"/g,
            `stroke-width="${weight}"`,
          )
        }

        content = encodeURIComponent(content)
        let size = theme("spacing.6")

        return {
          [`--lucide-${name}`]: `url('data:image/svg+xml;utf8,${content}')`,
          "-webkit-mask": `var(--lucide-${name})`,
          mask: `var(--lucide-${name})`,
          "mask-size": "contain",
          "mask-repeat": "no-repeat",
          "background-color": "currentColor",
          "vertical-align": "middle",
          display: "inline-block",
          // An empty span has no minimum width, so in a crowded flex row it
          // would shrink and squash the glyph. An SVG of a set size never did.
          "flex-shrink": "0",
          // "width": size,
          // "height": size
        }
      },
    },
    { values },
  )
})
