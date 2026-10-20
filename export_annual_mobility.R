# Annual recorded scramble contribution, AMC-1.0 (prospectively accepted).
# Usage: Rscript export_annual_mobility.R <pbp-directory> <schedule-directory>
#        <accepted-assets-directory> <empty-output-directory>
# Inputs: preserved play_by_play_<year>.parquet (19 years, excluding 2011),
# historical_schedule_reference.rds, schedule_reference.rds, and the six pinned
# NFL v2/annual/depth JSON/manifest assets. No private report is required.
# Output: new versioned JSON/manifest, native CSVs, keyed verification/provenance.
# Original code MIT. nflverse PBP aggregates CC BY 4.0; retain upstream notices.
# C_S=sum(raw scramble EPA)/N_O, O=D disjoint union recorded non-scramble R.
# Whole-play contribution combines usage and shared value, not isolated mobility.
suppressPackageStartupMessages({library(dplyr); library(readr)})
stopifnot(all(vapply(c("arrow", "digest", "jsonlite"), requireNamespace, logical(1), quietly = TRUE)))
a <- commandArgs(trailingOnly = TRUE)
if (length(a) != 4L || !all(dir.exists(a))) stop("Supply four existing directories; output must be empty.")
stopifnot(length(list.files(a[4], all.files = TRUE, no.. = TRUE)) == 0L)
out <- normalizePath(a[4], mustWork = TRUE)
sha <- function(f) digest::digest(file = f, algo = "sha256")
hash_text <- function(x) digest::digest(charToRaw(x), algo = "sha256", serialize = FALSE)
verify <- function(f, h) { if (!file.exists(f) || sha(f) != h) stop("Missing/changed pinned input: ", basename(f)); invisible(f) }
emit <- function(x, n) { f <- file.path(out, paste0(n, ".csv")); stopifnot(!file.exists(f)); write_csv(x, f, na = "NA") }
json <- function(x) paste0(as.character(jsonlite::toJSON(x, auto_unbox = TRUE, dataframe = "rows", digits = 17,
  na = "null", null = "null", pretty = TRUE)), "\n")
nonempty <- function(x) !is.na(x) & nzchar(trimws(x))
# PBP standardises relocation codes; schedules retain historical team names.
# This comparison-only mapping never changes actors, opportunity keys or sources.
team_code <- function(x) recode(x, STL = "LA", SD = "LAC", OAK = "LV", JAC = "JAX")
keycols <- c("season", "game_id", "play_id", "actor_id", "role", "population")
keyhash <- function(x) hash_text(paste0(paste(sort(do.call(paste, c(as.list(select(x, all_of(keycols))), sep = "|")), method = "radix"), collapse = "\n"), "\n"))
# Absolute tolerance frozen before estimation; never adjusted to fit reconciliation.
tolerance <- 1e-10
proposal_hash <- "621389f64511131cfa3d9841a64af9e3bf594c7c2eea7716d6916271088552a6"
years <- setdiff(2006:2025, 2011L)
asset_files <- c("nfl-qb-2023-2024-v2.json", "nfl-qb-2023-2024-v2.manifest.json",
  "nfl-qb-annual-2006-2025-v1.json", "nfl-qb-annual-2006-2025-v1.manifest.json",
  "nfl-qb-depth-2006-2025-v1.json", "nfl-qb-depth-2006-2025-v1.manifest.json")
asset_pins <- c("56c45de0fefde398d74ca31763e56fd86b60c43dd2c3f3b20be566acb57241e1", "a707dce3334864193fde79576c69940170b5cadb59ce3fa35df7b7b4f1878a62",
  "4a5afb5431eab1ba9119af49ae175fa5abd899d70e3f58ea9f5906e76122ba68", "e12f8c348585f80bc1cb258b0913b9222a2662b81365ab9072c218feb9d757f9",
  "5aa2bc98de1c26f9056d5ccbab03327cc90bd4a0a37bd3ac568d0c9cb65285ae", "f48d29dd22a0f27fe95c5f057d1e7becfde449ae20102d258f69855de2169e90")
for (i in seq_along(asset_files)) verify(file.path(a[3], asset_files[i]), asset_pins[i])
assets <- tibble(filename = asset_files, sha256 = asset_pins)
annual <- jsonlite::fromJSON(file.path(a[3], asset_files[3]))
legacy <- jsonlite::fromJSON(file.path(a[3], asset_files[1]))
cohort <- as_tibble(annual$rows) |> arrange(player_key, season)
stopifnot(nrow(cohort) == 560L, !anyDuplicated(cohort[c("player_key", "season")]), setequal(cohort$season, years),
  nrow(legacy$rows) == 40L, !anyDuplicated(legacy$rows[c("player_key", "season")]))
schedule_files <- c("historical_schedule_reference.rds", "schedule_reference.rds")
schedule_pins <- c("79316f760cbf969c4fd50b9fc000d9ce0bfefe448ac35062d670baf75a9054ca", "659e4ae782353bb80d196c6789e11eae545a93be9fdb668dd3e3ae4fdac860eb")
for (i in seq_along(schedule_files)) verify(file.path(a[2], schedule_files[i]), schedule_pins[i])
schedules <- lapply(file.path(a[2], schedule_files), readRDS)
# Count-only audit pins canonical selected O keys, not EPA calculations.
# Each hash sorts season|game|play|GSIS|role|population lines, with final newline.
key_pins <- c(
  "bc1ff980fd1f8b6cab1407a5c6f3f9d7f415a0858252ac3fd9a0ac3c8d32bcb3",
  "25eaaaa222831b9515c10f721e85b96768a7aa33408ff93071d634b01d2d24b9",
  "0d8983af79572f72c0de1ea873bba3bc6dd03247d9694642caa1cbe463ad8f69",
  "355aa359b86cf3ddc6100b54ae1692b47ecf11f935df8f44e32b3d44b90e389c",
  "b4d2c2f16be83fd324b61d2f1076b74bc768eee2d428d2f72f2ae19db75314e4",
  "5a7e322e6fdd87c58ec2be023b09f0f40e281a74737dd396b94103b24ee95200",
  "38daa3880585ce46e14c5c49b774e29a4ed88f2a661981ec6e15d7a7c266f8e3",
  "fea5a28edd534b31bd6cb1b853a099807f33618081c6640389e4363d9ee1eb4b",
  "73915e14bc73ad0d5817a1c4735bc1c4c399f0e13af1efd837727ca9bd50e365",
  "59682292ebff3a1e6e9597479ea584b3d0fce321ea28841879e8f6066e8f1798",
  "de888805750e4f1d53064a6570085712e1b2e4fb53b082800d989a7f9f5e0931",
  "7627ad510d7dc2adaa13efc9ec15fe7a1b7a5fda513c9054cee48b7eac33f8ae",
  "5c28ef2cf8dadbb21f112c6467322571ba6aa82e4199239f7864e546c60d8fd9",
  "5a0dc19cb3f5208700ffa7151681fcf109d9b33cf1d7150d5c077d09ab92dcca",
  "8a915fa2ab0eda2f488db89f02fefd00524402c9182992fb0bfe2a056dee13d0",
  "525daeb9bea35a60b375129f57d187f5d92392a0761de299bd5299d32567698a",
  "b8915009659ef3d27eebc28d10c97409c737cc3e51618f3b7da683fb50de7949",
  "44ee23bcd97d02db273ff4e304cab5d8d0d2f677bb4671f7966871d1e83ed58d",
  "6685e7023d052acd275aa5050a5ab2a69ccae50c4393ee7b71fcccb1e44a15c8"
)
names(key_pins) <- years
sources <- as_tibble(annual$sources$pbp) |> filter(season %in% years) |>
  mutate(filename = paste0("play_by_play_", season, ".parquet"))
stopifnot(nrow(sources) == 19L, !anyDuplicated(sources$season))
for (i in seq_len(nrow(sources))) {
  f <- file.path(a[1], sources$filename[i]); verify(f, sources$sha256[i]); stopifnot(file.info(f)$size == sources$bytes[i])
}
flags <- c("qb_dropback", "pass_attempt", "rush_attempt", "sack", "qb_scramble", "qb_spike", "qb_kneel", "two_point_attempt")
cols <- c("season", "season_type", "game_id", "play_id", "game_date", "play_type", "posteam", "passer_player_id", "rusher_player_id", "epa", "desc", flags)
all_o <- count_checks <- season_checks <- flag_checks <- list()
for (year in years) {
  cat("Validate recorded opportunities", year, "\n"); flush.console()
  raw <- arrow::read_parquet(file.path(a[1], paste0("play_by_play_", year, ".parquet")), col_select = all_of(cols))
  stopifnot(all(raw$season == year), all(nonempty(raw$game_id)), all(is.finite(raw$play_id)),
    !anyDuplicated(raw[c("game_id", "play_id")]), all(vapply(raw[c(flags, "play_id", "epa")], is.numeric, logical(1))))
  x <- filter(raw, season_type == "REG")
  ids <- filter(cohort, season == year)$player_key
  x <- x |> mutate(actor_id = if_else(play_type == "pass", passer_player_id, rusher_player_id),
    D_rule = qb_dropback == 1 & play_type %in% c("pass", "run") & qb_spike == 0 & qb_kneel == 0 & two_point_attempt == 0,
    R_rule = play_type == "run" & rush_attempt == 1 & qb_scramble == 0 & qb_kneel == 0 & two_point_attempt == 0)
  stopifnot(nrow(filter(x, actor_id %in% ids, is.na(D_rule))) == 0L,
    nrow(filter(x, rusher_player_id %in% ids, is.na(R_rule))) == 0L,
    all(nonempty(filter(x, D_rule)$actor_id)), all(nonempty(filter(x, R_rule)$rusher_player_id)))
  d <- filter(x, D_rule, actor_id %in% ids) |> mutate(population = "D",
    role = case_when(play_type == "pass" & sack == 0 ~ "other_pass", play_type == "pass" & sack == 1 ~ "sack",
      play_type == "run" & sack == 0 & qb_scramble == 1 ~ "scramble", TRUE ~ NA_character_))
  r <- filter(x, R_rule, rusher_player_id %in% ids) |> mutate(actor_id = rusher_player_id, population = "R", role = "recorded_non_scramble_run")
  stopifnot(!anyNA(d$role), all(ifelse(d$play_type == "pass", d$pass_attempt == 1 & is.na(d$rusher_player_id),
    d$rush_attempt == 1 & is.na(d$passer_player_id))),
    nrow(inner_join(select(d, game_id, play_id), select(r, game_id, play_id), by = c("game_id", "play_id"), relationship = "one-to-one")) == 0L)
  o <- bind_rows(d, r) |> arrange(actor_id, game_id, play_id)
  stopifnot(all(grepl("^00-[0-9]{7}$", o$actor_id)), !anyDuplicated(o[c("game_id", "play_id", "actor_id")]),
    all(vapply(o[flags], function(z) all(!is.na(z) & z %in% c(0, 1)), logical(1))), keyhash(o) == key_pins[as.character(year)])
  sch <- schedules[[if (year <= 2022) 1L else 2L]] |> filter(season == year, game_type == "REG")
  stopifnot(!anyDuplicated(sch$game_id))
  j <- match(o$game_id, sch$game_id)
  stopifnot(!anyNA(j), all(as.Date(o$game_date) == as.Date(sch$gameday[j])),
    all(nonempty(o$posteam)), all(team_code(o$posteam) == team_code(sch$home_team[j]) | team_code(o$posteam) == team_code(sch$away_team[j])), all(is.finite(filter(o, population == "D")$epa)))
  counts <- o |> group_by(actor_id, season) |> summarise(dropbacks = sum(population == "D"),
    dropback_games = n_distinct(game_id[population == "D"]), sacks = sum(role == "sack"), scramble_runs = sum(role == "scramble"),
    nonscramble_runs = sum(population == "R"), scramble_games = n_distinct(game_id[role == "scramble"]),
    nonscramble_games = n_distinct(game_id[population == "R"]), combined_opportunities = n(), combined_games = n_distinct(game_id), .groups = "drop")
  expected <- filter(cohort, season == year) |> select(player_key, season, dropbacks, dropback_games, sacks, scramble_runs)
  check <- left_join(expected, counts, by = c("player_key" = "actor_id", "season"), suffix = c("_expected", ""), relationship = "one-to-one")
  stopifnot(nrow(counts) == length(ids), nrow(check) == length(ids))
  for (f in c("dropbacks", "dropback_games", "sacks", "scramble_runs")) stopifnot(all(check[[f]] == check[[paste0(f, "_expected")]]))
  # A separate raw-row selection reconstructs each denominator, without O keys.
  # Per-actor counts and game unions must agree before any EPA aggregation.
  for (id in ids) {
    xd <- filter(x, actor_id == id, qb_dropback == 1, play_type %in% c("pass", "run"), qb_spike == 0, qb_kneel == 0, two_point_attempt == 0)
    xr <- filter(x, rusher_player_id == id, play_type == "run", rush_attempt == 1, qb_scramble == 0, qb_kneel == 0, two_point_attempt == 0)
    cc <- filter(counts, actor_id == id)
    stopifnot(nrow(xd) + nrow(xr) == cc$combined_opportunities, length(union(xd$game_id, xr$game_id)) == cc$combined_games,
      nrow(xr) == cc$nonscramble_runs)
  }
  bad_epa <- filter(o, !is.finite(epa))
  if (nrow(bad_epa)) stopifnot(year == 2007L, nrow(bad_epa) == 1L, bad_epa$actor_id == "00-0022164",
    bad_epa$game_id == "2007_02_NYJ_BAL", bad_epa$play_id == 4495, bad_epa$population == "R", bad_epa$qb_kneel == 0,
    grepl("Took knee", bad_epa$desc, fixed = TRUE))
  emit(select(bad_epa, all_of(keycols), qb_kneel, epa, desc), paste0(year, "_nonfinite_source_diagnostics"))
  flag_checks[[as.character(year)]] <- tibble(season = year, pass_sack_scramble_flag_overlap = sum(d$play_type == "pass" & d$qb_scramble == 1),
    R_only_games = nrow(anti_join(distinct(r, actor_id, game_id), distinct(d, actor_id, game_id), by = c("actor_id", "game_id"))))
  season_checks[[as.character(year)]] <- tibble(season = year, target_rows = nrow(counts), D = nrow(d), S = sum(d$role == "scramble"),
    R = nrow(r), O = nrow(o), O_key_sha256 = keyhash(o), raw_rows = nrow(raw), REG_rows = nrow(x), source_nonfinite_O = nrow(bad_epa))
  all_o[[as.character(year)]] <- select(o, all_of(keycols), epa)
  count_checks[[as.character(year)]] <- check
}
O <- bind_rows(all_o); count_checks <- bind_rows(count_checks)
stopifnot(nrow(O) == 304117L, sum(O$population == "D") == 295150L, sum(O$role == "scramble") == 11252L,
  sum(O$population == "R") == 8967L, sum(bind_rows(flag_checks)$R_only_games) == 8L,
  sum(bind_rows(flag_checks)$pass_sack_scramble_flag_overlap) == 11L)
old_o <- semi_join(O, as_tibble(legacy$rows) |> select(player_key, season), by = c("actor_id" = "player_key", "season"))
stopifnot(keyhash(old_o) == "36b26831ac277e74916022b7c07b935991a8c273f926eb2c8a27f97c5d4c99d4")
emit(select(O, -epa), "frozen_O_keys"); emit(count_checks, "count_reconciliation")
emit(bind_rows(season_checks), "season_gates"); emit(bind_rows(flag_checks), "flag_and_game_diagnostics")
# All count/key/source gates pass before this first EPA sum.
games <- O |> group_by(actor_id, season, game_id) |> summarise(N = n(), n_S = sum(role == "scramble"),
  U_S = sum(epa[role == "scramble"]), .groups = "drop") |> arrange(actor_id, season, game_id)
emit(games, "actor_game_sums")
ratio <- function(N_g, U_g) {
  G <- length(N_g); N <- sum(N_g); U <- sum(U_g); estimate <- if (N > 0 && is.finite(U)) U / N else NA_real_
  remaining <- N - N_g; deleted <- rep(NA_real_, G); ok <- remaining > 0
  deleted[ok] <- (U - U_g[ok]) / remaining[ok]
  status <- if (N <= 0) "nonpositive_O" else if (G < 2) "fewer_than_two_O_games" else if (any(!ok)) "nonpositive_deleted_O" else
    if (!all(is.finite(deleted)) || !is.finite(estimate)) "nonfinite_ratio" else "defined"
  center <- variance <- lower <- upper <- NA_real_
  if (status == "defined") {
    center <- mean(deleted); variance <- (G - 1) / G * sum((deleted - center)^2)
    if (!is.finite(variance) || variance < 0) status <- "nonfinite_or_invalid_variance" else {
      lower <- estimate - 1.96 * sqrt(variance); upper <- estimate + 1.96 * sqrt(variance)
      status <- if (variance == 0) "collapsed_no_observed_deletion_variation" else "approximate_conditional_game_sampling_sensitivity"
    }
  }
  list(estimate = estimate, lower = lower, upper = upper, status = status, deleted = deleted, remaining = remaining, center = center, variance = variance)
}
# Bounded algebra checks include natural zero and nonpositive deletion cases.
stopifnot(ratio(c(1, 2), c(1, 8))$estimate == 3, ratio(c(1, 2), c(1, 8))$variance == 2.25,
  ratio(c(2, 3), c(0, 0))$status == "collapsed_no_observed_deletion_variation", ratio(c(0, 1), c(0, 1))$status == "nonpositive_deleted_O")
rows <- deletions <- direct_checks <- list()
for (i in seq_len(nrow(cohort))) {
  id <- cohort$player_key[i]; year <- cohort$season[i]
  g <- filter(games, actor_id == id, season == year); plays <- filter(O, actor_id == id, season == year)
  cc <- filter(count_checks, player_key == id, season == year)
  blocked <- year == 2007L && id == "00-0022164"
  if (blocked) {
    q <- list(estimate = NA_real_, lower = NA_real_, upper = NA_real_, status = "blocked_pending_role_review")
    reason <- "Recorded R in 2007_02_NYJ_BAL/play4495 has qb_kneel=0, Took knee description and missing EPA; O membership unresolved. No repair or exclusion."
  } else {
    stopifnot(all(is.finite(plays$epa)), all(g$N > 0), sum(g$N) > 0)
    q <- ratio(g$N, g$U_S)
    # Independently drop raw O-game rows and resummarise, without subtraction.
    direct <- vapply(g$game_id, function(omitted) {
      retained <- filter(plays, game_id != omitted)
      if (nrow(retained)) sum(retained$epa[retained$role == "scramble"]) / nrow(retained) else NA_real_
    }, numeric(1))
    full_direct <- sum(plays$epa[plays$role == "scramble"]) / nrow(plays)
    stopifnot(identical(unname(is.na(direct)), is.na(q$deleted)), abs(full_direct - q$estimate) <= tolerance,
      all(abs(direct - q$deleted) <= tolerance), all(q$remaining > 0))
    v_direct <- (nrow(g) - 1) / nrow(g) * sum((direct - mean(direct))^2)
    stopifnot(abs(v_direct - q$variance) <= tolerance)
    direct_checks[[length(direct_checks) + 1L]] <- tibble(player_key = id, season = year,
      point_abs_delta = abs(full_direct - q$estimate), max_deletion_abs_delta = max(abs(direct - q$deleted)), variance_abs_delta = abs(v_direct - q$variance))
    deletions[[length(deletions) + 1L]] <- mutate(g, deleted_N_O = q$remaining, deleted_contribution = q$deleted,
      direct_deleted_contribution = direct, deletion_center = q$center)
    reason <- NA_character_
  }
  rows[[i]] <- tibble(player_key = id, season = year, observed_name = cohort$observed_name[i], display_name = cohort$display_name[i], name_status = cohort$name_status[i],
    dropbacks = cc$dropbacks, dropback_games = cc$dropback_games, sacks = cc$sacks, scramble_runs = cc$scramble_runs,
    nonscramble_runs = cc$nonscramble_runs, combined_opportunities = cc$combined_opportunities, combined_games = cc$combined_games,
    scramble_games = cc$scramble_games, nonscramble_games = cc$nonscramble_games,
    scramble_contribution = q$estimate, scramble_contribution_lower = q$lower, scramble_contribution_upper = q$upper,
    point_status = if (blocked) "blocked_pending_role_review" else "observed_contribution", scramble_interval_status = q$status, unavailable_reason = reason)
}
rows <- bind_rows(rows); direct_checks <- bind_rows(direct_checks)
available <- c("approximate_conditional_game_sampling_sensitivity", "collapsed_no_observed_deletion_variation")
ok <- rows$point_status == "observed_contribution"
stopifnot(nrow(rows) == 560L, sum(ok) == 559L, sum(!ok) == 1L, all(is.finite(rows$scramble_contribution[ok])),
  all(is.na(rows$scramble_contribution[!ok])), all(rows$scramble_interval_status[ok] %in% available),
  all(rows$scramble_contribution_lower[ok] <= rows$scramble_contribution[ok]), all(rows$scramble_contribution_upper[ok] >= rows$scramble_contribution[ok]),
  all(is.na(rows$scramble_contribution_lower[!ok])), all(is.na(rows$scramble_contribution_upper[!ok])),
  sum(rows$scramble_runs == 0) == 4L, all(rows$scramble_contribution[rows$scramble_runs == 0] == 0),
  all(rows$scramble_interval_status[rows$scramble_runs == 0] == "collapsed_no_observed_deletion_variation"),
  sum(ok & rows$season %in% 2022:2025) == 119L)
# Every original40 key/count/status/null exactly; every native point/range within
# the predeclared absolute tolerance. Keep all per-row deltas, not only maxima.
old <- as_tibble(legacy$rows) |> arrange(player_key, season)
now <- semi_join(rows, old, by = c("player_key", "season")) |> arrange(player_key, season)
recon <- list()
for (f in c("player_key", "season", "dropbacks", "dropback_games", "sacks", "scramble_runs", "nonscramble_runs",
  "combined_opportunities", "combined_games", "scramble_games", "nonscramble_games", "scramble_interval_status")) {
  stopifnot(identical(now[[f]], old[[f]]) || isTRUE(all.equal(now[[f]], old[[f]], tolerance = 0, check.attributes = FALSE)))
  recon[[f]] <- tibble(player_key = now$player_key, season = now$season, field = f, actual = as.character(now[[f]]), reference = as.character(old[[f]]), absolute_delta = NA_real_, exact = TRUE)
}
for (f in c("scramble_contribution", "scramble_contribution_lower", "scramble_contribution_upper")) {
  stopifnot(identical(is.na(now[[f]]), is.na(old[[f]])))
  delta <- abs(now[[f]] - old[[f]]); stopifnot(all(delta[is.finite(delta)] <= tolerance))
  recon[[f]] <- tibble(player_key = now$player_key, season = now$season, field = f, actual = as.character(now[[f]]), reference = as.character(old[[f]]), absolute_delta = delta, exact = now[[f]] == old[[f]])
}
recon <- bind_rows(recon)
emit(recon, "original40_reconciliation_per_row"); emit(filter(recon, is.finite(absolute_delta)) |> group_by(field) |>
  summarise(maximum_absolute_difference = max(absolute_delta), tolerance = tolerance, .groups = "drop"), "original40_numeric_maxima")
emit(rows, "annual_mobility_rows"); emit(bind_rows(deletions), "game_deletions"); emit(direct_checks, "direct_reconstruction")
references <- rows |> group_by(season) |> summarise(eligible_player_seasons = n(), finite_accepted_values = sum(point_status == "observed_contribution" & is.finite(scramble_contribution)), .groups = "drop")
stopifnot(filter(references, season == 2007)$finite_accepted_values == 26L)
catalog <- tibble(season = 2006:2025, status = if_else(season == 2011, "source_blocked", "exported"),
  reason = if_else(season == 2011, "unresolved_duplicate_events_and_air_yards", NA_character_),
  row_count = vapply(season, function(y) sum(rows$season == y), integer(1)),
  finite_point_count = vapply(season, function(y) sum(rows$season == y & ok), integer(1)))
units <- list(scramble_contribution = "expected_points_per_included_recorded_quarterback_play",
  scramble_contribution_lower = "expected_points_per_included_recorded_quarterback_play", scramble_contribution_upper = "expected_points_per_included_recorded_quarterback_play",
  dropbacks = "plays", dropback_games = "actor_games", sacks = "plays", scramble_runs = "plays", nonscramble_runs = "plays",
  combined_opportunities = "plays", combined_games = "actor_games", scramble_games = "actor_games", nonscramble_games = "actor_games")
script <- sub("^--file=", "", grep("^--file=", commandArgs(), value = TRUE)); script_hash <- sha(script)
generated <- format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
versions <- list(method = "AMC-1.0", proposal_sha256 = proposal_hash, recorded_dropbacks = "AD-1.1",
  original_rushing_definition = "recorded-run-contribution-1.0", original_rushing_script_sha256 = "4f29f1e61e781f3f382ed6ef06d420f12ca45cf9dd93db7d8d89e087b3c91e07", original_rushing_design_sha256 = "347a063258182a6558a0b372fc465b2637f09038b02175e89b61c3e23b0cd932",
  export_script_sha256 = script_hash, native_numeric_absolute_tolerance = tolerance)
provenance <- list(pbp = sources, schedules = tibble(filename = schedule_files, sha256 = schedule_pins,
  use = c("2006-2022 regular-season dates/teams", "2023-2025 regular-season dates/teams"),
  notices_url = "https://github.com/nflverse/nfldata"), unchanged_accepted_assets = assets,
  annual_frozen_membership_sha256 = annual$aggregate_input_hashes$annual_membership_counts,
  accepted_D_manifest_sha256 = annual$aggregate_input_hashes$D_manifest,
  count_only_O_key_hashes = tibble(season = years, sha256 = unname(key_pins)),
  schedule_side_comparison_aliases = "STL=LA; SD=LAC; OAK=LV; JAC=JAX. Comparison only; raw values unchanged.",
  canonical_key_hash_encoding = "Bytewise-sorted UTF-8 season|game_id|integer play_id|actor_id|role|population lines, newline terminated.")
attribution <- annual$attribution
attribution$transformation_notice <- "New annual scramble EPA/O aggregates and marginal whole-O-game deletion sensitivities from preserved raw nflverse PBP. Original40 assets/studies unchanged; no isolated-mobility, forecasting or era-neutral claim."
payload <- list(schema_version = 1L, data_version = "2006-2025-annual-mobility-v1", dataset_kind = "independent_annual_scramble_contribution",
  generated_utc = generated, seasons = years, season_catalog = catalog,
  eligibility = annual$eligibility, units = units,
  denominators = list(scramble_contribution = "Sum supplied signed raw EPA on recorded scramble S divided by N_O. O=D disjoint union R. S subset D. R is recorded non-scramble actor-running, including aborted/lateral plays; no CP, E-game, positive-EPA or penalty filter.",
    D = "AD-1.1: qb_dropback1, recorded pass/run, spike0,kneel0,two_point0; raw passer for pass/sack, raw rusher for scramble run. Binary pass/sack scramble flags are diagnostics, never reclassification.",
    R = "Recorded run, rush_attempt1, scramble0,kneel0,two_point0; raw rusher; no absent-passer or designed-run requirement."),
  uncertainty = list(interval = "Approximate marginal 95% conditional all-O-game deletion sensitivity: theta +/-1.96*sqrt((G-1)/G*sum((deletion-mean(deletion))^2)). Include all O games, including zero-S and R-only games. Positive full and deletion O denominators; fixed membership; no failed replicate drops.",
    collapsed = "No observed deletion variation, not certainty.", limitations = "Conditional working game-sampling sensitivity, not calibrated talent or prediction intervals. Independent game shocks, stable opportunities and normal approximation may fail. Excludes serial dependence, source/model error, selection and supporting-cast uncertainty; marginal ranges do not test player/year differences. EPA is shared whole-play value."),
  reference_population = list(rule = "Within-year finite accepted C_S values from these frozen eligible player-seasons only. Consumer calculates descriptive same-year midrank percentiles; no ranks or percentiles estimated here. Display finite N; fewer than two peers unavailable. Never substitute legacy20, selected opponent, another year or zero.",
    counts = references),
  missingness = list(zero = "Zero recorded S with positive observed O yields genuine zero contribution; it does not imply zero mobility talent.",
    blocked = "00-0022164 season2007 withheld pending recorded-role review; all counts retained and native point/range null. No raw source repair or exclusion.",
    source_blocked_2011 = "No invented rows; see season catalog.", missing_player_season = "No eligible record; do not substitute another player/year or zero."),
  analysis_versions = versions, sources = provenance, attribution = attribution, rows = rows)
base <- "nfl-qb-mobility-2006-2025-v1"
text <- json(payload); stopifnot(jsonlite::validate(text))
roundtrip <- jsonlite::fromJSON(text)
stopifnot(isTRUE(all.equal(as.data.frame(rows), roundtrip$rows, tolerance = 0, check.attributes = FALSE)),
  all(vapply(rows[vapply(rows, is.numeric, logical(1))], function(x) !any(is.nan(x) | is.infinite(x)), logical(1))))
for (bad in c("/Users/", "/private/", "file://", ".local.md")) stopifnot(!grepl(bad, text, fixed = TRUE))
manifest <- list(schema_version = 1L, data_version = payload$data_version, dataset_kind = payload$dataset_kind, generated_utc = generated,
  payload = list(filename = paste0(base, ".json"), sha256 = hash_text(text)), row_count = nrow(rows), finite_point_count = sum(ok),
  row_keys_sha256 = hash_text(format_csv(select(rows, player_key, season))), season_catalog = catalog, units = units,
  reference_population = payload$reference_population, analysis_versions = versions, input_provenance = provenance,
  export_script_sha256 = script_hash)
writeBin(charToRaw(text), file.path(out, paste0(base, ".json")))
writeBin(charToRaw(json(manifest)), file.path(out, paste0(base, ".manifest.json")))
r <- jsonlite::fromJSON(file.path(out, paste0(base, ".json")))
m <- jsonlite::fromJSON(file.path(out, paste0(base, ".manifest.json")))
stopifnot(sha(file.path(out, paste0(base, ".json"))) == m$payload$sha256,
  m$payload$filename == paste0(base, ".json"), r$schema_version == m$schema_version, r$data_version == m$data_version,
  r$generated_utc == m$generated_utc, nrow(r$rows) == m$row_count, sum(is.finite(r$rows$scramble_contribution)) == m$finite_point_count,
  identical(r$season_catalog, m$season_catalog), identical(r$reference_population, m$reference_population),
  identical(names(r$rows), names(rows)), m$row_keys_sha256 == hash_text(format_csv(select(rows, player_key, season))))
for (i in seq_along(asset_files)) verify(file.path(a[3], asset_files[i]), asset_pins[i])
emit(sources, "source_provenance"); emit(assets, "unchanged_accepted_assets"); emit(references, "annual_reference_counts")
checks <- tibble(check = c("all_source_and_six_asset_pins", "all19_count_only_frozen_O_key_sets", "AD11_counts_and_disjoint_S_subset_D",
  "raw_row_denominator_and_all_O_game_reconstruction", "dates_teams_actors_binary_flags", "eight_R_only_games_retained",
  "eleven_pass_sack_scramble_flags_not_reclassified", "one_keyed_Boller_block_only", "all_direct_game_deletions_and_variances",
  "four_natural_zero_collapsed_ranges", "original40_keys_counts_games_status_nulls_and_numeric_reconciliation",
  "560_membership_559_finite_119_recent_2011_blocked", "finite_sameyear_reference_counts", "public_roundtrip_no_local_paths", "immutable_six_assets_preserved"), passed = TRUE)
emit(checks, "verification")
writeLines(capture.output(sessionInfo()), file.path(out, "sessionInfo.txt"))
writeLines(json(list(arguments = a, generated_utc = generated, export_script_sha256 = script_hash,
  payload_sha256 = manifest$payload$sha256, manifest_sha256 = sha(file.path(out, paste0(base, ".manifest.json"))),
  maximum_original40_absolute_difference = max(recon$absolute_delta, na.rm = TRUE),
  maximum_direct_deletion_absolute_difference = max(direct_checks$max_deletion_abs_delta), checks = checks)), file.path(out, "run_record.json"))
cat("Rows:", nrow(rows), "Finite:", sum(ok), "\nPayload SHA256:", manifest$payload$sha256, "\nCode SHA256:", script_hash, "\n")
