# Customer Branch Contracts

This fork keeps two customer-facing branches with different default research
semantics. The active branch here is `customer-normal-experiment-mode`.

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

## `customer-normal-experiment-mode`

Default mode: normal empirical AI Scientist run.

- Run the experiments required by the idea when compute, data access, and
  credentials are available.
- Produce measured result tables, logs, figures, and reproducibility artifacts.
- Use forecast or pilot estimates only as planning aids before execution; final
  manuscript claims must be backed by measured artifacts.
- Keep the same paper-quality, figure, citation, DOCX, and reviewer gates used by
  the review-backed branch.

The two branches intentionally share tooling where possible. The branch name is
the customer-facing contract: use the review-backed branch when the machine is
too small for experiments, and the normal-experiment branch when real execution
is allowed.
