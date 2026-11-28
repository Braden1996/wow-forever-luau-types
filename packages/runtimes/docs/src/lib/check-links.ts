// Offline link check of the built site: every internal href must name an emitted page, and every #anchor an id on
// that page. The Astro build fails if a link is broken.

import { existsSync, readdirSync, readFileSync, statSync } from "node:fs";
import { join } from "node:path";

import { BASE } from "./base.ts";

function htmlFiles(dir: string): string[] {
  return readdirSync(dir).flatMap((entry) => {
    const path = join(dir, entry);
    if (statSync(path).isDirectory()) {
      return entry === "pagefind" ? [] : htmlFiles(path);
    }
    return path.endsWith(".html") ? [path] : [];
  });
}

const idCache = new Map<string, ReadonlySet<string>>();

function idsOf(file: string): ReadonlySet<string> {
  let ids = idCache.get(file);
  if (ids === undefined) {
    ids = new Set([...readFileSync(file, "utf8").matchAll(/ id="([^"]+)"/g)].map((match) => match[1] ?? ""));
    idCache.set(file, ids);
  }
  return ids;
}

function problemWith(href: string, dist: string): string | undefined {
  const [path = "", hash] = href.slice(BASE.length).split("#");
  const target = path === "" || path.endsWith("/") ? join(dist, path, "index.html") : join(dist, path);
  if (!existsSync(target)) {
    return "missing page";
  }
  if (
    hash !== undefined &&
    hash.length > 0 &&
    target.endsWith(".html") &&
    !idsOf(target).has(decodeURIComponent(hash))
  ) {
    return "missing anchor";
  }
  return undefined;
}

export function checkLinks(dist: string): string {
  idCache.clear();
  const broken = new Map<string, string[]>();
  const files = htmlFiles(dist);
  for (const file of files) {
    for (const match of readFileSync(file, "utf8").matchAll(/href="([^"]+)"/g)) {
      const href = (match[1] ?? "").replaceAll("&amp;", "&");
      if (!href.startsWith(BASE)) {
        continue;
      }
      const problem = problemWith(href, dist);
      if (problem !== undefined) {
        const key = `${problem}: ${href}`;
        broken.set(key, [...(broken.get(key) ?? []), file]);
      }
    }
  }

  if (broken.size > 0) {
    for (const [key, from] of broken) {
      console.error(`${key} (from ${from.length} pages, e.g. ${from[0] ?? ""})`);
    }
    throw new Error(`${broken.size} broken internal links in ${files.length} pages`);
  }
  return `${files.length} pages, no broken internal links`;
}
