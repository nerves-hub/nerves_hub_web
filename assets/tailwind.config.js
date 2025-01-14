// See the Tailwind configuration guide for advanced usage
// https://tailwindcss.com/docs/configuration

import plugin from "tailwindcss/plugin"
import defaultTheme from "tailwindcss/defaultTheme"
import tailWindForms from "@tailwindcss/forms"

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
          "linear-gradient(90deg, rgba(99, 102, 241, 0) 50%, rgba(99, 102, 241, 0.08) 100%), linear-gradient(90deg, rgba(63, 63, 70, 0.24) 0%, rgba(63, 63, 70, 0.48) 100%)"
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
        purple: {
          600: "#6366F1"
        }
      },
      boxShadow: {
        "filter-slider":
          "-16px 0px 32px -4px #141417, 0px 4px 4px -4px #141417;"
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
    )
  ]
}
