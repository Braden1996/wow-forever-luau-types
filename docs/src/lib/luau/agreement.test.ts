// The site's checker (luau-web-checker) must agree with luau-lsp on this repository's own samples, the ones
// scripts/test.luau runs luau-lsp over:
//   tests/pass/<addon>/, templates/<name>/   zero diagnostics, with the addon's own .d.luau files loaded
//   tests/fail/*.luau                        exactly the diagnostics in tests/fail/<name>.expected
// So the code blocks are never checked by something that disagrees with the editor.

import { describe, expect, test } from "bun:test";
import { readdirSync, readFileSync, statSync } from "node:fs";
import { join, relative } from "node:path";

import { Checker } from "luau-web-checker";

import { findRepoRoot, readDefinitionsSource } from "../api/load.ts";
import { readDisabledGlobals } from "./build-checker.ts";

const root = findRepoRoot();
const definitions = readDefinitionsSource(root);
const disabledGlobals = readDisabledGlobals(root);
const read = (path: string): string => readFileSync(path, "utf8").replaceAll("\r\n", "\n");

// Loading the 1.7 MB definitions takes a few seconds per checker.
const LOAD_TIMEOUT = 60_000;

function luauFiles(dir: string): string[] {
  return readdirSync(dir)
    .toSorted()
    .flatMap((entry) => {
      const path = join(dir, entry);
      if (statSync(path).isDirectory()) {
        return entry.startsWith(".") ? [] : luauFiles(path);
      }
      return entry.endsWith(".luau") ? [path] : [];
    });
}

function create(addonDefinitions: readonly string[]): Promise<Checker> {
  return Checker.create({
    definitions: Object.fromEntries([
      ["@wow", definitions],
      ...addonDefinitions.map((file, index) => [`@addon${String(index + 1)}`, read(file)]),
    ]),
    disabledGlobals,
  });
}

const passDirs = ["tests/pass", "templates"].flatMap((parent) =>
  readdirSync(join(root, parent))
    .toSorted()
    .map((name) => join(root, parent, name))
    .filter((path) => statSync(path).isDirectory()),
);

describe("passing samples and templates: no diagnostics", () => {
  test.each(passDirs.map((dir) => relative(root, dir)))(
    "%s",
    async (dir) => {
      // A template's types/wow-forever.d.luau is a user's downloaded copy; the generated file is loaded instead.
      const files = luauFiles(join(root, dir)).filter(
        (file) => !file.replaceAll("\\", "/").endsWith("/types/wow-forever.d.luau"),
      );
      const checker = await create(files.filter((file) => file.endsWith(".d.luau")));
      try {
        const sources = files.filter((file) => !file.endsWith(".d.luau"));
        expect(sources.length).toBeGreaterThan(0);
        for (const file of sources) {
          checker.setSource(relative(root, file), read(file));
        }
        const reported = sources.flatMap((file) =>
          checker
            .check(relative(root, file))
            .map((d) => `${relative(root, file)}:${String(d.line)}:${String(d.column)}: ${d.kind}: ${d.message}`),
        );
        expect(reported).toEqual([]);
      } finally {
        checker.dispose();
      }
    },
    LOAD_TIMEOUT,
  );
});

describe("failing samples: exactly the .expected diagnostics", () => {
  const failDir = join(root, "tests", "fail");
  const files = readdirSync(failDir)
    .filter((file) => file.endsWith(".luau"))
    .toSorted();

  test(
    "every tests/fail sample",
    async () => {
      expect(files.length).toBeGreaterThan(0);
      const checker = await create([]);
      try {
        for (const file of files) {
          checker.setSource(file, read(join(failDir, file)));
          const actual = `${checker
            .check(file)
            .map((d) => `${String(d.line)}:${String(d.column)}: ${d.kind}: ${d.message}`)
            .join("\n")}\n`;
          const expected = read(join(failDir, file.replace(/\.luau$/u, ".expected")));
          expect({ file, diagnostics: actual }).toEqual({ file, diagnostics: expected });
          checker.removeSource(file);
        }
      } finally {
        checker.dispose();
      }
    },
    LOAD_TIMEOUT,
  );
});
