# NFL QBs Visualized

How do quarterbacks compare when we isolate them from their team and situation?
This project explores that question through season statistics, repeatability
studies and interactive player comparisons. The current measures describe recorded
performance; they do not yet isolate quarterback skill or provide a context-adjusted
overall score. The longer-term aim also includes evaluating context-aware performance
while retaining credit for excellent actual play.

The annual data cover **560 qualifying player-seasons from 2006–2025, excluding
2011**. They include shared play value, completion outcomes relative to model
expectations, sack avoidance and scramble contribution. Attributed expert
assessments appear alongside the measured outcomes as a separate source of evidence.

## Start here

- [Explore quarterback profiles and season comparisons](https://www.nslanalytics.com/projects/nfl-qbs-re-evaluated/).
- Inspect [the published JSON datasets](public/data/) to use the aggregates without
  rerunning the research.
- Read the [project explanation](src/content/projects/nfl-qbs-re-evaluated.mdx)
  for definitions, formulas and interpretation limits.
- Follow [Getting started](#getting-started) to verify the published files.
  Detailed reproduction commands are available below for each analysis.

## What's included

| Location | Contents |
| --- | --- |
| Root `*.R` files | Input audits, statistical studies, plotting and export scripts. |
| `public/data/` | Four datasets and their checksum manifests, eight JSON files in total. |
| `src/lib/` | Data validation, percentiles, attributed expert ranks and chart interactions. |
| `src/components/` | The NFL interface and shared layout/help components. |
| `src/content/projects/` | The project's explanation, formulas and limitations. |
| `scripts/` | Data, percentile, profile and player-search checks. |

The four datasets contain the fixed-cohort 2023–2024 comparison, annual outcomes,
passing-depth outcomes and annual scramble contribution. The original comparison
keeps its ten association results separate from its 40 player-season records.
The annual files cover 560 player-seasons; annual Mobility has 559 finite values.
Unavailable values remain explicit rather than becoming zero.

The chart code comes from the
[portfolio implementation at commit `6c6b765`](https://github.com/nanu731/portfolio/tree/6c6b765).
That repository supplies Astro configuration, styling, fonts, routing and deployment.
The files here are the NFL implementation, not a standalone website. No other
project's application code or data is included.

Raw play-by-play, FTN charting records and intermediate analysis files are not
included. Reproducing a study requires its exact source snapshots; a newer download
with the same filename may contain different data.

## Getting started

### Check the published files

Use Node.js 24 or later from this repository root. These checks use built-in Node modules and install no packages:

```sh
node scripts/verify-nfl-percentiles.mjs
node scripts/verify-nfl-mobility.mjs
```

Full profile and search integration checks also require a checkout of the linked portfolio revision and its completed production build. `NFL_PORTFOLIO_ROOT` identifies that checkout. The checks use this repository's NFL code/data and the portfolio's built pages or NBA search reference:

```sh
NFL_PORTFOLIO_ROOT=/path/to/portfolio node scripts/verify-nfl-profile.mjs
NFL_PORTFOLIO_ROOT=/path/to/portfolio node scripts/verify-nfl-search.mjs
```

These are source and data checks. Browser interaction and visual checks are separate.

### Reproduce an analysis

Start with the annual comparison if you want to follow the original two-season
study. Each section lists its required inputs and commands. Later exports depend
on outputs from earlier analyses; they are not independent one-command downloads.
The uppercase paths in the examples are placeholders for your existing input and
output directories.

<details>
<summary>R scripts and tested package versions</summary>

- `annual_input_counts.R`: verifies frozen annual eligibility, recorded-dropback roles, source identity and EPA availability before expanded summaries.
- `annual_display.R`: calculates separate annual outcome and depth-residual exports from the verified opportunities, retaining source hashes, conditional uncertainty and explicit unavailable states.
- `export_annual_mobility.R`: exports annual recorded scramble contribution for the same frozen player-seasons, with explicit unavailable records and conditional game-sampling ranges.
- `audit_inputs.R`: downloads and audits official 2023 PBP/FTN inputs and a schedule reference; preserves originals and provenance receipts.
- `pilot_accuracy.R`: uses existing exact snapshots for the 2023 same-throw interleaved/chronological split comparison and count-only FTN diagnostics.
- `export_comparison.R`: exports only the frozen annual comparison and baseline aggregates with a separate payload-digest manifest.
- `rush_contribution.R`: describes recorded scramble/non-scramble-run contribution per combined opportunity, with four frozen association endpoints and marginal actor-season sensitivity intervals.
- `sack_repeatability.R`: uses exact 2023/2024 PBP/schedule and opportunity manifests for fixed-cohort recorded sack-avoidance associations; no FTN or pressure denominator.
- `annual_stability.R`: uses existing exact PBP/schedule snapshots for the paired 2023–2024 annual comparison. Each year is a fixed stratum; leave-game deviations are centered on the full estimate, not the deletion mean. FTN is unnecessary for this script.

The scripts use installed R packages without installing dependencies. The tested environment uses R 4.6.0 and the following packages:

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

</details>

<details>
<summary>Reproduce the annual comparison</summary>

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

Before analysis, the script checks byte sizes and hashes. Before computing annual metrics, it saves the actual common cohort, eligible keys, count-only game mapping, specification/input/script hashes and a run record. The cohort requires at least 200 CP-eligible recorded pass outcomes and ten games in each year, with a 20-passer full-data reporting floor. Candidate and baseline use identical rows. Results, influence checks, and verification examples receive a unique prefix in INPUT_2024; no player-performance leaderboard is produced.

</details>

<details>
<summary>Reproduce the 2023 audit and split pilot</summary>

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

</details>

<details>
<summary>Recorded-dropback observed-value baseline</summary>

`performance_baseline.R` uses the exact PBP snapshots above and the matching annual `cohort_counts.csv` / `frozen_E_keys.csv` manifests to fix the common regular-use cohort by counts. It needs only installed dplyr, readr, arrow and digest. Supply the annual output prefix, including its trailing underscore. Outputs are sorted by actor ID/year: raw shared EPA totals, pooled opportunity means and marginal actor-game sensitivity intervals. Opportunities include recorded played passes, sacks and scrambles without a CP filter; designed rushing and the wider penalty universe are outside scope. This supplies no independent support-quality adjustment or overall score.

```sh
Rscript performance_baseline.R "INPUT_2023" "INPUT_2024" "ANNUAL_PREFIX_"
```

</details>

<details>
<summary>Recorded sack-avoidance repeatability</summary>

`sack_repeatability.R` describes `100 × (dropbacks − recorded sacks) / dropbacks` for the same fixed 20 regular-use passers. Opportunities are recorded played passes, sacks and scramble-runs, with no CP, EPA-availability, E-game, penalty or description filter. The cohort was selected by at least 200 eligible throws and ten eligible games in **each** year, so survivor and CP-related selection remain. It is not a position-certified quarterback population.

The primary analysis compares odd/even 2023 actor-games ordered by date and game ID. The only split sensitivity compares the first `ceiling(G/2)` actor-games with the rest; the secondary analysis compares full 2023 and 2024 seasons. Rates pool opportunities within actor-half/year; Pearson correlations weight actors equally. No 2024 split, ranking, pressure denominator or adjusted score is computed.

Use the exact PBP/schedule snapshots above plus three preserved local opportunity/count manifests. These input manifests are not redistributed in this repository. Exact reproduction requires these matching bytes; the script never silently replaces them or downloads substitutes.

| Argument | Existing manifest | Required SHA256 |
|---|---|---|
| `COHORT_CSV` | `common_cohort_exposures.csv`, 20 IDs and annual E exposure counts | `4460604f27bbbe432fd42e9bbdcf426315844d5fb996f769bbd268fe375235bf` |
| `E_KEYS_CSV` | Annual comparison's `frozen_E_keys.csv` | `67f05a4386241620f24b4618ebd504931fa7659c5c8c57c4c9f5b2a3f9056808` |
| `D_KEYS_CSV` | Observed-value baseline's `frozen_baseline_keys.csv` | `be1f386ebc899a29043491f93568388863447d789705c2fc0833e46b85b6d946` |

Supply the full paths, including any timestamp prefixes, and an existing writable output directory outside Git. Only installed dplyr, readr, arrow and digest are required. The last argument identifies the fixed specification.

```sh
Rscript sack_repeatability.R "INPUT_2023" "INPUT_2024" "COHORT_CSV" "E_KEYS_CSV" "D_KEYS_CSV" "OUTPUT_DIR" "e60420a5020804a5cafcd3eaf559b20d17ab716c52e9130e32f48c6ae1f070d7"
```

Before calculating rates, the script verifies source hashes and fixed E/D keys, reconstructs membership and split maps as an independent check, and saves counts, keys, maps, contributing games and a design/script-hashed run manifest. Timestamped outputs include actor-half/year counts and rates, all whole-NFL-game deletions, paired-actor influence checks, unavailable statuses, and complement/known-mean arithmetic checks. Zero-sack records remain; missing diagnostic flags remain explicit.

Approximate 95% conditional working-model sensitivity intervals use Fisher-transformed correlations and delete complete NFL games across both teams, all selected actors and both half labels. Each season's replicates are centered on **their own mean**, then its finite-game variance contribution is summed. This prospectively specified annual centering differs from `annual_stability.R`; earlier CPOE outputs are unchanged. Undefined/boundary correlations or zero/nonfinite variance withhold the affected interval without dropping replicates or changing cohorts. These sensitivities do not establish NFL coverage, absolute agreement, player separation, pressure handling, isolated skill, prediction or overall decision quality; persistent surroundings, serial dependence, selection and rare sacks remain limitations.

</details>

<details>
<summary>Recorded run contribution</summary>

`rush_contribution.R` keeps the same fixed 20-ID cohort and distinguishes **S**, recorded scramble-runs within fixed dropbacks D, from **R**, recorded non-scramble actor runs outside D. R includes aborted and lateral plays and must not be called designed rushing. Combined opportunities are the disjoint union **O = D ∪ R**. For each role k, contribution is `sum(role EPA) / N_O`, combining frequency and shared observed value. Its denominator is not the role's run count. With no role opportunities, contribution is zero and per-role mean EPA is unavailable; neither describes zero ability.

Use the exact original PBP/schedule, common-cohort exposure CSV and baseline D-key manifest described above, plus these fixed keyed partitions (only `in_R=TRUE` keys are used; numeric EPA comes from the original typed PBP):

| Existing manifest | Required SHA256 |
|---|---|
| `rush_2023_keyed_partitions.csv` | `1648351bd64060d52041c9bfb977afe24cfde454788d013b7e4ffc3864f1ce36` |
| `rush_2024_keyed_partitions.csv` | `a555e4020169a987c66f73351e95975f3c07faff559def179ba93cdbb11ef22c` |

```sh
Rscript rush_contribution.R "INPUT_2023" "INPUT_2024" "COHORT_CSV" "D_KEYS_CSV" "R2023_KEYS_CSV" "R2024_KEYS_CSV" "OUTPUT_DIR" "347a063258182a6558a0b372fc465b2637f09038b02175e89b61c3e23b0cd932"
```

Supply existing paths, including timestamp prefixes where present, and an existing writable output directory outside Git. The script needs installed dplyr, readr, arrow and digest only. Missing/changed hashes or target attribution/EPA contradictions stop execution. It freezes source/specification/script hashes, cohort, O keys/counts and new O-game maps before EPA sums or rates.

The two primary analyses measure 2023 odd/even O-game associations for the two contributions. The two secondary analyses measure their full 2023–2024 associations. The script computes no other split or correlation contrast. Whole-NFL-game deletions remove both teams, roles and half labels while recomputing numerator and denominator on unchanged membership/maps. Each season's Fisher replicates use their own mean for conditional correlation intervals. Separate marginal actor-season ratio intervals use every actor O game, including zero-role games. Outputs retain shares, role counts/games, per-role means, overlapping aborted/lateral/fumble/penalty diagnostics, undefined statuses and paired-actor influence checks, sorted by ID rather than performance.

These are conditional working-model sensitivities, not demonstrated NFL coverage, rankings, forecasts or isolated mobility. R preserves whole-play and other participants' effects. S already contributes to EPA/D; the O-denominated measures must not be added to that D-denominated mean or presented as independent skill axes. Sparse signed EPA, usage/scheme, persistent support, selection and serial dependence limit interpretation. Website use requires a reviewed export-contract revision; this script does not publish comparison data.

</details>

<details>
<summary>Export the annual comparison data</summary>

`export_comparison.R` creates aggregate comparison JSON for the fixed 20-ID, 40-season-row cohort. It reconstructs CPOE and completion means only from the exact frozen in-cohort E keys joined one-to-one to the original PBP. It does not rerun eligibility, calculate individual CPOE/completion uncertainty or fit anything. Validation-only annual `r_C`, `r_B` and their difference must reproduce the fixed outputs within `1e-10`; disagreement stops export. EPA means, marginal conditional interval limits/statuses and dropback counts are copied from the existing baseline rows.

Use the exact PBP/schedule snapshots above, the fixed annual and baseline output prefixes (including trailing underscores), and two separate existing writable directories for public-ready assets and private run evidence:

```sh
Rscript export_comparison.R "INPUT_2023" "INPUT_2024" "ANNUAL_PREFIX_" "BASELINE_PREFIX_" "ASSET_DIR" "LOCAL_EVIDENCE_DIR"
```

The annual prefix must provide `annual_associations.csv`, `conditional_intervals.csv`, `cohort_counts.csv`, `frozen_E_keys.csv`, `verified_sources.csv` and `run_record.rds`. The baseline prefix must provide `actor_season_results.csv` and `run_record.rds`. Every file is pinned by SHA256 in the script; these retained local inputs are not redistributed here. Installed dplyr, readr, arrow, digest and jsonlite are sufficient.

Outputs are `nfl-qb-2023-2024-v1.json` and `nfl-qb-2023-2024-v1.manifest.json`. The manifest separately records the payload SHA256, schema/data versions, actual generation time, seasons, cohort/row counts, units and aggregate hashes. Consumers must reject a mismatched or stale pair. The exporter checks this pair, preserves differing existing assets by stopping, and never silently fetches replacements. This is data preparation; no consumer UI or deployment is included.

Rows use published GSIS IDs and observed abbreviated names, with source precision and native units. EPA performance remains separate from matched-row CPOE/completion; their denominators differ. Null interval limits indicate unavailability, never zero. No individual CPOE/completion intervals, FTN numbers, sack-study fields, percentiles, ranks, ratings or context-adjusted score are exported. Study-level intervals stay separate from player rows. Explicit public metadata preserves source attribution, transformation notices and analysis hashes; local paths, raw plays and run records remain private. PBP data attribution under CC BY 4.0 is separate from original-code MIT licensing. The conditional intervals do not establish NFL coverage, isolated skill, forecast validity or useful player separation.

</details>

<details>
<summary>Export the broader descriptive profile</summary>

`export_profile.R` packages fixed aggregates into schema v2 without rerunning eligibility, correlations or uncertainty calculations. It preserves every v1 player field and all three annual study rows, then adds recorded sack avoidance, separate scramble/non-scramble contributions and their existing marginal intervals. All three sack and four run study rows remain separate from the 40 player-season records.

```sh
Rscript export_profile.R "V1_JSON" "V1_MANIFEST" "SACK_PREFIX_" "RUSH_PREFIX_" "ASSET_DIR" "LOCAL_EVIDENCE_DIR"
```

Use existing, separate output directories outside Git and the exact retained aggregate snapshots pinned by SHA256 in the script. The sack prefix supplies `annual_actor_rates.csv`, `annual_counts.csv` and `results.csv`; annual side A means 2023, B means 2024. The run prefix supplies `actor_season_points.csv`, `actor_season_intervals.csv`, `results.csv`, `frozen_hashes.csv`, `run_manifest.rds`, `frozen_O_keys.csv` and `frozen_O_maps.csv`. Frozen keys/maps are hash-checked only and never serialized. Installed dplyr, readr, digest and jsonlite suffice.

Outputs are `nfl-qb-2023-2024-v2.json` and `nfl-qb-2023-2024-v2.manifest.json`, data version `2023-2024-broader-profile-v2`. The script verifies complete one-to-one actor-season mappings, unchanged v1 scalars, D/O/role denominator identities, known statuses, integer counts, all ten study rows, source-precision JSON round-trips and the matching manifest. It refuses changed inputs or differing existing assets and preserves v1. Public metadata distinguishes the earlier exporter from the actual v2 script and retains upstream notices. Local evidence records remain outside the public assets.

Native-unit domains use all 40 rows across both seasons and include available marginal endpoints. Signed measures include zero, percentages remain within 0–100, constant values expand by one native unit, and unavailable measures receive no invented domain. Correlations use −1 to 1, the paired correlation difference −2 to 2, and recorded composition 0–100 percent. Consumers must retain these shared scales and validate the payload digest, versions, generation time, counts, units, domains and input hashes against the manifest before use.

Run contributions use `sum(role EPA)/N_O`, combining frequency and shared value. Role shares are converted from fractions to percent once. Per-run EPA is a separate diagnostic; no recorded role events means zero count/share/contribution and a null per-run mean. Missing evidence is never zero. Recorded non-scramble runs include aborted and lateral plays and must not be called designed rushing. Composition uses disjoint other D passes, sacks, scrambles and R, rather than overlapping diagnostic flags.

Intervals remain conditional sensitivities, not tests of player differences or season changes. Annual CPOE retains its full-estimate-centered variance; sack/run studies retain their own-replicate-mean centering. The evidence does not establish independent traits, isolated mobility, forecasts, rankings, metric superiority or a context-adjusted overall score. A website must validate these files before using them, and data reuse remains subject to the source terms.

</details>

<details>
<summary>Independent annual and depth exports</summary>

The annual display selects qualifying recorded passers within each season, without requiring qualification in adjacent years. The older paired studies and their 20-player 2023–2024 cohort remain separate. All 560 annual records and their original 40-record overlap were independently reconciled before consumer use.

`annual_display.R` consumes preserved, hash-pinned count-audit manifests, the official GSIS-keyed display-name snapshot, immutable v2 assets for reconciliation, and depth-count evidence. It does not download replacement data. Supply an existing empty output directory; inputs and private ledgers stay outside version control.

```sh
Rscript annual_display.R "COUNT_PREFIX_" "PLAYERS_CSV" "V2_JSON" "V2_MANIFEST" "TRAIT_COUNT_DIR" "EMPTY_OUTPUT_DIR"
```

Outputs are `nfl-qb-annual-2006-2025-v1.json` (schema 3) and `nfl-qb-depth-2006-2025-v1.json` (schema 1), each with a matching digest manifest. The annual asset contains 560 records. The depth asset preserves 2,240 records, including a negative-depth diagnostic bin. Both catalogs show 2011 as source-blocked without fabricated performance rows. Original v2 files remain unchanged.

Depth bins use intended air yards: negative [−15,0), short [0,10), medium [10,20), and deep [20,70). Each residual is `100 × sum(completion − supplied completion probability) / included throws`, in percentage points. The bins partition the same eligible throws used for annual CPOE. They measure completion outcomes relative to a supplied expectation, rather than observed ball placement or isolated accuracy.

EPA intervals delete complete recorded-dropback games. Depth intervals delete every seasonal eligible-throw game, including games with no throws in the selected bin. These marginal game-jackknife sensitivities omit uncertainty in model calibration, source labels, supporting players and opportunity selection. They neither test differences between players, years or depths nor provide simultaneous 95% coverage across three depth positions. Sparse deep samples and unknown upstream CP/EP training vintage remain limitations.

Native display bounds are frozen over the complete fixed reference data, including available endpoints and zero for signed measures. The three displayed depth bins share one percentage-point domain. Any radial transformation is display geometry; equal distances across different statistics do not represent equal ability. These exports contain no percentile, arm-strength rating, processing score, overall winner or context-neutral talent estimate.

</details>

<details>
<summary>Annual recorded scramble contribution</summary>

`export_annual_mobility.R` extends the recorded scramble-contribution display to the same 560 qualifying player-seasons. It reconstructs disjoint recorded dropbacks **D** and recorded non-scramble actor runs **R**, then uses their union **O = D ∪ R**. The displayed contribution is `sum(scramble EPA) / number of O plays`. It combines scramble frequency with shared play value; it does not measure isolated mobility, running speed or designed-rushing skill.

```sh
Rscript export_annual_mobility.R "PBP_DIR" "SCHEDULE_DIR" "ACCEPTED_ASSETS_DIR" "EMPTY_OUTPUT_DIR"
```

Supply existing directories. `PBP_DIR` contains the 19 preserved `play_by_play_<year>.parquet` snapshots for 2006–2025 excluding 2011. `SCHEDULE_DIR` contains `historical_schedule_reference.rds` and `schedule_reference.rds`. `ACCEPTED_ASSETS_DIR` contains the unchanged v2, annual and depth JSON/manifest pairs described above. The exporter verifies every source and asset hash, the frozen annual membership and all selected opportunity-key sets before aggregation. It uses installed dplyr, readr, arrow, digest and jsonlite; no network download or additional package is required.

Outputs are `nfl-qb-mobility-2006-2025-v1.json` and its digest manifest, plus private verification, source-provenance, game-deletion and original-study reconciliation files. Keep the latter files outside version control. The original six assets and the 40-record paired study remain unchanged. Reproduction requires their exact retained snapshots; changing a filename or retrieving a newer release is insufficient.

The export contains 559 finite contributions. Kyle Boller’s 2007 record retains its counts, but one non-scramble opportunity has a recorded-role contradiction, so the point and range remain unavailable. 2011 remains excluded. Four seasons with no recorded scrambles retain genuine zero contributions and collapsed conditional ranges; missing evidence is never assigned zero. Historical team-code aliases are normalized solely for schedule comparisons, without altering raw sources or opportunity membership.

Conditional game-jackknife ranges delete every O game, including games with no scrambles and eight games containing only R opportunities. They describe sensitivity to the observed game sample, not demonstrated coverage, player differences or forecasts. Any consumer percentile must use finite values from the selected season’s frozen peer group, with its actual N displayed; it must not reuse the earlier paired cohort. Supporting players, scheme, opportunity selection, unknown upstream EP model vintage and whole-play attribution remain limitations.

</details>

<details>
<summary>Optional evidence-summary figure</summary>

`plot_repeatability.R` reads existing interleaved/chronological pilot and annual interval CSVs plus their cohort-count CSVs; it performs no estimation. Supply the two full output prefixes, including their trailing underscores, and an unused PNG path in an existing local output directory. The figure distinguishes the two correlations from their paired difference and labels the different cohorts; it is an evidence summary rather than a player skill chart.

```sh
Rscript plot_repeatability.R "PILOT_PREFIX_" "ANNUAL_PREFIX_" "NEW_OUTPUT.png"
```

</details>

## Methods and limitations

Annual eligibility requires at least 200 model-eligible throws in ten games within
each season. The annual view selects each season on its own. The separate
2023–2024 studies use 20 regular-use passers who qualify in both seasons, so those
results describe a more selective group. Neither sample is a position-certified
census of NFL quarterbacks.

The studies compare nflfastR completion percentage over expected (CPOE) with
ordinary completion percentage on the same eligible 2023 throws, examine their
2023–2024 association, and study sack avoidance and recorded run contribution
across fixed game sets and seasons. Repeatability is one piece of evidence; it
cannot by itself separate skill from persistent teammates, coaching or scheme.

Completion residuals compare outcomes with the supplied model's expectation.
Expected points added (EPA) is shared play value. Passing-depth residuals do not
measure ball placement, and recorded scramble contribution combines frequency
with whole-play value. ESPN ranks are expert judgments, not measured skill
percentiles. These sources do not establish seven isolated skills or an overall
talent score.

The reported game-jackknife ranges describe how estimates change when observed
games are left out under the working assumptions. They omit uncertainty in the
upstream models and supporting context. Serial dependence, survivor selection
and unknown completion-probability and expected-points model training dates remain
limitations. One annual transition does not establish repeated forecast validation.

The annual exports exclude 2011 because of unresolved duplicate-event and
pass-depth conflicts. Kyle Boller's 2007 scramble contribution retains its counts
but withholds its value and range because one non-scramble opportunity has a
recorded-role contradiction. Genuine zero events and missing evidence remain
different states.

## Data and license

The [MIT license](LICENSE) covers original project code. Third-party data retain separate terms:

- PBP is distributed through nflverse under the [nflverse-data CC BY 4.0 license](https://github.com/nflverse/nflverse-data/blob/master/LICENSE.md). Retain applicable attribution and source notices.
- The released FTN subset is documented as CC BY-SA 4.0 with attribution **FTN Data via nflverse**; see the [official FTN loader documentation](https://nflreadr.nflverse.com/reference/load_ftn_charting.html). This does not grant rights to unreleased FTN products.
- The separately maintained [nfldata schedule source](https://github.com/nflverse/nfldata) has its own upstream notices. Dataset availability and the code's MIT license do not settle every proposed derived-output use.

The published aggregates in `public/data/` derive from nflverse PBP and retain CC BY 4.0 attribution and transformation notices in their metadata. Their data terms remain separate from the MIT license for original project code. Raw inputs and numerical FTN-derived outputs are not redistributed here.

The chart code also contains minimal attributed ESPN preseason ranking facts, with links, actual editions, categories, dates, and panel or author descriptions. These are expert judgments rather than tracking measurements, and ranks are not skill percentiles. ESPN material is not covered by this repository's MIT license or represented as an openly licensed dataset. No full articles are reproduced.

Additional datasets, combined databases, figures or other derived outputs require their own source-specific attribution and permissions assessment.
