# Customer Branch Contracts

This fork keeps two customer-facing branches with different default research
semantics. Both branches deliberately combine the useful parts of AI
Scientist-v2 and AI Scientist-v3:

- keep the v2 discipline around ideation, experiment-plan critique,
  journal-to-report continuity, real citations, complete manuscript structure,
  LLM review, and VLM-style figure/table auditing;
- keep the v3 operating model around Claude/Harbor execution, small markdown
  instruction surfaces, recoverable artifacts, versioned snapshots, and strict
  quality gates instead of a large Python orchestration layer.

## `customer-review-backed-paper-mode`

Default mode: low-compute, review-backed manuscript generation.

- Do not run training, benchmarking, ablations, or expensive dataset downloads.
- Review the proposed experiment for rationality before writing the paper.
- If the plan fails, write `preflight_repair.md` and
  `revised_experiment_protocol.md` before manuscript generation.
- Use conservative, literature-calibrated forecast data in
  `predicted_results/predicted_results.csv`.
- Generate figures, figure provenance, manifest templates, environment locks,
  PDF, DOCX, reviewer artifacts, and an area-chair gate.
- If the area-chair gate says `Repair Before Finish`, return to the named
  upstream artifact instead of finishing cosmetically.
- Local verification is expected to cover scripts, static gates, paper
  compilation, DOCX export, and reviewer orchestration. It must not claim that
  experiments were executed.

## `customer-normal-experiment-mode`

Default mode: normal empirical AI Scientist run.

- Run the experiments required by the idea when compute, data access, and
  credentials are available.
- Produce measured result tables, logs, figures, and reproducibility artifacts.
- Use forecast or pilot estimates only as planning aids before execution; final
  manuscript claims must be backed by measured artifacts.
- Keep the same paper-quality, figure, citation, DOCX, and reviewer gates used by
  the review-backed branch.
- On machines without enough compute, local verification is limited to workflow,
  shell, Python, and static-contract checks. Do not weaken the empirical
  verifier: a full normal run is only verified when the actual experiment suite
  produces measured artifacts under `results/`.

The two branches intentionally share tooling where possible. The branch name is
the customer-facing contract: use the review-backed branch when the machine is
too small for experiments, and the normal-experiment branch when real execution
is allowed.

## Local Verification Boundary

Use `scripts/verify_customer_workflow.sh` before committing either branch. The
script checks repository-level tests and syntax without starting expensive
training. For `customer-normal-experiment-mode`, this is a static workflow
verification only; the commit message should record the full empirical run as
not tested when hardware is insufficient.
