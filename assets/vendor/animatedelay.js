const plugin = require("tailwindcss/plugin")

module.exports = plugin(function ({ matchUtilities, theme }) {
  matchUtilities(
    {
      "animate-delay": (value) => ({
        animationDelay: value,
      }),
    },
    { values: theme("transitionDelay") },
  )
})
