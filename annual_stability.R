# Descriptive 2023-to-2024 same-throw annual association, specification 1.0.
# Usage: Rscript annual_stability.R <2023-input-workspace> <2024-input-workspace>
# Requires the exact source snapshots below; performs no downloads.
# Conditional game-jackknife intervals are working-model sensitivities, not
# established NFL confidence coverage, forecasts, or isolated-skill estimates.
# PBP source: nflverse-data, CC BY 4.0; original code license is separate.
suppressPackageStartupMessages({library(dplyr); library(readr); library(tidyr)})
stopifnot(requireNamespace("arrow", quietly = TRUE),
          requireNamespace("digest", quietly = TRUE),
          requireNamespace("stringr", quietly = TRUE))
args <- commandArgs(trailingOnly = TRUE)
if (length(args) != 2 || !all(dir.exists(args))) stop("Supply existing 2023 and 2024 input workspaces.")
old <- normalizePath(args[[1]], mustWork = TRUE)
work <- normalizePath(args[[2]], mustWork = TRUE)
run <- paste0(format(Sys.time(), "%Y%m%dT%H%M%S", tz = "UTC"), "_annual_", Sys.getpid())
path <- function(name) file.path(work, paste0(run, "_", name))
emit <- function(x, name) {
  target <- path(paste0(name, ".csv"))
  if (file.exists(target)) stop("Refusing to overwrite: ", target)
  write_csv(x, target, na = "NA")
}
sources <- tibble(
  file = c("play_by_play_2023.parquet", "play_by_play_2024.parquet", "schedule_reference.rds"),
  workspace = c(old, work, old), bytes = c(20534088, 20597560, 428923),
  sha256 = c("bd3484731408def6b0ec93225bba2bd7b2c65769ca707a2b9444d891abdc6776",
    "3fd2896bc0b911b615142d2f1fabae54a4bbba5ab7b73b28187b118ef8af6a3b",
    "659e4ae782353bb80d196c6789e11eae545a93be9fdb668dd3e3ae4fdac860eb"),
  url = c("https://github.com/nflverse/nflverse-data/releases/download/pbp/play_by_play_2023.parquet",
    "https://github.com/nflverse/nflverse-data/releases/download/pbp/play_by_play_2024.parquet",
    "https://raw.githubusercontent.com/nflverse/nfldata/1bc55c1a32253a78875ca786f8492479a2006567/data/games.rds"))
for (i in seq_len(nrow(sources))) {
  input <- file.path(sources$workspace[i], sources$file[i])
  if (!file.exists(input)) stop("Missing required snapshot: ", sources$file[i])
  stopifnot(file.info(input)$size == sources$bytes[i],
    digest::digest(file = input, algo = "sha256") == sources$sha256[i])
}
emit(sources, "verified_sources")
schedule_all <- readRDS(file.path(old, "schedule_reference.rds"))

# Frozen P/E semantics are repeated locally to avoid a framework or changes to
# the earlier scripts. Unknown source values remain unknown and are classified.
prepare_season <- function(year, workspace) {
  pbp <- arrow::read_parquet(file.path(workspace, paste0("play_by_play_", year, ".parquet"))) |>
    filter(season == year, season_type == "REG")
  schedule <- filter(schedule_all, season == year, game_type == "REG")
  required <- c("season", "game_id", "play_id", "game_date", "posteam", "passer_player_id",
    "passer_player_name", "play_type", "pass_attempt", "sack", "qb_spike", "two_point_attempt",
    "complete_pass", "incomplete_pass", "interception", "cp", "cpoe", "air_yards",
    "pass_location", "receiver_player_id", "desc")
  stopifnot(all(required %in% names(pbp)), is.character(pbp$game_id),
    is.character(pbp$passer_player_id), is.numeric(pbp$play_id),
    !anyNA(pbp[c("game_id", "play_id")]), !anyDuplicated(pbp[c("game_id", "play_id")]),
    !anyDuplicated(schedule$game_id), nrow(anti_join(pbp, schedule, by = "game_id")) == 0)
  flags <- c("pass_attempt", "sack", "qb_spike", "two_point_attempt", "complete_pass",
             "incomplete_pass", "interception")
  stopifnot(all(vapply(pbp[c(flags, "cp", "cpoe", "air_yards")], is.numeric, logical(1))),
    all(vapply(pbp[flags], function(x) all(is.na(x) | x %in% c(0, 1)), logical(1))))
  rows <- pbp |> mutate(accepted_date = as.Date(game_date), p_reason = case_when(
    is.na(game_id) | is.na(play_id) | is.na(accepted_date) |
      is.na(passer_player_id) | trimws(passer_player_id) == "" ~ "unknown_identity_or_date",
    is.na(play_type) ~ "unknown_play_type",
    play_type != "pass" ~ "not_pass_play_type",
    is.na(pass_attempt) ~ "unknown_attempt_flag",
    pass_attempt != 1 ~ "not_recorded_attempt",
    is.na(sack) | is.na(qb_spike) | is.na(two_point_attempt) ~ "unknown_sack_spike_conversion",
    sack != 0 ~ "sack", qb_spike != 0 ~ "spike", two_point_attempt != 0 ~ "two_point",
    is.na(complete_pass) | is.na(incomplete_pass) | is.na(interception) ~ "unknown_outcome",
    complete_pass != 1 & incomplete_pass != 1 & interception != 1 ~ "no_recorded_outcome",
    TRUE ~ NA_character_), in_P = is.na(p_reason))
  final_description <- sub(".*play was REVERSED[.]", "", rows$desc, ignore.case = TRUE)
  bad <- filter(rows, in_P,
    (complete_pass == 1 & (incomplete_pass == 1 | interception == 1)) |
    grepl("\\bNo Play\\b", final_description, ignore.case = TRUE) |
    (!is.na(cp) & (!is.finite(cp) | cp < 0 | cp > 1)) |
    (!is.na(cpoe) & (!is.finite(cpoe) | is.na(cp) |
      abs(cpoe - 100 * (complete_pass - cp)) > 1e-8)))
  emit(select(bad, all_of(required)), paste0("contradictions_", year))
  if (nrow(bad) > 0) stop("Input/eligibility contradiction; no annual estimation: ", year)
  dates <- as.Date(schedule$gameday[match(rows$game_id, schedule$game_id)])
  stopifnot(all(rows$accepted_date[rows$in_P] == dates[rows$in_P]))
  receiver <- stringr::str_extract(rows$desc,
    "(?<=((to)|(for))\\s[:digit:]{0,2}\\-{0,1})[A-Z][A-z]*\\.\\s?[A-Z][A-z]+(\\s(I{2,3})|(IV))?")
  rows <- rows |> mutate(e_reason = case_when(
    !in_P ~ "outside_P", !is.finite(cp) ~ "missing_cp", !is.finite(cpoe) ~ "missing_cpoe",
    is.na(air_yards) ~ "missing_air_yards",
    air_yards < -15 | air_yards >= 70 ~ "air_yards_outside_domain",
    is.na(pass_location) ~ "missing_pass_location",
    is.na(receiver) & is.na(receiver_player_id) ~ "missing_receiver",
    TRUE ~ NA_character_), in_E = in_P & is.na(e_reason))
  emit(count(rows, p_reason, e_reason), paste0("denominator_flow_", year))
  emit(select(rows, season, game_id, play_id, passer_player_id, posteam, in_P, in_E,
              p_reason, e_reason), paste0("eligibility_", year))
  for (group in c("game_id", "posteam", "passer_player_id", "play_type")) {
    coverage <- rows |> group_by(across(all_of(group))) |> summarise(
      P_count = sum(in_P), E_count = sum(in_E), missing_cp_in_P = sum(in_P & is.na(cp)),
      retained_fraction = if_else(P_count > 0, E_count / P_count, NA_real_), .groups = "drop")
    emit(coverage, paste0("coverage_", group, "_", year))
  }
  rows
}
rows <- bind_rows(prepare_season(2023, old), prepare_season(2024, work))
eligible <- filter(rows, in_E)
observed <- rows |> filter(!is.na(passer_player_id), trimws(passer_player_id) != "") |>
  distinct(passer_player_id, season, passer_player_name)
stopifnot(!anyDuplicated(select(observed, passer_player_id, season)))
mapping <- eligible |> count(season, passer_player_id, game_id, accepted_date, posteam,
                              name = "E_throws") |> arrange(season, game_id, passer_player_id)
exposures <- mapping |> group_by(passer_player_id, season) |>
  summarise(E_throws = sum(E_throws), E_games = n_distinct(game_id), .groups = "drop") |>
  complete(passer_player_id = sort(unique(observed$passer_player_id)), season = c(2023, 2024),
           fill = list(E_throws = 0L, E_games = 0L)) |>
  mutate(qualifies_year = E_throws >= 200 & E_games >= 10,
    observed_year = paste(passer_player_id, season) %in% paste(observed$passer_player_id, observed$season))
membership <- exposures |> group_by(passer_player_id) |>
  summarise(qualifies_both = all(qualifies_year), .groups = "drop")
cohort <- sort(filter(membership, qualifies_both)$passer_player_id)
emit(left_join(exposures, observed, by = c("passer_player_id", "season"),
  relationship = "one-to-one") |> left_join(membership, by = "passer_player_id"), "cohort_counts")
emit(mapping, "frozen_game_mapping")
keys <- eligible |> select(season, game_id, play_id, passer_player_id) |>
  mutate(in_cohort = passer_player_id %in% cohort) |> arrange(season, game_id, play_id)
emit(keys, "frozen_E_keys")
population <- rows |> group_by(season) |> summarise(records = n(), P_count = sum(in_P),
  E_count = sum(in_E), cohort_P = sum(in_P & passer_player_id %in% cohort),
  cohort_E = sum(in_E & passer_player_id %in% cohort), .groups = "drop")
emit(population, "population_counts")
script <- sub("^--file=", "", grep("^--file=", commandArgs(), value = TRUE))
record <- list(specification_version = "annual-1.0",
  specification_sha256 = "76f2e6d49b23b1e1d508fb27e3957db0990b39081eb1572a99572902437d690b",
  stage = "frozen_before_annual_metric_calculation",
  frozen_utc = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
  inputs = sources, script_sha256 = digest::digest(file = script, algo = "sha256"),
  P_rule = "2023/2024 schedule REG; observed game/play/date/nonempty passer; pass/attempt=1; sack/spike/two_point=0; binary outcomes with >=1; no contradictory completion; played penalties retained",
  E_rule = "P; finite cp in [0,1], cpoe identity tolerance 1e-8; air_yards [-15,70); observed pass_location; accepted receiver parser or ID; no FTN exclusion",
  cohort_rule = ">=200 E throws AND >=10 E games EACH season; fixed intersection >=20 passers",
  endpoint = "Pearson annual CPOE association minus Pearson annual same-row completion percentage association; equal passer weights",
  uncertainty = "sum_s ((G_s-1)/G_s)*sum_g((T[-s,g]-T_full)^2); paired raw Delta; Fisher-z components; 1.96 conditional working-model intervals",
  diagnostics = "Whole-season-specific NFL game deletions; paired two-season passer deletions; no requalification",
  cohort = cohort, cohort_counts = exposures, game_mapping = mapping, population = population,
  E_keys_sha256 = digest::digest(file = path("frozen_E_keys.csv"), algo = "sha256"),
  mapping_sha256 = digest::digest(file = path("frozen_game_mapping.csv"), algo = "sha256"))
stopifnot(!file.exists(path("run_record.rds")))
saveRDS(record, path("run_record.rds"))
if (length(cohort) < 20) stop("Insufficient common cohort; frozen count-only evidence retained.")
sample <- filter(eligible, passer_player_id %in% cohort)
stopifnot(all(is.finite(sample$cpoe)), all(sample$complete_pass %in% c(0, 1)),
          all(abs(sample$cpoe - 100 * (sample$complete_pass - sample$cp)) <= 1e-8))

safe_cor <- function(a, b) {
  if (!all(is.finite(c(a, b)))) return(list(value = NA_real_, status = "undefined_annual_mean"))
  if (var(a) == 0 || var(b) == 0) return(list(value = NA_real_, status = "zero_passer_variance"))
  value <- cor(a, b)
  list(value = value, status = if (!is.finite(value)) "nonfinite_correlation" else
    if (abs(value) == 1) "perfect_correlation" else "defined")
}
associations <- function(data, ids) {
  # One data argument, no separate row filtering or missing-value removal.
  means <- data |> group_by(passer_player_id, season) |>
    summarise(C = mean(cpoe), B = 100 * mean(complete_pass), .groups = "drop") |>
    complete(passer_player_id = ids, season = c(2023, 2024)) |>
    pivot_wider(names_from = season, values_from = c(C, B)) |> arrange(passer_player_id)
  stopifnot(identical(means$passer_player_id, sort(ids)))
  C <- safe_cor(means$C_2023, means$C_2024)
  B <- safe_cor(means$B_2023, means$B_2024)
  tibble(r_C = C$value, r_B = B$value, Delta = C$value - B$value,
    C_status = C$status, B_status = B$status,
    Delta_status = if (C$status == "defined" && B$status == "defined") "defined" else
      "undefined_or_boundary_component")
}
stratified_variance <- function(deletions, full, seasons) {
  if (!is.finite(full) || !all(is.finite(deletions))) return(NA_real_)
  terms <- vapply(split(deletions, seasons), function(values) {
    G <- length(values)
    if (G < 2) return(NA_real_)
    (G - 1) / G * sum((values - full)^2) # Full estimate, NOT a deletion mean.
  }, numeric(1))
  sum(terms)
}
# Independent known-mean example: equal fixed weights on (1,3,5) and (2,6).
# T_full=3.5; variance=.25*var(1,3,5)/3 + .25*var(2,6)/2 = 4/3.
toy_deletions <- c(4, 3.5, 3, 4.5, 2.5)
toy_seasons <- c(1, 1, 1, 2, 2)
stopifnot(abs(stratified_variance(toy_deletions, 3.5, toy_seasons) - 4 / 3) < 1e-12,
  # Squaring this toy mean distinguishes full-estimate from deletion-mean centering.
  abs(stratified_variance(toy_deletions^2, 3.5^2, toy_seasons) - 797 / 12) < 1e-12,
  is.na(stratified_variance(c(1, NA), 1, c(1, 1))),
  stratified_variance(rep(1, 4), 1, c(1, 1, 2, 2)) == 0)
emit(tibble(example = c("fixed-weight stratified mean", "squared toy mean"),
  variance = c(stratified_variance(toy_deletions, 3.5, toy_seasons),
    stratified_variance(toy_deletions^2, 3.5^2, toy_seasons)),
  known_variance = c(4 / 3, 797 / 12)), "known_example_verification")

full <- associations(sample, cohort)
emit(full, "annual_associations")
games <- distinct(sample, season, game_id) |> arrange(season, game_id)
deletions <- bind_rows(lapply(seq_len(nrow(games)), function(i) {
  year <- games$season[i]; game <- games$game_id[i]
  deleted <- filter(sample, season == .env$year, game_id == .env$game)
  retained <- filter(sample, !(season == .env$year & game_id == .env$game))
  stopifnot(nrow(retained) + nrow(deleted) == nrow(sample),
    !any(retained$season == year & retained$game_id == game),
    sum(retained$season != year) == sum(sample$season != year))
  bind_cols(tibble(deleted_season = year, deleted_game = game, deleted_rows = nrow(deleted),
    deleted_passers = n_distinct(deleted$passer_player_id),
    remaining_passers = n_distinct(retained$passer_player_id)), associations(retained, cohort))
}))
emit(deletions, "season_game_deletions")
intervals <- bind_rows(lapply(c("r_C", "r_B", "Delta"), function(statistic) {
  status_column <- c(r_C = "C_status", r_B = "B_status", Delta = "Delta_status")[[statistic]]
  valid <- full[[status_column]] == "defined" && all(deletions[[status_column]] == "defined")
  transform <- if (statistic == "Delta") identity else atanh
  inverse <- if (statistic == "Delta") identity else tanh
  V <- if (valid) stratified_variance(transform(deletions[[statistic]]),
    transform(full[[statistic]]), deletions$deleted_season) else NA_real_
  defined <- valid && is.finite(V) && V > 0
  tibble(statistic = statistic, estimate = full[[statistic]],
    variance_scale = if (statistic == "Delta") "raw_Delta" else "Fisher_z", variance = V,
    SE = if (defined) sqrt(V) else NA_real_,
    lower = if (defined) inverse(transform(full[[statistic]]) - 1.96 * sqrt(V)) else NA_real_,
    upper = if (defined) inverse(transform(full[[statistic]]) + 1.96 * sqrt(V)) else NA_real_,
    status = if (defined) "conditional_working_model_sensitivity" else "unavailable_degenerate_interval")
}))
emit(intervals, "conditional_intervals")
emit(bind_rows(lapply(sort(unique(deletions$deleted_season)), function(year) {
  d <- filter(deletions, deleted_season == .env$year)
  tibble(season = year, G = nrow(d), coefficient = (nrow(d) - 1) / nrow(d),
    Delta_variance_contribution = stratified_variance(d$Delta, full$Delta, d$deleted_season),
    min_r_C = min(d$r_C), max_r_C = max(d$r_C), min_r_B = min(d$r_B), max_r_B = max(d$r_B),
    min_Delta = min(d$Delta), max_Delta = max(d$Delta),
    reversals = sum(d$Delta * full$Delta < 0, na.rm = TRUE),
    undefined_or_boundary = sum(d$Delta_status != "defined"),
    games_with_multiple_passers = sum(d$deleted_passers > 1))
})), "game_influence_by_season")
passer_deletions <- bind_rows(lapply(cohort, function(id) {
  ids <- setdiff(cohort, id)
  retained <- filter(sample, passer_player_id != .env$id)
  stopifnot(n_distinct(retained$passer_player_id) == length(ids))
  bind_cols(tibble(deleted_passer_id = id), associations(retained, ids))
}))
emit(passer_deletions, "paired_passer_deletions")
emit(tibble(deletions = nrow(passer_deletions),
  min_r_C = min(passer_deletions$r_C), max_r_C = max(passer_deletions$r_C),
  min_r_B = min(passer_deletions$r_B), max_r_B = max(passer_deletions$r_B),
  min_Delta = min(passer_deletions$Delta), max_Delta = max(passer_deletions$Delta),
  reversals = sum(passer_deletions$Delta * full$Delta < 0, na.rm = TRUE),
  undefined_or_boundary = sum(passer_deletions$Delta_status != "defined")), "passer_influence_range")
writeLines(capture.output(sessionInfo()), path("sessionInfo.txt"))
writeLines(c("Completed all available predefined annual outputs and influence checks.",
  "Descriptive only. Interval signs/widths do not decide independence credibility."), path("completion.txt"))
cat("Completed annual comparison. Evidence prefix:", file.path(work, run), "\n")
print(intervals, width = Inf)
