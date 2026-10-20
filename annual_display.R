# Independent annual outcomes and depth completion residuals, AD-1.0/1.1 + DPX-1.0.
# Usage: Rscript annual_display.R <count-prefix> <players-csv> <v2-json> <v2-manifest>
#        <trait-count-dir> <fresh-output-dir>
# No downloads, source repairs, study estimation or site publication.
# Original code MIT; nflverse PBP aggregates retain CC BY 4.0 attribution.
suppressPackageStartupMessages({library(dplyr); library(readr)})
stopifnot(all(vapply(c("arrow", "digest", "jsonlite"), requireNamespace, logical(1), quietly = TRUE)))
a <- commandArgs(trailingOnly = TRUE)
if (length(a) != 6L || !all(dir.exists(a[5:6]))) stop("Supply six paths; output directory must exist and be empty.")
out <- normalizePath(a[6], mustWork = TRUE)
stopifnot(length(list.files(out, all.files = TRUE, no.. = TRUE)) == 0)
run <- paste0(format(Sys.time(), "%Y%m%dT%H%M%S", tz = "UTC"), "_annual_display_", Sys.getpid(), "_")
p <- function(x) paste0(a[1], x)
evidence <- function(x) file.path(out, paste0(run, x))
sha <- function(f) digest::digest(file = f, algo = "sha256")
hash_text <- function(x) digest::digest(charToRaw(x), algo = "sha256", serialize = FALSE)
verify <- function(f, expected) { if (!file.exists(f) || sha(f) != expected) stop("Missing/changed pinned input: ", basename(f)); invisible(f) }
read <- function(f) read_csv(f, show_col_types = FALSE)
emit <- function(x, name) { f <- evidence(paste0(name, ".csv")); stopifnot(!file.exists(f)); write_csv(x, f, na = "NA") }
key_text <- function(x) format_csv(x, na = "NA")
json <- function(x) paste0(as.character(jsonlite::toJSON(x, auto_unbox = TRUE, dataframe = "rows", digits = 17,
  na = "null", null = "null", pretty = TRUE)), "\n")
nonempty <- function(x) !is.na(x) & nzchar(trimws(x))
count_pin <- "6086987ab160812cce3a07cb5eff00447a0b06d39c166d0df63e0c0635f29552"
annual_design <- "7d9c08e156c85fb7c69005b79c192c9b0e45d312ae3b8d5f94c4cdfcb8887ce1"
depth_design <- "d097199d263267202330d3f17d4bb3b1b86aa5311c822f992326f6fb1d41206a"
verify(a[2], "87495575e01a608a52c453db95faad23bcf3c8e216d90c3cbd9b6a15b25afc6e")
verify(a[3], "56c45de0fefde398d74ca31763e56fd86b60c43dd2c3f3b20be566acb57241e1")
verify(a[4], "a707dce3334864193fde79576c69940170b5cadb59ce3fa35df7b7b4f1878a62")
verify(p("frozen_annual_cohort.csv"), count_pin)
verify(p("frozen_all_E_keys.csv"), "6ae887b1328a8aea8ccc194eb5986bc7cdad460e152295adbe44cef20885744f")
verify(p("frozen_D_key_manifest.csv"), "fe6c9ce3c74c9c3fabfe0cfbb6343368cc923ba3a58498e4d7791e2ef85c79c3")
verify(p("verified_source_provenance.csv"), "e101eac3aafa3ab4ee4b40bc5d4c3c4aa1ee5b4ccf8db0509abd06fad8e2d927")
verify(p("output_manifest.csv"), "4af063b1cfd8466cd76e17e693ffd55e436c7db03e615b5f371d57bd834989c6")
# The accepted output manifest pins gate, availability, count and key evidence.
outputs <- read(p("output_manifest.csv"))
for (i in seq_len(nrow(outputs))) verify(file.path(dirname(a[1]), outputs$file[i]), outputs$sha256[i])
stopifnot(identical(read(p("gate_result.csv"))$status, "count_gate_passed"))
years <- setdiff(2006:2025, 2011)
gates <- read(p("season_gate_status.csv"))
stopifnot(setequal(gates$season, 2006:2025), all(filter(gates, season %in% years)$status == "count_gate_passed"),
  identical(filter(gates, season == 2011)$status, "source_blocked"))
cohort <- read(p("frozen_annual_cohort.csv"))
E_keys <- read(p("frozen_all_E_keys.csv"))
D_manifest <- read(p("frozen_D_key_manifest.csv"))
sources <- read(p("verified_source_provenance.csv"))
counts <- read(p("verified_selected_counts.csv"))
old <- jsonlite::fromJSON(a[3]); old_manifest <- jsonlite::fromJSON(a[4])
stopifnot(old_manifest$payload$sha256 == sha(a[3]), nrow(cohort) == 560L,
  !anyDuplicated(cohort[c("player_key", "season")]), setequal(cohort$season, years),
  hash_text(key_text(arrange(cohort, season, player_key))) == count_pin,
  !anyDuplicated(E_keys[c("season", "game_id", "play_id")]), setequal(D_manifest$season, years))
# Verify every retained source, including provenance for blocked 2011, before any mean.
for (i in seq_len(nrow(sources))) {
  verify(sources$file[i], sources$sha256[i]); stopifnot(file.info(sources$file[i])$size == sources$bytes[i])
}
for (i in seq_len(nrow(D_manifest))) {
  verify(D_manifest$D_file[i], D_manifest$D_sha256[i])
  verify(D_manifest$actor_game_file[i], D_manifest$actor_game_sha256[i])
}
tf_files <- c("depth_actor_season_bin_counts_v2.csv", "depth_old_common20_counts_v2.csv", "depth_season_counts.csv")
tf_hashes <- c("0abeb174a03c8f0567f04e4cb447d2ec539e9a18983c34e24819c6b8f40ee376",
  "75c250f0a6963c4083ed8acb2ffc6b53c8e5422ca564795c78e2fc2c58dcb22b",
  "07b54010c8094219d04dc0644adfa20245ce3f2854fbdbe50f3ae9fe17b61036")
for (i in seq_along(tf_files)) verify(file.path(a[5], tf_files[i]), tf_hashes[i])
tf <- read(file.path(a[5], tf_files[1])); tf_old <- read(file.path(a[5], tf_files[2]))
tf_seasons <- read(file.path(a[5], tf_files[3]))
common <- intersect(filter(cohort, season == 2023)$player_key, filter(cohort, season == 2024)$player_key)
stopifnot(length(common) == 20L, setequal(common, old$rows$player_key))
players <- read_csv(a[2], col_types = cols(.default = col_character()), show_col_types = FALSE) |>
  filter(nonempty(gsis_id), nonempty(display_name)) |> distinct(gsis_id, display_name) |>
  group_by(gsis_id) |> filter(n() == 1L) |> ungroup() |> select(gsis_id, display_name)
bins <- tibble(bin = c("negative", "short", "medium", "deep"), air_yards_lower = c(-15, 0, 10, 20), air_yards_upper = c(0, 10, 20, 70))
available <- c("approximate_conditional_game_sampling_sensitivity", "collapsed_no_observed_deletion_variation")
unavailable <- c("no_opportunities", "nonfinite_mean_or_deletion", "fewer_than_two_games", "nonpositive_deletion_denominator",
  "nonfinite_or_invalid_variance", "nonfinite_interval_endpoints", "nonfinite_epa_on_frozen_D")
# One calculation for either outcome; supplied frame includes zero-bin E games.
sensitivity <- function(n_g, S_g, values, games, frame) {
  N <- sum(n_g); G <- length(n_g); S <- sum(S_g)
  theta <- if (N > 0L && all(is.finite(values)) && is.finite(S)) S / N else NA_real_
  lower <- upper <- V <- NA_real_; deletion <- rep(NA_real_, G)
  status <- if (N == 0L) "no_opportunities" else if (!is.finite(theta)) "nonfinite_mean_or_deletion" else
    if (G < 2L) "fewer_than_two_games" else if (any(N - n_g <= 0)) "nonpositive_deletion_denominator" else "defined"
  if (status == "defined") {
    deletion <- (S - S_g) / (N - n_g)
    if (any(!is.finite(deletion))) status <- "nonfinite_mean_or_deletion" else {
      V <- (G - 1) / G * sum((deletion - mean(deletion))^2)
      if (!is.finite(V) || V < 0) status <- "nonfinite_or_invalid_variance" else {
        lower <- theta - 1.96 * sqrt(V); upper <- theta + 1.96 * sqrt(V)
        if (any(!is.finite(c(lower, upper)))) { lower <- upper <- NA_real_; status <- "nonfinite_interval_endpoints" } else
          status <- if (V == 0) "collapsed_no_observed_deletion_variation" else available[1]
      }
    }
  }
  # Independent direct-row deletion and variance check, without grouped sums.
  if (status %in% available) {
    direct <- vapply(frame, function(g) mean(values[games != g]), numeric(1))
    stopifnot(all(abs(direct - deletion) <= 1e-10), abs(mean(values) - theta) <= 1e-10,
      abs((G - 1) * mean((direct - mean(direct))^2) - V) <= 1e-10)
  }
  list(point = theta, lower = lower, upper = upper, status = status, variance = V, deletion = deletion)
}
check_bounds <- function(point, lo, hi, status) {
  stopifnot(all(status %in% c(available, unavailable)), identical(is.na(lo), is.na(hi)))
  ok <- status %in% available
  stopifnot(all(is.finite(point[ok])), all(is.finite(lo[ok])), all(is.finite(hi[ok])),
    all(lo[ok] <= point[ok]), all(hi[ok] >= point[ok]), all(is.na(lo[!ok])), all(is.na(hi[!ok])))
  z <- status == available[2]; stopifnot(all(lo[z] == hi[z]))
}
annual <- depth <- depth_counts <- list()
for (year in years) {
  message("Calculating frozen season ", year)
  chosen <- filter(cohort, season == year)
  source <- filter(sources, season == year)
  raw <- arrow::read_parquet(source$file, col_select = c("season", "season_type", "game_id", "play_id", "passer_player_id",
    "rusher_player_id", "passer_player_name", "play_type", "qb_dropback", "qb_spike", "qb_kneel", "two_point_attempt",
    "sack", "qb_scramble", "cp", "cpoe", "air_yards", "complete_pass", "epa")) |>
    filter(season == year, season_type == "REG")
  stopifnot(!anyDuplicated(raw[c("season", "game_id", "play_id")]))
  ek <- filter(E_keys, season == year, passer_player_id %in% chosen$player_key)
  E <- left_join(ek, raw, by = c("season", "game_id", "play_id", "passer_player_id"), relationship = "one-to-one")
  stopifnot(nrow(E) == nrow(ek), !anyNA(E$season_type), all(is.finite(E$cpoe)), all(is.finite(E$cp)),
    all(E$cp >= 0 & E$cp <= 1), all(E$complete_pass %in% c(0, 1)), all(E$air_yards >= -15 & E$air_yards < 70),
    all(abs(E$cpoe - 100 * (E$complete_pass - E$cp)) <= 1e-8))
  E <- mutate(E, bin = as.character(cut(air_yards, c(-15, 0, 10, 20, 70), labels = bins$bin, right = FALSE)))
  dm <- filter(D_manifest, season == year); dk <- read(dm$D_file)
  stopifnot(!anyDuplicated(dk[c("season", "game_id", "play_id")]))
  D <- left_join(dk, raw, by = c("season", "game_id", "play_id", "passer_player_id", "rusher_player_id"),
    relationship = "one-to-one")
  stopifnot(!anyNA(D$season_type), all(D$qb_dropback == 1), all(D$qb_spike == 0), all(D$qb_kneel == 0),
    all(D$two_point_attempt == 0), all(D$role %in% c("other_pass", "sack", "scramble")),
    all(ifelse(D$play_type == "pass", D$actor_id == D$passer_player_id, D$actor_id == D$rusher_player_id)),
    all(D$role == ifelse(D$play_type == "pass", ifelse(D$sack == 1, "sack", "other_pass"), "scramble")),
    nrow(anti_join(ek, dk, by = c("season", "game_id", "play_id", "passer_player_id" = "actor_id"))) == 0L)
  for (id in chosen$player_key) {
    e <- filter(E, passer_player_id == id); d <- filter(D, actor_id == id)
    ec <- filter(chosen, player_key == id); dc <- filter(counts, season == year, player_key == id)
    frame <- sort(unique(e$game_id))
    stopifnot(nrow(e) == ec$eligible_throws, length(frame) == ec$eligible_games,
      nrow(d) == dc$dropbacks, n_distinct(d$game_id) == dc$dropback_games,
      sum(d$role == "sack") == dc$sacks, sum(d$role == "scramble") == dc$scramble_runs,
      nrow(d) >= nrow(e), n_distinct(d$game_id) >= length(frame))
    labels <- sort(unique(e$passer_player_name[nonempty(e$passer_player_name)]))
    observed <- if (length(labels)) labels[1] else id
    display <- players$display_name[match(id, players$gsis_id)]
    status <- if (!is.na(display)) "verified_source_display_name" else if (length(labels)) "observed_source_label" else "identifier_only"
    if (is.na(display)) display <- observed
    if (length(labels) != 1L) emit(tibble(player_key = id, season = year, observed_label = labels), paste0(year, "_", id, "_name_variants"))
    dg <- d |> group_by(game_id) |> summarise(n_g = n(), S_g = sum(epa), .groups = "drop") |> arrange(game_id)
    q <- sensitivity(dg$n_g, dg$S_g, d$epa, d$game_id, dg$game_id)
    if (any(!is.finite(d$epa))) { q$point <- q$lower <- q$upper <- NA_real_; q$status <- "nonfinite_epa_on_frozen_D" }
    whole <- mean(e$cpoe)
    stopifnot(abs(whole - 100 * mean(e$complete_pass - e$cp)) <= 1e-8)
    annual[[length(annual) + 1L]] <- tibble(player_key = id, season = as.integer(year), observed_name = observed,
      display_name = display, name_status = status, eligible_throws = nrow(e), eligible_games = length(frame), cpoe_pp = whole,
      completion_pct = 100 * mean(e$complete_pass), dropbacks = nrow(d), dropback_games = nrow(dg),
      sacks = sum(d$role == "sack"), scramble_runs = sum(d$role == "scramble"),
      sack_avoidance_pct = 100 * (nrow(d) - sum(d$role == "sack")) / nrow(d),
      epa_per_dropback = q$point, epa_lower = q$lower, epa_upper = q$upper, epa_interval_status = q$status)
    for (b in seq_len(nrow(bins))) {
      eb <- filter(e, bin == bins$bin[b])
      bg <- eb |> group_by(game_id) |> summarise(n_g = n(), S_g = sum(cpoe), .groups = "drop")
      bg <- left_join(tibble(game_id = frame), bg, by = "game_id", relationship = "one-to-one") |>
        mutate(n_g = coalesce(n_g, 0L), S_g = coalesce(S_g, 0))
      stopifnot(nrow(bg) == ec$eligible_games, sum(bg$n_g) == nrow(eb))
      z <- sensitivity(bg$n_g, bg$S_g, eb$cpoe, eb$game_id, frame)
      if (nrow(eb)) stopifnot(abs(z$point - 100 * mean(eb$complete_pass - eb$cp)) <= 1e-8)
      depth[[length(depth) + 1L]] <- tibble(player_key = id, season = as.integer(year), observed_name = observed,
        display_name = display, name_status = status, bin = bins$bin[b], air_yards_lower = bins$air_yards_lower[b],
        air_yards_upper = bins$air_yards_upper[b], eligible_throws = nrow(e), eligible_games = length(frame),
        bin_throws = nrow(eb), positive_bin_games = sum(bg$n_g > 0), cpoe_pp = z$point, lower = z$lower, upper = z$upper, interval_status = z$status)
      depth_counts[[length(depth_counts) + 1L]] <- tibble(season = year, passer_player_id = id, eligible_throws = nrow(e),
        eligible_games = length(frame), bin = bins$bin[b], bin_throws = nrow(eb), bin_games = sum(bg$n_g > 0),
        max_game_bin_throws = max(bg$n_g), zero_bin_games = sum(bg$n_g == 0), old_common20 = year %in% 2023:2024 && id %in% common,
        count_status = if (nrow(eb) == 0) "no_opportunities" else if (sum(bg$n_g > 0) == 1) "one_positive_bin_game" else "multiple_positive_bin_games")
      emit(mutate(bg, player_key = id, season = year, bin = bins$bin[b], deletion = z$deletion), paste0(year, "_", id, "_", bins$bin[b], "_deletions"))
    }
  }
  rm(raw, E, D); invisible(gc())
}
rows <- bind_rows(annual) |> arrange(player_key, season)
depth_rows <- bind_rows(depth) |> mutate(bin_order = match(bin, bins$bin)) |> arrange(player_key, season, bin_order) |> select(-bin_order)
depth_check <- bind_rows(depth_counts)
stopifnot(nrow(rows) == 560L, nrow(depth_rows) == 2240L, !anyDuplicated(rows[c("player_key", "season")]),
  !anyDuplicated(depth_rows[c("player_key", "season", "bin")]), !any(rows$season == 2011), !any(depth_rows$season == 2011))
# Reproduce authoritative feasibility counts, including corrected maximum game counts.
for (reference in list(tf, tf_old)) {
  actual <- if (nrow(reference) == 160L) filter(depth_check, old_common20) else depth_check
  k <- c("season", "passer_player_id", "bin")
  actual <- arrange(actual, season, passer_player_id, match(bin, bins$bin))
  reference <- arrange(reference, season, passer_player_id, match(bin, bins$bin))
  stopifnot(identical(names(actual), names(reference)), isTRUE(all.equal(actual, reference, tolerance = 0, check.attributes = FALSE)))
}
# Season totals independently reproduce TF-1.0's fixed count table.
season_bins <- depth_check |> group_by(season, bin) |> summarise(n = sum(bin_throws), .groups = "drop")
for (y in years) {
  target <- filter(tf_seasons, season == y)
  actual <- filter(depth_check, season == y)
  stopifnot(sum(filter(E_keys, season == y)$season == y) == target$full_frozen_E,
    n_distinct(actual$passer_player_id) == target$selected_actors, sum(actual$bin_throws) == target$selected_E)
  for (b in bins$bin) stopifnot(filter(season_bins, season == y, bin == b)$n == target[[b]])
}
recovered <- depth_rows |> group_by(player_key, season) |> summarise(N = sum(bin_throws),
  sum_cpoe = sum(if_else(bin_throws == 0, 0, cpoe_pp * bin_throws)), .groups = "drop") |>
  left_join(select(rows, player_key, season, eligible_throws, cpoe_pp), by = c("player_key", "season"), relationship = "one-to-one")
stopifnot(all(recovered$N == recovered$eligible_throws), all(abs(recovered$sum_cpoe / recovered$N - recovered$cpoe_pp) <= 1e-8))
check_bounds(rows$epa_per_dropback, rows$epa_lower, rows$epa_upper, rows$epa_interval_status)
check_bounds(depth_rows$cpoe_pp, depth_rows$lower, depth_rows$upper, depth_rows$interval_status)
stopifnot(all(rows$completion_pct >= 0 & rows$completion_pct <= 100), all(rows$sack_avoidance_pct >= 0 & rows$sack_avoidance_pct <= 100),
  all(rows$sacks + rows$scramble_runs <= rows$dropbacks))
# Exact old keys/counts/status/nulls; native numerical tolerance was prospectively fixed.
old40 <- rows |> filter(season %in% 2023:2024, player_key %in% common) |> arrange(player_key, season)
reference40 <- as_tibble(old$rows) |> arrange(player_key, season)
reconciliation <- list()
for (f in c("player_key", "season", "eligible_throws", "eligible_games", "dropbacks", "dropback_games", "sacks", "scramble_runs", "epa_interval_status"))
  stopifnot(identical(old40[[f]], reference40[[f]]) || isTRUE(all.equal(old40[[f]], reference40[[f]], tolerance = 0)))
for (f in c("cpoe_pp", "completion_pct", "epa_per_dropback", "sack_avoidance_pct", "epa_lower", "epa_upper")) {
  stopifnot(identical(is.na(old40[[f]]), is.na(reference40[[f]])))
  delta <- abs(old40[[f]] - reference40[[f]])
  stopifnot(all(delta[is.finite(delta)] <= 1e-10))
  reconciliation[[f]] <- tibble(field = f, maximum_absolute_difference = max(delta, na.rm = TRUE), matched_rows = 40L)
}
emit(bind_rows(reconciliation), "old40_reconciliation")
emit(rows, "annual_rows"); emit(depth_rows, "depth_rows"); emit(depth_check, "depth_count_reconciliation")
# Domains are frozen over the entire exported population, never selected pairs.
domain <- function(values, unit, percent = FALSE, limits = FALSE) {
  values <- values[is.finite(values)]
  if (!length(values)) return(list(min = NULL, max = NULL, unit = unit, status = "all_unavailable", includes_marginal_limits = limits, constant_observed = FALSE))
  if (percent) stopifnot(all(values >= 0 & values <= 100))
  constant <- length(unique(values)) == 1L
  lo <- min(values); hi <- max(values)
  if (!percent) { lo <- min(lo, 0); hi <- max(hi, 0) }
  if (lo == hi) { lo <- lo - 1; hi <- hi + 1; if (percent) { lo <- max(0, lo); hi <- min(100, hi) } }
  stopifnot(lo < hi, all(values >= lo & values <= hi))
  list(min = lo, max = hi, unit = unit, status = "available", includes_marginal_limits = limits, constant_observed = constant)
}
units <- list(cpoe_pp = "percentage_points", completion_pct = "percent", eligible_throws = "throws", eligible_games = "actor_games",
  dropbacks = "dropbacks", dropback_games = "actor_games", sacks = "sacks", scramble_runs = "runs", sack_avoidance_pct = "percent",
  epa_per_dropback = "expected_points_per_dropback", epa_lower = "expected_points_per_dropback", epa_upper = "expected_points_per_dropback")
domains <- list(cpoe_pp = domain(rows$cpoe_pp, units$cpoe_pp), completion_pct = domain(rows$completion_pct, units$completion_pct, TRUE),
  sack_avoidance_pct = domain(rows$sack_avoidance_pct, units$sack_avoidance_pct, TRUE),
  epa_per_dropback = domain(c(rows$epa_per_dropback, rows$epa_lower, rows$epa_upper), units$epa_per_dropback, limits = TRUE))
shown <- filter(depth_rows, bin != "negative")
depth_domain <- domain(c(shown$cpoe_pp, shown$lower, shown$upper), "percentage_points", limits = TRUE)
depth_units <- list(air_yards_lower = "yards", air_yards_upper = "yards", eligible_throws = "throws", eligible_games = "actor_games",
  bin_throws = "throws", positive_bin_games = "actor_games", cpoe_pp = "percentage_points", lower = "percentage_points", upper = "percentage_points")
catalog <- tibble(season = 2006:2025, status = if_else(season == 2011, "source_blocked", "exported"),
  reason = if_else(season == 2011, "unresolved_duplicate_events_and_air_yards", NA_character_),
  row_count = vapply(season, function(y) sum(rows$season == y), integer(1)))
generated <- format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
script <- sub("^--file=", "", grep("^--file=", commandArgs(), value = TRUE)); script_hash <- sha(script)
versions <- list(annual = list(version = "AD-1.0+AD-1.1", specification_sha256 = annual_design),
  depth = list(version = "DPX-1.0", specification_sha256 = depth_design),
  export = list(version = "annual-depth-1.0", script_sha256 = script_hash))
aggregate_hashes <- list(annual_membership_counts = count_pin, E_keys = sha(p("frozen_all_E_keys.csv")),
  D_manifest = sha(p("frozen_D_key_manifest.csv")), count_gate_outputs = sha(p("output_manifest.csv")),
  trait_bin_counts = tf_hashes[1], trait_common_counts = tf_hashes[2], trait_season_counts = tf_hashes[3],
  preserved_v2_payload = sha(a[3]), preserved_v2_manifest = sha(a[4]), player_names = sha(a[2]))
public_sources <- sources |> select(season, url, retrieved_utc, bytes, sha256, asset_created_utc, asset_updated_utc,
  generating_CP_model_vintage, generating_EP_model_vintage)
source_info <- list(pbp = public_sources, schedule_reference = old$sources[old$sources$id == "schedule_reference", ],
  player_names = list(url = "https://github.com/nflverse/nflverse-data/releases/download/players/players.csv",
    sha256 = sha(a[2]), use = "Display names only, exact raw GSIS ID match.", notices_url = "https://github.com/nflverse/nflverse-rosters"))
attribution <- old$attribution
attribution$source_notices <- paste(attribution$source_notices, "Player-list notices remain attached to that separate source.")
attribution$transformation_notice <- "New independently selected annual summaries from frozen eligible throws and all recorded actor dropbacks; newly calculated marginal conditional EPA and depth-residual game-deletion sensitivities. No isolated-trait or era-neutral interpretation."
eligibility <- list(rule = "At least 200 frozen eligible throws and ten eligible games in each season independently; team changes pool by raw GSIS ID.",
  population = "Recorded passers, not position-certified; frozen 560 actor-seasons; no adjacent-season requirement.",
  model_limit = "Generating CP/EP model and training vintage unknown; observed seasonal values are not era-neutral skill or forecasts.",
  missing_player_season = "No eligible record; do not substitute another year/player or a zero.")
denominators <- list(cpoe_pp = "Mean supplied CPOE over all frozen E throws; percentage points.",
  completion_pct = "100 times completions divided by the same E throws; matched-row diagnostic.",
  epa_per_dropback = "Sum supplied raw EPA on all frozen actor D divided by D, including sacks and scramble-runs; shared play value.",
  sack_avoidance_pct = "100*(D minus recorded sacks)/D; recorded outcome proxy, not pocket presence.")
uncertainty <- list(epa = "Approximate marginal 95% conditional complete D-game deletion sensitivity: theta +/-1.96*sqrt((G-1)/G*sum((deletion-mean(deletion))^2)). All actor D games; frozen qualification; no replicate drops.",
  other_individual_metrics = "not_estimated", collapsed = "No observed deletion variation, not certainty.",
  limitations = "Approximately independent game shocks conditional on fixed opportunities/player-season/support/model and selection; excludes serial dependence, source/model error and support uncertainty. Marginal bars do not test player/year differences.",
  interpretation = "EPA is shared with receivers/protection/scheme/opposition; CPOE is model-dependent; overlapping outcomes are not independent traits.")
payload <- list(schema_version = 3L, data_version = "2006-2025-independent-annual-v1", dataset_kind = "independent_annual_display",
  generated_utc = generated, seasons = years, season_catalog = catalog, eligibility = eligibility, units = units,
  denominators = denominators, uncertainty = uncertainty, sources = source_info, attribution = attribution,
  analysis_versions = versions, aggregate_input_hashes = aggregate_hashes, rows = rows, domains = domains)
depth_catalog <- mutate(catalog, row_count = row_count * 4L)
depth_payload <- payload
depth_payload$schema_version <- 1L; depth_payload$data_version <- "2006-2025-depth-residual-v1"
depth_payload$dataset_kind <- "independent_annual_depth_display"; depth_payload$season_catalog <- depth_catalog
depth_payload$units <- depth_units
depth_payload$denominators <- list(cpoe_pp = "Mean supplied CPOE on E throws in the fixed air-yard bin; independent identity 100*mean(completion-cp). Depth-specific completion residual proxy, not isolated placement/accuracy.",
  game_frame = "All seasonal E games, including zero-bin exposure; positive_bin_games counts only games with bin throws. No bin-volume threshold.")
depth_payload$uncertainty <- list(interval = "Approximate marginal 95% conditional all-E-game deletion sensitivity: theta +/-1.96*sqrt((G-1)/G*sum((deletion-mean(deletion))^2)); no failed replicate drops or requalification.",
  limitations = "Not calibrated talent confidence or prediction intervals; marginal bars neither test between-depth/player/year differences nor provide simultaneous 95% coverage across the three displayed axes. Independent game shocks/stable opportunity sampling/normal approximation may fail; excludes CP training/calibration, source labels, selection, receivers, coverage, protection and scheme uncertainty. Unknown CP vintage/calibration precludes era-neutral or causal comparisons.",
  collapsed = "No observed deletion variation, not certainty.",
  geometry = "Shared short/medium/deep native-pp domain across all 560 actor-seasons and endpoints plus zero. Negative is diagnostic only. Any later radius is display geometry, not a percentile, trait score or rating.")
depth_payload$rows <- NULL; depth_payload$domains <- NULL
depth_payload$bins <- bins; depth_payload$rows <- depth_rows; depth_payload$domains <- list(depth_cpoe_pp = depth_domain)
annual_fields <- c("player_key", "season", "observed_name", "display_name", "name_status", "eligible_throws", "eligible_games", "cpoe_pp", "completion_pct", "dropbacks", "dropback_games", "sacks", "scramble_runs", "sack_avoidance_pct", "epa_per_dropback", "epa_lower", "epa_upper", "epa_interval_status")
depth_fields <- c("player_key", "season", "observed_name", "display_name", "name_status", "bin", "air_yards_lower", "air_yards_upper", "eligible_throws", "eligible_games", "bin_throws", "positive_bin_games", "cpoe_pp", "lower", "upper", "interval_status")
top <- c("schema_version", "data_version", "dataset_kind", "generated_utc", "seasons", "season_catalog", "eligibility", "units", "denominators", "uncertainty", "sources", "attribution", "analysis_versions", "aggregate_input_hashes", "rows", "domains")
stopifnot(identical(names(payload), top), identical(names(rows), annual_fields), identical(names(depth_rows), depth_fields),
  identical(names(depth_payload), append(top[1:14], c("bins", "rows", "domains"))))
export <- function(x, basename, keys) {
  text <- json(x); stopifnot(jsonlite::validate(text), identical(text, json(x)))
  rt <- jsonlite::fromJSON(text)
  stopifnot(isTRUE(all.equal(as.data.frame(x$rows), rt$rows, tolerance = 0, check.attributes = FALSE)),
    all(vapply(x$rows[vapply(x$rows, is.numeric, logical(1))], function(v) !any(is.nan(v) | is.infinite(v)), logical(1))))
  forbidden <- c("/Users/", "/private/", "file://", ".local.md", "game_id", "play_id", "FTN", "desc\"")
  stopifnot(!any(vapply(forbidden, function(s) grepl(s, text, fixed = TRUE), logical(1))))
  manifest <- list(schema_version = x$schema_version, data_version = x$data_version, dataset_kind = x$dataset_kind,
    generated_utc = generated, payload = list(filename = paste0(basename, ".json"), sha256 = hash_text(text)), seasons = years,
    season_catalog = x$season_catalog, row_count = nrow(x$rows), row_keys_sha256 = hash_text(key_text(x$rows[keys])), units = x$units,
    domains = x$domains, analysis_versions = versions, aggregate_input_hashes = aggregate_hashes,
    source_hashes = select(sources, season, sha256), export_script_sha256 = script_hash)
  mf <- json(manifest); stopifnot(jsonlite::validate(mf))
  f <- file.path(out, paste0(basename, ".json")); m <- file.path(out, paste0(basename, ".manifest.json"))
  stopifnot(!file.exists(f), !file.exists(m)); writeBin(charToRaw(text), f); writeBin(charToRaw(mf), m)
  r <- jsonlite::fromJSON(f); z <- jsonlite::fromJSON(m)
  stopifnot(sha(f) == z$payload$sha256, z$payload$filename == basename(f), r$schema_version == z$schema_version,
    r$data_version == z$data_version, r$generated_utc == z$generated_utc, identical(r$domains, z$domains),
    identical(r$season_catalog, z$season_catalog), nrow(r$rows) == z$row_count)
  tibble(file = basename(c(f, m)), sha256 = c(sha(f), sha(m)))
}
assets <- bind_rows(export(payload, "nfl-qb-annual-2006-2025-v1", c("player_key", "season")),
  export(depth_payload, "nfl-qb-depth-2006-2025-v1", c("player_key", "season", "bin")))
verify(a[3], aggregate_hashes$preserved_v2_payload); verify(a[4], aggregate_hashes$preserved_v2_manifest)
emit(assets, "candidate_assets")
emit(tibble(check = c("pinned_source_design_keys_and_cohort", "exact_frozen_key_joins_and_counts", "TF_v2_all_and_common_counts",
  "CP_identity_and_four_bin_recovery", "direct_row_game_deletions", "all40_v2_numeric_count_status_null_reconciliation", "fixed_domains_and_2011_catalog",
  "public_allowlists_finite_nulls_and_roundtrip", "fresh_manifest_pairs", "immutable_v2_preserved"), passed = TRUE), "verification")
saveRDS(list(args = a, run_prefix = evidence(""), code_sha256 = script_hash, generated_utc = generated, assets = assets,
  annual_rows = nrow(rows), depth_rows = nrow(depth_rows), annual_domains = domains, depth_domain = depth_domain), evidence("run_record.rds"))
writeLines(capture.output(sessionInfo()), evidence("sessionInfo.txt"))
cat("Candidate directory:", out, "\nEvidence prefix:", evidence(""), "\nCode SHA256:", script_hash, "\n")
print(assets, width = Inf)
