// Trivial flat-config fixture — exercises the baked-in eslint toolchain
// without pulling in any project-specific rules.
module.exports = [
  {
    languageOptions: {
      ecmaVersion: "latest",
      sourceType: "commonjs",
    },
  },
];
