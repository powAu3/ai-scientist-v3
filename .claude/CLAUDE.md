# AI Scientist v3 - Customer Review-Backed Paper Mode

Autonomous AI research writer for low-compute settings. The agent still produces
a complete paper, but it replaces the experiment-running phase with a rigorous
experiment-rationality review and clearly labeled predicted results. The paper
must be honest: it may present a study proposal, protocol, design analysis,
feasibility audit, threats-to-validity review, and predicted/expected outcomes,
but it must not claim that predicted results were actually measured.
Do not call these values fake. Treat them as protocol-estimated or
literature-calibrated forecasts with explicit evidence status, assumptions, and
replacement points for future measured runs.

This branch contract is `customer-review-backed-paper-mode`. Its sibling
`customer-normal-experiment-mode` is for real empirical runs when compute and
data access are available. Do not silently switch this branch into experiment
execution mode.

## Workspace

- `experiment_review.md` - Primary evidence artifact: experiment-rationality review
- `review.json` - Required structured companion with strict gate scores
- `preflight_repair.md` - Required when the proposed experiment is not runnable as-is
- `revised_experiment_protocol.md` - Required repaired protocol when the gate fails
- `predicted_results/predicted_results.csv` - Required predicted, non-measured data
- `figures/` - Required figures made from predicted data or review scorecards
- `latex/` - ICLR 2025 workshop template; fill `latex/template.tex`
  and export `latex/template.pdf` plus `latex/template.docx`
- `literature/` - Paper index, notes, citations, and related-work evidence
- `manuscript_explanation.md` - Separate reader note for provenance, forecast
  replacement triggers, and the PDF-as-effect-test framing
- `reviews/` - Optional direct review artifacts when not using `submissions/`
- `submissions/` - Versioned snapshots created by `scripts/submit_for_review.sh`
- `blank_icbinb_latex/` - Clean LaTeX template copied to `latex/` in Harbor
- `/search-papers` - Skill for checking related work, baselines, and novelty claims

Package installation should be minimal. Do not download large datasets, train
models, tune hyperparameters, run benchmark suites, or generate fake results.
Lightweight shell commands for file inspection, LaTeX compilation, and small
metadata checks are fine.

API keys, if configured:
- `S2_API_KEY` - Semantic Scholar, higher rate limits
- `OPENALEX_API_KEY` - OpenAlex, expanded paper lookup
- `HF_TOKEN` - HuggingFace metadata lookup only; do not download large datasets
- `OPENAI_API_KEY`, `GEMINI_API_KEY`, `GOOGLE_API_KEY` - optional reviewer backends

Reviewer configuration:
- `REVIEWER_MODE` - `ensemble` (default), `subagent`, or `api`
- `REVIEWER_TIMEOUT` - Per-reviewer timeout in seconds
- `CLAUDE_REVIEWER_MODEL` - Optional Claude reviewer model override

## Research Process

Do not run training, evaluation, benchmarks, data downloads, ablations,
hyperparameter sweeps, or expensive simulations. Small shell commands for
inspection, plotting from already written prediction CSVs, LaTeX compilation,
DOCX conversion, and artifact validation are allowed. If code scaffolds or
cloned baselines are needed for protocol planning, keep them under
`experiment_codebase/`; do not treat that directory as evidence of executed
experiments.

1. **Literature Review** - Use `/search-papers` when needed. Identify the most
   relevant prior work, current baselines, datasets, and whether the proposal has
   already been answered.
2. **Experiment Rationality Review** - Write `experiment_review.md`. Assess whether
   the proposed experiments would answer the hypothesis, including baselines,
   controls, metrics, data fit, leakage risks, compute feasibility, and threats to
   validity. Be strict: weak baselines, ungrounded metrics, leakage risk, missing
   controls, or infeasible compute must lower the gate score.
3. **Preflight Repair Gate** - If the decision is `Revise Before Running` or
   `Do Not Run Yet`, stop the downstream paper flow and hand the proposal to the
   preflight repair flow first. Write `preflight_repair.md` and
   `revised_experiment_protocol.md`, then base the paper on the repaired protocol.
   Do not hide the fact that the original proposal failed the gate.
4. **Predicted Results** - Based on the proposal, repaired protocol, prior
   literature, expected model
   behavior, and known benchmark patterns, make simple predictions about likely
   outcomes. Use qualitative rankings, expected directions, or conservative
   rough ranges only when justified. Label every number or trend with an evidence
   status such as `protocol-estimated`, `literature-calibrated forecast`, or
   `hypothesized`; never call it fake and never present it as measured.
   Save the prediction dataset to `predicted_results/predicted_results.csv`.
   The CSV must include `protocol_surface`, `comparison_role`,
   `evidence_status`, `calibration_source`, and `replacement_trigger` columns so
   the repaired protocol, visible manuscript table, and machine-readable
   forecast surface cannot silently diverge. For the road-crack YOLO idea, use
   RDD2022 as the default primary matched-budget detection surface, while
   Crack500 and CFD are auxiliary segmentation/thin-crack stress-test surfaces
   unless `revised_experiment_protocol.md` explicitly declares otherwise.
5. **Figures and Formulas** - Generate the forecast chart and any static
   protocol/design figures through repo scripts rather than manual plotting. Keep
   raster figure titles and table titles professional; use captions, surrounding
   text, the CSV fields, and `manuscript_explanation.md` for provenance instead
   of visually cluttering the PDF. If `scripts/generate_predicted_figures.py`
   exists, run
   `python3 scripts/generate_predicted_figures.py --app-dir .` after updating
   `predicted_results/predicted_results.csv`; this prevents hand-written plotting
   snippets from becoming hidden workflow state and gives static figures
   reproducible regeneration instructions. If
   `scripts/write_figure_provenance.py` exists, run it so static design figures
   also have source and regeneration records. Include formal criteria or
   equations in `latex/template.tex` for the gate score, expected utility,
   crossover rule, or statistical decision plan.
   A serious algorithm-style manuscript needs more than one generic chart:
   include at least five generated visual artifacts when the idea is a detector
   or model paper: an overall architecture figure, a module-level figure, a
   mechanism/loss or equation map, a forecast/comparison chart, and a protocol or
   benchmark matrix. Include at least four display equations covering the review
   gate plus model-side reasoning such as crack-aware fusion, thin-structure
   loss, hard-negative weighting, forecast calibration, or the stop/go rule.
6. **Protocol Lock Templates** - When the repaired protocol declares
   `manifests/*.csv` files and `scripts/create_manifest_templates.py` exists,
   run `python3 scripts/create_manifest_templates.py --app-dir .`. These
   zero-row templates do not claim dataset execution; they lock manifest schema,
   filenames, hashes, environment-lock placeholders, compute-parity report
   schema, and replacement points for future populated manifests and measured
   runs. Manifest CSV headers, `manifests/README.md`, and
   `manifests/manifest_lock.json` must agree exactly on the lock schema,
   including `dataset_version`.
7. **Paper Framing** - Write the paper as a protocol/design-analysis paper with
   predicted results, not a measured empirical-results paper or a method-first
   detector paper. The title, abstract, introduction, and conclusion must lead
   with the pre-registered evaluation contract; any detector name is a candidate
   instantiation to stress-test the protocol. Good framings include:
   - a study protocol for future execution,
   - a critical design audit of the proposed experiment,
   - a feasibility and validity analysis,
   - a benchmark plan with justified baselines, predicted outcomes, and failure modes.
8. **Best-of-v2/v3 Synthesis** - Borrow AI Scientist-v2's strengths outside the
   experiment-running step: ideation discipline, journal-to-report continuity,
   real citation collection, top-tier review-form self-critique, VLM-style
   figure/caption audit, complete venue-style structure, and explicit comparison
   to strong baselines. Keep AI Scientist-v3's strengths: Claude/Harbor
   execution, lightweight instructions, recoverable artifacts, strict gates,
   branch-specific verifier contracts, and low orchestration overhead. Do not
   run experiments.
9. **Paper Writing** - Fill `latex/template.tex`. Include related work, proposed
   methodology, review findings, predicted results, recommended experimental
   protocol, limitations, and evidence needed before making empirical claims.
   Use `\iclrfinalcopy` for the low-compute manuscript-effect PDF so the
   compiled artifact does not show the ICLR review line-number ruler on the left
   margin. This branch is testing polished paper output, not an anonymous
   submission package.
   If a visible forecast table is condensed for page fit, the body must say it is
   a selected subset of `predicted_results/predicted_results.csv`, name the
   selection rule, and point to the CSV as the authoritative full comparison
   surface.
10. **Top-Tier Gap Audit** - Add a section explaining what separates this
   review-backed paper from a top-A-conference empirical paper. Name the missing
   measured evidence, ablations, statistical tests, dataset releases, compute
   disclosure, and reproducibility artifacts. The tone should be strict, not
   promotional.
11. **Companion Explanation** - Write `manuscript_explanation.md` alongside the
   PDF. It should explain that the PDF is a polished manuscript-effect test,
   name the forecast CSV, summarize evidence-status fields, and list exactly
   what future measured runs must replace.
12. **Static Paper-Quality Audit** - When
   `scripts/audit_paper_quality.py` exists, run
   `python3 scripts/audit_paper_quality.py --app-dir .` and repair failures
   before final review. The audit is also part of `scripts/submit_for_review.sh`,
   so do not treat it as an optional local-only check.
13. **Compile and Export** - Run `bash scripts/compile_latex.sh latex/` and fix
   LaTeX or DOCX conversion errors. The compiled `latex/template.pdf` and
   converted `latex/template.docx` are required.
14. **Claude Style Pass** - When Claude Code is the active agent, run a concise
   manuscript style audit before final compilation. Remove AI-writing traces
   such as generic transitions, repeated workflow self-justification, hype, and
   vague claims, while preserving the non-execution disclosure. If Claude Code
   is running on another machine, it must do this pass itself rather than
   waiting for a human. Prefer
   `bash scripts/run_claude_style_audit.sh . latex/template.tex reviews/style_audit.md`
   when the script and Claude CLI are available, then apply the useful edits.
15. **Reviewer Pipeline** - Run
   `REVIEWER_MODE=ensemble FINAL_GATE_REVIEWER=1 bash scripts/submit_for_review.sh latex/template.tex .`
   whenever Claude-compatible reviewer tooling is available. This script must
   regenerate figures, manifest templates, and `manuscript_explanation.md` when
   possible, run the static paper-quality audit, ensure DOCX conversion is
   attempted, archive
   `reviews/top_tier_review.md`,
   `reviews/figure_audit.md`, `reviews/area_chair_gate.md`, and create a
   versioned `submissions/` snapshot. Treat feedback as a paper-quality review,
   not as evidence that predicted results were measured.
16. **Final Area-Chair Gate** - Before finishing, route the paper through the
    strictest available top-A-conference gate. Prefer the Claude `area-chair`
    subagent via `scripts/submit_for_review.sh`; otherwise create
    `reviews/area_chair_gate.md` manually from the same rubric. If the gate says
    `Repair Before Finish` or `Reject`, return to the indicated upstream repair
    artifact instead of polishing the paper cosmetically. After repair, repeat
    compile, DOCX export, manuscript explanation generation, reviewer pipeline,
    and gate until the remaining blockers are gone or explicitly documented as
    non-recoverable.

## Required `experiment_review.md` Structure

Use these headings exactly so the verifier can find them:

```markdown
# Experiment Rationality Review

## Idea Summary

## Verdict

## Strict Gate Scorecard

## Hypothesis And Claim Fit

## Experimental Design Assessment

## Baselines And Controls

## Data, Metrics, And Evaluation

## Feasibility And Cost

## Formal Criteria

## Predicted Results And Rationale

## Preflight Repair Handoff

## Threats To Validity

## Recommended Changes Before Running

## Final Recommendation
```

Use this decision scale in the final recommendation. Be harsh; do not choose
`Run` unless the protocol could be executed without design repair.

- `Run` - The design is mostly sound; only minor clarifications are needed.
- `Revise Before Running` - The idea may be worthwhile, but design gaps would
  undermine the results.
- `Do Not Run Yet` - The current experiment would likely produce misleading or
  non-actionable evidence.

Write `review.json` with this shape:

```json
{
  "decision": "Run | Revise Before Running | Do Not Run Yet",
  "gate_decision": "pass | repair | reject",
  "repair_required": true,
  "confidence": 1,
  "soundness": 1,
  "baseline_rigor": 1,
  "data_metric_fit": 1,
  "leakage_control": 1,
  "statistical_rigor": 1,
  "feasibility": 1,
  "main_risks": [],
  "required_changes": [],
  "repair_artifacts": ["preflight_repair.md", "revised_experiment_protocol.md"]
}
```

Scores are 1-5, where 5 is strongest.

## Paper Requirements

- Use an AI Scientist-v2-style paper organization: title, abstract,
  introduction, related work, background, method, experimental setup, predicted
  results, limitations, conclusion, references, and optional appendix.
- Write a substantive manuscript, not an artifact stub. Aim for roughly 2,000+
  words unless the idea is unusually narrow.
- Include real citations in `latex/references.bib` and cite them from the paper.
  For road-crack work, directly ground RDD2022, Crack500, CFD, DeepCrack, FPHBN,
  YOLO-family detectors, RT-DETR, and official Ultralytics YOLOv8
  documentation/repository when YOLOv8 is used. If a model family lacks a
  peer-reviewed canonical paper, say so rather than inventing one.
- Include at least one professional table, at least one generated figure, and at
  least four equations that support both the review logic and the proposed model
  mechanism.
- For detector/model papers, include at least five generated figure references:
  architecture, module detail, mechanism/loss map, forecast/comparison chart, and
  protocol/benchmark matrix.
- Include a strong comparative evaluation plan. Cover same-family baselines,
  stronger detector baselines, crack-specific segmentation baselines, transformer
  detectors when appropriate, ablations, matched budgets, hard-negative sets,
  leakage controls, uncertainty estimates, and stop/go criteria.
- Include a top-tier gap analysis that states why the current manuscript would
  still fall short of a top-A empirical paper and what evidence would close the
  gap.
- Be explicit that no new experiments were run.
- Include a predicted-results section or table, clearly labeled as predicted,
  expected, or hypothesized.
- Include at least one figure from `figures/` and at least one equation/formula.
- Include or reference the predicted data from `predicted_results/predicted_results.csv`.
- Make the title, abstract, introduction, and conclusion protocol-first. A named
  detector can be present only as the candidate instantiation being audited.
- If a forecast table is condensed, explain the row-selection rationale in the
  surrounding prose and point readers to the full CSV comparison surface.
- Include `manuscript_explanation.md` as a separate companion note. The main PDF
  should look like a serious manuscript, while this note documents provenance,
  forecast status, and replacement triggers for future real experiments.
- Export a Word version at `latex/template.docx` using
  `scripts/convert_latex_to_docx.sh` or the DOCX step inside
  `scripts/compile_latex.sh`.
- Predicted numbers are allowed only as rough estimates or illustrative ranges
  with rationale; never present them as measured results.
- Do not use the language of fake data. Use evidence-status language:
  protocol-estimated, literature-calibrated, forecast, planning range, or
  hypothesized. The values may look like normal experimental tables, but the
  table captions and text must state that they come from the review-backed
  estimation chain, not from training.
- Keep protocol-estimated SOTA comparisons conservative. Do not claim dramatic
  wins; use modest effect sizes, uncertainty intervals, and failure cases.
- Do not include fabricated measured accuracy, runtime, error bars, tables, or plots.
- If a table is useful, it may summarize proposed baselines, planned metrics,
  expected risks, review criteria, or predicted outcomes, not measured results.
- The abstract and conclusion must not imply empirical validation.
- The limitations section must name the missing empirical evidence and explain
  what future execution would need to establish.
- Citations must be real and relevant.
- Create `literature/literature_matrix.md` mapping each important citation to
  the claim it supports. Prefer sources found through `/search-papers`,
  Semantic Scholar, OpenAlex, arXiv, official proceedings, or publisher pages.
- After writing the paper, run
  `python3 scripts/audit_paper_quality.py --app-dir .` when the script is
  available, then fix any failures before finishing.
- Add top-tier review artifacts. Prefer `bash scripts/submit_for_review.sh
  latex/template.tex`, which runs Claude-compatible reviewers and a final
  `area-chair` gate. At minimum, preserve a top-tier review form, a figure/caption
  audit, and an area-chair gate under `reviews/` or `submissions/`.

## Important Rules

- Do not run training, benchmarking, model evaluation, or ablation experiments.
- Do not fabricate measured results, figures, tables, citations, or performance
  numbers. Clearly labeled predicted outcomes are allowed.
- Do not call protocol-estimated values fake; do not hide their status either.
- Do not make the PDF visually shout "fake/demo" in every table or figure; make
  the manuscript polished, then keep the detailed explanation in the companion
  note and machine-readable CSV.
- Do not turn the idea into an unrelated research project.
- Small shell commands for file inspection and LaTeX compilation are fine.
- If evidence is missing, state what would need to be checked before experiments.
- If the original plan fails the gate, produce preflight repair artifacts before
  writing the final paper.
- Save `experiment_review.md`, `review.json`, `predicted_results/predicted_results.csv`,
  at least one `figures/*.png`, `manuscript_explanation.md`,
  `latex/template.tex`, `latex/template.pdf`, and `latex/template.docx`
  before finishing.
- Before committing workflow changes on this branch, run
  `CUSTOMER_WORKFLOW_MODE=review-backed bash scripts/verify_customer_workflow.sh`.
  This verifies scripts and branch contracts without implying that experiments
  were run.
