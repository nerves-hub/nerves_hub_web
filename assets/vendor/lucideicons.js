const plugin = require("tailwindcss/plugin")
const fs = require("fs")
const path = require("path")

module.exports = plugin(function ({ matchComponents, theme }) {
  let iconsDir = path.join(__dirname, "../../deps/lucide/icons")
  let values = {}
  let weights = [
    ["--verythin", "0.8"],
    ["--thin", "1"],
    ["--light", "1.25"],
    ["--semilight", "1.5"],
    ["", ""],
    ["--semibold", "2.25"],
    ["--bold", "2.5"],
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
          // "width": size,
          // "height": size
        }
      },
    },
    { values },
  )
})
