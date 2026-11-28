// Checks the build-time model against the real generated files, so a generator change that the parser does not
// understand fails here rather than silently dropping pages.

import { describe, expect, test } from "bun:test";

import { coverageTotals } from "./coverage.ts";
import { buildCards, buildSearchIndex } from "./indexes.ts";
import { loadCatalog, readReport } from "./load.ts";
import { apiPaths } from "./paths.ts";

const catalog = loadCatalog();
const { parsed } = catalog;

function reportCount(key: string): number {
  const report = readReport();
  if (typeof report !== "object" || report === null || !("counts" in report)) {
    throw new Error("report.json has no counts");
  }
  const counts: unknown = report.counts;
  if (typeof counts !== "object" || counts === null || !(key in counts)) {
    throw new Error(`report.json has no counts.${key}`);
  }
  const value: unknown = Object.entries(counts).find(([name]) => name === key)?.[1];
  if (typeof value !== "number") {
    throw new Error(`counts.${key} is not a number`);
  }
  return value;
}

describe("the parsed definitions match the generator's report", () => {
  test("every event, enum and widget is parsed", () => {
    expect(parsed.events.length).toBe(coverageTotals(catalog.coverage, "events").typed);
    expect(parsed.enums.length).toBe(coverageTotals(catalog.coverage, "enums").typed);
    expect(parsed.widgets.length).toBe(
      reportCount("widgets") + reportCount("scriptObjects") + reportCount("widgetMixins"),
    );
  });

  test("every global table is parsed (Enum is modelled separately)", () => {
    expect(parsed.namespaces.length + 1).toBe(reportCount("globalTables"));
  });

  test("the widget hierarchy is connected", () => {
    for (const widget of parsed.widgets) {
      if (widget.parent !== undefined) {
        expect(catalog.widgets.has(widget.parent)).toBe(true);
      }
    }
    expect(catalog.widgetChain("Button").map((link) => link.name)).toEqual([
      "Button",
      "Frame",
      "ScriptRegion",
      "Object",
      "FrameScriptObject",
    ]);
  });

  test("CreateFrame's frame types are creatable widgets", () => {
    for (const frameType of parsed.frameTypes) {
      expect(catalog.widgets.get(frameType)?.creatable).toBe(true);
    }
  });
});

describe("cross-references", () => {
  test("type names resolve to pages", () => {
    expect(catalog.resolve("QuestInfo")?.path).toBe(apiPaths.structure("QuestInfo"));
    expect(catalog.resolve("Enum_ItemQuality")?.path).toBe(apiPaths.enumPage("ItemQuality"));
    expect(catalog.resolve("ButtonScriptType")?.path).toBe(`${apiPaths.widget("Button")}#scripts`);
    expect(catalog.resolve("NotAType")).toBeUndefined();
  });

  test("used-by lists the APIs that mention a type", () => {
    const labels = catalog.usedBy({ path: "", card: "structure", name: "QuestInfo" }).map((ref) => ref.label);
    expect(labels).toContain("C_QuestLog.GetInfo");
  });
});

describe("static output", () => {
  test("page slugs do not collide on a case-insensitive file system", () => {
    const groups = [
      parsed.namespaces.map((entry) => entry.name),
      parsed.widgets.map((entry) => entry.name),
      parsed.events.map((entry) => entry.name),
      parsed.enums.map((entry) => entry.name),
      parsed.structures.map((entry) => entry.name),
    ];
    for (const names of groups) {
      expect(new Set(names.map((name) => name.toLowerCase())).size).toBe(names.length);
    }
  });

  test("the search index and cards cover every page kind", () => {
    const kinds = new Set<string>(buildSearchIndex(catalog).map((entry) => entry[1]));
    expect([...kinds].toSorted()).toEqual(
      ["alias", "enum", "event", "function", "method", "namespace", "structure", "value", "widget"].toSorted(),
    );
    expect([...buildCards(catalog).keys()].map(String).toSorted()).toEqual(
      ["alias", "enum", "event", "global", "namespace", "structure", "widget"].toSorted(),
    );
  });
});
