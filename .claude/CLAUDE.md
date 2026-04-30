# AI Scientist v3 - Customer Normal Experiment Mode

Autonomous AI research scientist for normal empirical runs. This branch is for
machines where data access, credentials, and compute are available. Unlike
`customer-review-backed-paper-mode`, this branch should run the experiments
needed by the idea and write the paper from measured artifacts.

This branch contract is `customer-normal-experiment-mode`. Its sibling
`customer-review-backed-paper-mode` is the low-compute branch where experiments
are replaced by review-backed forecasts. Do not silently fall back to forecasted
final results in this branch unless an experiment is blocked and the blocker is
recorded in the paper and reviewer artifacts.

## Workspace

- `experiment_review.md` - Pre-run design review and execution plan
- `review.json` - Structured gate scores and execution decision
- `preflight_repair.md` - Required when the proposed experiment is not runnable as-is
- `revised_experiment_protocol.md` - Repaired protocol when the gate fails
- `experiment_codebase/` - Code, configs, and lightweight patches used for the run
- `cloned_repos/` - External reference repositories, when needed
- `results/` - Measured CSV/JSON results, run logs, checkpoints metadata, and summaries
- `configs/`, `manifests/`, `reports/` - Environment, data, split, and compute parity records
- `figures/` - Figures generated from measured results or explicit diagnostic logs
- `latex/` - ICLR 2025 workshop template; fill `latex/template.tex`
  and export `latex/template.pdf` plus `latex/template.docx`
- `literature/` - Paper index, notes, citations, and related-work evidence
- `manuscript_explanation.md` - Companion note for provenance, measured-artifact
  locations, run limits, and replacement triggers for incomplete experiments
- `reviews/` - Optional direct review artifacts when not using `submissions/`
- `submissions/` - Versioned snapshots created by `scripts/submit_for_review.sh`
- `/search-papers` - Skill for checking related work, baselines, and novelty claims

Package installation and dataset/model downloads are allowed when required by
the idea and compatible with the available machine, credentials, storage, and
license constraints. Keep downloads targeted and logged. Store experiment code in
`experiment_codebase/`, and never use untracked local state as evidence.

## Research Process

1. **Literature Review** - Use `/search-papers` when needed. Identify current
   baselines, datasets, metrics, and whether the idea has already been answered.
2. **Experiment Rationality Review** - Write `experiment_review.md`. Assess
   whether the proposed experiments answer the hypothesis. Be strict about
   baselines, controls, dataset splits, metrics, leakage risks, compute budget,
   statistical rigor, and reproducibility.
3. **Preflight Repair Gate** - If the protocol is weak, write
   `preflight_repair.md` and `revised_experiment_protocol.md` before running.
   Do not spend compute on an experiment the gate says would be misleading.
4. **Implementation and Execution** - Build or adapt code under
   `experiment_codebase/`. Run the smallest sufficient experiment suite that can
   support the paper claims. Capture commands, seeds, configs, package versions,
   hardware, wall-clock time, and failure logs.
5. **Measured Results** - Save measured results under `results/`, preferably as
   `results/measured_results.csv` plus any task-specific JSON summaries. Final
   manuscript tables must cite these measured artifacts. Forecast or pilot values
   are allowed only as planning notes, not as final evidence.
6. **Reproducibility Locks** - Materialize `configs/`, `manifests/`, and
   `reports/` with data splits, environment details, and compute-parity records.
   If a run is partial, mark the exact missing rows or skipped baselines.
7. **Figures and Formulas** - Generate figures from measured CSV/JSON/log
   artifacts. Static architecture figures are allowed, but result plots must be
   backed by measured data. Include equations for objectives, evaluation metrics,
   statistical tests, or stopping rules.
8. **Paper Writing** - Fill `latex/template.tex` with a full empirical paper:
   related work, method, experimental setup, results, ablations, limitations,
   and conclusion. Claims must match the measured evidence actually produced.
9. **Companion Explanation** - Write `manuscript_explanation.md` with the run
   provenance: where results live, which baselines ran, which failed or were
   skipped, and what would be required to extend the evidence.
10. **Static Paper-Quality Audit** - Run
    `python3 scripts/audit_paper_quality.py --app-dir .` when available. Repair
    failures before final review; adapt the manuscript rather than weakening the
    audit.
11. **Compile and Export** - Run `bash scripts/compile_latex.sh latex/` and fix
    LaTeX or DOCX conversion errors. The compiled `latex/template.pdf` and
    converted `latex/template.docx` are required.
12. **Claude Style Pass** - When Claude Code is the active agent, run
    `bash scripts/run_claude_style_audit.sh . latex/template.tex reviews/style_audit.md`
    when available, then apply only edits that improve clarity without softening
    empirical limitations.
13. **Reviewer Pipeline** - Run
    `REVIEWER_MODE=ensemble FINAL_GATE_REVIEWER=1 bash scripts/submit_for_review.sh latex/template.tex .`
    when reviewer tooling is available. Treat reviewer output as a gate on
    scientific quality, reproducibility, citation validity, and claim/evidence fit.
14. **Final Area-Chair Gate** - If the gate says `Repair Before Finish` or
    `Reject`, return to the named upstream artifact, rerun the necessary
    experiment or repair, regenerate paper artifacts, and repeat the gate.

## Required `experiment_review.md` Structure

Use these headings exactly:

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

## Execution Plan

## Preflight Repair Handoff

## Threats To Validity

## Final Recommendation
```

Use this decision scale:

- `Run` - The design is sound enough to execute.
- `Revise Before Running` - The idea may be worthwhile, but design gaps would
  undermine the result.
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

- Use an AI Scientist-v2-style empirical paper organization: title, abstract,
  introduction, related work, background, method, experimental setup, results,
  ablations, limitations, conclusion, references, and optional appendix.
- Write a substantive manuscript, not an artifact stub. Aim for roughly 2,000+
  words unless the idea is unusually narrow.
- Include real citations in `latex/references.bib` and cite them from the paper.
- Include professional measured-result tables, generated figures, and at least
  one equation or formal metric.
- Include strong baselines, ablations, matched budgets, leakage controls,
  uncertainty estimates, and reproducibility details.
- Be explicit about what ran, what failed, what was skipped, and why.
- Do not report forecast or pilot values as final measured results.
- Create `literature/literature_matrix.md` mapping each important citation to
  the claim it supports.
- Create `manuscript_explanation.md` as a companion provenance note.
- Export a Word version at `latex/template.docx`.
- Add top-tier review artifacts under `reviews/` or `submissions/`.

## Important Rules

- Run experiments only when the preflight gate says the protocol is sound enough
  and the required data/compute/license conditions are available.
- Never fabricate measured results, figures, tables, citations, logs, or
  checkpoints.
- If an experiment cannot be completed, downgrade the claim and record the
  blocker instead of filling the gap with forecasts.
- Keep result artifacts machine-readable; final paper tables should be traceable
  to `results/`, `configs/`, `manifests/`, and `reports/`.
- Save `experiment_review.md`, `review.json`, measured `results/`, at least one
  figure, `manuscript_explanation.md`, `latex/template.tex`,
  `latex/template.pdf`, and `latex/template.docx` before finishing.
