// The code-block conventions (snippets.ts): hidden preludes, `-- error` marks and what fails the build.

import { afterAll, beforeAll, describe, expect, test } from "bun:test";

import { Checker } from "luau-web-checker";

import { checkSnippet, isDefinitionsFile, SnippetError } from "./snippets.ts";

let checker: Checker;

beforeAll(async () => {
  checker = await Checker.create({
    definitions: { "@test": "declare function GetMoney(): number\ndeclare function SetName(name: string): ()\n" },
    strict: true,
  });
});

afterAll(() => {
  checker.dispose();
});

describe("checkSnippet", () => {
  test("a clean block gives hovers and no errors", () => {
    const checked = checkSnippet(checker, "a.luau", "local money = GetMoney()\nlocal doubled = money * 2");
    expect(checked.hidden).toBe(0);
    expect(checked.errors).toEqual([]);
    expect(checked.hovers.find((hover) => hover.name === "doubled")).toMatchObject({ line: 2, type: "number" });
  });

  test("a hidden prelude is checked, and positions count from the first shown line", () => {
    const checked = checkSnippet(checker, "b.luau", "local prefix = 'x'\n-- ---cut---\nSetName(prefix)");
    expect(checked.hidden).toBe(2);
    expect(checked.hovers.map((hover) => [hover.line, hover.name])).toEqual([
      [1, "SetName"],
      [1, "prefix"],
    ]);
  });

  test("a marked line must have an error, and keeps it for display", () => {
    const checked = checkSnippet(checker, "c.luau", "SetName(1) -- error: a number is not a string");
    expect(checked.errors).toHaveLength(1);
    expect(checked.errors[0]).toMatchObject({ line: 1, kind: "TypeError" });
  });

  test("an unmarked error fails", () => {
    expect(() => checkSnippet(checker, "d.luau", "SetName(1)")).toThrow(SnippetError);
  });

  test("a mark without an error fails", () => {
    expect(() => checkSnippet(checker, "e.luau", 'SetName("ok") -- error')).toThrow("has no error");
  });

  test("an error in the hidden prelude fails", () => {
    expect(() => checkSnippet(checker, "f.luau", "SetName(1)\n-- ---cut---\nlocal _ = 1")).toThrow("hidden prelude");
  });

  test("lint warnings are not errors", () => {
    expect(checkSnippet(checker, "g.luau", "local unused = 1").errors).toEqual([]);
  });

  test("the module is removed afterwards", () => {
    checkSnippet(checker, "h.luau", "local x = 1");
    expect(checker.check("h.luau")).toEqual([]);
  });
});

test("definitions files are recognised by a top-level declare", () => {
  expect(isDefinitionsFile("export type DB = { n: number }\ndeclare MyDB: DB?")).toBe(true);
  expect(isDefinitionsFile("local declared = 1")).toBe(false);
});
