import test from "node:test";
import assert from "node:assert/strict";
import { columnsFor, COLUMNS, BREAKPOINT_PX } from "../src/grid.js";

test("por encima del breakpoint son las columnas de la rejilla", () => {
  assert.equal(columnsFor(BREAKPOINT_PX), COLUMNS);
  assert.equal(columnsFor(1440), 6);
});

test("por debajo del breakpoint una sola columna", () => {
  assert.equal(columnsFor(375), 1);
});
