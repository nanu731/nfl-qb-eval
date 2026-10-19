# nfl-qb-eval

Can public NFL data help describe repeatable quarterback execution with less dependence on supporting circumstances? This exploratory project also aims eventually to evaluate context-aware performance while preserving credit for excellent actual play. Neither goal is an established capability.

Current code audits inputs, compares supplied nflfastR completion percentage over expected (CPOE) with ordinary completion percentage on identical eligible 2023 throws, and describes their 2023–2024 annual associations. These analyses concern selected regular-use passers, not a position-certified quarterback cohort or a validated overall score. Conditional game-jackknife intervals are working-model sensitivities; persistent context, serial dependence, survivor selection, and unknown CP model/training vintage remain limitations. One annual transition is not a clean historical forecast or repeated temporal validation.

## Scripts and prerequisites

- `audit_inputs.R`: downloads and audits official 2023 PBP/FTN inputs and a schedule reference; preserves originals and provenance receipts.
- `pilot_accuracy.R`: uses existing exact snapshots for the 2023 same-throw interleaved/chronological split comparison and count-only FTN diagnostics.
- `annual_stability.R`: uses existing exact PBP/schedule snapshots for the paired 2023–2024 annual comparison. Each year is a fixed stratum; leave-game deviations are centered on the full estimate, not the deletion mean. FTN is unnecessary for this script.

The scripts use installed R packages; they do not install dependencies. Tested with R 4.6.0 and:

| Package | Tested version | Used by |
|---|---|---|
| dplyr | 1.2.1 | All scripts; requires the modern join `relationship` argument |
| readr | 2.2.0 | All scripts |
| arrow | 25.0.0 | All scripts, reading Parquet |
| digest | 0.6.39 | All scripts, SHA256 verification |
| stringr | 1.6.0 | All scripts, frozen receiver-description rule |
| tidyr | 1.3.2 | Pilot and annual comparison |
| curl | 7.1.0 | Input audit downloads |
| jsonlite | 2.0.0 | Input audit release metadata |

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

## Code and data terms

Original project code is [MIT licensed](LICENSE). Third-party data have separate terms:

- PBP is distributed through nflverse under the [nflverse-data CC BY 4.0 license](https://github.com/nflverse/nflverse-data/blob/master/LICENSE.md). Retain applicable attribution and source notices.
- The released FTN subset is documented as CC BY-SA 4.0 with attribution **FTN Data via nflverse**; see the [official FTN loader documentation](https://nflreadr.nflverse.com/reference/load_ftn_charting.html). This does not grant rights to unreleased FTN products.
- The separately maintained [nfldata schedule source](https://github.com/nflverse/nfldata) has its own upstream notices. Dataset availability and the code's MIT license do not settle every proposed derived-output use.

Raw inputs and numerical FTN-derived outputs are not redistributed here. Any future public dataset, combined database, figure, or other derived output requires source-specific attribution and permissions assessment.
