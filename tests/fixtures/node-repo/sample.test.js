const { test } = require("node:test");
const assert = require("node:assert/strict");

test("truth stays true", () => {
  assert.equal(1 + 1, 2);
});
