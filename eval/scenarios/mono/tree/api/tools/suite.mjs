#!/usr/bin/env node
// The api suite: `node --test` over every module's test, or over the single file
// named after `--only`. Wrapped so a wrong name fails with the list of known
// tests instead of silently running nothing.
import { spawnSync } from "node:child_process";
import { readdirSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const src = resolve(dirname(fileURLToPath(import.meta.url)), "..", "src");
const files = readdirSync(src).filter((name) => name.endsWith(".test.js")).sort();
const flag = process.argv.indexOf("--only");
const requested = flag === -1 ? undefined : process.argv[flag + 1];
const chosen = requested ? files.filter((name) => name === requested.replace(/^.*\//, "")) : files;

if (chosen.length === 0) {
  console.error(`no test called '${requested}'. Known: ${files.join(", ")}`);
  process.exit(2);
}

const run = spawnSync(process.execPath, ["--test", ...chosen.map((name) => join(src, name))], {
  stdio: "inherit",
});
process.exit(run.status ?? 1);
