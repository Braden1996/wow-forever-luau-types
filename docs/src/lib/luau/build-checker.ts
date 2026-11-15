// Build-time only: one luau-web-checker instance for the whole build, set up as an addon's editor is (the generated
// definitions as `@wow`, definitions/luau-lsp.settings.json's disabled globals) and strict by default, as the guides
// recommend. The guides' example addon has its own definitions file (example-addon.d.luau, `@example`), as a real
// addon does. Loading the definitions takes a few seconds, so it happens once per process.

import { readFileSync } from "node:fs";
import { join } from "node:path";

import { Checker } from "luau-web-checker";

import { findRepoRoot, readDefinitionsSource } from "../api/load.ts";

const SETTINGS_KEY = "luau-lsp.types.disabledGlobals";

export function readDisabledGlobals(root: string): string[] {
  const settings: unknown = JSON.parse(readFileSync(join(root, "definitions", "luau-lsp.settings.json"), "utf8"));
  const names: unknown =
    typeof settings === "object" && settings !== null
      ? Object.entries(settings).find(([key]) => key === SETTINGS_KEY)?.[1]
      : undefined;
  if (!Array.isArray(names) || !names.every((name): name is string => typeof name === "string")) {
    throw new TypeError(`definitions/luau-lsp.settings.json: ${SETTINGS_KEY} is not a list of names`);
  }
  return names;
}

let shared: Promise<Checker> | undefined;

export function buildChecker(): Promise<Checker> {
  shared ??= (async () => {
    const root = findRepoRoot();
    const checker = await Checker.create({
      definitions: {
        "@wow": readDefinitionsSource(root),
        "@example": readFileSync(join(root, "docs", "src", "lib", "luau", "example-addon.d.luau"), "utf8"),
      },
      disabledGlobals: readDisabledGlobals(root),
      strict: true,
    });
    if (checker.unknownGlobals.length > 0) {
      throw new Error(
        `luau-lsp.settings.json disables globals that do not exist: ${checker.unknownGlobals.join(", ")}`,
      );
    }
    return checker;
  })();
  return shared;
}
