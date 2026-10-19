# Recorded scramble/non-scramble-run contribution, frozen specification 1.0.
# Usage: Rscript rush_contribution.R <2023-inputs> <2024-inputs> <cohort.csv>
#        <D-keys.csv> <R-2023-keys.csv> <R-2024-keys.csv> <existing-output-dir> <design-sha256>
# C_k = role EPA sum / O count, O = disjoint D union R; not EPA per role run.
# Original code MIT; nflverse PBP CC BY 4.0 attribution and upstream notices separate.
suppressPackageStartupMessages({library(dplyr); library(readr)})
stopifnot(requireNamespace("arrow", quietly = TRUE), requireNamespace("digest", quietly = TRUE))
args <- commandArgs(trailingOnly = TRUE)
if (length(args) != 8 || !all(dir.exists(args[c(1, 2, 7)]))) stop("Supply input directories, cohort/D/R manifests, output directory and design SHA256.")
design_hash <- "347a063258182a6558a0b372fc465b2637f09038b02175e89b61c3e23b0cd932"
stopifnot(identical(args[8], design_hash))
work2023 <- normalizePath(args[1], mustWork = TRUE); work2024 <- normalizePath(args[2], mustWork = TRUE)
out <- normalizePath(args[7], mustWork = TRUE)
run <- paste0(format(Sys.time(), "%Y%m%dT%H%M%S", tz = "UTC"), "_rush_", Sys.getpid(), "_")
path <- function(n) file.path(out, paste0(run, n))
emit <- function(x, n) { f <- path(paste0(n, ".csv")); stopifnot(!file.exists(f)); write_csv(x, f, na = "NA") }
sha <- function(f) digest::digest(file = f, algo = "sha256")
sources <- tibble(label = c("pbp2023", "pbp2024", "schedule", "cohort", "D_keys", "R2023", "R2024"),
  file = c(file.path(work2023, "play_by_play_2023.parquet"), file.path(work2024, "play_by_play_2024.parquet"),
    file.path(work2023, "schedule_reference.rds"), args[3:6]),
  sha256 = c("bd3484731408def6b0ec93225bba2bd7b2c65769ca707a2b9444d891abdc6776",
    "3fd2896bc0b911b615142d2f1fabae54a4bbba5ab7b73b28187b118ef8af6a3b",
    "659e4ae782353bb80d196c6789e11eae545a93be9fdb668dd3e3ae4fdac860eb",
    "4460604f27bbbe432fd42e9bbdcf426315844d5fb996f769bbd268fe375235bf",
    "be1f386ebc899a29043491f93568388863447d789705c2fc0833e46b85b6d946",
    "1648351bd64060d52041c9bfb977afe24cfde454788d013b7e4ffc3864f1ce36",
    "a555e4020169a987c66f73351e95975f3c07faff559def179ba93cdbb11ef22c"))
for (i in seq_len(nrow(sources))) stopifnot(file.exists(sources$file[i]), sha(sources$file[i]) == sources$sha256[i])
sources <- mutate(sources, bytes = file.info(file)$size)
emit(sources, "verified_sources")
counts <- read_csv(args[3], show_col_types = FALSE)
ids <- sort(counts$passer_player_id)
stopifnot(length(ids) == 20, !anyDuplicated(ids), all(counts$common_qualifies),
  all(counts$E_2023 >= 200 & counts$E_2024 >= 200 & counts$E_games_2023 >= 10 & counts$E_games_2024 >= 10))
D <- read_csv(args[4], show_col_types = FALSE) |> select(season, actor_id, game_id, play_id, role) |>
  mutate(population = "D")
R <- bind_rows(lapply(args[5:6], function(f) read_csv(f, show_col_types = FALSE,
  col_select = c(season, game_id, play_id, rusher_player_id, in_R)) |> filter(in_R) |>
    transmute(season, actor_id = rusher_player_id, game_id, play_id, role = "recorded_non_scramble_run", population = "R")))
stopifnot(!anyNA(D), !anyNA(R), all(D$actor_id %in% ids), all(R$actor_id %in% ids),
  !anyDuplicated(D[c("season", "game_id", "play_id")]), !anyDuplicated(R[c("season", "game_id", "play_id")]),
  nrow(inner_join(D, R, by = c("season", "game_id", "play_id"), relationship = "one-to-one")) == 0,
  all(D$role %in% c("other_pass", "sack", "scramble")))
O_keys <- bind_rows(D, R) |> arrange(actor_id, season, game_id, play_id)
schedule <- readRDS(sources$file[3]) |> filter(season %in% c(2023, 2024), game_type == "REG")
stopifnot(!anyDuplicated(schedule$game_id), !anyNA(schedule[c("game_id", "gameday")]))
flags <- c("qb_dropback", "pass_attempt", "rush_attempt", "sack", "qb_scramble", "qb_spike", "qb_kneel", "two_point_attempt")
diag_flags <- c("aborted_play", "lateral_rush", "fumble", "fumble_lost", "penalty")
raw <- list()
O <- bind_rows(lapply(c(2023, 2024), function(year) {
  f <- sources$file[match(paste0("pbp", year), sources$label)]
  columns <- c("season", "season_type", "game_id", "play_id", "game_date", "play_type", "posteam",
    "passer_player_id", "rusher_player_id", "epa", flags, diag_flags)
  x <- arrow::read_parquet(f, col_select = all_of(columns)) |> filter(season == year, season_type == "REG")
  stopifnot(!anyNA(x[c("game_id", "play_id")]), !anyDuplicated(x[c("game_id", "play_id")]),
    is.character(x$game_id), is.numeric(x$play_id), is.character(x$passer_player_id),
    is.character(x$rusher_player_id), is.numeric(x$epa), all(vapply(x[c(flags, diag_flags)], is.numeric, logical(1))))
  raw[[as.character(year)]] <<- x
  k <- filter(O_keys, season == year)
  z <- left_join(k, x, by = c("season", "game_id", "play_id"), relationship = "one-to-one") |>
    mutate(accepted_date = as.Date(game_date), raw_actor = if_else(role %in% c("scramble", "recorded_non_scramble_run"), rusher_player_id, passer_player_id))
  required_D <- with(z, population == "D" & (is.na(qb_dropback) | qb_dropback != 1 | !play_type %in% c("pass", "run") |
    is.na(qb_spike) | qb_spike != 0 | is.na(qb_kneel) | qb_kneel != 0 | is.na(two_point_attempt) | two_point_attempt != 0))
  role_ok <- with(z, (role == "other_pass" & play_type == "pass" & sack == 0 & qb_scramble == 0 & pass_attempt == 1 & is.na(rusher_player_id)) |
    (role == "sack" & play_type == "pass" & sack == 1 & qb_scramble == 0 & pass_attempt == 1 & is.na(rusher_player_id)) |
    (role == "scramble" & play_type == "run" & sack == 0 & qb_scramble == 1 & rush_attempt == 1 & is.na(passer_player_id)) |
    (role == "recorded_non_scramble_run" & play_type == "run" & rush_attempt == 1 & qb_scramble == 0 & qb_kneel == 0 & two_point_attempt == 0))
  dates <- as.Date(schedule$gameday[match(z$game_id, schedule$game_id)])
  bad <- z[which(is.na(z$raw_actor) | z$raw_actor != z$actor_id | trimws(z$actor_id) == "" |
    is.na(z$accepted_date) | is.na(dates) | z$accepted_date != dates | !is.finite(z$epa) |
    is.na(required_D) | required_D | is.na(role_ok) | !role_ok), ]
  emit(bad, paste0("contradictions_", year))
  if (nrow(bad)) stop("Target key/role/attribution/date/EPA contradiction; no affected estimates: ", year)
  stopifnot(nrow(z) == nrow(k), !anyNA(z$season_type))
  emit(tibble(field = columns, type = vapply(x[columns], function(v) paste(class(v), collapse = "/"), character(1))), paste0("schema_", year))
  z
}))
# Before any EPA sum/rate, reconcile the frozen target keys independently from raw flags.
independent <- bind_rows(lapply(raw, function(x) {
  actor_D <- ifelse(x$play_type == "pass", x$passer_player_id, x$rusher_player_id)
  d <- which(x$qb_dropback == 1 & x$play_type %in% c("pass", "run") & x$qb_spike == 0 &
    x$qb_kneel == 0 & x$two_point_attempt == 0 & actor_D %in% ids)
  r <- which(x$play_type == "run" & x$rush_attempt == 1 & x$qb_scramble == 0 &
    x$qb_kneel == 0 & x$two_point_attempt == 0 & x$rusher_player_id %in% ids)
  stopifnot(length(intersect(d, r)) == 0)
  bind_rows(tibble(season = x$season[d], actor_id = actor_D[d], game_id = x$game_id[d], play_id = x$play_id[d],
    role = ifelse(x$play_type[d] == "run", "scramble", ifelse(x$sack[d] == 1, "sack", "other_pass")), population = "D"),
    tibble(season = x$season[r], actor_id = x$rusher_player_id[r], game_id = x$game_id[r], play_id = x$play_id[r],
      role = "recorded_non_scramble_run", population = "R"))
})) |> arrange(actor_id, season, game_id, play_id)
stopifnot(isTRUE(all.equal(O_keys, independent, check.attributes = FALSE)))
count_guards <- O |> group_by(season) |> summarise(O = n(), D = sum(population == "D"),
  S = sum(role == "scramble"), R = sum(population == "R"), R_aborted = sum(population == "R" & aborted_play == 1, na.rm = TRUE),
  R_lateral = sum(population == "R" & lateral_rush == 1, na.rm = TRUE), .groups = "drop") |> arrange(season)
stopifnot(all(count_guards$D == c(11371, 9989)), all(count_guards$S == c(558, 504)),
  all(count_guards$R == c(388, 369)), all(count_guards$O == c(11759, 10358)),
  all(count_guards$R_aborted == c(33, 43)), all(count_guards$R_lateral == 1))
maps <- O |> distinct(actor_id, season, game_id, accepted_date) |> arrange(actor_id, season, accepted_date, game_id) |>
  group_by(actor_id, season) |> mutate(game_index = row_number(), actor_games = n()) |> ungroup() |>
  mutate(half = if_else(season == 2023, if_else(game_index %% 2 == 1, "A", "B"), NA_character_))
independent_maps <- bind_rows(lapply(ids, function(id) bind_rows(lapply(c(2023, 2024), function(s) {
  z <- O[O$actor_id == id & O$season == s, ]; g <- unique(z[c("game_id", "accepted_date")]); g <- g[order(g$accepted_date, g$game_id), ]
  j <- seq_len(nrow(g)); tibble(actor_id = id, season = s, game_id = g$game_id, accepted_date = g$accepted_date,
    game_index = j, actor_games = length(j), half = if (s == 2023) ifelse(j %% 2, "A", "B") else NA_character_)
}))))
stopifnot(isTRUE(all.equal(maps, independent_maps, check.attributes = FALSE)))
O <- left_join(O, select(maps, actor_id, season, game_id, half), by = c("actor_id", "season", "game_id"), relationship = "many-to-one")
exposure <- O |> group_by(actor_id, season) |> summarise(N_O = n(), O_games = n_distinct(game_id), .groups = "drop")
half_counts <- filter(O, season == 2023) |> count(actor_id, half, name = "N_O")
stopifnot(nrow(exposure) == 40, all(exposure$N_O > 0), all(exposure$O_games >= 2), nrow(half_counts) == 40, all(half_counts$N_O > 0))
emit(O_keys, "frozen_O_keys"); emit(maps, "frozen_O_maps"); emit(arrange(counts, passer_player_id), "frozen_cohort")
emit(count_guards, "count_guards"); emit(exposure, "actor_season_count_guards"); emit(half_counts, "half_count_guards")
game_lists <- bind_rows(mutate(distinct(filter(O, season == 2023), season, game_id), analysis = "interleaved"),
  mutate(distinct(O, season, game_id), analysis = "annual")) |> arrange(analysis, season, game_id)
emit(game_lists, "frozen_contributing_games")
emit(tibble(check = c("independent_original_D_R_keys", "D_R_disjoint_S_subset_D", "independent_O_game_maps", "positive_actor_half_O"), passed = TRUE), "pre_estimation_verification")
frozen_names <- c("frozen_O_keys.csv", "frozen_O_maps.csv", "frozen_cohort.csv", "count_guards.csv", "frozen_contributing_games.csv", "half_count_guards.csv")
frozen_hashes <- tibble(file = frozen_names, sha256 = vapply(path(frozen_names), sha, character(1)))
emit(frozen_hashes, "frozen_hashes")
script <- sub("^--file=", "", grep("^--file=", commandArgs(), value = TRUE))
record <- list(version = "recorded-run-contribution-1.0", stage = "frozen_before_EPA_sums_or_rates", design_sha256 = args[8],
  script_sha256 = sha(script), frozen_utc = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
  sources = sources, cohort = ids, frozen_hashes = frozen_hashes,
  definition_authority_sha256 = "e4563fdf81f7e126b655cc95ebb6e1c7d000f4073f5495e7d9db78956f8ae64c",
  denominator = "O=D disjoint union R; S subset D; raw actor across teams; no CP/E-game/outcome/penalty/text filter",
  endpoint = "two 2023 interleaved Pearson C_S/C_R associations; two annual 2023/2024 self-associations; C_k=sum(role EPA)/N_O",
  uncertainty = "whole NFL O-game deletion; Fisher correlation intervals with own replicate mean in each season; actor-season ratio intervals on all actor O games, centered on replicate mean",
  limits = "Shared observed contribution combines usage and value; R is recorded non-scramble actor runs, not designed runs or mobility skill")
saveRDS(record, path("run_manifest.rds"))

# Each actor-game stays intact; include games with zero role opportunities.
g <- O |> group_by(actor_id, season, game_id, half) |> summarise(N = n(),
  n_S = sum(role == "scramble"), n_R = sum(population == "R"),
  U_S = sum(epa[role == "scramble"]), U_R = sum(epa[population == "R"]), .groups = "drop") |> arrange(actor_id, season, game_id)
emit(g, "actor_game_sums")
point_summary <- function(data, groups) {
  bind_rows(lapply(c("S", "R"), function(k) {
    data |> group_by(across(all_of(groups))) |> summarise(N_O = sum(N), O_games = n(),
      n_role = sum(.data[[paste0("n_", k)]]), role_games = sum(.data[[paste0("n_", k)]] > 0),
      role_epa = sum(.data[[paste0("U_", k)]]), .groups = "drop") |>
      mutate(component = k, contribution = role_epa / N_O, share = n_role / N_O,
        role_mean_epa = if_else(n_role > 0, role_epa / n_role, NA_real_),
        role_mean_status = if_else(n_role > 0, "observed_role_mean", "no_recorded_role_opportunities"))
  }))
}
annual_points <- point_summary(g, c("actor_id", "season")) |> arrange(actor_id, season, component)
half_points <- point_summary(filter(g, season == 2023), c("actor_id", "half")) |> arrange(actor_id, half, component)
for (z in list(annual_points, half_points)) stopifnot(all(z$N_O > 0), all(is.finite(z$contribution)),
  all(z$share >= 0 & z$share <= 1), all(abs(z$contribution[z$n_role > 0] - z$share[z$n_role > 0] * z$role_mean_epa[z$n_role > 0]) < 1e-12),
  all(z$contribution[z$n_role == 0] == 0), all(is.na(z$role_mean_epa[z$n_role == 0])))
emit(annual_points, "actor_season_points"); emit(half_points, "actor_half_points")
for (k in c("S", "R")) {
  z <- filter(O, if (k == "S") role == "scramble" else population == "R")
  diag <- z |> group_by(actor_id, season) |> summarise(role_rows = n(),
    across(all_of(diag_flags), list(one = ~sum(.x == 1, na.rm = TRUE), unknown = ~sum(is.na(.x)),
      nonbinary = ~sum(!is.na(.x) & !.x %in% c(0, 1))), .names = "{.col}_{.fn}"), .groups = "drop")
  emit(diag |> arrange(actor_id, season), paste0(k, "_outcome_diagnostics"))
}

safe_cor <- function(x, y) {
  if (!all(is.finite(c(x, y)))) return(list(r = NA_real_, status = "nonfinite_rate"))
  if (length(x) < 2 || var(x) == 0 || var(y) == 0) return(list(r = NA_real_, status = "zero_actor_variance"))
  r <- cor(x, y)
  list(r = r, status = if (!is.finite(r)) "nonfinite_correlation" else
    if (abs(r) == 1) "perfect_correlation" else "defined")
}
variance_terms <- function(z, strata) {
  bind_rows(lapply(sort(unique(strata)), function(s) {
    values <- z[strata == s]; G <- length(values)
    m <- if (G >= 1 && all(is.finite(values))) mean(values) else NA_real_
    V <- if (G >= 2 && is.finite(m)) (G - 1) / G * sum((values - m)^2) else NA_real_
    tibble(stratum = s, G = G, deletion_center_z = m, coefficient = (G - 1) / G, variance = V)
  }))
}
fisher_interval <- function(full_r, deletion_r, strata) {
  status <- if (!is.finite(full_r)) "undefined_full_correlation" else
    if (abs(full_r) == 1) "perfect_full_correlation" else
      if (any(!is.finite(deletion_r))) "undefined_deletion_correlation" else
        if (any(abs(deletion_r) == 1)) "perfect_deletion_correlation" else "defined"
  z <- rep(NA_real_, length(deletion_r))
  ok <- is.finite(deletion_r) & abs(deletion_r) < 1
  z[ok] <- atanh(deletion_r[ok])
  terms <- variance_terms(z, strata)
  V <- SE <- lower <- upper <- NA_real_
  if (status == "defined") {
    if (any(terms$G < 2)) status <- "fewer_than_two_games_in_stratum" else {
      V <- sum(terms$variance)
      if (!is.finite(V)) status <- "nonfinite_variance" else if (V <= 0) status <- "zero_or_invalid_variance" else {
        SE <- sqrt(V); lower <- tanh(atanh(full_r) - 1.96 * SE); upper <- tanh(atanh(full_r) + 1.96 * SE)
        status <- "approximate_95pct_conditional_working_model_sensitivity"
      }
    }
  }
  list(summary = tibble(variance_z = V, SE_z = SE, lower = lower, upper = upper, interval_status = status), terms = terms)
}
association <- function(data, analysis, component, members) {
  sums <- data |> mutate(side = if (analysis == "annual") if_else(season == 2023, "A", "B") else half) |>
    group_by(actor_id, side) |> summarise(N = sum(N), U = sum(.data[[paste0("U_", component)]]), .groups = "drop")
  grid <- expand.grid(actor_id = members, side = c("A", "B"), stringsAsFactors = FALSE) |> arrange(actor_id, side)
  values <- left_join(grid, sums, by = c("actor_id", "side"), relationship = "one-to-one") |>
    mutate(N = coalesce(N, 0L), value = if_else(N > 0, U / N, NA_real_))
  if (any(values$N <= 0) || !all(is.finite(values$value))) return(tibble(r = NA_real_, status = "nonpositive_O_or_nonfinite_contribution", min_O = min(values$N)))
  a <- filter(values, side == "A"); b <- filter(values, side == "B")
  stopifnot(identical(a$actor_id, sort(members)), identical(b$actor_id, sort(members)))
  correlation <- safe_cor(a$value, b$value)
  tibble(r = correlation$r, status = correlation$status, min_O = min(values$N))
}
ratio_sensitivity <- function(N_g, U_g) {
  G <- length(N_g); N <- sum(N_g); U <- sum(U_g)
  estimate <- if (N > 0 && is.finite(U)) U / N else NA_real_
  remaining <- N - N_g
  deleted <- rep(NA_real_, G); ok <- remaining > 0
  deleted[ok] <- (U - U_g[ok]) / remaining[ok]
  status <- if (N <= 0) "nonpositive_O" else if (G < 2) "fewer_than_two_O_games" else
    if (any(!ok)) "nonpositive_deleted_O" else if (!all(is.finite(deleted)) || !is.finite(estimate)) "nonfinite_ratio" else "defined"
  m <- V <- SE <- lower <- upper <- NA_real_
  if (status == "defined") {
    m <- mean(deleted); V <- (G - 1) / G * sum((deleted - m)^2)
    if (!is.finite(V) || V < 0) status <- "nonfinite_or_invalid_variance" else {
      SE <- sqrt(V); lower <- estimate - 1.96 * SE; upper <- estimate + 1.96 * SE
      status <- if (V == 0) "collapsed_no_observed_deletion_variation" else "approximate_conditional_game_sampling_sensitivity"
    }
  }
  list(summary = tibble(estimate = estimate, O_games = G, deletion_center = m, variance = V, SE = SE,
    lower = lower, upper = upper, interval_status = status,
    deletion_min = if (all(is.finite(deleted)) && G > 0) min(deleted) else NA_real_,
    deletion_max = if (all(is.finite(deleted)) && G > 0) max(deleted) else NA_real_),
    deleted = deleted, remaining = remaining)
}
known <- ratio_sensitivity(rep(1, 4), 1:4)
unequal <- ratio_sensitivity(c(1, 2), c(1, 8))
zero <- ratio_sensitivity(c(2, 3), c(0, 0))
empty_role <- point_summary(tibble(actor_id = "toy", N = c(2L, 3L), n_S = c(0L, 0L), n_R = c(1L, 1L),
  U_S = c(0, 0), U_R = c(1, -1)), "actor_id") |> filter(component == "S")
stopifnot(abs(known$summary$estimate - 2.5) < 1e-12, abs(known$summary$SE - sqrt(5 / 12)) < 1e-12,
  identical(unequal$deleted, c(4, 1)), unequal$summary$estimate == 3, unequal$summary$variance == 2.25,
  zero$summary$estimate == 0, zero$summary$variance == 0,
  zero$summary$interval_status == "collapsed_no_observed_deletion_variation",
  empty_role$contribution == 0, empty_role$share == 0, is.na(empty_role$role_mean_epa),
  ratio_sensitivity(c(0, 0), c(0, 0))$summary$interval_status == "nonpositive_O",
  ratio_sensitivity(c(1), c(1))$summary$interval_status == "fewer_than_two_O_games",
  ratio_sensitivity(c(0, 1), c(0, 1))$summary$interval_status == "nonpositive_deleted_O",
  ratio_sensitivity(c(1, 1), c(NA, 1))$summary$interval_status == "nonfinite_ratio",
  safe_cor(rep(0, 4), 1:4)$status == "zero_actor_variance",
  fisher_interval(.2, c(1, .1), c(1, 1))$summary$interval_status == "perfect_deletion_correlation",
  fisher_interval(1, c(.1, .2), c(1, 1))$summary$interval_status == "perfect_full_correlation",
  fisher_interval(.2, c(NA, .1), c(1, 1))$summary$interval_status == "undefined_deletion_correlation",
  fisher_interval(NA_real_, c(.1, .2), c(1, 1))$summary$interval_status == "undefined_full_correlation",
  fisher_interval(.2, c(.1, .1), c(1, 1))$summary$interval_status == "zero_or_invalid_variance",
  fisher_interval(.2, c(.1, .2), c(1, 2))$summary$interval_status == "fewer_than_two_games_in_stratum",
  abs(sum(variance_terms(c(4, 3.5, 3, 4.5, 2.5)^2, c(2023, 2023, 2023, 2024, 2024))$variance) - 2353 / 36) < 1e-12)
emit(tibble(check = c("known_mean_SE", "unequal_denominator_variance", "zero_role_collapsed_variance", "unavailable_status_guards"),
  actual = c(known$summary$SE, unequal$summary$variance, zero$summary$variance, 1),
  expected = c(sqrt(5 / 12), 2.25, 0, 1)), "math_verification")

marginal <- marginal_deleted <- list()
for (id in ids) for (year in c(2023, 2024)) for (k in c("S", "R")) {
  data <- filter(g, actor_id == id, season == year) |> arrange(game_id)
  result <- ratio_sensitivity(data$N, data[[paste0("U_", k)]])
  label <- paste(id, year, k)
  marginal[[label]] <- bind_cols(tibble(actor_id = id, season = year, component = k), result$summary)
  marginal_deleted[[label]] <- tibble(actor_id = id, season = year, component = k, game_id = data$game_id,
    deleted_N = data$N, deleted_role_epa = data[[paste0("U_", k)]], remaining_O = result$remaining,
    deletion_contribution = result$deleted)
}
# All O games appear for both roles, including zero-role games.
marginal <- bind_rows(marginal) |> arrange(actor_id, season, component)
stopifnot(nrow(marginal) == 80, all(abs(marginal$estimate - annual_points$contribution) < 1e-12))
emit(marginal, "actor_season_intervals")
emit(bind_rows(marginal_deleted) |> arrange(actor_id, season, component, game_id), "actor_season_game_deletions")
range_summary <- function(v) {
  finite <- v[is.finite(v)]
  tibble(undefined = sum(!is.finite(v)), minimum = if (length(finite)) min(finite) else NA_real_,
    maximum = if (length(finite)) max(finite) else NA_real_)
}
results <- list()
for (analysis in c("interleaved", "annual")) for (k in c("S", "R")) {
  data <- if (analysis == "annual") g else filter(g, season == 2023)
  full <- association(data, analysis, k, ids)
  games <- filter(game_lists, .data$analysis == .env$analysis)
  deleted <- bind_rows(lapply(seq_len(nrow(games)), function(j) {
    s <- games$season[j]; game <- games$game_id[j]
    removed <- filter(data, season == s, game_id == game)
    retained <- filter(data, !(season == s & game_id == game))
    stopifnot(sum(removed$N) + sum(retained$N) == sum(data$N), nrow(removed) > 0,
      !any(retained$season == s & retained$game_id == game))
    bind_cols(tibble(season = s, game_id = game, removed_O = sum(removed$N),
      removed_role_epa = sum(removed[[paste0("U_", k)]]), removed_actors = n_distinct(removed$actor_id),
      removed_half_labels = if (analysis == "annual") 1L else n_distinct(removed$half)),
      association(retained, analysis, k, ids))
  })) |> arrange(season, game_id)
  interval <- fisher_interval(full$r, deleted$r, deleted$season)
  actor_deleted <- bind_rows(lapply(ids, function(id) {
    members <- ids[ids != id]; stopifnot(length(members) == 19)
    bind_cols(tibble(deleted_actor = id), association(filter(data, actor_id != id), analysis, k, members))
  })) |> mutate(sign_reversal = r * full$r < 0) |> arrange(deleted_actor)
  label <- paste0(analysis, "_", k)
  emit(deleted, paste0(label, "_game_deletions")); emit(actor_deleted, paste0(label, "_actor_deletions"))
  emit(interval$terms, paste0(label, "_variance_terms"))
  gr <- range_summary(deleted$r); ar <- range_summary(actor_deleted$r)
  results[[label]] <- bind_cols(tibble(analysis = analysis, component = k, actors = 20L, contributing_games = nrow(games)),
    full, interval$summary, tibble(game_deletion_min = gr$minimum, game_deletion_max = gr$maximum,
      game_undefined = gr$undefined, actor_deletion_min = ar$minimum, actor_deletion_max = ar$maximum,
      actor_undefined = ar$undefined, actor_sign_reversals = sum(actor_deleted$sign_reversal, na.rm = TRUE)))
}
results <- bind_rows(results)
emit(results, "results")
emit(half_points |> group_by(component) |> summarise(zero_role_halves = sum(n_role == 0),
  total_halves = n(), .groups = "drop"), "zero_role_half_counts")
stopifnot(all(vapply(seq_len(nrow(frozen_hashes)), function(i) sha(path(frozen_hashes$file[i])) == frozen_hashes$sha256[i], logical(1))))
writeLines(capture.output(sessionInfo()), path("sessionInfo.txt"))
writeLines(c("Completed all four fixed endpoints, paired influence and marginal actor-season ratio sensitivities.",
  "Observed shared contribution combines frequency and value; no mobility rating, designed-run label, context-adjusted score or forecast."), path("completion.txt"))
cat("Completed. Evidence prefix:", path(""), "\n")
print(select(results, analysis, component, r, lower, upper, interval_status, actor_sign_reversals), width = Inf)
