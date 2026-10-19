# nfl-qb-eval

Can public NFL data help describe repeatable quarterback execution with less dependence on supporting circumstances? This exploratory project also aims eventually to evaluate context-aware performance while preserving credit for excellent actual play. Neither goal is an established capability.

Current code audits inputs, compares supplied nflfastR completion percentage over expected (CPOE) with ordinary completion percentage on identical eligible 2023 throws, describes their 2023–2024 annual associations, and examines recorded sack-avoidance associations across fixed game sets and seasons. These analyses concern selected regular-use passers, not a position-certified quarterback cohort or a validated overall score. Conditional game-jackknife intervals are working-model sensitivities; persistent context, serial dependence, survivor selection, and unknown CP model/training vintage remain limitations. One annual transition is not a clean historical forecast or repeated temporal validation.

## Scripts and prerequisites

- `audit_inputs.R`: downloads and audits official 2023 PBP/FTN inputs and a schedule reference; preserves originals and provenance receipts.
- `pilot_accuracy.R`: uses existing exact snapshots for the 2023 same-throw interleaved/chronological split comparison and count-only FTN diagnostics.
- `export_comparison.R`: exports only the frozen annual comparison and baseline aggregates with a separate payload-digest manifest.
- `rush_contribution.R`: describes recorded scramble/non-scramble-run contribution per combined opportunity, with four frozen association endpoints and marginal actor-season sensitivity intervals.
- `sack_repeatability.R`: uses exact 2023/2024 PBP/schedule and opportunity manifests for fixed-cohort recorded sack-avoidance associations; no FTN or pressure denominator.
- `annual_stability.R`: uses existing exact PBP/schedule snapshots for the paired 2023–2024 annual comparison. Each year is a fixed stratum; leave-game deviations are centered on the full estimate, not the deletion mean. FTN is unnecessary for this script.

The scripts use installed R packages; they do not install dependencies. Tested with R 4.6.0 and:

| Package | Tested version | Used by |
|---|---|---|
| dplyr | 1.2.1 | All scripts; requires the modern join `relationship` argument |
| readr | 2.2.0 | All scripts |
| arrow | 25.0.0 | Audit, pilot, annual comparison, baseline, sack/run studies and comparison export; reading Parquet |
| digest | 0.6.39 | Audit, pilot, annual comparison, baseline, sack/run studies and comparison export; SHA256 verification |
| stringr | 1.6.0 | Audit, pilot and annual comparison; frozen receiver-description rule |
| tidyr | 1.3.2 | Pilot and annual comparison |
| curl | 7.1.0 | Input audit downloads |
| jsonlite | 2.0.0 | Input audit release metadata and comparison JSON export |
| ggplot2 | 4.0.3 | Optional evidence-summary figure |

Run from the repository root. Supply existing writable input workspaces outside version control, either external directories or locations covered by `.gitignore`. Inputs and timestamped outputs remain local. `INPUT_2023` and `INPUT_2024` below are placeholders for those existing directory paths, not literal required folder names.

## Reproduce the annual comparison

Obtain these files directly from their official links, preserve original bytes, and save them with the indicated filenames. The annual script requires only the two PBP files and the pinned schedule; it does not require acquisition receipts, FTN, or another audit run.

| Filename | Workspace | Official source | Required bytes |
|---|---|---|---:|
| `play_by_play_2023.parquet` | INPUT_2023 | [2023 PBP release asset](https://github.com/nflverse/nflverse-data/releases/download/pbp/play_by_play_2023.parquet) | 20,534,088 |
| `play_by_play_2024.parquet` | INPUT_2024 | [2024 PBP release asset](https://github.com/nflverse/nflverse-data/releases/download/pbp/play_by_play_2024.parquet) | 20,597,560 |
| `schedule_reference.rds` | INPUT_2023 | [Pinned nfldata games.rds](https://raw.githubusercontent.com/nflverse/nfldata/1bc55c1a32253a78875ca786f8492479a2006567/data/games.rds) | 428,923 |

Required SHA256 values:

```text
play_by_play_2023.parquet  bd3484731408def6b0ec93225bba2bd7b2c65769ca707a2b9444d891abdc6776
play_by_play_2024.parquet  3fd2896bc0b911b615142d2f1fabae54a4bbba5ab7b73b28187b118ef8af6a3b
schedule_reference.rds    659e4ae782353bb80d196c6789e11eae545a93be9fdb668dd3e3ae4fdac860eb
```

The pinned schedule already contains both complete regular seasons. The PBP snapshots include postseason rows, which the script retains in the original files and excludes by the declared regular-season scope.

```sh
Rscript annual_stability.R "INPUT_2023" "INPUT_2024"
```

The script checks byte sizes/hashes before analysis. It saves the actual common cohort, eligible keys, count-only game mapping, specification/input/script hashes, and a run record before computing annual metrics. The cohort requires at least 200 CP-eligible recorded pass outcomes and ten games in each year, with a 20-passer full-data reporting floor. Candidate and baseline use identical rows. Results, influence checks, and verification examples receive a unique prefix in INPUT_2024; no player-performance leaderboard is produced.

## Reproduce the 2023 audit and split pilot

For a fresh official-source audit:

```sh
Rscript audit_inputs.R "INPUT_2023"
```

This creates `download_receipts.csv` and retains the release metadata and downloaded files. Its schedule reference is pinned to the commit resolved at acquisition time. A fresh audit records the versions currently served; it does not guarantee the exact historical snapshots required by the pilot or annual script.

For the fixed split pilot, INPUT_2023 must contain the matching 2023 PBP and schedule above, plus:

| Filename | Official source | Required bytes | Required SHA256 |
|---|---|---:|---|
| `ftn_charting_2023.parquet` | [2023 FTN public release asset](https://github.com/nflverse/nflverse-data/releases/download/ftn_charting/ftn_charting_2023.parquet) | 567,781 | `162f0f48a8fca23f86a334c78e27f8daa7443e6b383beada0416b65c593b2c0e` |

The pilot also requires `download_receipts.csv` containing one receipt per required input, with columns `file,url,retrieved_utc,bytes,sha256`. The audit creates this log automatically. If acquiring the pinned files separately, record their official URLs, actual UTC acquisition times, sizes and hashes truthfully in that format; do not substitute an earlier retrieval date or edit existing receipts to conceal changed bytes.

```sh
Rscript pilot_accuracy.R "INPUT_2023"
```

The pilot freezes cohort and game assignments before summaries. It requires at least 100 eligible throws and five games in each interleaved half and at least 20 qualifying passers. FTN labels remain diagnostic; missing labels are not false, and a nonmissing label does not establish applicability to every play.

**Exact reproduction requires matching snapshots.** Release tags are mutable. If an official download no longer matches the required hash, the fixed analysis stops; a matching filename or tag is insufficient. Preserve original downloads, receipts and run records. Changed inputs/specifications constitute a different run, not exact reproduction.

## Recorded-dropback observed-value baseline

`performance_baseline.R` uses the exact PBP snapshots above and the matching annual `cohort_counts.csv` / `frozen_E_keys.csv` manifests to fix the common regular-use cohort by counts. It needs only installed dplyr, readr, arrow and digest. Supply the annual output prefix, including its trailing underscore. Outputs are sorted by actor ID/year: raw shared EPA totals, pooled opportunity means and marginal actor-game sensitivity intervals. Opportunities include recorded played passes, sacks and scrambles without a CP filter; designed rushing and the wider penalty universe are outside scope. This supplies no independent support-quality adjustment or overall score.

```sh
Rscript performance_baseline.R "INPUT_2023" "INPUT_2024" "ANNUAL_PREFIX_"
```

## Recorded sack-avoidance repeatability

`sack_repeatability.R` describes `100 × (dropbacks − recorded sacks) / dropbacks` for the same fixed 20 regular-use passers. Opportunities are recorded played passes, sacks and scramble-runs, with no CP, EPA-availability, E-game, penalty or description filter. The cohort was selected by at least 200 eligible throws and ten eligible games in **each** year, so survivor and CP-related selection remain. It is not a position-certified quarterback population.

The primary analysis compares odd/even 2023 actor-games ordered by date and game ID. The only split sensitivity compares the first `ceiling(G/2)` actor-games with the rest; the secondary analysis compares full 2023 and 2024 seasons. Rates pool opportunities within actor-half/year; Pearson correlations weight actors equally. No 2024 split, ranking, pressure denominator or adjusted score is computed.

Use the exact PBP/schedule snapshots above plus three preserved local opportunity/count manifests. They are inputs, not internal methods notes, and are not redistributed in this repository. Exact reproduction requires these matching bytes; the script never silently replaces them or downloads substitutes.

| Argument | Existing manifest | Required SHA256 |
|---|---|---|
| `COHORT_CSV` | `common_cohort_exposures.csv`, 20 IDs and annual E exposure counts | `4460604f27bbbe432fd42e9bbdcf426315844d5fb996f769bbd268fe375235bf` |
| `E_KEYS_CSV` | Annual comparison's `frozen_E_keys.csv` | `67f05a4386241620f24b4618ebd504931fa7659c5c8c57c4c9f5b2a3f9056808` |
| `D_KEYS_CSV` | Observed-value baseline's `frozen_baseline_keys.csv` | `be1f386ebc899a29043491f93568388863447d789705c2fc0833e46b85b6d946` |

Supply the full paths, including any timestamp prefixes, and an existing writable output directory outside Git. Only installed dplyr, readr, arrow and digest are required. The last argument identifies the fixed specification; no private design document is read at runtime.

```sh
Rscript sack_repeatability.R "INPUT_2023" "INPUT_2024" "COHORT_CSV" "E_KEYS_CSV" "D_KEYS_CSV" "OUTPUT_DIR" "e60420a5020804a5cafcd3eaf559b20d17ab716c52e9130e32f48c6ae1f070d7"
```

The script verifies source hashes and accepted E/D keys, independently reconstructs membership and split maps, and saves counts, keys, maps, contributing games and a design/script-hashed run manifest before rates. Timestamped outputs include actor-half/year counts and rates, all whole-NFL-game deletions, paired-actor influence checks, unavailable statuses, and complement/known-mean arithmetic checks. Zero-sack records remain; missing diagnostic flags remain explicit.

Approximate 95% conditional working-model sensitivity intervals use Fisher-transformed correlations and delete complete NFL games across both teams, all selected actors and both half labels. Each season's replicates are centered on **their own mean**, then its finite-game variance contribution is summed. This prospectively specified annual centering differs from `annual_stability.R`; earlier CPOE outputs are unchanged. Undefined/boundary correlations or zero/nonfinite variance withhold the affected interval without dropping replicates or changing cohorts. These sensitivities do not establish NFL coverage, absolute agreement, player separation, pressure handling, isolated skill, prediction or overall decision quality; persistent surroundings, serial dependence, selection and rare sacks remain limitations.

## Recorded run contribution

`rush_contribution.R` keeps the same fixed 20-ID cohort and distinguishes **S**, recorded scramble-runs within accepted dropbacks D, from **R**, recorded non-scramble actor runs outside D. R includes aborted and lateral plays and must not be called designed rushing. Combined opportunities are the disjoint union **O = D ∪ R**. For each role k, contribution is `sum(role EPA) / N_O`, combining frequency and shared observed value. Its denominator is not the role's run count. With no role opportunities, contribution is zero and per-role mean EPA is unavailable; neither describes zero ability.

Use the exact original PBP/schedule, common-cohort exposure CSV and baseline D-key manifest described above, plus these accepted keyed partitions (only `in_R=TRUE` keys are used; numeric EPA comes from the original typed PBP):

| Existing manifest | Required SHA256 |
|---|---|
| `rush_2023_keyed_partitions.csv` | `1648351bd64060d52041c9bfb977afe24cfde454788d013b7e4ffc3864f1ce36` |
| `rush_2024_keyed_partitions.csv` | `a555e4020169a987c66f73351e95975f3c07faff559def179ba93cdbb11ef22c` |

```sh
Rscript rush_contribution.R "INPUT_2023" "INPUT_2024" "COHORT_CSV" "D_KEYS_CSV" "R2023_KEYS_CSV" "R2024_KEYS_CSV" "OUTPUT_DIR" "347a063258182a6558a0b372fc465b2637f09038b02175e89b61c3e23b0cd932"
```

Supply existing paths, including timestamp prefixes where present, and an existing writable output directory outside Git. The script needs installed dplyr, readr, arrow and digest only; no ignored design notes at runtime. Missing/changed hashes or target attribution/EPA contradictions stop execution. It freezes source/specification/script hashes, cohort, O keys/counts and new O-game maps before EPA sums or rates.

The two primaries are 2023 odd/even O-game associations for the two contributions; the two secondaries are their full 2023–2024 associations. No other split or correlation contrast is computed. Whole-NFL-game deletions remove both teams, roles and half labels while recomputing numerator and denominator on unchanged membership/maps. Each season's Fisher replicates use their own mean for conditional correlation intervals. Separate marginal actor-season ratio intervals use every actor O game, including zero-role games. Outputs retain shares, role counts/games, per-role means, overlapping aborted/lateral/fumble/penalty diagnostics, undefined statuses and paired-actor influence checks, sorted by ID rather than performance.

These are conditional working-model sensitivities, not demonstrated NFL coverage, rankings, forecasts or isolated mobility. R preserves whole-play and other participants' effects. S already contributes to EPA/D; the O-denominated measures must not be added to that D-denominated mean or presented as independent skill axes. Sparse signed EPA, usage/scheme, persistent support, selection and serial dependence limit interpretation. Website use requires a reviewed export-contract revision; this script does not publish comparison data.

## Export the annual comparison data

`export_comparison.R` creates aggregate comparison JSON for the fixed 20-ID, 40-season-row cohort. It reconstructs CPOE and completion means only from the exact frozen in-cohort E keys joined one-to-one to the original PBP. It does not rerun eligibility, calculate individual CPOE/completion uncertainty or fit anything. Validation-only annual `r_C`, `r_B` and their difference must reproduce the accepted outputs within `1e-10`; disagreement stops export. EPA means, marginal conditional interval limits/statuses and dropback counts are copied from the existing baseline rows.

Use the exact PBP/schedule snapshots above, the accepted annual and baseline output prefixes (including trailing underscores), and two separate existing writable directories for public-ready assets and private run evidence:

```sh
Rscript export_comparison.R "INPUT_2023" "INPUT_2024" "ANNUAL_PREFIX_" "BASELINE_PREFIX_" "ASSET_DIR" "LOCAL_EVIDENCE_DIR"
```

The annual prefix must provide `annual_associations.csv`, `conditional_intervals.csv`, `cohort_counts.csv`, `frozen_E_keys.csv`, `verified_sources.csv` and `run_record.rds`. The baseline prefix must provide `actor_season_results.csv` and `run_record.rds`. Every file is pinned by SHA256 in the script; these retained local inputs are not redistributed here. No ignored methods/context note is needed at runtime. Installed dplyr, readr, arrow, digest and jsonlite are sufficient.

Outputs are `nfl-qb-2023-2024-v1.json` and `nfl-qb-2023-2024-v1.manifest.json`. The manifest separately records the payload SHA256, schema/data versions, actual generation time, seasons, cohort/row counts, units and aggregate hashes. Consumers must reject a mismatched or stale pair. The exporter checks this pair, preserves differing existing assets by stopping, and never silently fetches replacements. This is data preparation; no consumer UI or deployment is included.

Rows use published GSIS IDs and observed abbreviated names, with source precision and native units. EPA performance remains separate from matched-row CPOE/completion; their denominators differ. Null interval limits indicate unavailability, never zero. No individual CPOE/completion intervals, FTN numbers, sack-study fields, percentiles, ranks, ratings or context-adjusted score are exported. Study-level intervals stay separate from player rows. Explicit public metadata preserves source attribution, transformation notices and analysis hashes; local paths, raw plays and run records remain private. PBP data attribution under CC BY 4.0 is separate from original-code MIT licensing. The conditional intervals do not establish NFL coverage, isolated skill, forecast validity or useful player separation.

## Optional evidence-summary figure

`plot_repeatability.R` reads existing interleaved/chronological pilot and annual interval CSVs plus their cohort-count CSVs; it performs no estimation. Supply the two full output prefixes, including their trailing underscores, and an unused PNG path in an existing local output directory. The figure distinguishes the two correlations from their paired difference and labels the different cohorts; it is an evidence summary rather than a player skill chart.

```sh
Rscript plot_repeatability.R "PILOT_PREFIX_" "ANNUAL_PREFIX_" "NEW_OUTPUT.png"
```

## Code and data terms

Original project code is [MIT licensed](LICENSE). Third-party data have separate terms:

- PBP is distributed through nflverse under the [nflverse-data CC BY 4.0 license](https://github.com/nflverse/nflverse-data/blob/master/LICENSE.md). Retain applicable attribution and source notices.
- The released FTN subset is documented as CC BY-SA 4.0 with attribution **FTN Data via nflverse**; see the [official FTN loader documentation](https://nflreadr.nflverse.com/reference/load_ftn_charting.html). This does not grant rights to unreleased FTN products.
- The separately maintained [nfldata schedule source](https://github.com/nflverse/nfldata) has its own upstream notices. Dataset availability and the code's MIT license do not settle every proposed derived-output use.

Raw inputs and numerical FTN-derived outputs are not redistributed here. Any future public dataset, combined database, figure, or other derived output requires source-specific attribution and permissions assessment.
