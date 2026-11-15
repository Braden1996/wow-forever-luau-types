// Hover cards for every `a[data-sym]` on the page: one delegated listener, cards fetched lazily from the static
// /api/cards/<kind>.json shards. Mounted once per page from the footer override; renders nothing until a hover.

import type { ReactElement } from "react";

import type { CardData } from "./load-index.ts";

import { useEffect, useRef, useState } from "react";

import { loadCard } from "./load-index.ts";

interface Shown {
  readonly card: CardData;
  readonly top: number;
  readonly left: number;
  readonly below: boolean;
}

const OPEN_DELAY = 250;
const CLOSE_DELAY = 150;
const CARD_WIDTH = 440;

function anchorOf(target: EventTarget | null): HTMLAnchorElement | undefined {
  if (!(target instanceof Element)) {
    return undefined;
  }
  const anchor = target.closest("a[data-sym]");
  return anchor instanceof HTMLAnchorElement ? anchor : undefined;
}

function place(anchor: HTMLElement, card: CardData): Shown {
  const rect = anchor.getBoundingClientRect();
  const below = rect.top < window.innerHeight / 2;
  const left = Math.max(8, Math.min(rect.left, window.innerWidth - CARD_WIDTH - 8));
  return { card, left, below, top: below ? rect.bottom + 6 : window.innerHeight - rect.top + 6 };
}

export const HoverCards = (): ReactElement | null => {
  const [shown, setShown] = useState<Shown | undefined>(undefined);
  const openTimer = useRef<number | undefined>(undefined);
  const closeTimer = useRef<number | undefined>(undefined);
  const current = useRef<HTMLAnchorElement | undefined>(undefined);

  useEffect(() => {
    const cancelOpen = (): void => {
      window.clearTimeout(openTimer.current);
    };
    const scheduleClose = (): void => {
      window.clearTimeout(closeTimer.current);
      closeTimer.current = window.setTimeout(() => {
        current.current = undefined;
        setShown(undefined);
      }, CLOSE_DELAY);
    };
    const open = (anchor: HTMLAnchorElement): void => {
      window.clearTimeout(closeTimer.current);
      cancelOpen();
      current.current = anchor;
      openTimer.current = window.setTimeout(() => {
        const symbol = anchor.dataset["sym"];
        if (symbol === undefined) {
          return;
        }
        loadCard(symbol).then(
          (card) => {
            if (card !== undefined && current.current === anchor) {
              setShown(place(anchor, card));
            }
          },
          () => {
            setShown(undefined);
          },
        );
      }, OPEN_DELAY);
    };
    const onOver = (event: Event): void => {
      const anchor = anchorOf(event.target);
      if (anchor !== undefined && anchor !== current.current) {
        open(anchor);
      }
    };
    const onOut = (event: Event): void => {
      if (anchorOf(event.target) !== undefined) {
        cancelOpen();
        scheduleClose();
      }
    };
    const onKey = (event: KeyboardEvent): void => {
      if (event.key === "Escape") {
        setShown(undefined);
      }
    };
    document.addEventListener("pointerover", onOver);
    document.addEventListener("pointerout", onOut);
    document.addEventListener("focusin", onOver);
    document.addEventListener("focusout", onOut);
    document.addEventListener("keydown", onKey);
    window.addEventListener("scroll", scheduleClose, { passive: true });
    return () => {
      document.removeEventListener("pointerover", onOver);
      document.removeEventListener("pointerout", onOut);
      document.removeEventListener("focusin", onOver);
      document.removeEventListener("focusout", onOut);
      document.removeEventListener("keydown", onKey);
      window.removeEventListener("scroll", scheduleClose);
      cancelOpen();
      window.clearTimeout(closeTimer.current);
    };
  }, []);

  if (shown === undefined) {
    return null;
  }
  const { card } = shown;
  const position = shown.below ? { top: shown.top } : { bottom: shown.top };
  const quality = card.status === "untyped" ? "wc-tooltip-uncommon" : card.status === "typed" ? "wc-tooltip-rare" : "wc-tooltip";
  return (
    <div
      role="tooltip"
      className={`hover-card fantasy wc-tooltip-base ${quality}`}
      style={{ ...position, left: shown.left, width: CARD_WIDTH }}
      onPointerEnter={() => {
        window.clearTimeout(closeTimer.current);
      }}
      onPointerLeave={() => {
        setShown(undefined);
        current.current = undefined;
      }}
    >
      <div className="hover-card-head">
        <span className="hover-card-title">{card.title}</span>
        <span className="hover-card-kind">
          {card.kind}
          {card.status !== undefined && ` · ${card.status}${card.source === undefined ? "" : ` (${card.source})`}`}
        </span>
      </div>
      <pre className="hover-card-snippet">
        <code>{card.snippet}</code>
      </pre>
    </div>
  );
};
