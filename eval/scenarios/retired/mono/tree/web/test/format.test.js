import test from "node:test";
import assert from "node:assert/strict";
import { humanSize } from "../src/format.js";

test("los bytes no se convierten", () => {
  assert.equal(humanSize(512), "512 B");
});

test("los kilobytes se redondean", () => {
  assert.equal(humanSize(2048), "2 KB");
});

test("los megabytes llevan un decimal", () => {
  assert.equal(humanSize(3 * 1024 * 1024), "3.0 MB");
});
