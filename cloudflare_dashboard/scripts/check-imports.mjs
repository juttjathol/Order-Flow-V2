#!/usr/bin/env node
// Resolve every relative import under cloudflare_dashboard/functions.
import { readdirSync, readFileSync, statSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const fnRoot = join(root, "functions");

function walk(dir, acc = []) {
  for (const n of readdirSync(dir)) {
    const p = join(dir, n);
    if (statSync(p).isDirectory()) walk(p, acc);
    else if (n.endsWith(".js") || n.endsWith(".mjs")) acc.push(p);
  }
  return acc;
}

let bad = 0;
for (const f of walk(fnRoot)) {
  const text = readFileSync(f, "utf8");
  const re = /from\s+["'](\.\.?\/[^"']+)["']/g;
  let m;
  while ((m = re.exec(text))) {
    const spec = m[1];
    const target = resolve(dirname(f), spec);
    try {
      statSync(target);
      console.log("ok", f.replace(root + "/", ""), "->", spec);
    } catch {
      console.error("MISSING", f.replace(root + "/", ""), spec, "resolved", target);
      bad += 1;
    }
  }
}
if (bad) {
  console.error(`${bad} unresolved import(s)`);
  process.exit(1);
}
console.log("all relative imports resolve");
