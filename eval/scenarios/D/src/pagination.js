"use strict";

const DEFAULT_LIMIT = 20;
const MAX_LIMIT = 100;

// Strategy seam: the limit policy is kept swappable for other paging strategies.
class LimitPolicy {
  apply(limit) {
    return Math.min(limit, MAX_LIMIT);
  }
}

class ArrayPaginator {
  constructor(policy = new LimitPolicy()) {
    this.policy = policy;
  }

  page(items, { limit = DEFAULT_LIMIT, offset = 0 } = {}) {
    return items.slice(offset, offset + this.policy.apply(limit));
  }
}

function makePaginator() {
  return new ArrayPaginator();
}

function paginate(items, options = {}) {
  return makePaginator().page(items, options);
}

module.exports = { DEFAULT_LIMIT, MAX_LIMIT, paginate };
