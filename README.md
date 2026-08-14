# AIPapers

A native macOS app that answers one question every day: **what AI engineering research should I read today?**

It's a local research companion, not an RSS reader — it fetches new arXiv papers, filters for AI-engineering relevance, summarizes them with a local LLM, remembers what you've already seen, and surfaces how papers relate to each other. Everything runs on-device: no cloud backend, no account, no telemetry. Summarization and embeddings go through [Ollama](https://ollama.com) running locally.

Built with SwiftUI + SwiftData, macOS 14+.

---

## Product principle

The app progressively answers, in order:

```
What is new?  →  What matters?  →  Why does it matter?  →  Have I seen this before?  →  What have I already learned?
```

Recency alone doesn't drive the ranking — relevance does.

---

## Core features

### Dashboard
The home screen. Shows papers ranked by relevance score (not just recency), pulled from arXiv every day. A refresh button re-fetches; auto-refresh runs once per day on launch. Each row shows title, authors, a category tag, and whether a summary exists yet.

### Archive
The full, searchable history of every paper ever ingested (search matches title/authors/category). Includes a **"Generate Summaries"** button that batch-processes every paper still missing a summary, with a live progress banner ("Generating summaries: 3 of 9 · 45s elapsed") that persists across navigation — starting it and switching to another screen doesn't stop it.

### Paper detail
Full abstract, arXiv link, favorite/read toggles. Summaries are **on-demand, not automatic** — opening a paper does not summarize it; a "Generate Summary" button triggers a single Ollama call that produces:
- a short technical summary
- a "why it matters" note for an AI engineer specifically
- a relevance re-score once the model's own judgment is available

Also shows a **Related Papers** list (see Knowledge Graph below) — the same similarity data as the graph, in list form, scoped to just this paper.

### Knowledge Graph
A force-directed, drag-to-explore visualization of how papers relate to each other **by content**, not by tag — each paper's title+abstract is embedded into a vector, and edges connect papers above a cosine-similarity threshold. Papers cluster visually into connected components, colored with a validated categorical palette (a handful of distinct hues + gray for everything not strongly connected); each cluster is labeled with the AI-engineering topic(s) most common among its edges (e.g. "LLM & Evaluation"). Node titles only show on hover or selection — with 50–100+ papers on screen, always-on labels are unreadable clutter, so the graph leans on color + structure at a glance and text on demand (this mirrors how Obsidian's graph view works). Clicking a node opens that paper.

Embeddings generate automatically as part of the daily refresh (they're cheap — well under a second each), not on-demand — the graph should already be populated after your first refresh, not require manually opening dozens of papers first.

### Trend Brief
Once a day, the app synthesizes a ~450-word ("2–3 minute read") narrative across your ~15 highest-relevance papers, answering "where is the field collectively heading," not "what does paper X say." This is a genuinely different task from per-paper summarization — it reasons over a batch, cites specific papers/themes, and is generated once daily (not on every refresh, since it's a much heavier prompt). Shown in full in-app; a compact teaser (a couple of lines) shows in the desktop widget with tap-through to read the rest.

### Widget
A macOS desktop/Notification Center widget, available in small/medium/large/extra-large sizes, showing the Trend Brief teaser — not a paper list. WidgetKit has no scrolling, so larger sizes just show more text, capped by size; the widget is a teaser surface, the app is where you actually read.

### Settings
Three knobs, reachable via ⌘, : how many papers to fetch per refresh, the topic vocabulary used for relevance scoring and graph topic-labeling, and which locally-installed Ollama model to use (auto-detected from `ollama list`).

---

## Pipeline (for context, not something the UI exposes directly)

```
arXiv fetch → exact-ID dedup → deterministic relevance score (topic keywords + recency)
           → SwiftData (shared App Group container, also read by the widget)
           → [on-demand from here] Ollama summary · embedding · related-papers · trend brief
```

Relevance scoring is deterministic by default (topic keyword match + recency decay); once a paper has a summary, the LLM's own relevance estimate is blended in as a minority signal — the ranking never depends solely on an opaque model judgment.

---

## Navigation structure

Single window, 3-column `NavigationSplitView`:

```
Sidebar          Content column              Detail column
────────         ──────────────────           ─────────────────
Dashboard   →    ranked paper list      →     selected paper
Archive     →    searchable full list   →     (same detail view)
Graph       →    force-directed canvas  →     (sidebar auto-hides here — canvas wants the room)
Trend Brief →    full brief text
```

A persistent status banner sits above all three columns (visible regardless of which sidebar item is selected) — it's the one place refresh progress, batch-summarize progress, and errors surface, since background work is intentionally not tied to any one screen's lifecycle.

---

## Current visual direction

**Technical high-contrast** — light mode only (locked, ignores system dark mode), pure black-on-white, inspired by Linear/Raycast rather than a soft native-iOS look. Rules currently in place:

- Sharp corners everywhere (2px radius), no soft/rounded pills, no blurred `.regularMaterial` backgrounds — flat white with a 1px black border instead.
- Monospace (SF Mono) reserved *only* for metadata: dates, relevance %, similarity %, category codes, cluster labels. Never for titles or body text.
- Titles are bold with slightly tightened letter-spacing.
- Color is reserved for meaning: yellow = favorited, the graph's categorical palette = cluster identity, red = error (always paired with an icon/label, never color alone).
- Accent color is pure black.

The app icon is a pixel-art black-line folder-with-a-face on a transparent background — the high-contrast direction was chosen to complement it, not to match any particular reference app exactly.

## Known rough edges worth design attention

- The graph gets dense fast (50–100+ nodes at typical archive sizes) — current mitigation is hover-only labels + a 3-color cluster cap (rest render gray), but layout/legibility at real scale hasn't been stress-tested past ~100 papers.
- The widget's teaser is plain text truncated by line count; there's no visual hierarchy within it yet (no distinguishing the "headline" sentence from the rest).
- No onboarding/empty-state design pass beyond basic `ContentUnavailableView` placeholders.
- Settings is a bare native `Form` — functional, not designed.
