// The theme's hover cards (starlight-warcraft), plus this site's own source: every `a[data-sym]` opens the API
// reference card for that symbol, fetched lazily from the static /api/cards/<kind>.json shards. The theme handles
// the checked Luau code blocks' inferred types (`data-luau-type`) and errors (`data-luau-error`) itself. Mounted once
// per page from the footer override; renders nothing until a hover.

import type { ReactElement } from "react";
import type { HoverCardData, HoverCardSource } from "starlight-warcraft/react";
import { HoverCards } from "starlight-warcraft/react";

import type { CardData } from "./load-index.ts";
import { loadCard } from "./load-index.ts";

/** An API reference card as a theme hover card: rare (blue) when typed, uncommon (green) when untyped. */
export function symbolCard(card: CardData): HoverCardData {
  const detail =
    card.status === undefined ? "" : ` · ${card.status}${card.source === undefined ? "" : ` (${card.source})`}`;
  const base = { title: card.title, kind: `${card.kind}${detail}`, body: card.snippet };
  if (card.status === "typed") {
    return { ...base, quality: "rare" };
  }
  if (card.status === "untyped") {
    return { ...base, quality: "uncommon" };
  }
  return base;
}

const SOURCES: readonly HoverCardSource[] = [
  {
    selector: "a[data-sym]",
    load: async (anchor) => {
      const symbol = anchor.dataset["sym"];
      const card = symbol === undefined ? undefined : await loadCard(symbol);
      return card === undefined ? undefined : symbolCard(card);
    },
  },
];

export const SiteHoverCards = (): ReactElement => <HoverCards sources={SOURCES} />;
