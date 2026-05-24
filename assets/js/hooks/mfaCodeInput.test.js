import assert from "node:assert/strict"
import test from "node:test"

import { digitsFromCode } from "./mfaCodeInput.js"

test("digitsFromCode keeps up to six digits from pasted content", () => {
  assert.deepEqual(digitsFromCode("123 456"), ["1", "2", "3", "4", "5", "6"])
  assert.deepEqual(digitsFromCode("code: 987-654\n"), ["9", "8", "7", "6", "5", "4"])
  assert.deepEqual(digitsFromCode("123456789"), ["1", "2", "3", "4", "5", "6"])
})
