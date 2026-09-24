# AI Papers

**A private research companion for AI engineers.** Every day it pulls new papers from arXiv and Hugging Face, and tells you which ones matter for *the system you actually run*: whether a paper applies, what you'd change, how much work it is, and whether there's code to start from.

It's a native macOS app, and all the work happens on your Mac. Summaries, analysis, search and Q&A run on a local model through [Ollama](https://ollama.com). There's no account, no cloud backend and no telemetry. Your notes and your stack description never leave the machine.

---

## What it does

**Finds papers.** It pulls from two sources: the newest arXiv submissions in AI and ML, and Hugging Face's daily papers (what the community upvoted). Papers you've already seen are never shown again. For every paper it looks up whether the **code and weights** are public. Hugging Face now holds Papers with Code's paper-to-repository links, so that's where they come from.

**Tells you if a paper is for you.** Describe your stack once, for example "RAG over pgvector, Llama 3.1 8B on vLLM, 800 ms p95". Each paper then gets a verdict (*applies / maybe / not for you*), the concrete change it suggests, and the effort: config change, code change, retraining or research. Papers that apply rise to the top of the dashboard and the widget.

**Keeps the numbers honest.** The **claims ledger** pulls each paper's headline results into one table, grouped by benchmark and metric, and marks when a newer paper beats an older one. A number is kept only if it appears in the paper's own abstract. Anything the model invents is dropped.

**Helps you implement it.** "Implement this" writes a step-by-step plan: prerequisites, the smallest experiment first, how you'll know it worked, and the risks. It uses the full paper text once you've opened the PDF. You tick the steps off as you go. The **lab notebook** records what you tried and whether it held up in your system.

**Helps you learn.** Ask "what is X?" and get a structured explanation: intuition, a worked example, a common misconception, and a question to check yourself. Equations are typeset. Save the question, and it comes back for spaced review after 1, 3, 7, 16 and 35 days.

**Everything else.**
- **Reading:** read the full paper in-app. The PDF is cached, so it works offline.
- **Search and Q&A:** search by meaning or by keyword. Ask your archive questions and get cited answers.
- **Triage and trends:** a keyboard triage mode, a weekly digest of themes and rising terms, and a connections graph across topics.
- **Exports and widgets:** export to Markdown or Obsidian, and use desktop widgets in three sizes.

## Requirements

- macOS 26.5 or later, Apple silicon recommended.
- [Ollama](https://ollama.com/download). On first launch the app checks for it and offers to download the two models it uses: `gemma4` for text and `mxbai-embed-large` for embeddings. That's a one-time download of a few GB. You can pick other installed models in Settings.
- An internet connection only for pulling new papers and PDFs. Everything else works offline, and there's a "Work offline" switch.

## Build

```sh
./install.sh   # builds Release and installs to /Applications
```

Or open `AIPapers.xcodeproj` in Xcode and run the `AIPapers` scheme.

## How it's built

SwiftUI, SwiftData and WidgetKit, in Swift. There are two small bundled web views: D3 for the connections graph and KaTeX for equations, both loaded from the app bundle, never from the network.

```
arXiv + Hugging Face → dedupe → relevance score → SwiftData (App Group, shared with the widget)
      → local model: summaries · topics · stack fit · claims · plans · explanations · answers
      → embeddings: related papers · semantic search · picks · connections · weekly themes
```

Model output is treated as untrusted. Titles, authors, dates and IDs always come from the source. Topics snap to a fixed taxonomy. Verdicts must be one of the allowed values. Claim numbers must appear in the abstract. Ranking stays deterministic, and a model's judgment is one signal, never the whole decision.

## Data sources and licences

- Paper metadata and PDFs: [arXiv](https://arxiv.org). Thank you to arXiv for use of its open access interoperability. PDFs are cached only on your Mac.
- Daily papers and code, model and dataset links: the [Hugging Face](https://huggingface.co/papers) public API.
- Bundled libraries: [D3](https://d3js.org) (ISC) and [KaTeX](https://katex.org) (MIT).
- Models are downloaded by Ollama under their own licences. None are bundled.
