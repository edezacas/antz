"use strict";

const DEFAULT_LIMIT = 20;

function paginate(items, options = {}) {
  const { limit = DEFAULT_LIMIT, offset = 0 } = options;
  return items.slice(offset, offset + limit);
}

module.exports = { DEFAULT_LIMIT, paginate };
