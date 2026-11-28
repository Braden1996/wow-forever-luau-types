// Ranking for the symbol search. Pure functions so they can be unit tested; the island only renders.

import type { SearchEntry, SearchKind } from "../../lib/api/indexes.ts";

export interface SearchHit {
  readonly entry: SearchEntry;
  readonly score: number;
}

const KIND_BONUS: Readonly<Record<SearchKind, number>> = {
  namespace: 6,
  widget: 6,
  function: 4,
  event: 4,
  structure: 3,
  enum: 3,
  method: 2,
  alias: 1,
  value: 0,
};

/** The last segment of a qualified name: `GetInfo` for `C_QuestLog.GetInfo`, `SetText` for `Button:SetText`. */
function leaf(name: string): string {
  const cut = Math.max(name.lastIndexOf("."), name.lastIndexOf(":"));
  return cut < 0 ? name : name.slice(cut + 1);
}

/** True when every character of `needle` appears in order in `haystack`. */
function isSubsequence(needle: string, haystack: string): boolean {
  let at = 0;
  for (const char of haystack) {
    if (char === needle[at]) {
      at += 1;
      if (at === needle.length) {
        return true;
      }
    }
  }
  return needle.length === 0;
}

/** Scores one name against a lower-cased query; 0 means no match. */
export function scoreName(name: string, query: string): number {
  const lower = name.toLowerCase();
  const tail = leaf(lower);
  if (lower === query || tail === query) {
    return 100;
  }
  if (tail.startsWith(query)) {
    return 80 - Math.min(tail.length - query.length, 20) / 2;
  }
  if (lower.startsWith(query)) {
    return 70 - Math.min(lower.length - query.length, 20) / 2;
  }
  const index = lower.indexOf(query);
  if (index >= 0) {
    return 50 - Math.min(index, 20) / 2;
  }
  if (query.length >= 3 && isSubsequence(query, lower)) {
    return 20 - Math.min(lower.length - query.length, 18) / 2;
  }
  return 0;
}

export function searchSymbols(
  entries: readonly SearchEntry[],
  rawQuery: string,
  kinds: ReadonlySet<SearchKind> | undefined,
  limit = 60,
): SearchHit[] {
  const query = rawQuery.trim().toLowerCase();
  if (query.length === 0) {
    return [];
  }
  const hits: SearchHit[] = [];
  for (const entry of entries) {
    if (kinds !== undefined && kinds.size > 0 && !kinds.has(entry[1])) {
      continue;
    }
    const base = scoreName(entry[0], query);
    if (base > 0) {
      hits.push({ entry, score: base + KIND_BONUS[entry[1]] - entry[3] * 5 });
    }
  }
  return hits.toSorted((a, b) => b.score - a.score || a.entry[0].localeCompare(b.entry[0], "en")).slice(0, limit);
}

export const KIND_LABELS: Readonly<Record<SearchKind, string>> = {
  namespace: "Namespace",
  function: "Function",
  value: "Value",
  widget: "Widget",
  method: "Method",
  event: "Event",
  enum: "Enum",
  structure: "Structure",
  alias: "Alias",
};
