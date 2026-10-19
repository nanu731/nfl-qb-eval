# Package accepted 2023/2024 player-season aggregates, schema v2.
# Usage: Rscript export_profile.R <v1-json> <v1-manifest> <sack-prefix>
#        <rush-prefix> <existing-asset-dir> <existing-local-evidence-dir>
# Copies estimates/intervals; checks arithmetic identities without new estimation.
# Original code MIT; aggregate PBP data retain nflverse CC BY 4.0 attribution.
suppressPackageStartupMessages({library(dplyr); library(readr)})
stopifnot(all(vapply(c("digest", "jsonlite"), requireNamespace, logical(1), quietly = TRUE)))
args <- commandArgs(trailingOnly = TRUE)
if (length(args) != 6 || !all(dir.exists(args[5:6])))
  stop("Supply v1 JSON/manifest, sack/rush prefixes, and two existing separate output directories.")
asset_dir <- normalizePath(args[5], mustWork = TRUE)
evidence_dir <- normalizePath(args[6], mustWork = TRUE)
stopifnot(asset_dir != evidence_dir)
run <- paste0(format(Sys.time(), "%Y%m%dT%H%M%S", tz = "UTC"), "_profile_", Sys.getpid(), "_")
local_path <- function(suffix) file.path(evidence_dir, paste0(run, suffix))
emit <- function(x, suffix) { f <- local_path(paste0(suffix, ".csv")); stopifnot(!file.exists(f)); write_csv(x, f, na = "NA") }
sha <- function(f) digest::digest(file = f, algo = "sha256")
contract_hash <- "ce69303df3bb8708a3d85992bdf6c03bbf0215c7f71f69cf07911d7529328149"
# This exact scientific/mapping revision was accepted before implementation.
inputs <- tibble(
  label = c("v1_payload", "v1_manifest", "sack_rates", "sack_counts", "sack_results", "rush_points", "rush_intervals",
    "rush_results", "rush_frozen_hashes", "rush_manifest", "rush_O_keys", "rush_O_maps"),
  file = c(args[1:2], paste0(args[3], c("annual_actor_rates.csv", "annual_counts.csv", "results.csv")),
    paste0(args[4], c("actor_season_points.csv", "actor_season_intervals.csv", "results.csv", "frozen_hashes.csv",
      "run_manifest.rds", "frozen_O_keys.csv", "frozen_O_maps.csv"))),
  sha256 = c("66264611b91e2f0666facb71dcb42cd05160d1f9f2f095702ce27c96486365d0",
    "e3fd1808b0aae47ce53fc2e9ef388a237f11eba53c604d2bae75f03b817a17c2",
    "c5fe5f8bdd73f1d38a5ed5b65ea7dfb4c73027ccb593169b96fd357024f7bde0",
    "d07d030d99969720598754e9e23712904f70ead59342ea4f8dc67e9cff924647",
    "92afb33f9c1b0f3890c23eb2562062c2eb447f8ba07722b763777fd78582b28d",
    "0b5b8f6c9d13e65cdafaf057fceba6f53d7f46b3a19707a1e11d84ef2b22508e",
    "30eed49d888ba7c2ab079a00bad2c53fe3a4646dd32a3deabe9759541f9bac26",
    "e07aa3a0ef149fd3c2705e6b63aca4964ae98835be03a1a9c565f3ebb8b3c893",
    "9cee899a995364d6c13ccb0fce426fdfd2d8fd51a1299939e0c93f3aac868934",
    "44eceec8d0c2b009975487d6fa80761f0fd4cb6b3cb2b4f3c52bb7ec40b15050",
    "8fde2aa8c2253f5a07292549fa297941c329648bdfb84a4a9dab151e6b48739b",
    "563457a68f8d251561236601c6aae8c9a0018d4c3765556accd037f8529b935f"))
for (i in seq_len(nrow(inputs)))
  if (!file.exists(inputs$file[i]) || sha(inputs$file[i]) != inputs$sha256[i]) stop("Missing/changed pinned input: ", inputs$label[i])
inputs <- mutate(inputs, bytes = file.info(file)$size)
emit(inputs, "verified_inputs")
path <- function(label) inputs$file[match(label, inputs$label)]
read_input <- function(label, columns) {
  x <- read_csv(path(label), show_col_types = FALSE)
  stopifnot(identical(names(x), columns)); x
}
v1 <- jsonlite::fromJSON(path("v1_payload"))
v1_manifest <- jsonlite::fromJSON(path("v1_manifest"))
stopifnot(v1$schema_version == 1L, v1$data_version == "2023-2024-annual-baseline-v1",
  v1_manifest$payload$filename == basename(path("v1_payload")), v1_manifest$payload$sha256 == sha(path("v1_payload")),
  identical(v1$generated_utc, v1_manifest$generated_utc), identical(v1$data_version, v1_manifest$data_version),
  identical(v1$schema_version, v1_manifest$schema_version), identical(v1$seasons, v1_manifest$seasons),
  identical(v1$units, v1_manifest$units), identical(v1$aggregate_input_hashes, v1_manifest$aggregate_input_hashes),
  v1$cohort$count == v1_manifest$cohort_count, nrow(v1$rows) == v1_manifest$row_count)
base_fields <- c("player_key", "observed_name", "season", "eligible_throws", "eligible_games", "cpoe_pp", "completion_pct",
  "dropbacks", "dropback_games", "epa_per_dropback", "epa_lower", "epa_upper", "epa_interval_status")
b <- v1$rows
stopifnot(identical(names(b), base_fields), nrow(b) == 40, !anyDuplicated(b[c("player_key", "season")]),
  length(unique(b$player_key)) == 20, all(grepl("^00-[0-9]{7}$", b$player_key)),
  setequal(b$season, c(2023L, 2024L)), all(table(b$player_key) == 2),
  !anyNA(b[c("player_key", "observed_name")]), all(nzchar(b$observed_name)),
  all(b$eligible_throws >= 200), all(b$eligible_games >= 10),
  all(vapply(split(b$observed_name, b$player_key), function(x) length(unique(x)) == 1, logical(1))))
k <- read_input("sack_counts", c("actor_id", "season", "N", "games", "sacks", "scrambles", "interception_observed_one",
  "interception_unknown", "interception_nonbinary", "fumble_lost_observed_one", "fumble_lost_unknown", "fumble_lost_nonbinary",
  "penalty_observed_one", "penalty_unknown", "penalty_nonbinary"))
kr <- read_input("sack_rates", c("actor_id", "side", "N", "S", "avoidance", "sack_rate"))
stopifnot(all(kr$side %in% c("A", "B")))
kr <- mutate(kr, season = if_else(side == "A", 2023L, 2024L))
j <- read_input("rush_points", c("actor_id", "season", "N_O", "O_games", "n_role", "role_games", "role_epa",
  "component", "contribution", "share", "role_mean_epa", "role_mean_status"))
ji <- read_input("rush_intervals", c("actor_id", "season", "component", "estimate", "O_games", "deletion_center",
  "variance", "SE", "lower", "upper", "interval_status", "deletion_min", "deletion_max"))
stopifnot(nrow(j) == 80, nrow(ji) == 80, all(j$component %in% c("S", "R")), all(ji$component %in% c("S", "R")),
  !anyNA(j[c("actor_id", "season", "component")]), !anyNA(ji[c("actor_id", "season", "component")]),
  !anyDuplicated(j[c("actor_id", "season", "component")]), !anyDuplicated(ji[c("actor_id", "season", "component")]))
# Align complete, unique actor-season keys without silently dropping unmatched rows.
key <- function(id, year) paste(id, year, sep = ":")
base_key <- key(b$player_key, b$season)
align <- function(x) {
  stopifnot(!anyNA(x[c("actor_id", "season")]), !anyDuplicated(x[c("actor_id", "season")]), nrow(x) == 40)
  keys <- key(x$actor_id, x$season); stopifnot(setequal(keys, base_key)); x[match(base_key, keys), ]
}
k <- align(k); kr <- align(kr)
s <- align(filter(j, component == "S")); r <- align(filter(j, component == "R"))
si <- align(filter(ji, component == "S")); ri <- align(filter(ji, component == "R"))
stopifnot(all(k$N == b$dropbacks), all(k$games == b$dropback_games), all(kr$N == k$N), all(kr$S == k$sacks),
  all(abs(kr$avoidance - 100 * (k$N - k$sacks) / k$N) <= 1e-10),
  all(abs(kr$avoidance + kr$sack_rate - 100) <= 1e-10), all(k$scrambles == s$n_role),
  all(s$N_O == r$N_O), all(s$O_games == r$O_games), all(s$N_O == b$dropbacks + r$n_role),
  all(si$O_games == s$O_games), all(ri$O_games == r$O_games),
  all(abs(si$estimate - s$contribution) <= 1e-12), all(abs(ri$estimate - r$contribution) <= 1e-12))
for (x in list(s, r)) {
  stopifnot(all(is.finite(x$role_epa)), all(abs(100 * x$share - 100 * x$n_role / x$N_O) <= 1e-10),
    all(abs(x$contribution - x$role_epa / x$N_O) <= 1e-12), all(x$role_games <= x$n_role),
    all(x$role_games <= x$O_games), all(x$O_games <= x$N_O),
    all(x$role_mean_status %in% c("observed_role_mean", "no_recorded_role_opportunities")))
  observed <- x$role_mean_status == "observed_role_mean"
  stopifnot(all(x$n_role[observed] > 0), all(is.finite(x$role_mean_epa[observed])),
    all(abs(x$role_mean_epa[observed] - x$role_epa[observed] / x$n_role[observed]) <= 1e-12),
    all(x$n_role[!observed] == 0), all(x$role_games[!observed] == 0), all(x$share[!observed] == 0),
    all(x$contribution[!observed] == 0), all(is.na(x$role_mean_epa[!observed])))
}
rows <- bind_cols(b, tibble(sacks = k$sacks, scramble_runs = s$n_role, sack_avoidance_pct = kr$avoidance,
  combined_opportunities = s$N_O, combined_games = s$O_games, nonscramble_runs = r$n_role,
  scramble_games = s$role_games, nonscramble_games = r$role_games,
  scramble_share_pct = 100 * s$share, nonscramble_share_pct = 100 * r$share,
  scramble_contribution = s$contribution, nonscramble_contribution = r$contribution,
  scramble_contribution_lower = si$lower, scramble_contribution_upper = si$upper,
  nonscramble_contribution_lower = ri$lower, nonscramble_contribution_upper = ri$upper,
  scramble_interval_status = si$interval_status, nonscramble_interval_status = ri$interval_status,
  scramble_epa_per_run = s$role_mean_epa, nonscramble_epa_per_run = r$role_mean_epa,
  scramble_role_mean_status = s$role_mean_status, nonscramble_role_mean_status = r$role_mean_status))
count_fields <- c("season", "eligible_throws", "eligible_games", "dropbacks", "dropback_games", "sacks", "scramble_runs",
  "combined_opportunities", "combined_games", "nonscramble_runs", "scramble_games", "nonscramble_games")
for (f in count_fields) {
  stopifnot(all(is.finite(rows[[f]])), all(rows[[f]] >= 0), all(rows[[f]] == floor(rows[[f]])))
  rows[[f]] <- as.integer(rows[[f]])
}
stopifnot(all(rows$sacks + rows$scramble_runs <= rows$dropbacks), all(rows$combined_games >= rows$dropback_games),
  all(rows$combined_games > 0))
# Bounds/status validation distinguishes a genuine zero from unavailable evidence.
marginal_available <- c("approximate_conditional_game_sampling_sensitivity", "collapsed_no_observed_deletion_variation")
marginal_unavailable <- c("nonpositive_O", "fewer_than_two_O_games", "nonpositive_deleted_O", "nonfinite_ratio", "nonfinite_or_invalid_variance")
fisher_available <- "approximate_95pct_conditional_working_model_sensitivity"
fisher_unavailable <- c("undefined_full_correlation", "perfect_full_correlation", "undefined_deletion_correlation",
  "perfect_deletion_correlation", "fewer_than_two_games_in_stratum", "nonfinite_variance", "zero_or_invalid_variance")
check_bounds <- function(lo, hi, status, available, unavailable) {
  stopifnot(!anyNA(status), all(status %in% c(available, unavailable)), identical(is.na(lo), is.na(hi)))
  ok <- status %in% available
  stopifnot(all(is.finite(lo[ok])), all(is.finite(hi[ok])), all(lo[ok] <= hi[ok]),
    all(is.na(lo[!ok])), all(is.na(hi[!ok])))
  collapsed <- status == "collapsed_no_observed_deletion_variation"
  stopifnot(all(lo[collapsed] == hi[collapsed]))
}
check_bounds(rows$epa_lower, rows$epa_upper, rows$epa_interval_status, marginal_available,
  c("no_opportunities", "fewer_than_two_games", "nonpositive_deletion_denominator", "nonfinite_mean_or_deletion", "nonfinite_or_invalid_variance", "nonfinite_interval_endpoints"))
check_bounds(si$lower, si$upper, si$interval_status, marginal_available, marginal_unavailable)
check_bounds(ri$lower, ri$upper, ri$interval_status, marginal_available, marginal_unavailable)
totals <- rows |> group_by(season) |> summarise(E = sum(eligible_throws), D = sum(dropbacks),
  O = sum(combined_opportunities), R = sum(nonscramble_runs), S = sum(scramble_runs), .groups = "drop") |> arrange(season)
stopifnot(all(totals$E == c(9705, 8517)), all(totals$D == c(11371, 9989)), all(totals$O == c(11759, 10358)),
  all(totals$R == c(388, 369)), all(totals$S == c(558, 504)))
emit(totals, "denominator_guards")
ks <- read_input("sack_results", c("analysis", "actors", "contributing_games", "r", "status", "complement_r", "min_N",
  "complement_error", "variance_z", "SE_z", "lower", "upper", "interval_status", "game_deletion_min", "game_deletion_max",
  "game_deletions_undefined", "actor_deletion_min", "actor_deletion_max", "actor_deletions_undefined", "actor_sign_reversals"))
js <- read_input("rush_results", c("analysis", "component", "actors", "contributing_games", "r", "status", "min_O", "variance_z", "SE_z",
  "lower", "upper", "interval_status", "game_deletion_min", "game_deletion_max", "game_undefined", "actor_deletion_min",
  "actor_deletion_max", "actor_undefined", "actor_sign_reversals"))
stopifnot(identical(ks$analysis, c("interleaved", "chronological", "annual")),
  identical(js$analysis, c("interleaved", "interleaved", "annual", "annual")), identical(js$component, c("S", "R", "S", "R")),
  identical(v1$study_associations$statistic, c("r_C", "r_B", "Delta")))
studies <- lapply(seq_len(3), function(i) c(as.list(v1$study_associations[i, ]), list(
  study_id = "annual_cpoe_comparison", analysis = "annual", seasons = I(c(2023L, 2024L)), cohort_count = 20L,
  metric = c("cpoe_pp", "completion_pct", "cpoe_vs_completion")[i])))
for (source in c("sack", "rush")) {
  table <- if (source == "sack") ks else js
  check_bounds(table$lower, table$upper, table$interval_status, fisher_available, fisher_unavailable)
  stopifnot(all(table$actors == 20), all(table$contributing_games == if_else(table$analysis == "annual", 431, 223)),
    all(table$status %in% c("defined", "nonpositive_O_or_nonfinite_contribution", "nonfinite_rate", "zero_actor_variance",
      "nonfinite_correlation", "perfect_correlation")))
  for (i in seq_len(nrow(table))) {
    x <- table[i, ]; available <- x$interval_status %in% fisher_available
    stopifnot(!is.infinite(x$r), !is.nan(x$r), is.na(x$r) || abs(x$r) <= 1)
    if (x$status == "defined") stopifnot(is.finite(x$r), abs(x$r) < 1)
    if (available) stopifnot(x$status == "defined", is.finite(x$variance_z), x$variance_z > 0,
      is.finite(x$SE_z), x$SE_z > 0, x$lower >= -1, x$upper <= 1)
    influence <- list(game_deletion_min = x$game_deletion_min, game_deletion_max = x$game_deletion_max,
      game_undefined = if (source == "sack") x$game_deletions_undefined else x$game_undefined,
      actor_deletion_min = x$actor_deletion_min, actor_deletion_max = x$actor_deletion_max,
      actor_undefined = if (source == "sack") x$actor_deletions_undefined else x$actor_undefined,
      actor_sign_reversals = x$actor_sign_reversals)
    studies[[length(studies) + 1L]] <- list(study_id = if (source == "sack") "recorded_sack_avoidance" else "recorded_run_contribution",
      analysis = x$analysis, seasons = I(if (x$analysis == "annual") c(2023L, 2024L) else 2023L),
      cohort_count = as.integer(x$actors), contributing_games = as.integer(x$contributing_games),
      metric = if (source == "sack") "sack_avoidance_pct" else if (x$component == "S") "scramble_contribution" else "nonscramble_contribution",
      statistic = "r", estimate = x$r, point_status = x$status, variance_scale = "Fisher_z", variance = x$variance_z,
      SE = x$SE_z, lower = x$lower, upper = x$upper, status = x$interval_status, influence = influence)
  }
}
stopifnot(length(studies) == 10)
frozen <- read_input("rush_frozen_hashes", c("file", "sha256"))
for (label in c("rush_O_keys", "rush_O_maps")) {
  suffix <- if (label == "rush_O_keys") "frozen_O_keys.csv" else "frozen_O_maps.csv"
  stopifnot(frozen$sha256[match(suffix, frozen$file)] == sha(path(label)))
}
run_manifest <- readRDS(path("rush_manifest"))
stopifnot(run_manifest$stage == "frozen_before_EPA_sums_or_rates", run_manifest$version == "recorded-run-contribution-1.0",
  run_manifest$design_sha256 == "347a063258182a6558a0b372fc465b2637f09038b02175e89b61c3e23b0cd932",
  run_manifest$script_sha256 == "4f29f1e61e781f3f382ed6ef06d420f12ca45cf9dd93db7d8d89e087b3c91e07",
  setequal(run_manifest$cohort, b$player_key))
script <- sub("^--file=", "", grep("^--file=", commandArgs(), value = TRUE))
script_hash <- sha(script)
units <- c(v1$units, list(sacks = "sacks", scramble_runs = "runs", sack_avoidance_pct = "percent",
  combined_opportunities = "combined_opportunities", combined_games = "actor_games", nonscramble_runs = "runs",
  scramble_games = "actor_games", nonscramble_games = "actor_games", scramble_share_pct = "percent", nonscramble_share_pct = "percent",
  scramble_contribution = "expected_points_per_combined_opportunity", nonscramble_contribution = "expected_points_per_combined_opportunity",
  scramble_contribution_lower = "expected_points_per_combined_opportunity", scramble_contribution_upper = "expected_points_per_combined_opportunity",
  nonscramble_contribution_lower = "expected_points_per_combined_opportunity", nonscramble_contribution_upper = "expected_points_per_combined_opportunity",
  scramble_epa_per_run = "expected_points_per_role_run", nonscramble_epa_per_run = "expected_points_per_role_run"))
# One native-unit domain across all 40 rows, including every available marginal endpoint.
metric_fields <- c("cpoe_pp", "completion_pct", "epa_per_dropback", "sack_avoidance_pct", "scramble_share_pct", "nonscramble_share_pct",
  "scramble_contribution", "nonscramble_contribution", "scramble_epa_per_run", "nonscramble_epa_per_run")
limits <- list(epa_per_dropback = c("epa_lower", "epa_upper"),
  scramble_contribution = c("scramble_contribution_lower", "scramble_contribution_upper"),
  nonscramble_contribution = c("nonscramble_contribution_lower", "nonscramble_contribution_upper"))
domains <- setNames(lapply(metric_fields, function(f) {
  values <- rows[[f]]; endpoints <- unlist(rows[limits[[f]]], use.names = FALSE)
  observed <- values[is.finite(values)]; all_values <- c(observed, endpoints[is.finite(endpoints)])
  if (!length(observed)) return(list(min = NULL, max = NULL, unit = units[[f]], status = "all_unavailable",
    includes_marginal_limits = length(limits[[f]]) > 0, constant_observed = FALSE))
  percent <- units[[f]] == "percent"
  lo <- min(all_values); hi <- max(all_values)
  if (!percent) { lo <- min(lo, 0); hi <- max(hi, 0) }
  constant <- length(unique(observed)) == 1
  if (constant) { lo <- min(lo, observed[1] - 1); hi <- max(hi, observed[1] + 1) }
  if (percent) { stopifnot(all(all_values >= 0 & all_values <= 100)); lo <- max(0, lo); hi <- min(100, hi) }
  stopifnot(is.finite(lo), is.finite(hi), lo < hi, all(all_values >= lo & all_values <= hi))
  list(min = lo, max = hi, unit = units[[f]], status = "available", includes_marginal_limits = length(limits[[f]]) > 0,
    constant_observed = constant)
}), metric_fields)
domains$recorded_composition_pct <- list(min = 0, max = 100, unit = "percent", status = "fixed_reference")
domains$study_correlation <- list(min = -1, max = 1, unit = "dimensionless", status = "fixed_reference")
domains$study_delta <- list(min = -2, max = 2, unit = "dimensionless", status = "fixed_reference")
aggregate_hashes <- c(list(v1_payload = sha(path("v1_payload"))), v1$aggregate_input_hashes,
  setNames(as.list(inputs$sha256[3:nrow(inputs)]), inputs$label[3:nrow(inputs)]))
generated <- format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
versions <- list(annual = v1$analysis_versions$annual, baseline = v1$analysis_versions$baseline,
  prior_export = v1$analysis_versions$export,
  sack = list(version = "recorded-sack-avoidance-1.0", specification_sha256 = "e60420a5020804a5cafcd3eaf559b20d17ab716c52e9130e32f48c6ae1f070d7",
    script_sha256 = "1350057387ec3e711bf02085360f58aa3f5a4f5007747f62ffbcb2fe9609ceff", commit = "0d3af5433c8aa3adf1ae79b4b7969dbacbacedb7"),
  rush = list(version = run_manifest$version, specification_sha256 = run_manifest$design_sha256,
    script_sha256 = run_manifest$script_sha256, commit = "af4e57776d1a7f848942273bcc5cf104ff296b99"),
  export = list(version = "2.1", specification_sha256 = contract_hash, script_sha256 = script_hash))
denominators <- c(v1$denominators, list(sack_avoidance_pct = "100*(D minus recorded sacks)/D. S scrambles already enter D.",
  combined_opportunities = "O is D disjoint union R; R is recorded non-scramble actor runs, including aborted/lateral plays, not designed runs.",
  run_contribution = "Sum of role play EPA divided by N_O; usage plus shared observed value. Do not add to EPA per D.",
  run_share_pct = "100 times role count/N_O; percent, not fraction.",
  role_mean_epa = "Sum of role play EPA/role count; diagnostic only. No role opportunities gives null, not zero ability.",
  recorded_composition = "Disjoint other D passes, sacks, scramble-runs and R over O; do not stack overlapping diagnostic flags."))
uncertainty <- c(v1$uncertainty, list(sack_avoidance_pct = "Individual uncertainty not estimated.",
  run_contribution = "Copied approximate 95% marginal conditional actor O-game ratio sensitivities, centered on the deletion mean; not player-difference, rank or season-change intervals.",
  run_shares_and_role_means = "No intervals estimated. Zero observed count/share/contribution is distinct from null unavailable per-run mean.",
  marginal_collapsed = "No observed deletion variation, not certainty.",
  sack_and_rush_studies = "Whole-NFL-game Fisher sensitivities; each season uses its own replicate mean. Annual strata contain 223 and 208 contributing games, not independent observations.",
  overlap = "S already enters D EPA and avoidance; the six views share evidence. No cross-study superiority test or isolated mobility/overall score."))
attribution <- v1$attribution
attribution$transformation_notice <- paste(attribution$transformation_notice,
  "Added existing recorded sack-avoidance/run-contribution aggregates and conditional sensitivities; derived role shares/composition from their accepted counts. No new estimation.")
payload <- list(schema_version = 2L, data_version = "2023-2024-broader-profile-v2", generated_utc = generated,
  seasons = c(2023L, 2024L), cohort = v1$cohort, units = units, denominators = denominators, uncertainty = uncertainty,
  sources = v1$sources, attribution = attribution, analysis_versions = versions, aggregate_input_hashes = aggregate_hashes,
  rows = rows, study_associations = studies, domains = domains)
serialize <- function(x) paste0(as.character(jsonlite::toJSON(x, auto_unbox = TRUE, dataframe = "rows", digits = 17,
  na = "null", null = "null", pretty = TRUE)), "\n")
json <- serialize(payload)
stopifnot(jsonlite::validate(json), identical(serialize(payload), json))
roundtrip <- jsonlite::fromJSON(json)
stopifnot(nrow(roundtrip$rows) == 40, nrow(roundtrip$study_associations) == 10,
  isTRUE(all.equal(as.data.frame(rows), roundtrip$rows, tolerance = 0, check.attributes = FALSE)),
  isTRUE(all.equal(as.data.frame(b), roundtrip$rows[base_fields], tolerance = 0, check.attributes = FALSE)))
# Compare every scalar study field after JSON round-trip; retain seasons as arrays.
rt_studies <- jsonlite::fromJSON(json, simplifyVector = FALSE)$study_associations
for (i in seq_along(studies)) for (f in names(studies[[i]]))
  stopifnot(isTRUE(all.equal(unname(unclass(unlist(studies[[i]][[f]]))), unname(unlist(rt_studies[[i]][[f]])), tolerance = 0, check.attributes = FALSE)))
null_fixture <- jsonlite::fromJSON(serialize(list(unavailable = NA_real_, observed_zero = 0)))
stopifnot(is.null(null_fixture$unavailable), null_fixture$observed_zero == 0)
allowed_top <- c("schema_version", "data_version", "generated_utc", "seasons", "cohort", "units", "denominators", "uncertainty",
  "sources", "attribution", "analysis_versions", "aggregate_input_hashes", "rows", "study_associations", "domains")
stopifnot(identical(names(roundtrip), allowed_top), !anyDuplicated(names(rows)), !anyDuplicated(names(units)),
  all(vapply(rows[vapply(rows, is.numeric, logical(1))], function(x) !any(is.infinite(x) | is.nan(x)), logical(1))))
forbidden <- c("/Users/", "/private/", "file://", ".local.md", "@users.noreply", "workspace", "run_manifest", "game_id", "play_id", "FTN")
stopifnot(!any(vapply(forbidden, function(s) grepl(s, json, fixed = TRUE), logical(1))))
asset_name <- "nfl-qb-2023-2024-v2.json"; manifest_name <- "nfl-qb-2023-2024-v2.manifest.json"
asset <- file.path(asset_dir, asset_name); manifest_file <- file.path(asset_dir, manifest_name)
payload_hash <- digest::digest(charToRaw(json), algo = "sha256", serialize = FALSE)
manifest <- list(schema_version = 2L, data_version = payload$data_version, generated_utc = generated,
  payload = list(filename = asset_name, sha256 = payload_hash), seasons = c(2023L, 2024L), cohort_count = 20L,
  row_count = 40L, study_row_count = 10L, units = units, domains = domains, aggregate_input_hashes = aggregate_hashes,
  export_script_sha256 = script_hash)
manifest_json <- serialize(manifest)
stopifnot(jsonlite::validate(manifest_json))
for (i in seq_along(c(asset, manifest_file))) {
  f <- c(asset, manifest_file)[i]; bytes <- charToRaw(c(json, manifest_json)[i])
  if (file.exists(f) && !identical(readBin(f, "raw", n = file.info(f)$size), bytes))
    stop("Existing asset differs; preserve it and authorize another version: ", basename(f))
}
for (i in seq_along(c(asset, manifest_file))) {
  f <- c(asset, manifest_file)[i]; if (!file.exists(f)) writeBin(charToRaw(c(json, manifest_json)[i]), f)
}
written <- jsonlite::fromJSON(asset); fresh <- jsonlite::fromJSON(manifest_file)
stopifnot(sha(asset) == fresh$payload$sha256, fresh$payload$filename == basename(asset),
  identical(written$schema_version, fresh$schema_version), identical(written$data_version, fresh$data_version),
  identical(written$generated_utc, fresh$generated_utc), identical(written$seasons, fresh$seasons),
  written$cohort$count == fresh$cohort_count, nrow(written$rows) == fresh$row_count,
  nrow(written$study_associations) == fresh$study_row_count, identical(written$units, fresh$units),
  identical(written$domains, fresh$domains), identical(written$aggregate_input_hashes, fresh$aggregate_input_hashes),
  written$analysis_versions$export$script_sha256 == fresh$export_script_sha256,
  sha(path("v1_payload")) == inputs$sha256[1], sha(path("v1_manifest")) == inputs$sha256[2])
emit(rows, "source_precision_rows")
emit(tibble(check = c("pinned_inputs_and_v1_pair", "complete_unique_actor_seasons", "source_mapping_and_denominators",
  "all_ten_study_rows", "known_statuses_and_null_semantics", "global_domains_with_limits", "exact_JSON_roundtrip",
  "public_allowlist", "freshness_pair", "deterministic_serialization", "v1_preserved"), passed = TRUE), "verification")
saveRDS(list(contract_sha256 = contract_hash, script_sha256 = script_hash, generated_utc = generated, inputs = inputs,
  asset = asset, manifest = manifest_file, payload_sha256 = sha(asset), manifest_sha256 = sha(manifest_file), args = args), local_path("run_record.rds"))
writeLines(capture.output(sessionInfo()), local_path("sessionInfo.txt"))
cat("Exported:", asset, "\nManifest:", manifest_file, "\nPayload SHA256:", sha(asset), "\nManifest SHA256:", sha(manifest_file),
  "\nScript SHA256:", script_hash, "\nLocal evidence prefix:", local_path(""), "\n")
