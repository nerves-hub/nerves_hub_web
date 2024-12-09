import js from '@eslint/js'

export default [
  js.configs.recommended,
  {
    languageOptions: {
      globals: {
        browser: true,
        node: true
      },
      ecmaVersion: 6,
      sourceType: 'module'
    },
    rules: {
      'no-empty': ['error', { allowEmptyCatch: true }]
    }
  }
]
