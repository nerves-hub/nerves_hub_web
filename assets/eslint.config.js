import js from "@eslint/js"
import globals from "globals"

// we need to be on node >= 18 to consume a version of "globals"
// that has this key without a trailing space; if we use it as-is
// eslint blows up
delete globals.browser["AudioWorkletGlobalScope "]

export default [
  js.configs.recommended,
  {
    languageOptions: {
      globals: {
        ...globals.browser,
        ...globals.jest,
        Intl: true
      },
      ecmaVersion: 6,
      sourceType: "module"
    },
    rules: {
      "no-empty": ["error", { allowEmptyCatch: true }],
      quotes: ["error", "double"]
    }
  }
]
