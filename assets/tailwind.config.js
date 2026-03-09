// See the Tailwind configuration guide for advanced usage
// https://tailwindcss.com/docs/configuration

import plugin from "tailwindcss/plugin"
import defaultTheme from "tailwindcss/defaultTheme"
import tailWindForms from "@tailwindcss/forms"

const fs = require("fs")
const path = require("path")

export default {
  content: ["./js/**/*.js", "../lib/*_web.ex", "../lib/*_web/**/*.*ex"],
  theme: {
    extend: {
      fontFamily: {
        sans: ["'Inter', sans-serif", ...defaultTheme.fontFamily.sans]
      },
      backgroundImage: theme => ({
        "sidebar-item-hover":
          "linear-gradient(90deg, rgba(63, 63, 70, 0.24) 0%, rgba(63, 63, 70, 0.48) 100%)",
        "sidebar-item-selected":
          "linear-gradient(90deg, rgba(99, 102, 241, 0) 50%, rgba(99, 102, 241, 0.08) 100%), linear-gradient(90deg, rgba(63, 63, 70, 0.24) 0%, rgba(63, 63, 70, 0.48) 100%)",
        "tab-selected":
          "linear-gradient(180deg, rgba(99, 102, 241, 0.00) 86.32%, rgba(99, 102, 241, 0.48) 103.41%)",
        "health-good":
          "linear-gradient(180deg, rgba(16, 185, 129, 0.00) 18.75%, rgba(16, 185, 129, 0.04) 81.25%)",
        "health-warning":
          "linear-gradient(180deg, rgba(245, 158, 11, 0.00) 18.75%, rgba(245, 158, 11, 0.04) 81.25%), linear-gradient(180deg, rgba(63, 63, 70, 0.16) 0%, rgba(63, 63, 70, 0.24) 100%)",
        "health-neutral":
          "linear-gradient(180deg, rgba(99, 102, 241, 0.00) 18.75%, rgba(99, 102, 241, 0.04) 81.25%), linear-gradient(180deg, rgba(63, 63, 70, 0.16) 0%, rgba(63, 63, 70, 0.24) 100%)",
        "health-plain":
          "linear-gradient(180deg, rgba(99, 99, 99, 0.00) 18.75%, rgba(99, 99, 99, 0.04) 81.25%), linear-gradient(180deg, rgba(63, 63, 63, 0.16) 0%, rgba(63, 63, 63, 0.24) 100%)",
        "progress-glow":
          "radial-gradient(ellipse 80% 80% at 50% -10%, rgba(16, 185, 129, 0.3) 0, rgba(16, 185, 129, 0.0) 80%), radial-gradient(ellipse 50% 50% at 50% -10%, rgba(16, 185, 129, 0.3) 0, rgba(16, 185, 129, 0.0) 50%)",
        "example-map": "url('/images/mapbox-north-america-dummy.png')",
        "example-map-dark": "url('/images/mapbox-north-america-dummy-dark.png')"
      }),
      colors: {
        base: {
          50: "#fafafa",
          100: "#f4f4f5",
          200: "#e4e4e7",
          300: "#d4d4d8",
          400: "#a1a1aa",
          500: "#71717a",
          600: "#52525b",
          700: "#3f3f46",
          800: "#27272a",
          900: "#18181b",
          950: "#141417"
        },
        "nerves-gray": {
          500: "#757575"
        },
        purple: {
          600: "#6366F1"
        },
        primary: {
          500: "#6366F1"
        },
        success: {
          500: "#10b981"
        },
        warning: {
          500: "#f59e0b"
        }
      },
      boxShadow: {
        "filter-slider":
          "-16px 0px 32px -4px #141417, 0px 4px 4px -4px #141417;",
        "device-details-content": "0 16 32 -4 #141417, 0 14 4 -4 #141417"
      }
    }
  },
  plugins: [
    tailWindForms,
    plugin(({ addVariant }) =>
      addVariant("phx-no-feedback", ["&.phx-no-feedback", ".phx-no-feedback &"])
    ),
    plugin(({ addVariant }) =>
      addVariant("phx-click-loading", [
        "&.phx-click-loading",
        ".phx-click-loading &"
      ])
    ),
    plugin(({ addVariant }) =>
      addVariant("phx-submit-loading", [
        "&.phx-submit-loading",
        ".phx-submit-loading &"
      ])
    ),
    plugin(({ addVariant }) =>
      addVariant("phx-change-loading", [
        "&.phx-change-loading",
        ".phx-change-loading &"
      ])
    ),
    plugin(function({ matchUtilities, theme }) {
      matchUtilities(
        {
          "animate-delay": value => ({
            animationDelay: value
          })
        },
        { values: theme("transitionDelay") }
      )
    }),
    plugin(function ({ matchComponents, theme }) {
      let iconsDir = path.join(__dirname, "../deps/lucide/icons")
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
        fs.readdirSync(iconsDir).forEach(file => {
          if (file.endsWith(".svg")) {
            let name = path.basename(file, ".svg") + suffix
            values[name] = { name, fullPath: path.join(iconsDir, file), weight: weight }
          }
        })
      })

      matchComponents({
        "lucide": ({ name, fullPath, weight }) => {
          let content = fs.readFileSync(fullPath).toString().replace(/\r?\n|\r/g, "")

          if (weight !== "") {
            content = content.replace(/stroke-width="2"/g, `stroke-width="${weight}"`)
          }

          content = encodeURIComponent(content)
          let size = theme("spacing.6")

          return {
            [`--lucide-${name}`]: `url('data:image/svg+xml;utf8,${content}')`,
            "-webkit-mask": `var(--lucide-${name})`,
            "mask": `var(--lucide-${name})`,
            "mask-size": "contain",
            "mask-repeat": "no-repeat",
            "background-color": "currentColor",
            "vertical-align": "middle",
            "display": "inline-block",
            // "width": size,
            // "height": size
          }
        }
      }, { values })
    })
  ]
}
