# Recorded sack avoidance on fixed played dropbacks, specification 1.0.
# Usage: Rscript sack_repeatability.R <2023-inputs> <2024-inputs> <cohort.csv>
#        <E-keys.csv> <D-keys.csv> <existing-output-directory> <design-sha256>
# Exact local snapshots/count manifests only; no downloads or internal-note reads.
# Pearson associations and conditional game-jackknife sensitivities describe a
# selected convenience cohort, not pressure conversion, prediction or isolated skill.
# Original code MIT; nflverse PBP CC BY 4.0 and upstream schedule notices are separate.
suppressPackageStartupMessages({library(dplyr); library(readr)})
stopifnot(requireNamespace("arrow", quietly = TRUE), requireNamespace("digest", quietly = TRUE))
args <- commandArgs(trailingOnly = TRUE)
if (length(args) != 7 || !all(dir.exists(args[c(1, 2, 6)]))) {
  stop("Supply 2023/2024 workspaces, cohort/E-key/D-key CSVs, an existing output directory and design SHA256.")
}
accepted_design <- "e60420a5020804a5cafcd3eaf559b20d17ab716c52e9130e32f48c6ae1f070d7"
stopifnot(identical(args[7], accepted_design))
work2023 <- normalizePath(args[1], mustWork = TRUE)
work2024 <- normalizePath(args[2], mustWork = TRUE)
out <- normalizePath(args[6], mustWork = TRUE)
run <- paste0(format(Sys.time(), "%Y%m%dT%H%M%S", tz = "UTC"), "_sack_", Sys.getpid())
path <- function(name) file.path(out, paste0(run, "_", name))
emit <- function(x, name) {
  target <- path(paste0(name, ".csv"))
  if (file.exists(target)) stop("Refusing to overwrite: ", target)
  write_csv(x, target, na = "NA")
}
sources <- tibble(
  label = c("pbp2023", "pbp2024", "schedule", "cohort", "E_keys", "D_keys"),
  file = c(file.path(work2023, "play_by_play_2023.parquet"),
    file.path(work2024, "play_by_play_2024.parquet"),
    file.path(work2023, "schedule_reference.rds"), args[3:5]),
  sha256 = c("bd3484731408def6b0ec93225bba2bd7b2c65769ca707a2b9444d891abdc6776",
    "3fd2896bc0b911b615142d2f1fabae54a4bbba5ab7b73b28187b118ef8af6a3b",
    "659e4ae782353bb80d196c6789e11eae545a93be9fdb668dd3e3ae4fdac860eb",
    "4460604f27bbbe432fd42e9bbdcf426315844d5fb996f769bbd268fe375235bf",
    "67f05a4386241620f24b4618ebd504931fa7659c5c8c57c4c9f5b2a3f9056808",
    "be1f386ebc899a29043491f93568388863447d789705c2fc0833e46b85b6d946"))
for (i in seq_len(nrow(sources))) {
  stopifnot(file.exists(sources$file[i]),
    digest::digest(file = sources$file[i], algo = "sha256") == sources$sha256[i])
}
sources <- mutate(sources, bytes = file.info(file)$size)
stopifnot(identical(as.numeric(sources$bytes[1:3]), c(20534088, 20597560, 428923)))
emit(sources, "verified_sources")
schedule <- readRDS(sources$file[3]) |> filter(season %in% c(2023, 2024), game_type == "REG")
stopifnot(!anyNA(schedule[c("game_id", "gameday")]), !anyDuplicated(schedule$game_id))
counts <- read_csv(args[3], show_col_types = FALSE)
E <- read_csv(args[4], show_col_types = FALSE)
accepted_D <- read_csv(args[5], show_col_types = FALSE)
stopifnot(!anyDuplicated(counts$passer_player_id), nrow(counts) == 20,
  all(counts$common_qualifies), all(counts$E_2023 >= 200 & counts$E_2024 >= 200),
  all(counts$E_games_2023 >= 10 & counts$E_games_2024 >= 10),
  !anyNA(E[c("season", "game_id", "play_id", "passer_player_id")]),
  !anyDuplicated(E[c("season", "game_id", "play_id")]))
cohort <- sort(counts$passer_player_id)
E_counts <- E |> group_by(passer_player_id, season) |>
  summarise(E_N = n(), E_games = n_distinct(game_id), .groups = "drop")
reconstructed <- E_counts |> group_by(passer_player_id) |>
  summarise(qualifies = n() == 2 && all(E_N >= 200 & E_games >= 10), .groups = "drop")
stopifnot(identical(sort(filter(reconstructed, qualifies)$passer_player_id), cohort),
  setequal(unique(filter(E, in_cohort)$passer_player_id), cohort))
for (year in c(2023, 2024)) {
  ec <- E_counts |> filter(season == year, passer_player_id %in% cohort) |> arrange(passer_player_id)
  cc <- arrange(counts, passer_player_id)
  stopifnot(identical(ec$passer_player_id, cohort),
    all(ec$E_N == cc[[paste0("E_", year)]]), all(ec$E_games == cc[[paste0("E_games_", year)]]))
}
emit(arrange(counts, passer_player_id), "frozen_cohort")

eligibility_flags <- c("qb_dropback", "qb_spike", "qb_kneel", "two_point_attempt")
role_flags <- c("sack", "qb_scramble", "pass_attempt", "rush_attempt")
diag_flags <- c("interception", "fumble_lost", "penalty")
flags <- c(eligibility_flags, role_flags, diag_flags)
raw <- list()
prepare <- function(year, file) {
  rows <- arrow::read_parquet(file) |> filter(season == year, season_type == "REG")
  required <- c("season", "game_id", "play_id", "game_date", "play_type", "posteam",
    "passer_player_id", "rusher_player_id", flags)
  stopifnot(all(required %in% names(rows)), is.character(rows$game_id),
    is.character(rows$passer_player_id), is.character(rows$rusher_player_id),
    is.numeric(rows$play_id), all(is.finite(rows$play_id)), all(rows$play_id == floor(rows$play_id)),
    !anyNA(rows[c("game_id", "play_id")]), !anyDuplicated(rows[c("game_id", "play_id")]),
    all(vapply(rows[flags], is.numeric, logical(1))))
  rows <- select(rows, all_of(required))
  raw[[as.character(year)]] <<- rows
  emit(tibble(field = required, type = vapply(rows[required], function(x) paste(class(x), collapse = "/"), character(1))),
    paste0("schema_", year))
  emit(bind_rows(lapply(flags, function(f) tibble(field = f, missing = sum(is.na(rows[[f]])),
    nonbinary = sum(!is.na(rows[[f]]) & !rows[[f]] %in% c(0, 1))))), paste0("flag_domains_", year))
  rows <- rows |> mutate(exclusion = case_when(
    is.na(qb_dropback) ~ "unknown_dropback", !qb_dropback %in% c(0, 1) ~ "nonbinary_dropback",
    qb_dropback != 1 ~ "not_recorded_dropback", is.na(play_type) ~ "unknown_play_type",
    !play_type %in% c("pass", "run") ~ "outside_played_pass_run",
    is.na(qb_spike) | is.na(qb_kneel) | is.na(two_point_attempt) ~ "unknown_special_flag",
    !qb_spike %in% c(0, 1) | !qb_kneel %in% c(0, 1) | !two_point_attempt %in% c(0, 1) ~ "nonbinary_special_flag",
    qb_spike != 0 ~ "spike", qb_kneel != 0 ~ "kneel", two_point_attempt != 0 ~ "two_point",
    TRUE ~ "included_D"))
  emit(count(rows, exclusion), paste0("exclusion_flow_", year))
  D <- rows |> filter(exclusion == "included_D") |> mutate(
    role = case_when(play_type == "pass" & sack == 0 & qb_scramble == 0 ~ "other_pass",
      play_type == "pass" & sack == 1 & qb_scramble == 0 ~ "sack",
      play_type == "run" & sack == 0 & qb_scramble == 1 ~ "scramble", TRUE ~ NA_character_),
    actor_id = if_else(play_type == "pass", passer_player_id, rusher_player_id),
    accepted_date = as.Date(game_date))
  bad <- D |> filter(is.na(role) | is.na(actor_id) | trimws(actor_id) == "" |
    is.na(accepted_date) | is.na(sack) | is.na(qb_scramble) |
    !sack %in% c(0, 1) | !qb_scramble %in% c(0, 1) |
    (play_type == "pass" & (is.na(pass_attempt) | pass_attempt != 1 | !is.na(rusher_player_id))) |
    (play_type == "run" & (is.na(rush_attempt) | rush_attempt != 1 | !is.na(passer_player_id))))
  emit(bad, paste0("contradictions_", year))
  if (nrow(bad)) stop("D role/ID/required-flag contradiction; no affected estimates: ", year)
  expected_date <- as.Date(schedule$gameday[match(D$game_id, schedule$game_id)])
  stopifnot(!anyNA(expected_date), all(D$accepted_date == expected_date))
  D
}
D <- bind_rows(prepare(2023, sources$file[1]), prepare(2024, sources$file[2]))
key_fields <- c("season", "actor_id", "game_id", "play_id", "role", "passer_player_id", "rusher_player_id")
selected <- filter(D, actor_id %in% cohort)
D_keys <- select(selected, all_of(key_fields)) |> arrange(actor_id, season, game_id, play_id)
reference_keys <- select(accepted_D, all_of(key_fields)) |> arrange(actor_id, season, game_id, play_id)
stopifnot(isTRUE(all.equal(D_keys, reference_keys, check.attributes = FALSE)))
E_selected <- filter(E, passer_player_id %in% cohort)
E_in_D <- inner_join(E_selected, select(selected, season, game_id, play_id, actor_id),
  by = c("season", "game_id", "play_id"), relationship = "one-to-one")
stopifnot(nrow(E_in_D) == nrow(E_selected), all(E_in_D$passer_player_id == E_in_D$actor_id))
all_counts <- D |> group_by(season) |> summarise(N = n(), sacks = sum(sack),
  scrambles = sum(role == "scramble"), .groups = "drop") |> arrange(season)
stopifnot(all(all_counts$N == c(20693, 20116)), all(all_counts$sacks == c(1410, 1314)),
  all(all_counts$scrambles == c(1035, 1062)))
selected_counts <- selected |> group_by(season) |> summarise(N = n(), actors = n_distinct(actor_id), .groups = "drop") |>
  arrange(season)
stopifnot(all(selected_counts$N == c(11371, 9989)), all(selected_counts$actors == 20))
exposure <- selected |> group_by(actor_id, season) |> summarise(N = n(), games = n_distinct(game_id), .groups = "drop")
stopifnot(nrow(exposure) == 40, all(exposure$N >= 200), all(exposure$games >= 10))
emit(all_counts, "all_actor_count_guards")
emit(selected_counts, "selected_count_guards")
emit(exposure |> arrange(actor_id, season), "actor_season_count_guards")
emit(select(D, all_of(key_fields)) |> arrange(season, game_id, play_id), "all_D_keys")
emit(D_keys, "frozen_D_keys")

mapping <- selected |> distinct(season, actor_id, game_id, accepted_date) |>
  arrange(season, actor_id, accepted_date, game_id) |> group_by(season, actor_id) |>
  mutate(game_index = row_number(), total_games = n()) |> ungroup()
splits <- filter(mapping, season == 2023) |> mutate(
  interleaved = if_else(game_index %% 2 == 1, "A", "B"),
  chronological = if_else(game_index <= ceiling(total_games / 2), "A", "B"))
# Independent base-R reconstruction before any rate: original rows, different
# selection expression and per-actor ordering; no helper used by prepare().
independent_keys <- bind_rows(lapply(raw, function(r) {
  idx <- which(r$qb_dropback == 1 & r$play_type %in% c("pass", "run") &
    r$qb_spike == 0 & r$qb_kneel == 0 & r$two_point_attempt == 0)
  x <- r[idx, ]
  x$actor_id <- x$passer_player_id
  x$actor_id[x$play_type == "run"] <- x$rusher_player_id[x$play_type == "run"]
  x$role <- ifelse(x$play_type == "run", "scramble", ifelse(x$sack == 1, "sack", "other_pass"))
  x[, key_fields]
})) |> arrange(season, game_id, play_id)
stopifnot(isTRUE(all.equal(independent_keys, select(D, all_of(key_fields)) |>
  arrange(season, game_id, play_id), check.attributes = FALSE)))
independent_splits <- bind_rows(lapply(cohort, function(id) {
  x <- raw[["2023"]]
  k <- independent_keys[independent_keys$season == 2023 & independent_keys$actor_id == id, ]
  gids <- unique(k$game_id)
  dates <- as.Date(x$game_date[match(gids, x$game_id)])
  o <- order(dates, gids); gids <- gids[o]; dates <- dates[o]; j <- seq_along(gids)
  tibble(season = 2023L, actor_id = id, game_id = gids, accepted_date = dates,
    game_index = j, total_games = length(gids), interleaved = ifelse(j %% 2, "A", "B"),
    chronological = ifelse(j <= ceiling(length(gids) / 2), "A", "B"))
}))
stopifnot(isTRUE(all.equal(splits, independent_splits, check.attributes = FALSE)))
# Verify raw E membership without relying on the cohort CSV's qualifying labels.
independent_ids <- sort(unique(E$passer_player_id))
independent_ids <- independent_ids[vapply(independent_ids, function(id) {
  all(vapply(c(2023, 2024), function(s) {
    e <- E[E$passer_player_id == id & E$season == s, ]
    nrow(e) >= 200 && length(unique(e$game_id)) >= 10
  }, logical(1)))
}, logical(1))]
stopifnot(identical(independent_ids, cohort))
emit(splits, "frozen_split_maps")
emit(mapping, "frozen_actor_game_dates")
emit(tibble(check = c("independent_original_D_keys", "independent_E_cohort", "independent_2023_split_maps",
  "accepted_D_key_identity", "accepted_E_keys_in_D"), passed = TRUE), "pre_estimation_verification")

# Counts retain unknown overlapping diagnostic flags; no rate-based eligibility.
count_outcomes <- function(data, groups) {
  data |> group_by(across(all_of(groups))) |> summarise(N = n(), games = n_distinct(game_id),
    sacks = sum(sack), scrambles = sum(role == "scramble"),
    across(all_of(diag_flags), list(observed_one = ~sum(.x == 1, na.rm = TRUE),
      unknown = ~sum(is.na(.x)), nonbinary = ~sum(!is.na(.x) & !.x %in% c(0, 1))),
      .names = "{.col}_{.fn}"), .groups = "drop")
}
count_data <- left_join(selected, select(splits, actor_id, game_id, interleaved, chronological),
  by = c("actor_id", "game_id"), relationship = "many-to-one")
# Game IDs contain season, so 2024 cannot inherit a 2023 half.
stopifnot(all(is.na(count_data$interleaved[count_data$season == 2024])))
for (analysis in c("interleaved", "chronological")) {
  rows <- filter(count_data, season == 2023) |> mutate(side = .data[[analysis]])
  emit(count_outcomes(rows, c("actor_id", "side")) |> arrange(actor_id, side), paste0(analysis, "_counts"))
}
emit(count_outcomes(selected, c("actor_id", "season")) |> arrange(actor_id, season), "annual_counts")
game_counts <- selected |> group_by(season, actor_id, game_id) |>
  summarise(N = n(), S = sum(sack), .groups = "drop") |>
  left_join(select(splits, actor_id, game_id, interleaved, chronological),
    by = c("actor_id", "game_id"), relationship = "many-to-one") |> arrange(season, game_id, actor_id)
emit(game_counts, "frozen_actor_game_counts")
game_lists <- bind_rows(lapply(c("interleaved", "chronological", "annual"), function(a) {
  g <- if (a == "annual") game_counts else filter(game_counts, season == 2023)
  distinct(g, season, game_id) |> mutate(analysis = a)
})) |> arrange(analysis, season, game_id)
emit(game_lists, "frozen_contributing_games")
frozen_files <- c("frozen_cohort.csv", "frozen_D_keys.csv", "frozen_split_maps.csv", "frozen_actor_game_dates.csv",
  "frozen_actor_game_counts.csv", "frozen_contributing_games.csv", "all_actor_count_guards.csv",
  "selected_count_guards.csv", "pre_estimation_verification.csv")
file_hashes <- tibble(file = frozen_files,
  sha256 = vapply(path(frozen_files), function(f) digest::digest(file = f, algo = "sha256"), character(1)))
emit(file_hashes, "frozen_file_hashes")
script <- sub("^--file=", "", grep("^--file=", commandArgs(), value = TRUE))
record <- list(specification = "recorded-sack-avoidance-1.0", design_sha256 = args[7],
  stage = "frozen_before_rates_or_correlations", frozen_utc = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
  script_sha256 = digest::digest(file = script, algo = "sha256"), sources = sources,
  cohort = cohort, frozen_file_hashes = file_hashes,
  population = "REG qb_dropback=1; pass/run; spike=kneel=two_point=0; raw passer for pass/sack, raw rusher for scramble-run; no CP/E-game/EPA/penalty/text restriction",
  cohort_rule = "exact 20 IDs; >=200 accepted E throws and >=10 E games EACH season; no requalification",
  analyses = "2023 odd/even D games; first ceiling(G/2) vs rest; annual 2023/2024 only",
  metric = "100*(N-S)/N, equal opportunities within actor-side, equal actors in Pearson correlation",
  uncertainty = "whole NFL game deletion across both teams/all actors/halves; Fisher z; each season centered on its OWN replicate mean; sum_s ((G_s-1)/G_s)*sum((z[-s,g]-mean_s(z[-s,g]))^2); tanh(z +/-1.96*sqrt(V))",
  limits = "conditional working-model sensitivities; fixed selected cohort and maps; no NFL coverage, calibrated skill, forecast or overall quality claim")
stopifnot(!file.exists(path("run_manifest.rds")))
saveRDS(record, path("run_manifest.rds"))

safe_cor <- function(x, y) {
  if (!all(is.finite(c(x, y)))) return(list(r = NA_real_, status = "nonfinite_rate"))
  if (length(x) < 2 || var(x) == 0 || var(y) == 0) return(list(r = NA_real_, status = "zero_actor_variance"))
  r <- cor(x, y)
  list(r = r, status = if (!is.finite(r)) "nonfinite_correlation" else
    if (abs(r) == 1) "perfect_correlation" else "defined")
}
association <- function(g, analysis, ids) {
  g <- mutate(g, side = if (analysis == "annual") if_else(season == 2023, "A", "B") else .data[[analysis]])
  sums <- g |> group_by(actor_id, side) |> summarise(N = sum(N), S = sum(S), .groups = "drop")
  grid <- expand.grid(actor_id = ids, side = c("A", "B"), stringsAsFactors = FALSE) |> arrange(actor_id, side)
  sums <- left_join(grid, sums, by = c("actor_id", "side"), relationship = "one-to-one")
  sums <- sums |> mutate(N = coalesce(N, 0L), S = coalesce(S, 0),
    avoidance = if_else(N > 0, 100 * (N - S) / N, NA_real_),
    sack_rate = if_else(N > 0, 100 * S / N, NA_real_))
  valid <- all(sums$N > 0) && all(is.finite(sums$avoidance)) && all(sums$avoidance >= 0 & sums$avoidance <= 100)
  if (!valid) return(list(summary = tibble(r = NA_real_, status = "nonpositive_N_or_invalid_rate",
    complement_r = NA_real_, min_N = min(sums$N), complement_error = NA_real_), rates = sums))
  stopifnot(all(abs(sums$avoidance + sums$sack_rate - 100) < 1e-12))
  a <- filter(sums, side == "A"); b <- filter(sums, side == "B")
  stopifnot(identical(a$actor_id, sort(ids)), identical(b$actor_id, sort(ids)))
  correlation <- safe_cor(a$avoidance, b$avoidance); comp <- safe_cor(a$sack_rate, b$sack_rate)
  err <- if (is.finite(correlation$r) && is.finite(comp$r)) abs(correlation$r - comp$r) else NA_real_
  stopifnot(identical(correlation$status, comp$status), is.na(err) || err < 1e-12)
  list(summary = tibble(r = correlation$r, status = correlation$status, complement_r = comp$r,
    min_N = min(sums$N), complement_error = err), rates = sums)
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
# Known-mean jackknife and nonlinear stratified example distinguish both centering rules.
x <- 1:4; del <- vapply(seq_along(x), function(j) mean(x[-j]), numeric(1))
toy <- c(4, 3.5, 3, 4.5, 2.5)^2; stratum <- c(2023, 2023, 2023, 2024, 2024)
stopifnot(abs(sqrt(sum(variance_terms(del, rep(2023, 4))$variance)) - sqrt(5 / 12)) < 1e-12,
  abs(sum(variance_terms(toy, stratum)$variance) - 2353 / 36) < 1e-12,
  safe_cor(rep(1, 4), 1:4)$status == "zero_actor_variance",
  safe_cor(1:4, 1:4)$status == "perfect_correlation",
  safe_cor(c(NA, 1), 1:2)$status == "nonfinite_rate",
  fisher_interval(NA_real_, c(.1, .2), c(1, 1))$summary$interval_status == "undefined_full_correlation",
  fisher_interval(1, c(.1, .2), c(1, 1))$summary$interval_status == "perfect_full_correlation",
  fisher_interval(.2, c(NA, .2), c(1, 1))$summary$interval_status == "undefined_deletion_correlation",
  fisher_interval(.2, c(1, .2), c(1, 1))$summary$interval_status == "perfect_deletion_correlation",
  fisher_interval(.2, c(.1, .2), c(1, 2))$summary$interval_status == "fewer_than_two_games_in_stratum",
  fisher_interval(.2, c(.1, .1), c(1, 1))$summary$interval_status == "zero_or_invalid_variance")
emit(tibble(check = c("known_mean_SE", "nonlinear_season_centered_variance", "unavailable_status_guards"),
  actual = c(sqrt(sum(variance_terms(del, rep(2023, 4))$variance)), sum(variance_terms(toy, stratum)$variance), 1),
  expected = c(sqrt(5 / 12), 2353 / 36, 1)), "math_verification")

range_summary <- function(x) {
  finite <- x[is.finite(x)]
  tibble(deletions = length(x), undefined = sum(!is.finite(x)),
    minimum = if (length(finite)) min(finite) else NA_real_,
    maximum = if (length(finite)) max(finite) else NA_real_)
}
results <- list()
for (analysis in c("interleaved", "chronological", "annual")) {
  g <- if (analysis == "annual") game_counts else filter(game_counts, season == 2023)
  full <- association(g, analysis, cohort)
  emit(full$rates, paste0(analysis, "_actor_rates"))
  games <- filter(game_lists, .data$analysis == .env$analysis)
  deleted <- bind_rows(lapply(seq_len(nrow(games)), function(j) {
    s <- games$season[j]; id <- games$game_id[j]
    removed <- filter(g, season == s, game_id == id)
    retained <- filter(g, !(season == s & game_id == id))
    stopifnot(nrow(removed) > 0, sum(removed$N) + sum(retained$N) == sum(g$N),
      !any(retained$season == s & retained$game_id == id))
    bind_cols(tibble(season = s, game_id = id, removed_N = sum(removed$N),
      removed_actors = n_distinct(removed$actor_id),
      removed_half_labels = if (analysis == "annual") 1L else n_distinct(removed[[analysis]])),
      association(retained, analysis, cohort)$summary)
  })) |> arrange(season, game_id)
  emit(deleted, paste0(analysis, "_game_deletions"))
  interval <- fisher_interval(full$summary$r, deleted$r, deleted$season)
  emit(interval$terms, paste0(analysis, "_variance_terms"))
  influence <- bind_rows(lapply(cohort, function(id) {
    remaining_ids <- cohort[cohort != id]
    remaining <- filter(g, actor_id != id)
    stopifnot(length(remaining_ids) == 19)
    bind_cols(tibble(deleted_actor = id), association(remaining, analysis, remaining_ids)$summary)
  })) |> mutate(sign_reversal = r * full$summary$r < 0) |> arrange(deleted_actor)
  emit(influence, paste0(analysis, "_actor_deletions"))
  emit(bind_rows(mutate(range_summary(deleted$r), unit = "NFL_game"),
    mutate(range_summary(influence$r), unit = "paired_actor")), paste0(analysis, "_influence_ranges"))
  results[[analysis]] <- bind_cols(tibble(analysis = analysis, actors = length(cohort),
    contributing_games = nrow(games)), full$summary, interval$summary,
    tibble(game_deletion_min = range_summary(deleted$r)$minimum,
      game_deletion_max = range_summary(deleted$r)$maximum,
      game_deletions_undefined = sum(!is.finite(deleted$r)),
      actor_deletion_min = range_summary(influence$r)$minimum,
      actor_deletion_max = range_summary(influence$r)$maximum,
      actor_deletions_undefined = sum(!is.finite(influence$r)),
      actor_sign_reversals = sum(influence$sign_reversal, na.rm = TRUE)))
}
results <- bind_rows(results)
emit(results, "results")
# Frozen artifacts must still have the pre-estimation hashes after all deletions.
stopifnot(all(vapply(seq_len(nrow(file_hashes)), function(i)
  digest::digest(file = path(file_hashes$file[i]), algo = "sha256") == file_hashes$sha256[i], logical(1))))
writeLines(capture.output(sessionInfo()), path("sessionInfo.txt"))
writeLines(c("Completed the three frozen descriptive sack-avoidance associations and fixed diagnostics.",
  "Conditional working-model sensitivity only; no forecast, isolated skill, overall score or ranking."), path("completion.txt"))
cat("Completed. Evidence prefix:", paste0(file.path(out, run), "_"), "\n")
print(select(results, analysis, r, lower, upper, interval_status, actor_sign_reversals), width = Inf)
