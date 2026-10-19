# Export existing annual CPOE/completion and raw-EPA summaries, schema v1.
# Usage: Rscript export_comparison.R <2023-inputs> <2024-inputs>
#        <annual-prefix> <baseline-prefix> <existing-asset-dir> <existing-local-evidence-dir>
# Reconstructs means on frozen E keys only; no eligibility, uncertainty or model fit.
# Original code MIT; aggregate PBP data retain nflverse CC BY 4.0 attribution.
suppressPackageStartupMessages({library(dplyr); library(readr)})
stopifnot(all(vapply(c("arrow", "digest", "jsonlite"), requireNamespace, logical(1), quietly = TRUE)))
args <- commandArgs(trailingOnly = TRUE)
if (length(args) != 6 || !all(dir.exists(args[c(1, 2, 5, 6)]))) {
  stop("Supply input workspaces, annual/baseline prefixes, existing asset directory and separate local evidence directory.")
}
work2023 <- normalizePath(args[1], mustWork = TRUE)
work2024 <- normalizePath(args[2], mustWork = TRUE)
asset_dir <- normalizePath(args[5], mustWork = TRUE)
evidence_dir <- normalizePath(args[6], mustWork = TRUE)
stopifnot(asset_dir != evidence_dir)
run <- paste0(format(Sys.time(), "%Y%m%dT%H%M%S", tz = "UTC"), "_export_", Sys.getpid(), "_")
local_path <- function(suffix) file.path(evidence_dir, paste0(run, suffix))
emit <- function(x, name) {
  f <- local_path(paste0(name, ".csv"))
  stopifnot(!file.exists(f)); write_csv(x, f, na = "NA")
}
sha <- function(f) digest::digest(file = f, algo = "sha256")
contract_hash <- "4522244b7399f0d4d93ab7622c92159525eeb27cd9a66046ee8f9658f6044da1"
inputs <- tibble(
  label = c("pbp2023", "pbp2024", "schedule", "annual_associations", "annual_intervals", "cohort", "E_keys",
    "baseline_rows", "annual_sources", "annual_record", "baseline_record"),
  file = c(file.path(work2023, "play_by_play_2023.parquet"), file.path(work2024, "play_by_play_2024.parquet"),
    file.path(work2023, "schedule_reference.rds"),
    paste0(args[3], c("annual_associations.csv", "conditional_intervals.csv", "cohort_counts.csv", "frozen_E_keys.csv")),
    paste0(args[4], "actor_season_results.csv"), paste0(args[3], c("verified_sources.csv", "run_record.rds")),
    paste0(args[4], "run_record.rds")),
  sha256 = c("bd3484731408def6b0ec93225bba2bd7b2c65769ca707a2b9444d891abdc6776",
    "3fd2896bc0b911b615142d2f1fabae54a4bbba5ab7b73b28187b118ef8af6a3b",
    "659e4ae782353bb80d196c6789e11eae545a93be9fdb668dd3e3ae4fdac860eb",
    "d78c2e97829ae77c3ffdbdb7002011bd4bc2809250da4fcc5269af32be99302f",
    "1fab47c8ba471d9568fdd19383a8e8756e6c40fac019a248dbe696feb1c88ff7",
    "2d4322731540a760c83f4bbea231f14581ca3b34bdc8c2376271d11ffe5546ba",
    "67f05a4386241620f24b4618ebd504931fa7659c5c8c57c4c9f5b2a3f9056808",
    "e01104a873504a636ecb62a68f47df2e958dba158892b6ae6b79038dfc1404dc",
    "e0e9b2e279824fcb8e1818f321643d8f70e95f8beec4d6bc2bc6afc8ef1c8bfd",
    "c6fd5e35194a84d41614ac5cbe6dcf1120644dfd21f1ba398f2ec2fd93c9bfd2",
    "3365a7b387987a9fc11cfa2dcde0a13ceb6e60a4ae4f10e24e9319f751e33b03"))
for (i in seq_len(nrow(inputs))) stopifnot(file.exists(inputs$file[i]), sha(inputs$file[i]) == inputs$sha256[i])
inputs <- mutate(inputs, bytes = file.info(file)$size)
stopifnot(all(inputs$bytes[1:3] == c(20534088, 20597560, 428923)))
emit(inputs, "verified_inputs")
read_input <- function(label) read_csv(inputs$file[match(label, inputs$label)], show_col_types = FALSE)
annual <- read_input("annual_associations"); intervals <- read_input("annual_intervals")
counts <- read_input("cohort"); E_all <- read_input("E_keys"); baseline <- read_input("baseline_rows")
expected_columns <- list(
  annual = c("r_C", "r_B", "Delta", "C_status", "B_status", "Delta_status"),
  intervals = c("statistic", "estimate", "variance_scale", "variance", "SE", "lower", "upper", "status"),
  counts = c("passer_player_id", "season", "E_throws", "E_games", "qualifies_year", "observed_year", "passer_player_name", "qualifies_both"),
  keys = c("season", "game_id", "play_id", "passer_player_id", "in_cohort"),
  baseline = c("actor_id", "season", "actor_name", "opportunities", "games", "total_epa", "mean_epa", "deletion_center",
    "jackknife_variance", "SE", "lower", "upper", "deletion_min", "deletion_max", "interval_status",
    "other_pass", "sacks", "scrambles", "played_penalty", "penalty_unknown", "missing_cp"))
stopifnot(identical(names(annual), expected_columns$annual), identical(names(intervals), expected_columns$intervals),
  identical(names(counts), expected_columns$counts), identical(names(E_all), expected_columns$keys),
  identical(names(baseline), expected_columns$baseline), nrow(annual) == 1,
  identical(intervals$statistic, c("r_C", "r_B", "Delta")),
  all(unlist(annual[c("C_status", "B_status", "Delta_status")]) == "defined"),
  !anyNA(E_all), !anyDuplicated(E_all[c("season", "game_id", "play_id")]),
  !anyDuplicated(counts[c("passer_player_id", "season")]), !anyDuplicated(baseline[c("actor_id", "season")]))
cohort <- filter(counts, qualifies_both) |> arrange(passer_player_id, season)
ids <- sort(unique(cohort$passer_player_id))
stopifnot(length(ids) == 20, nrow(cohort) == 40, all(cohort$E_throws >= 200 & cohort$E_games >= 10),
  setequal(cohort$season, c(2023, 2024)), nrow(baseline) == 40,
  all(cohort$qualifies_year), all(cohort$observed_year), all(grepl("^00-[0-9]{7}$", ids)),
  setequal(baseline$actor_id, ids), setequal(baseline$season, c(2023, 2024)))
E <- filter(E_all, in_cohort) |> arrange(season, game_id, play_id)
stopifnot(setequal(E$passer_player_id, ids))
# The accepted keys define the entire sample; no eligibility expression is rerun.
throws <- bind_rows(lapply(c(2023, 2024), function(year) {
  f <- inputs$file[match(paste0("pbp", year), inputs$label)]
  source <- arrow::read_parquet(f, col_select = c("season", "season_type", "game_id", "play_id",
    "passer_player_id", "passer_player_name", "complete_pass", "cp", "cpoe"))
  stopifnot(is.character(source$game_id), is.character(source$passer_player_id),
    is.numeric(source$play_id), !anyNA(source[c("game_id", "play_id")]),
    !anyDuplicated(source[c("game_id", "play_id")]))
  k <- filter(E, season == year)
  joined <- left_join(k, select(source, -passer_player_id), by = c("season", "game_id", "play_id"), relationship = "one-to-one")
  reconciled <- inner_join(k, select(source, season, game_id, play_id, source_id = passer_player_id),
    by = c("season", "game_id", "play_id"), relationship = "one-to-one")
  stopifnot(nrow(reconciled) == nrow(k), all(reconciled$passer_player_id == reconciled$source_id),
    nrow(joined) == nrow(k), all(joined$season_type == "REG"),
    all(is.finite(joined$cpoe)), all(is.finite(joined$cp)), all(joined$cp >= 0 & joined$cp <= 1),
    all(joined$complete_pass %in% c(0, 1)),
    all(abs(joined$cpoe - 100 * (joined$complete_pass - joined$cp)) <= 1e-8))
  joined
}))
stopifnot(nrow(throws) == nrow(E), !anyDuplicated(throws[c("season", "game_id", "play_id")]))
means <- throws |> group_by(passer_player_id, season) |> summarise(
  throws_from_keys = n(), games_from_keys = n_distinct(game_id), n_names = n_distinct(passer_player_name),
  source_name = first(passer_player_name), cpoe_pp = mean(cpoe), completion_pct = 100 * mean(complete_pass), .groups = "drop")
matched <- left_join(cohort, means, by = c("passer_player_id", "season"), relationship = "one-to-one") |>
  left_join(baseline, by = c("passer_player_id" = "actor_id", "season"), relationship = "one-to-one") |>
  arrange(passer_player_id, season)
stopifnot(nrow(matched) == 40, all(matched$throws_from_keys == matched$E_throws),
  all(matched$games_from_keys == matched$E_games), all(matched$n_names == 1),
  !anyNA(matched$passer_player_name), all(matched$passer_player_name == matched$source_name),
  all(matched$passer_player_name == matched$actor_name), all(matched$opportunities > 0), all(matched$games > 0))
totals <- matched |> group_by(season) |> summarise(E_N = sum(E_throws), E_actor_games = sum(E_games),
  D_N = sum(opportunities), D_actor_games = sum(games), .groups = "drop") |> arrange(season)
stopifnot(all(totals$E_N == c(9705, 8517)), all(totals$D_N == c(11371, 9989)),
  all(totals$E_actor_games == c(309, 288)), all(totals$D_actor_games == c(309, 288)))
a <- filter(matched, season == 2023); b <- filter(matched, season == 2024)
stopifnot(identical(a$passer_player_id, ids), identical(b$passer_player_id, ids))
reconstructed <- c(r_C = cor(a$cpoe_pp, b$cpoe_pp), r_B = cor(a$completion_pct, b$completion_pct))
reconstructed <- c(reconstructed, Delta = unname(reconstructed[1] - reconstructed[2]))
accepted <- as.numeric(annual[1, c("r_C", "r_B", "Delta")])
stopifnot(all(is.finite(reconstructed)), all(abs(reconstructed - accepted) <= 1e-10),
  all(abs(intervals$estimate - accepted) <= 1e-10))
emit(tibble(statistic = names(reconstructed), reconstructed = unname(reconstructed), accepted = accepted,
  absolute_error = abs(unname(reconstructed) - accepted), tolerance = 1e-10), "association_guard")
emit(totals, "denominator_guards")
rows <- matched |> transmute(player_key = passer_player_id, observed_name = passer_player_name,
  season = as.integer(season), eligible_throws = as.integer(E_throws), eligible_games = as.integer(E_games),
  cpoe_pp, completion_pct, dropbacks = as.integer(opportunities), dropback_games = as.integer(games),
  epa_per_dropback = mean_epa, epa_lower = lower, epa_upper = upper, epa_interval_status = interval_status)
row_fields <- c("player_key", "observed_name", "season", "eligible_throws", "eligible_games", "cpoe_pp", "completion_pct",
  "dropbacks", "dropback_games", "epa_per_dropback", "epa_lower", "epa_upper", "epa_interval_status")
validate_rows <- function(r) {
  stopifnot(identical(names(r), row_fields), nrow(r) == 40, !anyDuplicated(r[c("player_key", "season")]),
    is.character(r$player_key), is.character(r$observed_name), is.character(r$epa_interval_status),
    length(unique(r$player_key)) == 20, setequal(r$season, c(2023, 2024)),
    all(vapply(r[3:12], is.numeric, logical(1))),
    !anyNA(r[c("player_key", "observed_name", "epa_interval_status")]),
    all(nzchar(r$player_key)), all(nzchar(r$observed_name)), all(nzchar(r$epa_interval_status)))
  for (f in c("season", "eligible_throws", "eligible_games", "dropbacks", "dropback_games"))
    stopifnot(all(is.finite(r[[f]])), all(r[[f]] > 0), all(r[[f]] == floor(r[[f]])))
  stopifnot(all(is.finite(r$cpoe_pp)), all(is.finite(r$completion_pct)), all(is.finite(r$epa_per_dropback)),
    all(r$completion_pct >= 0 & r$completion_pct <= 100), all(abs(r$cpoe_pp) <= 100),
    all(r$eligible_throws >= 200), all(r$eligible_games >= 10),
    identical(is.na(r$epa_lower), is.na(r$epa_upper)))
  available <- !is.na(r$epa_lower)
  stopifnot(all(is.finite(r$epa_lower[available])), all(is.finite(r$epa_upper[available])),
    all(r$epa_lower[available] <= r$epa_upper[available]),
    all(r$epa_interval_status[available] %in% c("approximate_conditional_game_sampling_sensitivity", "collapsed_no_observed_deletion_variation")),
    !any(r$epa_interval_status[!available] %in% c("approximate_conditional_game_sampling_sensitivity", "collapsed_no_observed_deletion_variation")))
  invisible(TRUE)
}
validate_rows(rows)
# Explicit native-unit/source-field mapping; no individual CPOE intervals exist.
stopifnot(identical(rows$epa_per_dropback, matched$mean_epa), identical(rows$epa_lower, matched$lower),
  identical(rows$epa_upper, matched$upper), identical(rows$epa_interval_status, matched$interval_status))
emit(rows, "source_precision_rows")
annual_record <- readRDS(inputs$file[match("annual_record", inputs$label)])
baseline_record <- readRDS(inputs$file[match("baseline_record", inputs$label)])
script <- sub("^--file=", "", grep("^--file=", commandArgs(), value = TRUE))
script_hash <- sha(script)
# Select a small public metadata allowlist; never serialize a local run record.
analysis_metadata <- function(r) list(version = r$specification_version,
  specification_sha256 = r$specification_sha256, script_sha256 = r$script_sha256)
units <- list(cpoe_pp = "percentage_points", completion_pct = "percent", epa_per_dropback = "expected_points_per_dropback",
  epa_lower = "expected_points_per_dropback", epa_upper = "expected_points_per_dropback", study_associations = "dimensionless",
  eligible_throws = "throws", eligible_games = "actor_games", dropbacks = "dropbacks", dropback_games = "actor_games")
aggregate_labels <- c("annual_associations", "annual_intervals", "cohort", "E_keys", "baseline_rows")
aggregate_hashes <- setNames(as.list(inputs$sha256[match(aggregate_labels, inputs$label)]), aggregate_labels)
generated <- format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
payload <- list(schema_version = 1L, data_version = "2023-2024-annual-baseline-v1", generated_utc = generated,
  seasons = c(2023L, 2024L), cohort = list(count = 20L, rows = 40L,
    definition = "Same 20 published GSIS IDs with at least 200 accepted E throws and ten E games in each season; fixed membership across team changes.",
    limitation = "CP-related survivor-selected regular-use actors, not position-certified or all NFL quarterbacks.",
    identifier = "published nflverse/GSIS player ID", name = "observed abbreviated source label; no inferred full names"),
  units = units,
  denominators = list(cpoe_pp = "Mean supplied CPOE on the exact frozen in-cohort E keys.",
    completion_pct = "100 times mean complete_pass on those identical E keys.",
    epa_per_dropback = "Recorded played passes, sacks and scramble-runs; no CP, EPA-availability, E-game, penalty or description filter. Shared possession-team play value.",
    actor_games = "Sums of actor-game counts are not distinct NFL-game counts."),
  uncertainty = list(cpoe_pp = "Individual uncertainty not estimated.", completion_pct = "Individual uncertainty not estimated.",
    epa = "Existing approximate 95% marginal conditional actor-game-sampling sensitivities, centered on the deletion mean; not paired-player, difference or rank intervals.",
    study_associations = "Existing approximate 95% conditional whole-NFL-game working-model sensitivities; annual season-specific deviations centered on the full estimate.",
    limits = "No demonstrated NFL coverage, causal isolation, forecast, useful player separation or CPOE superiority; persistent context, serial dependence, survivor selection and unknown CP model vintage remain.",
    unavailable = "Null interval limits mean unavailable, not zero; preserve interval status."),
  sources = list(
    list(id = "pbp_2023", url = "https://github.com/nflverse/nflverse-data/releases/download/pbp/play_by_play_2023.parquet",
      sha256 = inputs$sha256[1], license = "CC BY 4.0", license_url = "https://creativecommons.org/licenses/by/4.0/"),
    list(id = "pbp_2024", url = "https://github.com/nflverse/nflverse-data/releases/download/pbp/play_by_play_2024.parquet",
      sha256 = inputs$sha256[2], license = "CC BY 4.0", license_url = "https://creativecommons.org/licenses/by/4.0/"),
    list(id = "schedule_reference", url = "https://raw.githubusercontent.com/nflverse/nfldata/1bc55c1a32253a78875ca786f8492479a2006567/data/games.rds",
      sha256 = inputs$sha256[3], notices_url = "https://github.com/nflverse/nfldata")),
  attribution = list(data = "PBP data: nflverse, CC BY 4.0. Aggregated and transformed for this analysis.",
    source_notices = "Retain applicable upstream notices and disclaimers; no endorsement is implied. Schedule reference has separate upstream notices.",
    data_license_url = "https://github.com/nflverse/nflverse-data/blob/master/LICENSE.md",
    analysis_repository = "https://github.com/nanu731/nfl-qb-eval", code_license = "MIT",
    transformation_notice = "Aggregated exact frozen eligible throws to player-season CPOE and completion means; copied existing raw-EPA summaries and conditional intervals. No new uncertainty estimation."),
  analysis_versions = list(annual = analysis_metadata(annual_record), baseline = analysis_metadata(baseline_record),
    export = list(version = "1.1", specification_sha256 = contract_hash, script_sha256 = script_hash)),
  aggregate_input_hashes = aggregate_hashes, rows = rows, study_associations = intervals)
serialize <- function(x) paste0(as.character(jsonlite::toJSON(x, auto_unbox = TRUE, dataframe = "rows", digits = 17,
  na = "null", null = "null", pretty = TRUE)), "\n")
json <- serialize(payload)
stopifnot(jsonlite::validate(json))
roundtrip <- jsonlite::fromJSON(json)
validate_rows(roundtrip$rows)
stopifnot(isTRUE(all.equal(as.data.frame(rows), roundtrip$rows, tolerance = 0, check.attributes = FALSE)),
  isTRUE(all.equal(as.data.frame(intervals), roundtrip$study_associations, tolerance = 0, check.attributes = FALSE)))
# NA serialization is checked without altering any source observation.
null_fixture <- jsonlite::fromJSON(serialize(list(unavailable = NA_real_, observed_zero = 0)))
stopifnot(is.null(null_fixture$unavailable), identical(null_fixture$observed_zero, 0L) || identical(null_fixture$observed_zero, 0))
# Repeated serialization of the same source-precision object is deterministic.
stopifnot(identical(serialize(payload), json))
forbidden <- c("/Users/", "/private/", "file://", ".local.md", "@users.noreply", "workspace", "run_record", "game_id", "play_id", "FTN")
stopifnot(!any(vapply(forbidden, function(s) grepl(s, json, fixed = TRUE), logical(1))))
# Complete top-level and row-field allowlists prevent accidental future additions.
allowed_top <- c("schema_version", "data_version", "generated_utc", "seasons", "cohort", "units", "denominators", "uncertainty",
  "sources", "attribution", "analysis_versions", "aggregate_input_hashes", "rows", "study_associations")
stopifnot(identical(names(roundtrip), allowed_top), identical(roundtrip$schema_version, 1L),
  identical(roundtrip$data_version, "2023-2024-annual-baseline-v1"), identical(roundtrip$seasons, c(2023L, 2024L)))
asset_name <- "nfl-qb-2023-2024-v1.json"
manifest_name <- "nfl-qb-2023-2024-v1.manifest.json"
asset <- file.path(asset_dir, asset_name); manifest_file <- file.path(asset_dir, manifest_name)
payload_hash <- digest::digest(charToRaw(json), algo = "sha256", serialize = FALSE)
manifest <- list(schema_version = 1L, data_version = payload$data_version, generated_utc = generated,
  payload = list(filename = asset_name, sha256 = payload_hash), seasons = c(2023L, 2024L),
  cohort_count = 20L, row_count = 40L, units = units, aggregate_input_hashes = aggregate_hashes,
  export_script_sha256 = script_hash)
manifest_json <- serialize(manifest)
stopifnot(jsonlite::validate(manifest_json))
# Validate the candidate pair before writing; never overwrite a differing asset.
for (i in seq_along(c(asset, manifest_file))) {
  f <- c(asset, manifest_file)[i]; bytes <- charToRaw(c(json, manifest_json)[i])
  if (file.exists(f) && !identical(readBin(f, "raw", n = file.info(f)$size), bytes))
    stop("Existing asset differs; preserve it and authorize a new version: ", basename(f))
}
for (i in seq_along(c(asset, manifest_file))) {
  f <- c(asset, manifest_file)[i]
  if (!file.exists(f)) writeBin(charToRaw(c(json, manifest_json)[i]), f)
}
stopifnot(sha(asset) == manifest$payload$sha256)
written <- jsonlite::fromJSON(asset); fresh <- jsonlite::fromJSON(manifest_file)
stopifnot(written$schema_version == fresh$schema_version, written$data_version == fresh$data_version,
  identical(written$generated_utc, fresh$generated_utc), identical(written$seasons, fresh$seasons),
  written$cohort$count == fresh$cohort_count, nrow(written$rows) == fresh$row_count,
  identical(written$units, fresh$units), identical(written$aggregate_input_hashes, fresh$aggregate_input_hashes))
record <- list(export_specification = "1.1", contract_sha256 = contract_hash, script_sha256 = script_hash,
  generated_utc = generated, inputs = inputs, annual_record = annual_record, baseline_record = baseline_record,
  asset = asset, manifest = manifest_file, payload_sha256 = sha(asset), manifest_sha256 = sha(manifest_file),
  args = args, stages = c("hash_schema_key_denominator_checks", "accepted_association_reproduction", "explicit_public_allowlist", "roundtrip_precision_null_and_pair_checks"))
saveRDS(record, local_path("run_record.rds"))
emit(tibble(check = c("source_hashes", "one_to_one_E_keys", "fixed_cohort_denominators", "accepted_association_guard", "source_mapping",
  "JSON_schema_roundtrip_precision", "null_not_zero", "metadata_allowlist", "freshness_pair", "deterministic_content"), passed = TRUE), "verification")
writeLines(capture.output(sessionInfo()), local_path("sessionInfo.txt"))
cat("Exported:", asset, "\nManifest:", manifest_file, "\nPayload SHA256:", sha(asset), "\nLocal evidence prefix:", local_path(""), "\n")
