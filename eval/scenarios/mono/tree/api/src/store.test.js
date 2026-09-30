import test from "node:test";
import assert from "node:assert/strict";
import { createStore, DEFAULT_CAPACITY } from "./store.js";

test("guarda y devuelve los registros en orden", () => {
  const store = createStore();
  store.add({ id: 1 });
  store.add({ id: 2 });
  assert.deepEqual(store.list(), [{ id: 1 }, { id: 2 }]);
});

test("rechaza el registro que pasa la capacidad", () => {
  const store = createStore({ capacity: 1 });
  store.add({ id: 1 });
  assert.throws(() => store.add({ id: 2 }), RangeError);
});

test("la lista devuelta no es la del store", () => {
  const store = createStore();
  store.add({ id: 1 });
  store.list().push({ id: 2 });
  assert.equal(store.size(), 1);
  assert.equal(DEFAULT_CAPACITY, 100);
});
