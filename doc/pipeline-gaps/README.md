# Pipeline Gaps

Docs mapping where `print_widget` sits versus a "99% fidelity" design→Flutter pipeline.

| File | What it is |
|------|-----------|
| `gaps-analysis.md` | Empirical post-mortem from the April 2026 CRM build (27 atoms + 23 molecules from Lovable). Concrete CLI/skill changes proposed from observed failures. |
| `ai-flutter-99-research.md` | External research: theoretical framework for design→Flutter AI pipelines at 95–99% fidelity. Covers IR/DSL, DTCG tokens, JSON Schema, multi-metric validation, self-revision loops. |

Both arrive at the same diagnosis from opposite directions: the pipeline needs a **structured intermediate representation** (per-element design spec) between pixels and Flutter code. The gaps-analysis proposes the concrete `extract --spec` / `scaffold` / `tokenize` / `snapshot` commands; the research provides the theoretical backing (Design2Code, ScreenCoder, DCGen, DTCG).
