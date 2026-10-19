# Recorded played-dropback shared-value baseline, specification 1.0.
# Usage: Rscript performance_baseline.R <2023-inputs> <2024-inputs> <annual-prefix>
# Reads fixed, public-generated count manifests, never annual performance estimates.
# Supplied raw EPA includes teammate/opponent effects; no independent-QB adjustment.
# Original code MIT; nflverse PBP data terms/attribution are separate (CC BY 4.0).
suppressPackageStartupMessages({library(dplyr); library(readr)})
stopifnot(requireNamespace("arrow", quietly = TRUE), requireNamespace("digest", quietly = TRUE))
args <- commandArgs(trailingOnly = TRUE)
if (length(args) != 3 || !all(dir.exists(args[1:2]))) {
  stop("Supply existing 2023/2024 input workspaces and the accepted annual output prefix.")
}
old <- normalizePath(args[1], mustWork = TRUE)
work <- normalizePath(args[2], mustWork = TRUE)
run <- paste0(format(Sys.time(), "%Y%m%dT%H%M%S", tz = "UTC"), "_baseline_", Sys.getpid())
path <- function(name) file.path(work, paste0(run, "_", name))
emit <- function(x, name) {
  file <- path(paste0(name, ".csv"))
  if (file.exists(file)) stop("Refusing to overwrite: ", file)
  write_csv(x, file, na = "NA")
}
sources <- tibble(file = c(file.path(old, "play_by_play_2023.parquet"),
  file.path(work, "play_by_play_2024.parquet")), bytes = c(20534088, 20597560),
  sha256 = c("bd3484731408def6b0ec93225bba2bd7b2c65769ca707a2b9444d891abdc6776",
             "3fd2896bc0b911b615142d2f1fabae54a4bbba5ab7b73b28187b118ef8af6a3b"))
manifests <- tibble(file = paste0(args[3], c("cohort_counts.csv", "frozen_E_keys.csv")),
  sha256 = c("2d4322731540a760c83f4bbea231f14581ca3b34bdc8c2376271d11ffe5546ba",
             "67f05a4386241620f24b4618ebd504931fa7659c5c8c57c4c9f5b2a3f9056808"))
for (i in seq_len(nrow(sources))) {
  stopifnot(file.exists(sources$file[i]), file.info(sources$file[i])$size == sources$bytes[i],
    digest::digest(file = sources$file[i], algo = "sha256") == sources$sha256[i])
}
for (i in seq_len(nrow(manifests))) {
  stopifnot(file.exists(manifests$file[i]),
    digest::digest(file = manifests$file[i], algo = "sha256") == manifests$sha256[i])
}
counts <- read_csv(manifests$file[1], show_col_types = FALSE)
E_keys <- read_csv(manifests$file[2], show_col_types = FALSE)
stopifnot(all(c("passer_player_id", "season", "E_throws", "E_games", "qualifies_both") %in% names(counts)),
  !anyDuplicated(counts[c("passer_player_id", "season")]),
  !anyDuplicated(E_keys[c("season", "game_id", "play_id")]),
  setequal(counts$season, c(2023, 2024)))
membership <- counts |> group_by(passer_player_id) |>
  summarise(qualifies = n() == 2 && all(E_throws >= 200 & E_games >= 10), .groups = "drop")
cohort <- sort(filter(membership, qualifies)$passer_player_id)
stopifnot(length(cohort) == 20, setequal(cohort, unique(filter(counts, qualifies_both)$passer_player_id)),
  setequal(cohort, unique(filter(E_keys, in_cohort)$passer_player_id)))
frozen_cohort <- counts |> filter(passer_player_id %in% cohort) |> arrange(passer_player_id, season)
key_counts <- E_keys |> group_by(passer_player_id, season) |>
  summarise(throws_from_keys = n(), games_from_keys = n_distinct(game_id), .groups = "drop")
count_check <- left_join(frozen_cohort, key_counts, by = c("passer_player_id", "season"),
                        relationship = "one-to-one")
stopifnot(all(count_check$E_throws == count_check$throws_from_keys),
          all(count_check$E_games == count_check$games_from_keys))
emit(frozen_cohort, "frozen_cohort_counts")

flags <- c("qb_dropback", "qb_scramble", "sack", "qb_spike", "qb_kneel",
           "two_point_attempt", "pass_attempt", "rush_attempt", "penalty")
prepare <- function(file, year) {
  rows <- arrow::read_parquet(file) |> filter(season == year, season_type == "REG")
  required <- c("season", "game_id", "play_id", "play_type", "posteam", flags,
    "passer_player_id", "rusher_player_id", "passer_player_name", "rusher_player_name", "epa", "cp")
  stopifnot(all(required %in% names(rows)),
    is.character(rows$game_id), is.numeric(rows$play_id), is.numeric(rows$epa),
    is.character(rows$passer_player_id), is.character(rows$rusher_player_id),
    is.character(rows$passer_player_name), is.character(rows$rusher_player_name),
    !anyNA(rows[c("game_id", "play_id")]), !anyDuplicated(rows[c("game_id", "play_id")]),
    all(vapply(rows[flags], is.numeric, logical(1))),
    all(vapply(rows[flags], function(x) all(is.na(x) | x %in% c(0, 1)), logical(1))))
  expected_dropback <- rows$play_type == "pass" | (rows$play_type == "run" & rows$qb_scramble == 1)
  stopifnot(identical(is.na(expected_dropback), is.na(rows$qb_dropback)),
    all(expected_dropback[!is.na(expected_dropback)] == rows$qb_dropback[!is.na(rows$qb_dropback)]))
  rows <- mutate(rows, exclusion = case_when(
    is.na(qb_dropback) ~ "unknown_dropback", qb_dropback != 1 ~ "not_recorded_dropback",
    is.na(play_type) ~ "unknown_play_type", !play_type %in% c("pass", "run") ~ "outside_played_pass_run",
    is.na(qb_spike) | is.na(qb_kneel) | is.na(two_point_attempt) ~ "unknown_special_play_flag",
    qb_spike != 0 ~ "spike", qb_kneel != 0 ~ "kneel", two_point_attempt != 0 ~ "two_point",
    TRUE ~ NA_character_))
  emit(count(rows, exclusion), paste0("exclusion_flow_", year))
  # No description/penalty/CP/outcome/E-game filter: retain audited played rulings.
  population <- filter(rows, is.na(exclusion)) |> mutate(
    role = case_when(play_type == "pass" & sack == 0 & qb_scramble == 0 ~ "other_pass",
      play_type == "pass" & sack == 1 & qb_scramble == 0 ~ "sack",
      play_type == "run" & sack == 0 & qb_scramble == 1 ~ "scramble", TRUE ~ NA_character_),
    actor_id = if_else(play_type == "pass", passer_player_id, rusher_player_id),
    actor_name = if_else(play_type == "pass", passer_player_name, rusher_player_name))
  bad <- filter(population, is.na(role) | is.na(actor_id) | trimws(actor_id) == "" |
    is.na(actor_name) | trimws(actor_name) == "" | !is.finite(epa) |
    (play_type == "pass" & (is.na(pass_attempt) | pass_attempt != 1 | !is.na(rusher_player_id))) |
    (play_type == "run" & (is.na(rush_attempt) | rush_attempt != 1 | !is.na(passer_player_id))))
  emit(select(bad, all_of(required), role, actor_id, actor_name), paste0("contradictions_", year))
  if (nrow(bad) > 0) stop("Baseline role/identity/EPA contradiction; no EPA estimates: ", year)
  name_check <- population |> distinct(actor_id, actor_name) |> count(actor_id)
  stopifnot(all(name_check$n == 1))
  emit(select(population, season, game_id, play_id, role, actor_id, passer_player_id, rusher_player_id),
       paste0("all_actor_keys_", year))
  population
}
population <- bind_rows(prepare(sources$file[1], 2023), prepare(sources$file[2], 2024))
baseline <- filter(population, actor_id %in% cohort)
baseline_keys <- baseline |> select(season, actor_id, game_id, play_id, role,
  passer_player_id, rusher_player_id) |> arrange(actor_id, season, game_id, play_id)
emit(baseline_keys, "frozen_baseline_keys")
E_games <- distinct(E_keys, season, actor_id = passer_player_id, game_id)
count_diagnostics <- baseline |>
  mutate(in_E_game = paste(season, actor_id, game_id) %in% paste(E_games$season, E_games$actor_id, E_games$game_id)) |>
  group_by(season) |> summarise(selected_opportunities = n(), selected_actors = n_distinct(actor_id),
    other_pass = sum(role == "other_pass"), sacks = sum(role == "sack"), scrambles = sum(role == "scramble"),
    played_penalty = sum(penalty == 1, na.rm = TRUE), penalty_unknown = sum(is.na(penalty)),
    missing_cp = sum(is.na(cp)), rows_outside_actor_E_games = sum(!in_E_game), .groups = "drop")
emit(count_diagnostics, "selected_population_counts")
emit(population |> group_by(season) |> summarise(all_actor_opportunities = n(),
  all_actors = n_distinct(actor_id), other_pass = sum(role == "other_pass"),
  sacks = sum(role == "sack"), scrambles = sum(role == "scramble"), .groups = "drop"), "all_actor_population_counts")
script <- sub("^--file=", "", grep("^--file=", commandArgs(), value = TRUE))
record <- list(specification_version = "observed-value-baseline-1.0",
  specification_sha256 = "e9c7144e955eab6c6fbcbc7ac1dd545e7a3bb93f32194ffe539007068a88807f",
  stage = "frozen_before_EPA_sums_or_averages", frozen_utc = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
  script_sha256 = digest::digest(file = script, algo = "sha256"), sources = sources, annual_manifests = manifests,
  cohort = cohort, cohort_counts = frozen_cohort,
  population_rule = "REG; qb_dropback=1; play_type pass/run; qb_spike=qb_kneel=two_point_attempt=0; no CP/completion/E-game/penalty/text filter",
  role_rule = "pass non-sack / sack: raw passer_player_id; scramble-run: raw rusher_player_id; disjoint roles, penalties overlap",
  metric = "Supplied raw EPA sum S and opportunity-weighted mean S/N, separately for each fixed actor-season",
  uncertainty = "Actor-season complete-game delete-one means; center variance on their mean m; ((G-1)/G)*sum((deletion-m)^2); 1.96 conditional game-sampling interval on mean only",
  cohort_sha256 = digest::digest(file = path("frozen_cohort_counts.csv"), algo = "sha256"),
  baseline_keys_sha256 = digest::digest(file = path("frozen_baseline_keys.csv"), algo = "sha256"))
stopifnot(!file.exists(path("run_record.rds")))
saveRDS(record, path("run_record.rds"))

mean_sensitivity <- function(n_g, S_g) {
  N <- sum(n_g); G <- length(n_g); S <- sum(S_g)
  theta <- if (N > 0 && is.finite(S)) S / N else NA_real_
  remaining <- N - n_g
  deletion <- rep(NA_real_, G)
  valid_denominator <- remaining > 0
  deletion[valid_denominator] <- (S - S_g[valid_denominator]) / remaining[valid_denominator]
  status <- if (N <= 0) "no_opportunities" else if (G < 2) "fewer_than_two_games" else
    if (any(!valid_denominator)) "nonpositive_deletion_denominator" else
      if (!all(is.finite(deletion)) || !is.finite(theta)) "nonfinite_mean_or_deletion" else "defined"
  m <- V <- SE <- lower <- upper <- NA_real_
  if (status == "defined") {
    m <- mean(deletion)
    V <- (G - 1) / G * sum((deletion - m)^2)
    if (!is.finite(V) || V < 0) status <- "nonfinite_or_invalid_variance" else {
      SE <- sqrt(V); lower <- theta - 1.96 * SE; upper <- theta + 1.96 * SE
      if (!all(is.finite(c(lower, upper)))) {
        lower <- upper <- NA_real_; status <- "nonfinite_interval_endpoints"
      } else status <- if (V == 0) "collapsed_no_observed_deletion_variation" else
        "approximate_conditional_game_sampling_sensitivity"
    }
  }
  list(summary = tibble(opportunities = N, games = G, total_epa = S, mean_epa = theta,
    deletion_center = m, jackknife_variance = V, SE = SE, lower = lower, upper = upper,
    deletion_min = if (G > 0 && all(is.finite(deletion))) min(deletion) else NA_real_,
    deletion_max = if (G > 0 && all(is.finite(deletion))) max(deletion) else NA_real_, interval_status = status),
    deletion = deletion, remaining = remaining)
}
equal <- mean_sensitivity(c(1, 1), c(1, 3))
unequal <- mean_sensitivity(c(1, 2), c(1, 8))
stopifnot(equal$summary$mean_epa == 2, equal$summary$deletion_center == 2,
  equal$summary$jackknife_variance == 1, equal$summary$SE == 1,
  identical(unequal$deletion, c(4, 1)), unequal$summary$mean_epa == 3,
  unequal$summary$deletion_center == 2.5, unequal$summary$jackknife_variance == 2.25)
emit(bind_rows(mutate(equal$summary, example = "equal games {1}/{3}"),
  mutate(unequal$summary, example = "unequal games {1}/{3,5}")), "known_mean_verification")

grid <- expand.grid(actor_id = cohort, season = c(2023, 2024), stringsAsFactors = FALSE) |>
  arrange(actor_id, season)
summaries <- deletions <- vector("list", nrow(grid))
for (i in seq_len(nrow(grid))) {
  id <- grid$actor_id[i]; year <- grid$season[i]
  data <- filter(baseline, actor_id == .env$id, season == .env$year)
  games <- data |> group_by(game_id) |> summarise(n_g = n(), S_g = sum(epa), .groups = "drop")
  result <- mean_sensitivity(games$n_g, games$S_g)
  roles <- tibble(other_pass = sum(data$role == "other_pass"), sacks = sum(data$role == "sack"),
    scrambles = sum(data$role == "scramble"), played_penalty = sum(data$penalty == 1, na.rm = TRUE),
    penalty_unknown = sum(is.na(data$penalty)), missing_cp = sum(is.na(data$cp)))
  stopifnot(roles$other_pass + roles$sacks + roles$scrambles == result$summary$opportunities)
  names <- unique(data$actor_name)
  summaries[[i]] <- bind_cols(grid[i, ], tibble(actor_name = if (length(names) == 1) names else NA_character_),
                              result$summary, roles)
  deletions[[i]] <- bind_cols(grid[rep(i, nrow(games)), ], games,
    tibble(remaining_opportunities = result$remaining, deletion_mean = result$deletion))
}
summary <- bind_rows(summaries) |> arrange(actor_id, season)
emit(summary, "actor_season_results")
emit(bind_rows(deletions) |> arrange(actor_id, season, game_id), "actor_game_deletions")
emit(count(summary, interval_status), "interval_status_counts")
writeLines(capture.output(sessionInfo()), path("sessionInfo.txt"))
writeLines(c("Completed fixed-actor baseline summaries and marginal actor-game sensitivity checks.",
  "Shared observed value; no paired-player/year-change/rank inference or support-quality adjustment."), path("completion.txt"))
cat("Completed recorded-dropback baseline. Evidence prefix:", file.path(work, run), "\n")
print(count_diagnostics, width = Inf)
print(count(summary, interval_status))
