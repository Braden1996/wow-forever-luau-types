// Reads definitions/coverage.json without trusting its shape: every entry is validated field by field.

import type { Coverage, CoverageStatus } from "./model.ts";

export type CoverageGroup = "enums" | "events" | "functions" | "structures" | "widgetMethods" | "widgets";

export type CoverageIndex = ReadonlyMap<CoverageGroup, ReadonlyMap<string, Coverage>>;

const GROUPS: readonly CoverageGroup[] = ["enums", "events", "functions", "structures", "widgetMethods", "widgets"];

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function isStatus(value: unknown): value is CoverageStatus {
  return value === "typed" || value === "untyped" || value === "excluded";
}

function optionalString(value: unknown): string | undefined {
  return typeof value === "string" ? value : undefined;
}

function readEntry(value: unknown): Coverage | undefined {
  if (!isRecord(value) || !isStatus(value["status"])) {
    return undefined;
  }
  return {
    status: value["status"],
    source: optionalString(value["source"]),
    reason: optionalString(value["reason"]),
  };
}

export function parseCoverage(json: unknown): CoverageIndex {
  const index = new Map<CoverageGroup, Map<string, Coverage>>();
  if (!isRecord(json)) {
    throw new Error("coverage.json: expected an object at the top level");
  }
  for (const group of GROUPS) {
    const entries = new Map<string, Coverage>();
    const raw = json[group];
    if (!isRecord(raw)) {
      throw new Error(`coverage.json: missing group "${group}"`);
    }
    for (const [key, value] of Object.entries(raw)) {
      const entry = readEntry(value);
      if (entry === undefined) {
        throw new Error(`coverage.json: ${group}.${key} has no valid status`);
      }
      entries.set(key, entry);
    }
    index.set(group, entries);
  }
  return index;
}

export function lookupCoverage(index: CoverageIndex, group: CoverageGroup, key: string): Coverage | undefined {
  return index.get(group)?.get(key);
}

export interface CoverageTotals {
  readonly typed: number;
  readonly untyped: number;
  readonly excluded: number;
}

export function coverageTotals(index: CoverageIndex, group: CoverageGroup): CoverageTotals {
  let typed = 0;
  let untyped = 0;
  let excluded = 0;
  for (const entry of index.get(group)?.values() ?? []) {
    if (entry.status === "typed") {
      typed += 1;
    } else if (entry.status === "untyped") {
      untyped += 1;
    } else {
      excluded += 1;
    }
  }
  return { typed, untyped, excluded };
}

/** Entries that are not in the definitions file (excluded), for the coverage page. */
export function excludedEntries(index: CoverageIndex, group: CoverageGroup): Array<readonly [string, Coverage]> {
  return [...(index.get(group)?.entries() ?? [])].filter(([, entry]) => entry.status === "excluded");
}
