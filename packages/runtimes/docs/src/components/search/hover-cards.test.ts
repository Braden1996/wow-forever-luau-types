import { describe, expect, test } from "bun:test";

import { symbolCard } from "./hover-cards.tsx";

const CARD = { title: "print", kind: "global function", snippet: "function print(...: any)", path: "/api/globals/p/" };

describe("symbolCard", () => {
  test("shows a typed symbol as a rare card with its status and source", () => {
    expect(symbolCard({ ...CARD, status: "typed", source: "Blizzard" })).toEqual({
      title: "print",
      kind: "global function · typed (Blizzard)",
      body: "function print(...: any)",
      quality: "rare",
    });
  });

  test("shows an untyped symbol as an uncommon card", () => {
    expect(symbolCard({ ...CARD, status: "untyped", source: undefined }).quality).toBe("uncommon");
  });

  test("leaves a symbol without a status at the common quality", () => {
    expect(symbolCard({ ...CARD, status: undefined, source: undefined })).toEqual({
      title: "print",
      kind: "global function",
      body: "function print(...: any)",
    });
  });
});
