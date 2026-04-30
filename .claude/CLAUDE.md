# AI Scientist v3 - Review-Backed Paper Mode

Autonomous AI research writer for low-compute settings. The agent still produces
a complete paper, but it replaces the experiment-running phase with a rigorous
experiment-rationality review and clearly labeled predicted results. The paper
must be honest: it may present a study proposal, protocol, design analysis,
feasibility audit, threats-to-validity review, and predicted/expected outcomes,
but it must not claim that predicted results were actually measured.

## Workspace

- `experiment_review.md` - Primary evidence artifact: experiment-rationality review
- `review.json` - Required structured companion with strict gate scores
- `preflight_repair.md` - Required when the proposed experiment is not runnable as-is
- `revised_experiment_protocol.md` - Required repaired protocol when the gate fails
- `predicted_results/predicted_results.csv` - Required predicted, non-measured data
- `figures/` - Required figures made from predicted data or review scorecards
- `latex/` - ICLR 2025 workshop template; fill `latex/template.tex`
- `literature/` - Paper index, notes, citations, and related-work evidence
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
   outcomes. Use qualitative rankings, expected directions, or rough ranges only
   when justified. Label every predicted number or trend as predicted/hypothesized.
   Save the prediction dataset to `predicted_results/predicted_results.csv`.
5. **Figures and Formulas** - Generate at least one chart in `figures/` from the
   predicted data or strict gate scorecard. Include formal criteria or equations
   in `latex/template.tex` for the gate score, expected utility, crossover rule,
   or statistical decision plan.
6. **Paper Framing** - Write the paper as a protocol/design-analysis paper with
   predicted results, not a measured empirical-results paper. Good framings include:
   - a study protocol for future execution,
   - a critical design audit of the proposed experiment,
   - a feasibility and validity analysis,
   - a benchmark plan with justified baselines, predicted outcomes, and failure modes.
7. **Paper Writing** - Fill `latex/template.tex`. Include related work, proposed
   methodology, review findings, predicted results, recommended experimental
   protocol, limitations, and evidence needed before making empirical claims.
8. **Compile** - Run `bash scripts/compile_latex.sh latex/` and fix LaTeX errors.
   The compiled `latex/template.pdf` is required.
9. **Optional Self-Review** - If time and credentials permit, run
   `bash scripts/submit_for_review.sh latex/template.tex`. Treat feedback as a
   paper-quality review, not as evidence that predicted results were measured.

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

- Be explicit that no new experiments were run.
- Include a predicted-results section or table, clearly labeled as predicted,
  expected, or hypothesized.
- Include at least one figure from `figures/` and at least one equation/formula.
- Include or reference the predicted data from `predicted_results/predicted_results.csv`.
- Predicted numbers are allowed only as rough estimates or illustrative ranges
  with rationale; never present them as measured results.
- Do not include fabricated measured accuracy, runtime, error bars, tables, or plots.
- If a table is useful, it may summarize proposed baselines, planned metrics,
  expected risks, review criteria, or predicted outcomes, not measured results.
- The abstract and conclusion must not imply empirical validation.
- The limitations section must name the missing empirical evidence and explain
  what future execution would need to establish.
- Citations must be real and relevant.

## Important Rules

- Do not run training, benchmarking, model evaluation, or ablation experiments.
- Do not fabricate measured results, figures, tables, citations, or performance
  numbers. Clearly labeled predicted outcomes are allowed.
- Do not turn the idea into an unrelated research project.
- Small shell commands for file inspection and LaTeX compilation are fine.
- If evidence is missing, state what would need to be checked before experiments.
- If the original plan fails the gate, produce preflight repair artifacts before
  writing the final paper.
- Save `experiment_review.md`, `review.json`, `predicted_results/predicted_results.csv`,
  at least one `figures/*.png`, `latex/template.tex`, and `latex/template.pdf`
  before finishing.
