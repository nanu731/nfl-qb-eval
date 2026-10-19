# Same-throw 2023 split association: supplied CPOE versus completion percentage.
# Usage: Rscript pilot_accuracy.R <existing-audited-input-workspace>
# Specification 1.1: fixed exposures/splits, paired whole-game jackknife.
# Results are descriptive. Approximate intervals are conditional working-model
# sensitivities, not established NFL confidence coverage or metric validation.
# No downloads, new models, filters searched, player rankings, or other seasons.
# PBP: nflverse-data CC BY 4.0. FTN Data via nflverse: CC BY-SA 4.0.

suppressPackageStartupMessages({
  library(dplyr)
  library(readr)
  library(tidyr)
})
stopifnot(requireNamespace("arrow", quietly = TRUE),
          requireNamespace("digest", quietly = TRUE),
          requireNamespace("stringr", quietly = TRUE))
args <- commandArgs(trailingOnly = TRUE)
if (length(args) != 1 || !dir.exists(args[[1]])) stop("Supply the existing audited input workspace.")
workspace <- normalizePath(args[[1]], mustWork = TRUE)
run <- paste0(format(Sys.time(), "%Y%m%dT%H%M%S", tz = "UTC"), "_pilot_", Sys.getpid())
path <- function(name) file.path(workspace, paste0(run, "_", name))
emit <- function(x, name) {
  target <- path(paste0(name, ".csv"))
  if (file.exists(target)) stop("Refusing to overwrite: ", target)
  write_csv(x, target, na = "NA")
}

expected <- c(
  "play_by_play_2023.parquet" = "bd3484731408def6b0ec93225bba2bd7b2c65769ca707a2b9444d891abdc6776",
  "ftn_charting_2023.parquet" = "162f0f48a8fca23f86a334c78e27f8daa7443e6b383beada0416b65c593b2c0e",
  "schedule_reference.rds" = "659e4ae782353bb80d196c6789e11eae545a93be9fdb668dd3e3ae4fdac860eb"
)
receipts <- read_csv(file.path(workspace, "download_receipts.csv"),
                     col_types = cols(.default = col_character()))
for (file in names(expected)) {
  receipt <- filter(receipts, .data$file == .env$file)
  input <- file.path(workspace, file)
  if (!file.exists(input) || nrow(receipt) != 1) stop("Missing snapshot/receipt: ", file)
  stopifnot(receipt$sha256 == expected[[file]],
    digest::digest(file = input, algo = "sha256") == expected[[file]],
    file.info(input)$size == as.numeric(receipt$bytes))
}
pbp <- arrow::read_parquet(file.path(workspace, "play_by_play_2023.parquet")) |>
  filter(season == 2023, season_type == "REG")
ftn <- arrow::read_parquet(file.path(workspace, "ftn_charting_2023.parquet"))
schedule <- readRDS(file.path(workspace, "schedule_reference.rds")) |>
  filter(season == 2023, game_type == "REG")
required <- c("game_id", "play_id", "game_date", "posteam", "passer_player_id",
  "passer_player_name", "play_type", "pass_attempt", "sack", "qb_spike", "two_point_attempt",
  "complete_pass", "incomplete_pass", "interception", "cp", "cpoe", "air_yards",
  "pass_location", "receiver_player_id", "desc")
labels <- c("is_catchable_ball", "is_throw_away", "is_drop", "is_created_reception",
            "is_screen_pass", "is_play_action", "is_trick_play")
stopifnot(all(required %in% names(pbp)), all(labels %in% names(ftn)),
  is.character(pbp$passer_player_id), is.character(pbp$game_id),
  is.numeric(pbp$play_id), all(vapply(ftn[labels], is.logical, logical(1))),
  all(vapply(pbp[c("cp", "cpoe", "complete_pass", "incomplete_pass", "interception")],
             is.numeric, logical(1))))
stopifnot(!anyDuplicated(schedule$game_id),
  nrow(anti_join(pbp, schedule, by = "game_id")) == 0)
ftn <- semi_join(ftn, schedule, by = c("nflverse_game_id" = "game_id"))
stopifnot(!anyNA(pbp[c("game_id", "play_id")]),
  !anyNA(ftn[c("nflverse_game_id", "nflverse_play_id")]),
  !anyDuplicated(pbp[c("game_id", "play_id")]),
  !anyDuplicated(ftn[c("nflverse_game_id", "nflverse_play_id")]))
rows <- left_join(pbp, select(ftn, nflverse_game_id, nflverse_play_id, all_of(labels),
                             n_offense_backfield, n_pass_rushers, ftn_play_id),
  by = c("game_id" = "nflverse_game_id", "play_id" = "nflverse_play_id"),
  relationship = "one-to-one", na_matches = "never") |>
  mutate(accepted_game_date = as.Date(game_date), ftn_available = !is.na(ftn_play_id))

# P is a recorded-play population, not a reconstructed official attempts total.
rows <- rows |> mutate(p_reason = case_when(
  is.na(game_id) | is.na(play_id) | is.na(accepted_game_date) |
    is.na(passer_player_id) | trimws(passer_player_id) == "" ~ "unknown_identity_or_date",
  is.na(play_type) ~ "unknown_play_type",
  play_type != "pass" ~ "not_pass_play_type",
  is.na(pass_attempt) ~ "unknown_attempt_flag",
  pass_attempt != 1 ~ "not_recorded_attempt",
  is.na(sack) | is.na(qb_spike) | is.na(two_point_attempt) ~ "unknown_sack_spike_conversion",
  sack != 0 ~ "sack",
  qb_spike != 0 ~ "spike",
  two_point_attempt != 0 ~ "two_point",
  is.na(complete_pass) | is.na(incomplete_pass) | is.na(interception) ~ "unknown_outcome",
  !(complete_pass %in% c(0, 1)) | !(incomplete_pass %in% c(0, 1)) |
    !(interception %in% c(0, 1)) ~ "nonbinary_outcome",
  complete_pass != 1 & incomplete_pass != 1 & interception != 1 ~ "no_recorded_outcome",
  TRUE ~ NA_character_), in_P = is.na(p_reason))
contradictions <- filter(rows, in_P,
  complete_pass == 1 & (incomplete_pass == 1 | interception == 1))
emit(select(contradictions, all_of(required)), "contradictory_outcomes")
if (nrow(contradictions) > 0 || any(rows$p_reason == "nonbinary_outcome", na.rm = TRUE)) {
  stop("Contradictory/nonbinary outcome; no estimation performed.")
}
# Old replay text can precede the corrected outcome. A nullified touchdown alone
# does not mean the recorded pass outcome was nullified; no penalty filter is used.
final_description <- sub(".*play was REVERSED[.]", "", rows$desc, ignore.case = TRUE)
nullified <- filter(rows, in_P & grepl("\\bNo Play\\b", final_description, ignore.case = TRUE))
emit(select(nullified, all_of(required)), "qualifying_no_play_contradictions")
if (nrow(nullified) > 0) stop("Qualifying pass described as No Play; eligibility decision required.")
bad_cp <- filter(rows, in_P, !is.na(cp) & (!is.finite(cp) | cp < 0 | cp > 1))
bad_cpoe <- filter(rows, in_P, !is.na(cpoe) &
  (!is.finite(cpoe) | is.na(cp) | abs(cpoe - 100 * (complete_pass - cp)) > 1e-8))
emit(select(bad_cp, all_of(required)), "invalid_cp")
emit(select(bad_cpoe, all_of(required)), "invalid_cpoe_identity")
if (nrow(bad_cp) + nrow(bad_cpoe) > 0) stop("CP domain/CPOE identity failure; no estimation.")
receiver_from_description <- stringr::str_extract(rows$desc,
  "(?<=((to)|(for))\\s[:digit:]{0,2}\\-{0,1})[A-Z][A-z]*\\.\\s?[A-Z][A-z]+(\\s(I{2,3})|(IV))?")
rows <- rows |> mutate(e_reason = case_when(
  !in_P ~ "outside_P",
  !is.finite(cp) ~ "missing_cp",
  !is.finite(cpoe) ~ "missing_cpoe",
  is.na(air_yards) ~ "missing_air_yards",
  air_yards < -15 | air_yards >= 70 ~ "air_yards_outside_domain",
  is.na(pass_location) ~ "missing_pass_location",
  is.na(receiver_from_description) & is.na(receiver_player_id) ~ "missing_receiver",
  TRUE ~ NA_character_), in_E = in_P & is.na(e_reason))
emit(count(rows, p_reason, e_reason), "denominator_flow")
emit(select(rows, game_id, play_id, posteam, passer_player_id, p_reason, e_reason, in_P, in_E),
     "eligibility_assignments")
coverage <- function(groups) rows |> group_by(across(all_of(groups))) |> summarise(
  P = sum(in_P), E = sum(in_E), missing_cp_in_P = sum(in_P & is.na(cp)),
  retained_fraction = if_else(P > 0, E / P, NA_real_), .groups = "drop")
emit(coverage("game_id"), "P_E_by_game")
emit(coverage("posteam"), "P_E_by_team")
emit(coverage("passer_player_id"), "P_E_by_passer")
eligible <- filter(rows, in_E)
mapping <- eligible |> count(passer_player_id, game_id, accepted_game_date, name = "E_throws") |>
  arrange(passer_player_id, accepted_game_date, game_id) |> group_by(passer_player_id) |>
  mutate(appearance = row_number(), appearances = n(),
    interleaved = if_else(appearance %% 2 == 1, "A", "B"),
    chronological = if_else(appearance <= ceiling(appearances / 2), "A", "B")) |> ungroup()
exposures <- mapping |> group_by(passer_player_id, half = interleaved) |>
  summarise(throws = sum(E_throws), games = n(), .groups = "drop") |>
  complete(passer_player_id, half = c("A", "B"), fill = list(throws = 0L, games = 0L)) |>
  pivot_wider(names_from = half, values_from = c(throws, games)) |>
  mutate(qualifies = throws_A >= 100 & throws_B >= 100 & games_A >= 5 & games_B >= 5)
cohort <- sort(filter(exposures, qualifies)$passer_player_id)
names <- distinct(eligible, passer_player_id, passer_player_name)
stopifnot(!anyDuplicated(names$passer_player_id))
emit(left_join(exposures, names, by = "passer_player_id", relationship = "one-to-one"),
     "cohort_counts")
emit(mapping, "frozen_game_mapping")
keys <- eligible |> select(game_id, play_id, passer_player_id) |>
  mutate(in_cohort = passer_player_id %in% cohort) |> arrange(game_id, play_id)
emit(keys, "frozen_E_keys")

# This is the only real-data estimation gate: all eligibility/cohort/mapping
# artifacts and the immutable run record exist before any metric averages.
script_file <- sub("^--file=", "", grep("^--file=", commandArgs(), value = TRUE))
record <- list(specification_version = "1.1",
  specification_sha256 = "c7587a1476d6a5c2f6bbd15a1ad5e04c67ff0d19ab0fb37ed55b1ff98a08ff5e",
  stage = "frozen_before_metric_calculation",
  frozen_utc = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
  script_sha256 = digest::digest(file = script_file, algo = "sha256"),
  inputs = filter(receipts, file %in% names(expected)),
  P_rule = "REG 2023; observed game/play/date/nonempty passer; pass/attempt=1; sack/spike/two_point=0; observed binary outcomes with >=1; no contradictory completion",
  E_rule = "P; finite cp in [0,1], cpoe identity tolerance 1e-8; air_yards [-15,70); observed pass_location; accepted parsed receiver or receiver ID",
  split_rule = "Per-passer E games sorted date/game_id; odd/even A/B; chronological first ceiling(n/2) A; mappings never reassigned",
  cohort_rule = "At least 100 E throws AND 5 E games per interleaved half; fixed >=20 passers",
  endpoint = "Pearson(CPOE_A,CPOE_B) - Pearson(completion_pct_A,completion_pct_B); equal passer weights",
  uncertainty = "Paired delete-one-NFL-game jackknife; fixed cohort/maps; Delta raw scale; component Fisher-z; 1.96 approximate conditional working-model intervals",
  sensitivities = c("chronological same-cohort halves", "delete-one-passer influence", "whole-game influence"),
  P_count = sum(rows$in_P), E_count = nrow(eligible), cohort = cohort,
  cohort_counts = exposures, game_mapping = mapping,
  E_keys_sha256 = digest::digest(file = path("frozen_E_keys.csv"), algo = "sha256"),
  game_mapping_sha256 = digest::digest(file = path("frozen_game_mapping.csv"), algo = "sha256"))
stopifnot(!file.exists(path("run_record.rds")))
saveRDS(record, path("run_record.rds"))
if (length(cohort) < 20) stop("Insufficient fixed cohort; count-only freeze retained.")
sample <- eligible |> filter(passer_player_id %in% cohort) |>
  left_join(select(mapping, passer_player_id, game_id, interleaved, chronological),
    by = c("passer_player_id", "game_id"), relationship = "many-to-one")
stopifnot(nrow(sample) == sum(filter(exposures, qualifies)$throws_A +
                             filter(exposures, qualifies)$throws_B),
  all(is.finite(sample$cpoe)), all(sample$complete_pass %in% c(0, 1)),
  all(abs(sample$cpoe - 100 * (sample$complete_pass - sample$cp)) <= 1e-8))

# Both metrics use the same data argument without separate missing-value removal.
associations <- function(data, ids) {
  means <- data |> group_by(passer_player_id, half) |>
    summarise(completion_pct = 100 * mean(complete_pass), cpoe_pp = mean(cpoe), .groups = "drop") |>
    complete(passer_player_id = ids, half = c("A", "B")) |>
    pivot_wider(names_from = half, values_from = c(completion_pct, cpoe_pp)) |>
    arrange(passer_player_id)
  values <- as.matrix(select(means, -passer_player_id))
  if (nrow(means) != length(ids) || !all(is.finite(values))) {
    return(tibble(r_C = NA_real_, r_B = NA_real_, Delta = NA_real_, status = "undefined_half_mean"))
  }
  if (any(apply(values, 2, stats::var) == 0)) {
    return(tibble(r_C = NA_real_, r_B = NA_real_, Delta = NA_real_, status = "zero_passer_variance"))
  }
  r_C <- cor(means$cpoe_pp_A, means$cpoe_pp_B)
  r_B <- cor(means$completion_pct_A, means$completion_pct_B)
  status <- if (!all(is.finite(c(r_C, r_B)))) "nonfinite_correlation" else
    if (any(abs(c(r_C, r_B)) == 1)) "boundary_correlation" else "defined"
  tibble(r_C = r_C, r_B = r_B, Delta = r_C - r_B, status = status)
}
jackknife_se <- function(deletions) {
  G <- length(deletions)
  if (G < 2 || !all(is.finite(deletions))) return(NA_real_)
  sqrt((G - 1) / G * sum((deletions - mean(deletions))^2))
}
# Known mean example: mean(1:4)=2.5; expected SE=sqrt(5/12).
known_means <- c(3, 8 / 3, 7 / 3, 2)
stopifnot(abs(jackknife_se(known_means) - sqrt(5 / 12)) < 1e-12,
          !is.finite(jackknife_se(c(1, NA))), jackknife_se(rep(1, 4)) == 0)
emit(tibble(example = "mean of 1:4", observed_se = jackknife_se(known_means),
            expected_se = sqrt(5 / 12)), "known_mean_verification")

analyze_split <- function(split) {
  data <- mutate(sample, half = .data[[split]])
  stopifnot(!anyNA(data$half), nrow(distinct(data, passer_player_id, game_id, half)) ==
              nrow(distinct(data, passer_player_id, game_id)))
  full <- associations(data, cohort)
  emit(full, paste0(split, "_associations"))
  games <- sort(unique(data$game_id))
  deletions <- bind_rows(lapply(games, function(game) {
    retained <- filter(data, game_id != .env$game)
    deleted <- filter(data, game_id == .env$game)
    stopifnot(!game %in% retained$game_id, nrow(retained) + nrow(deleted) == nrow(data))
    bind_cols(tibble(deleted_game = game, deleted_rows = nrow(deleted),
      deleted_passers = n_distinct(deleted$passer_player_id),
      deleted_A = sum(deleted$half == "A"), deleted_B = sum(deleted$half == "B"),
      remaining_passers = n_distinct(retained$passer_player_id)), associations(retained, cohort))
  }))
  emit(deletions, paste0(split, "_game_deletions"))
  valid <- full$status == "defined" && all(deletions$status == "defined")
  se_delta <- if (valid) jackknife_se(deletions$Delta) else NA_real_
  se_C <- if (valid) jackknife_se(atanh(deletions$r_C)) else NA_real_
  se_B <- if (valid) jackknife_se(atanh(deletions$r_B)) else NA_real_
  valid_variance <- valid && all(is.finite(c(se_delta, se_C, se_B))) &&
    all(c(se_delta, se_C, se_B) > 0)
  interval <- tibble(statistic = c("r_C", "r_B", "Delta"),
    estimate = c(full$r_C, full$r_B, full$Delta),
    se_scale = c("Fisher_z", "Fisher_z", "raw_Delta"),
    se = c(se_C, se_B, se_delta), lower = NA_real_, upper = NA_real_,
    status = if (valid_variance) "conditional_working_model_sensitivity" else
      "degenerate_no_normal_theory_intervals")
  if (valid_variance) {
    interval$lower <- c(tanh(atanh(full$r_C) - 1.96 * se_C),
      tanh(atanh(full$r_B) - 1.96 * se_B), full$Delta - 1.96 * se_delta)
    interval$upper <- c(tanh(atanh(full$r_C) + 1.96 * se_C),
      tanh(atanh(full$r_B) + 1.96 * se_B), full$Delta + 1.96 * se_delta)
    # Independent covariance identity checks pairing; do not add marginal SEs.
    factor <- (length(games) - 1)^2 / length(games)
    covariance_variance <- factor * (var(deletions$r_C) + var(deletions$r_B) -
                                       2 * cov(deletions$r_C, deletions$r_B))
    stopifnot(abs(covariance_variance - se_delta^2) < 1e-12)
  }
  exposure <- data |> group_by(passer_player_id, half) |>
    summarise(throws = n(), games = n_distinct(game_id), .groups = "drop")
  emit(exposure, paste0(split, "_exposures"))
  below_threshold <- any(exposure$throws < 100 | exposure$games < 5)
  interval <- mutate(interval, exposure_below_primary_gates = below_threshold,
    interpretation = if (split == "chronological" && below_threshold)
      "withhold_inferential_interpretation_of_sensitivity" else "descriptive_only")
  emit(interval, paste0(split, "_intervals"))
  emit(tibble(split = split, games = length(games), passers = length(cohort),
    all_defined = valid, variance_defined_positive = valid_variance,
    game_deletions_reversing_Delta = sum(deletions$Delta * full$Delta < 0, na.rm = TRUE),
    undefined_game_deletions = sum(deletions$status != "defined")), paste0(split, "_checks"))
  list(full = full, deletions = deletions, interval = interval)
}
primary <- analyze_split("interleaved")
chronological <- analyze_split("chronological")

passer_influence <- bind_rows(lapply(cohort, function(id) {
  ids <- setdiff(cohort, id)
  data <- sample |> filter(passer_player_id != .env$id) |> mutate(half = interleaved)
  bind_cols(tibble(deleted_passer_id = id), associations(data, ids))
}))
emit(passer_influence, "passer_deletions")
emit(tibble(diagnostic = "delete_one_passer", undefined = sum(passer_influence$status != "defined"),
  min_r_C = min(passer_influence$r_C), max_r_C = max(passer_influence$r_C),
  min_r_B = min(passer_influence$r_B), max_r_B = max(passer_influence$r_B),
  min_Delta = min(passer_influence$Delta), max_Delta = max(passer_influence$Delta),
  reversals = sum(passer_influence$Delta * primary$full$Delta < 0, na.rm = TRUE)), "passer_influence_range")

# Catchability is diagnostic only; unknown labels remain explicit, never FALSE.
diagnostic <- sample |> filter(ftn_available, !is.na(is_catchable_ball),
                              !is.na(is_throw_away), !is_throw_away)
emit(count(diagnostic, complete_pass, is_catchable_ball) |>
  complete(complete_pass = c(0, 1), is_catchable_ball = c(FALSE, TRUE), fill = list(n = 0L)),
  "catchability_completion_counts")
emit(tibble(cohort_E = nrow(sample), diagnostic_D = nrow(diagnostic),
  D_over_E = nrow(diagnostic) / nrow(sample),
  FTN_unavailable = sum(!sample$ftn_available),
  unknown_catchability = sum(sample$ftn_available & is.na(sample$is_catchable_ball)),
  unknown_throwaway = sum(sample$ftn_available & is.na(sample$is_throw_away)),
  known_throwaways = sum(sample$is_throw_away == TRUE, na.rm = TRUE),
  unknown_backfield = sum(is.na(sample$n_offense_backfield)),
  unknown_rushers = sum(is.na(sample$n_pass_rushers))), "diagnostic_denominators")
emit(bind_rows(lapply(c("is_drop", "is_created_reception", "is_screen_pass",
  "is_play_action", "is_trick_play"), function(label) {
  count(sample, value = as.character(.data[[label]])) |>
    complete(value = c("TRUE", "FALSE", NA_character_), fill = list(n = 0L)) |>
    mutate(label = label, group = if_else(label %in% c("is_drop", "is_created_reception"),
      "outcome", "context"), .before = 1)
})), "outcome_context_label_counts")
emit(tibble(P = sum(rows$in_P), E = nrow(eligible),
  E_over_P = nrow(eligible) / sum(rows$in_P), cohort_passers = length(cohort),
  cohort_E = nrow(sample), cohort_games = n_distinct(sample$game_id),
  E_FTN_unavailable = sum(!eligible$ftn_available),
  E_trick_missing = sum(is.na(eligible$is_trick_play)),
  cohort_E_trick_missing = sum(is.na(sample$is_trick_play))), "population_summary")
writeLines(capture.output(sessionInfo()), path("sessionInfo.txt"))
writeLines(c("Completed all predeclared calculations/diagnostics.",
  "Substantive conclusions remain descriptive-only; independence credibility is not selected from results.",
  "No known-degenerate deletion/passers were removed to obtain an interval."), path("completion.txt"))
cat("Completed pilot. Evidence prefix:", file.path(workspace, run), "\n")
print(primary$interval, width = Inf)
print(chronological$interval, width = Inf)
