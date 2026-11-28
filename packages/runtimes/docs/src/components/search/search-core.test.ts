import { describe, expect, test } from "bun:test";

import type { SearchEntry, SearchKind } from "../../lib/api/indexes.ts";
import { scoreName, searchSymbols } from "./search-core.ts";

const entries: SearchEntry[] = [
  ["C_QuestLog", "namespace", "/api/namespaces/C_QuestLog/", 0],
  ["C_QuestLog.GetInfo", "function", "/api/namespaces/C_QuestLog/#GetInfo", 0],
  ["C_QuestLog.GetInfoForQuest", "function", "/api/namespaces/C_QuestLog/#GetInfoForQuest", 0],
  ["Button:SetText", "method", "/api/widgets/Button/#SetText", 0],
  ["QuestInfo", "structure", "/api/structures/QuestInfo/", 0],
  ["QuestFrame_OnLoad", "function", "/api/globals/q/#QuestFrame_OnLoad", 1],
  ["PLAYER_LEVEL_UP", "event", "/api/events/PLAYER_LEVEL_UP/", 0],
];

describe("scoreName", () => {
  test("ranks exact over prefix over substring over subsequence", () => {
    const exact = scoreName("C_QuestLog.GetInfo", "getinfo");
    const prefix = scoreName("C_QuestLog.GetInfoForQuest", "getinfo");
    const substring = scoreName("PLAYER_LEVEL_UP", "level");
    const subsequence = scoreName("PLAYER_LEVEL_UP", "plu");
    expect(exact).toBeGreaterThan(prefix);
    expect(prefix).toBeGreaterThan(substring);
    expect(substring).toBeGreaterThan(subsequence);
    expect(subsequence).toBeGreaterThan(0);
    expect(scoreName("QuestInfo", "zzz")).toBe(0);
  });
});

describe("searchSymbols", () => {
  test("finds a namespace member by its leaf name", () => {
    expect(searchSymbols(entries, "GetInfo", undefined)[0]?.entry[0]).toBe("C_QuestLog.GetInfo");
  });

  test("ranks untyped functions below typed ones", () => {
    const names = searchSymbols(entries, "quest", undefined).map((hit) => hit.entry[0]);
    expect(names.indexOf("QuestFrame_OnLoad")).toBeGreaterThan(names.indexOf("QuestInfo"));
  });

  test("filters by kind", () => {
    const kinds = new Set<SearchKind>(["event"]);
    expect(searchSymbols(entries, "l", kinds).map((hit) => hit.entry[0])).toEqual(["PLAYER_LEVEL_UP"]);
  });

  test("an empty query returns nothing", () => {
    expect(searchSymbols(entries, "   ", undefined)).toEqual([]);
  });
});
