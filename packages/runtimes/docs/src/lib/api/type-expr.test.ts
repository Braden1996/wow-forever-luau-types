import { describe, expect, test } from "bun:test";

import {
  functionOverloads,
  isUntypedFunction,
  parseFunctionType,
  referencedTypes,
  splitTopLevel,
  stripOuterParens,
  tokenize,
} from "./type-expr.ts";

describe("splitTopLevel", () => {
  test("ignores separators inside brackets and arrows", () => {
    expect(splitTopLevel("a: { [number]: T }, b: (x: U) -> V, c: index<M, K>", ",")).toEqual([
      "a: { [number]: T }",
      "b: (x: U) -> V",
      "c: index<M, K>",
    ]);
  });

  test("ignores separators inside string literals", () => {
    expect(splitTopLevel('"a|b" | "c"', "|")).toEqual(['"a|b"', '"c"']);
  });
});

describe("stripOuterParens", () => {
  test("strips only a wrapping pair", () => {
    expect(stripOuterParens("((a) -> b)")).toBe("(a) -> b");
    expect(stripOuterParens("(a) -> (b)")).toBe("(a) -> (b)");
  });
});

describe("parseFunctionType", () => {
  test("reads parameters, optionality, variadics and returns", () => {
    expect(parseFunctionType("(button: string?, ...ClickButton) -> ()")).toEqual({
      generics: undefined,
      params: [
        { name: "button", type: "string?", optional: true, variadic: false },
        { name: undefined, type: "ClickButton", optional: false, variadic: true },
      ],
      returns: "()",
    });
  });

  test("reads generics", () => {
    const shape = parseFunctionType("<K>(frameType: K & keyof<FrameTypeMap>) -> index<FrameTypeMap, K>");
    expect(shape?.generics).toBe("K");
    expect(shape?.returns).toBe("index<FrameTypeMap, K>");
  });

  test("rejects non-function types", () => {
    expect(parseFunctionType("{ [string]: number }")).toBeUndefined();
    expect(parseFunctionType("(number, string)")).toBeUndefined();
  });
});

describe("functionOverloads", () => {
  test("splits an intersection of function types", () => {
    const overloads = functionOverloads("((id: number) -> string) & ((a: number, b: number) -> ())");
    expect(overloads.map((shape) => shape.params.length)).toEqual([1, 2]);
  });

  test("returns nothing for a value type", () => {
    expect(functionOverloads("Frame")).toEqual([]);
  });
});

describe("tokens", () => {
  test("classifies names, builtins, types and strings", () => {
    const kinds = tokenize('(info: QuestInfo?, kind: "a") -> number').flatMap((token) =>
      token.kind === "space" || token.kind === "punct" ? [] : [`${token.kind}:${token.text}`],
    );
    expect(kinds).toEqual(["name:info", "type:QuestInfo", "name:kind", 'string:"a"', "builtin:number"]);
  });

  test("lists referenced types once", () => {
    expect(referencedTypes("(a: Frame, b: Frame?) -> { Texture }")).toEqual(["Frame", "Texture"]);
  });

  test("recognises the untyped placeholder", () => {
    expect(isUntypedFunction("(...unknown) -> (...unknown)")).toBe(true);
    expect(isUntypedFunction("() -> ()")).toBe(false);
  });
});
