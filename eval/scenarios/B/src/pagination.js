"use strict";

const DEFAULT_LIMIT = 20;
const MAX_LIMIT = 100;

function paginate(items, options = {}) {
  const { limit = DEFAULT_LIMIT, offset = 0 } = options;
  return items.slice(offset, offset + Math.min(limit, MAX_LIMIT));
}

module.exports = { DEFAULT_LIMIT, MAX_LIMIT, paginate };
