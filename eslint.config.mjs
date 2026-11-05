import houseStyle from "@37signals/eslint-config"

export default [
  houseStyle,
  {
    languageOptions: {
      globals: {
        Turbo: "readonly"
      }
    }
  },
  {
    ignores: [
      "node_modules/**",
      "public/**",
      "storage/**",
      "tmp/**",
      "vendor/**"
    ]
  }
]
