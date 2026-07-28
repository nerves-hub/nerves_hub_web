// Unit tests for the pure tokenizer/suggestion/keyboard-decision logic in
// advancedQueryEditor.js. Runs on Node's built-in test runner - no
// dependencies, no DOM:
//
//   node --test assets/js
//
// The DOM half of the hook (caret handling, contenteditable rendering) is not
// covered here; it would need a real browser to test meaningfully.
import { describe, it } from "node:test"
import assert from "node:assert/strict"

import {
  tokenize,
  classify,
  contextAt,
  suggestionsFor,
  isCompleteQuery,
  closeUnterminatedString,
  commitAction,
} from "./advancedQueryEditor.js"

const SCHEMA = {
  columns: ["health", "identifier", "description", "version"],
  operators: {
    health: ["=", "!=", "is", "is not"],
    description: ["like", "not like"],
    version: ["=", ">", ">=", "<", "<="],
  },
  values: {
    health: ["healthy", "unhealthy", "offline"],
    version: ["1.2.3", "1.3.0"],
  },
}

// The suggestion/decision state the hook would be in with the caret at `caret`
// (default: end of input) and nothing highlighted in the dropdown.
function editorState(value, caret = value.length) {
  const classified = classify(tokenize(value))
  const ctx = contextAt(classified, caret)
  return { ctx, suggestions: suggestionsFor(ctx, SCHEMA) }
}

function actionFor(key, value, { activeIndex = -1, visible = true } = {}) {
  const { ctx, suggestions } = editorState(value)
  const closed = closeUnterminatedString(value)

  return commitAction(key, {
    suggestionsVisible: visible,
    suggestionCount: suggestions.length,
    activeIndex,
    prefix: ctx.prefix,
    empty: closed.trim() === "",
    complete: isCompleteQuery(closed),
  })
}

describe("tokenize", () => {
  it("takes the longest symbol match", () => {
    const tokens = tokenize("version >= 2")
    assert.deepEqual(
      tokens.map((t) => [t.type, t.value]),
      [
        ["ident", "version"],
        ["whitespace", " "],
        ["symbol", ">="],
        ["whitespace", " "],
        ["ident", "2"],
      ],
    )
  })

  it("tracks token offsets", () => {
    const [ident, ws, symbol] = tokenize("health =")
    assert.deepEqual([ident.start, ident.end], [0, 6])
    assert.deepEqual([ws.start, ws.end], [6, 7])
    assert.deepEqual([symbol.start, symbol.end], [7, 8])
  })

  it("handles quoted strings, including escapes", () => {
    const [token] = tokenize('"say \\"hi\\""')
    assert.equal(token.type, "string")
    assert.equal(token.value, '"say \\"hi\\""')
  })

  it("flags unterminated strings", () => {
    const tokens = tokenize('health = "off')
    assert.equal(tokens.at(-1).type, "unterminated_string")
  })
})

describe("classify", () => {
  it("assigns grammar roles left to right", () => {
    const { entries } = classify(
      tokenize('not health != "ok" and (version > 1)'),
    )
    const roles = entries
      .filter((e) => e.role !== "whitespace")
      .map((e) => [e.token.value, e.role])

    assert.deepEqual(roles, [
      ["not", "keyword"],
      ["health", "column"],
      ["!=", "operator"],
      ['"ok"', "string"],
      ["and", "keyword"],
      ["(", "paren"],
      ["version", "column"],
      [">", "operator"],
      ["1", "value"],
      [")", "paren"],
    ])
  })

  it("recognizes two-word operators", () => {
    const { entries, final } = classify(tokenize("health is not offline"))
    const operators = entries.filter((e) => e.role === "operator")

    assert.deepEqual(
      operators.map((e) => e.token.value),
      ["is", "not"],
    )
    assert.equal(final.operator, "is not")
  })
})

describe("contextAt", () => {
  it("captures the prefix and state of the token under the caret", () => {
    const ctx = contextAt(classify(tokenize("hea")), 3)
    assert.equal(ctx.state, "term_start")
    assert.equal(ctx.prefix, "hea")
    assert.equal(ctx.tokenStart, 0)
  })

  it("strips the opening quote from a string prefix", () => {
    const value = 'health = "unh'
    const ctx = contextAt(classify(tokenize(value)), value.length)
    assert.equal(ctx.state, "value")
    assert.equal(ctx.prefix, "unh")
  })

  it("is a fresh position after trailing whitespace", () => {
    const value = "description like "
    const ctx = contextAt(classify(tokenize(value)), value.length)
    assert.equal(ctx.state, "value")
    assert.equal(ctx.prefix, "")
  })
})

describe("suggestionsFor", () => {
  it("filters candidates by the typed prefix", () => {
    const { suggestions } = editorState("hea")
    assert.deepEqual(
      suggestions.map((s) => s.value),
      ["health"],
    )
  })

  it("drops a candidate the prefix already matches exactly", () => {
    const { suggestions } = editorState("description like")
    assert.deepEqual(suggestions, [])
  })

  it("offers a closing paren only inside parens", () => {
    const inside = editorState('(health = "ok" ')
    assert.ok(inside.suggestions.some((s) => s.value === ")"))

    const outside = editorState('health = "ok" ')
    assert.deepEqual(
      outside.suggestions.map((s) => s.value),
      ["and", "or"],
    )
  })
})

describe("isCompleteQuery", () => {
  it("accepts full terms and closed parens", () => {
    assert.ok(isCompleteQuery('health = "ok"'))
    assert.ok(isCompleteQuery('(health = "ok")'))
    assert.ok(isCompleteQuery('not health = "ok" and version > 1'))
  })

  it("rejects everything mid-term", () => {
    assert.ok(!isCompleteQuery(""))
    assert.ok(!isCompleteQuery("health"))
    assert.ok(!isCompleteQuery("health ="))
    assert.ok(!isCompleteQuery('health = "ok" and'))
    assert.ok(!isCompleteQuery('(health = "ok"'))
  })
})

describe("closeUnterminatedString", () => {
  it("closes a trailing open string", () => {
    assert.equal(
      closeUnterminatedString('health = "unhealthy'),
      'health = "unhealthy"',
    )
  })

  it("leaves anything else alone", () => {
    assert.equal(closeUnterminatedString('health = "ok"'), 'health = "ok"')
    assert.equal(closeUnterminatedString("health ="), "health =")
    assert.equal(closeUnterminatedString(""), "")
  })
})

describe("commitAction", () => {
  it("Tab completes with the first suggestion mid-word", () => {
    assert.deepEqual(actionFor("Tab", "hea"), { type: "accept", index: 0 })
  })

  it("Enter completes with the first suggestion mid-word", () => {
    assert.deepEqual(actionFor("Enter", "hea"), { type: "accept", index: 0 })
  })

  it("a highlighted suggestion wins over the first", () => {
    assert.deepEqual(actionFor("Tab", "hea", { activeIndex: 2 }), {
      type: "accept",
      index: 2,
    })
    assert.deepEqual(actionFor("Enter", "hea", { activeIndex: 1 }), {
      type: "accept",
      index: 1,
    })
  })

  it("Enter submits a complete query even while and/or hints are showing", () => {
    const value = 'health = "ok" '
    assert.ok(editorState(value).suggestions.length > 0)
    assert.deepEqual(actionFor("Enter", value), { type: "apply" })
  })

  it("Tab grabs the hint a fresh position is showing", () => {
    // Same position as above, but Tab is always an explicit completion.
    assert.deepEqual(actionFor("Tab", 'health = "ok" '), {
      type: "accept",
      index: 0,
    })
  })

  it("Enter completes a partially typed value", () => {
    // "1.2" prefix-matches the known value "1.2.3", so Enter completes it
    // rather than searching for the literal 1.2.
    assert.deepEqual(actionFor("Enter", "version = 1.2"), {
      type: "accept",
      index: 0,
    })
  })

  it("Enter advances out of a finished operator instead of failing the search", () => {
    assert.deepEqual(actionFor("Enter", "description like"), {
      type: "advance",
    })
  })

  it("Enter advances out of a finished column name", () => {
    assert.deepEqual(actionFor("Enter", "health"), { type: "advance" })
  })

  it("Enter advances rather than submit a dangling connective", () => {
    assert.deepEqual(actionFor("Enter", 'health = "ok" and'), {
      type: "advance",
    })
  })

  it("Enter advances rather than submit an unclosed paren group", () => {
    assert.deepEqual(actionFor("Enter", '(health = "ok" '), {
      type: "advance",
    })
  })

  it("Enter submits once a trailing string is auto-closed", () => {
    assert.deepEqual(actionFor("Enter", 'health = "unhealthy'), {
      type: "apply",
    })
  })

  it("Enter submits an empty query to clear the filter", () => {
    assert.deepEqual(actionFor("Enter", ""), { type: "apply" })
  })

  it("dismissed suggestions never get accepted", () => {
    assert.deepEqual(actionFor("Enter", "hea", { visible: false }), {
      type: "advance",
    })
    assert.deepEqual(actionFor("Tab", "hea", { visible: false }), {
      type: "none",
    })
  })

  it("Tab without suggestions is swallowed", () => {
    assert.deepEqual(actionFor("Tab", "description like"), { type: "none" })
  })
})

describe("typing flows", () => {
  it("advancing out of an operator lands on value suggestions", () => {
    // `description like` + Enter advances; the hook appends the separator
    // space via exitToTail, after which the value suggestions show.
    assert.deepEqual(actionFor("Enter", "description like"), {
      type: "advance",
    })

    const after = editorState("description like ")
    assert.equal(after.ctx.state, "value")
  })

  it("completing column and operator by Tab leads to a query ready to submit", () => {
    assert.deepEqual(actionFor("Tab", "hea"), { type: "accept", index: 0 })
    // The hook inserts "health " - Tab again grabs the first operator.
    assert.deepEqual(actionFor("Tab", "health "), { type: "accept", index: 0 })
    assert.equal(editorState("health ").suggestions[0].value, "=")

    assert.deepEqual(actionFor("Enter", 'health = "unhealthy"'), {
      type: "apply",
    })
  })
})
