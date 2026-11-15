// Build-time only: reads the generated definitions from the repository and builds the catalog once per process.

import { existsSync, readFileSync } from "node:fs";
import { dirname, join, resolve } from "node:path";

import type { Catalog } from "./catalog.ts";
import { buildCatalog } from "./catalog.ts";
import { parseCoverage } from "./coverage.ts";
import { parseDefinitions } from "./parse-definitions.ts";

const DEFINITIONS = join("definitions", "wow-forever.d.luau");
const COVERAGE = join("definitions", "coverage.json");

/** The repository root: the nearest ancestor of the working directory that has definitions/. */
export function findRepoRoot(start: string = process.cwd()): string {
  let dir = resolve(start);
  for (;;) {
    if (existsSync(join(dir, DEFINITIONS))) {
      return dir;
    }
    const parent = dirname(dir);
    if (parent === dir) {
      throw new Error(`definitions/wow-forever.d.luau not found above ${start}`);
    }
    dir = parent;
  }
}

export function readDefinitionsSource(root: string = findRepoRoot()): string {
  return readFileSync(join(root, DEFINITIONS), "utf8");
}

/** definitions/report.json, parsed but unvalidated: callers read it through narrowing helpers. */
export function readReport(root: string = findRepoRoot()): unknown {
  return JSON.parse(readFileSync(join(root, "definitions", "report.json"), "utf8"));
}

let cached: Catalog | undefined;

export function loadCatalog(): Catalog {
  if (cached === undefined) {
    const root = findRepoRoot();
    const coverage: unknown = JSON.parse(readFileSync(join(root, COVERAGE), "utf8"));
    cached = buildCatalog(parseDefinitions(readDefinitionsSource(root)), parseCoverage(coverage));
  }
  return cached;
}
