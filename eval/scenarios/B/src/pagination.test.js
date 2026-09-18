"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const { paginate } = require("./pagination");

test("devuelve la ventana pedida", () => {
  const items = [1, 2, 3, 4, 5];
  assert.deepEqual(paginate(items, { limit: 2, offset: 1 }), [2, 3]);
});

test("un offset más allá del final devuelve vacío", () => {
  assert.deepEqual(paginate([1, 2, 3], { offset: 10 }), []);
});

test("limit se respeta tal cual se pide", () => {
  const items = Array.from({ length: 200 }, (_, i) => i);
  assert.equal(paginate(items, { limit: 1000 }).length, 1000);
});
