// Every ```luau block on the site is type-checked at build time by luau-web-checker's Expressive Code plugin (Twoslash
// for Luau): `-- error` marks an expected error, `-- ---cut---` hides a prelude, and any other error fails the build.
// See the "Checked examples" page.
//
// This file adds what is particular to this site: API symbols link to their reference pages, with `data-sym` so the
// HoverCards island opens the same card as the API reference's links; everything else keeps the plugin's
// `data-luau-type` and `data-luau-error`, which HoverCards renders too (so the plugin's own tooltips are off).

import type { ExpressiveCodePlugin } from "@astrojs/starlight/expressive-code";
import type { Hover } from "luau-web-checker";
import type { HoverLink } from "luau-web-checker/expressive-code";
import { pluginLuauTypes } from "luau-web-checker/expressive-code";

import type { Catalog } from "../api/catalog.ts";
import { loadCatalog } from "../api/load.ts";
import { apiPaths } from "../api/paths.ts";
import { buildChecker } from "./build-checker.ts";

interface SymbolLink {
  readonly path: string;
  readonly sym: string;
}

/** The API page and hover card for an identifier, when the reference has one. */
export function symbolLink(catalog: Catalog, hover: Hover, previous: Hover | undefined): SymbolLink | undefined {
  switch (hover.kind) {
    case "global": {
      if (catalog.namespaces.has(hover.name)) {
        return { path: apiPaths.namespace(hover.name), sym: `namespace:${hover.name}` };
      }
      if (catalog.parsed.functions.some((fn) => fn.name === hover.name)) {
        return { path: apiPaths.global(hover.name), sym: `global:${hover.name}` };
      }
      return undefined;
    }
    case "property": {
      // `C_Item.GetItemInfo`: a member of a namespace, right after `C_Item.`.
      const ns = previous?.kind === "global" && previous.endColumn + 1 === hover.column ? previous.name : undefined;
      if (
        ns !== undefined &&
        previous?.line === hover.line &&
        catalog.namespaces.get(ns)?.members.some((member) => member.name === hover.name) === true
      ) {
        return { path: `${apiPaths.namespace(ns)}#${hover.name}`, sym: `namespace:${ns}` };
      }
      return undefined;
    }
    case "type": {
      // A type that is its own name (`Frame`) opens its reference card; one that expands (`EventHandler<"X">`
      // resolves to a function type) shows the expansion instead, which is the more useful answer there.
      const target = hover.type === hover.name ? catalog.resolve(hover.name) : undefined;
      return target === undefined ? undefined : { path: target.path, sym: `${target.card}:${target.name}` };
    }
    case "local":
      return undefined;
  }
}

/**
 * @param base The site's base path without a trailing slash (`/wow-forever-luau-types`), prefixed to API links.
 */
export function pluginLuauTypesForSite(base: string): ExpressiveCodePlugin {
  return pluginLuauTypes({
    checker: buildChecker,
    tooltips: false,
    link: (hover, previous): HoverLink | undefined => {
      const link = symbolLink(loadCatalog(), hover, previous);
      return link === undefined ? undefined : { href: `${base}${link.path}`, attributes: { "data-sym": link.sym } };
    },
  });
}
