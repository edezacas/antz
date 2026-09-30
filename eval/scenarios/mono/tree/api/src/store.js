export const DEFAULT_CAPACITY = 100;

export function createStore({ capacity = DEFAULT_CAPACITY } = {}) {
  const items = [];

  return {
    add(record) {
      if (items.length >= capacity) throw new RangeError("store is full");
      items.push(record);
      return record;
    },
    list() {
      return [...items];
    },
    size() {
      return items.length;
    },
  };
}
