# Count-only audit for independent annual recorded-passer comparisons.
# Usage: Rscript annual_input_counts.R <historical-audit-dir> <baseline-prefix> <v2-json> <output-dir>
# Requires preserved local inputs; performs no downloads or performance estimation.
# Original code MIT; nflverse PBP attribution and CC BY 4.0 terms are separate.
suppressPackageStartupMessages({library(dplyr); library(readr)})
stopifnot(requireNamespace("arrow", quietly = TRUE),
          requireNamespace("digest", quietly = TRUE),
          requireNamespace("stringr", quietly = TRUE),
          requireNamespace("jsonlite", quietly = TRUE))
# Two source-pinned final-ruling descriptions need a diagnostic-only text exception.
# Raw classifications and the P/E/D predicates remain untouched.
normalize_final_description <- function(rows) {
  text <- sub(".*play was REVERSED[.]", "", rows$desc, ignore.case = TRUE)
  applied <- rep(FALSE, nrow(rows))
  cases <- data.frame(game_id = c("2006_03_ATL_NO", "2006_05_KC_ARI"),
    play_id = c(1374, 3501), actor = c("00-0020531", "00-0007835"), complete = c(0, 1),
    marker = c("Play Challenged by ATL and REVERSED.", "Play Challenged by KC and REVERSED."),
    description_sha = c("441cabf12ee563433e4d531167c6a7a0496bcc4daf8d113723bd09700505b90e",
      "495eac20cc84510142f2f1967ec75166fa88dac34fe438db98ad594cf34699f0"),
    suffix_sha = c("34b8af6a76ed5e02393066ea177d16943794ce295b32b01800b8138324dc3427",
      "f1dcea1bab3789f0215872b0267c38ed670db7fba32b376c2cc8eff110dc3735"))
  for (i in seq_len(nrow(cases))) {
    hit <- which(rows$season == 2006 & rows$game_id == cases$game_id[i] & rows$play_id == cases$play_id[i])
    if (length(hit) != 1L) next
    r <- rows[hit, ]
    agreement <- isTRUE(all(c(r$replay_or_challenge == 1,
      r$replay_or_challenge_result == "reversed", r$play_type == "pass",
      r$passer_player_id == cases$actor[i], is.na(r$rusher_player_id),
      r$pass_attempt == 1, r$rush_attempt == 0, r$qb_dropback == 1,
      r$sack == 0, r$qb_scramble == 0, r$qb_spike == 0, r$qb_kneel == 0,
      r$two_point_attempt == 0, r$penalty == 0, r$interception == 0,
      r$complete_pass == cases$complete[i], r$incomplete_pass == 1 - cases$complete[i])))
    fingerprint <- digest::digest(r$desc, algo = "sha256", serialize = FALSE)
    if (!agreement || fingerprint != cases$description_sha[i]) next
    parts <- strsplit(r$desc, cases$marker[i], fixed = TRUE)[[1]]
    if (length(parts) != 2L || !nzchar(trimws(parts[2]))) next
    if (digest::digest(parts[2], algo = "sha256", serialize = FALSE) != cases$suffix_sha[i] ||
        grepl("\\bNo Play\\b", parts[2], ignore.case = TRUE)) next
    text[hit] <- parts[2]
    applied[hit] <- TRUE
  }
  list(text = text, applied = applied)
}
args <- commandArgs(trailingOnly = TRUE)
if (length(args) != 4 || !all(dir.exists(args[c(1, 4)]))) {
  stop("Supply existing historical audit/output directories, baseline prefix and v2 JSON.")
}
work <- normalizePath(args[1], mustWork = TRUE)
out <- normalizePath(args[4], mustWork = TRUE)
run <- paste0(format(Sys.time(), "%Y%m%dT%H%M%S", tz = "UTC"), "_annual_counts_", Sys.getpid(), "_")
path <- function(name) file.path(out, paste0(run, name))
sha <- function(file) digest::digest(file = file, algo = "sha256")
emit <- function(x, name) {
  file <- path(paste0(name, ".csv"))
  if (file.exists(file)) stop("Refusing to overwrite an existing artifact: ", file)
  write_csv(x, file, na = "NA")
  invisible(file)
}
nonempty <- function(x) !is.na(x) & nzchar(trimws(x))
eq <- function(x, value) !is.na(x) & x == value
years <- setdiff(2006:2025, 2011)
summaries <- list()
key_manifests <- list()
selected_counts <- list()
year_errors <- list()
stage <- "input_hash_verification"
active_year <- NA_integer_
failure <- NULL
normalized_total <- 0L

result <- tryCatch({
  pins <- tibble(file = c("final_source_provenance.csv", "final_season_summary.csv",
    "completed_game_ledger.csv", "audit_v1_E_key_manifest.csv", "audit_v1_annual_exposure_all.csv"),
    sha256 = c("7f7f4b19892fd3ca941666795fb2c827e6a5bb9f164fac1d950bee528033a38a",
      "91c21606eb6e900eb6b0299bb36f27187965bffe15a6e9e72c6cad9929154e61",
      "64cd16287f3c2488c21470c9e4958a74923cd21c2c290bc4f4ca186514211220",
      "41061ce0157776a74c2545ba71b337ae6f995b8dfd5867b9b87ce9a55a15ac2d",
      "ddd952cad097ed49d7c377049e2c2194abf5b26b16e8654e75abe72e386b3f2d"))
  for (i in seq_len(nrow(pins))) stopifnot(sha(file.path(work, pins$file[i])) == pins$sha256[i])
  emit(pins, "verified_input_manifest_pins")
  sources <- read_csv(file.path(work, pins$file[1]), show_col_types = FALSE)
  season_reference <- read_csv(file.path(work, pins$file[2]), show_col_types = FALSE)
  ledger <- read_csv(file.path(work, pins$file[3]), show_col_types = FALSE)
  E_manifest <- read_csv(file.path(work, pins$file[4]), show_col_types = FALSE)
  inventory <- read_csv(file.path(work, pins$file[5]), show_col_types = FALSE)
  stopifnot(nrow(sources) == 20, setequal(sources$season, 2006:2025), !anyDuplicated(sources$season),
    !anyDuplicated(ledger$game_id), all(ledger$status %in% c("completed", "cancelled")),
    identical(filter(ledger, status == "cancelled")$game_id, "2022_17_BUF_CIN"),
    all(filter(season_reference, season %in% years)$status == "compatible_count_only"),
    !anyDuplicated(inventory[c("season", "passer_player_id")]))
  for (i in seq_len(nrow(sources))) {
    stopifnot(file.info(sources$file[i])$size == sources$bytes[i], sha(sources$file[i]) == sources$sha256[i])
  }
  emit(mutate(sources, generating_CP_model_vintage = "unknown", generating_EP_model_vintage = "unknown"),
       "verified_source_provenance")
  all_E <- bind_rows(lapply(seq_len(nrow(E_manifest)), function(i) {
    stopifnot(sha(E_manifest$file[i]) == E_manifest$sha256[i])
    x <- read_csv(E_manifest$file[i], show_col_types = FALSE)
    stopifnot(nrow(x) == E_manifest$E_rows[i], all(x$season == E_manifest$season[i]),
      !anyNA(x), !anyDuplicated(x[c("season", "game_id", "play_id")]))
    x
  }))
  stopifnot(setequal(E_manifest$season, 2006:2025), nrow(E_manifest) == 20)
  E_counts <- all_E |> group_by(season, passer_player_id) |>
    summarise(key_E = n(), key_games = n_distinct(game_id), .groups = "drop")
  stopifnot(nrow(anti_join(E_counts, inventory, by = c("season", "passer_player_id"))) == 0)
  exposure_check <- left_join(inventory, E_counts, by = c("season", "passer_player_id"),
                             relationship = "one-to-one") |>
    mutate(key_E = coalesce(key_E, 0L), key_games = coalesce(key_games, 0L))
  stopifnot(all(exposure_check$E_rows == exposure_check$key_E),
    all(exposure_check$E_games == exposure_check$key_games),
    all(exposure_check$qualifies == (exposure_check$key_E >= 200 & exposure_check$key_games >= 10)))
  cohort <- exposure_check |> filter(season %in% years, qualifies) |>
    transmute(season = as.integer(season), player_key = passer_player_id,
      eligible_throws = as.integer(key_E), eligible_games = as.integer(key_games)) |>
    arrange(season, player_key)
  cohort_file <- emit(cohort, "frozen_annual_cohort")
  stopifnot(nrow(cohort) == 560,
    sha(cohort_file) == "6086987ab160812cce3a07cb5eff00447a0b06d39c166d0df63e0c0635f29552")
  emit(count(cohort, season, name = "candidate_player_seasons"), "candidate_season_counts")
  emit(filter(all_E, season %in% years) |> arrange(season, game_id, play_id, passer_player_id),
       "frozen_all_E_keys")
  emit(E_manifest, "verified_E_key_manifest")
  emit(filter(ledger, status == "cancelled"), "cancelled_game_classification")

  # Existing all-actor keys are reused only as count/identity evidence, never estimates.
  accepted_D_hashes <- c(`2023` = "41f2684b9f0aa52339fd4caf6c7700c36e636b7ee4e14fc1f76ec6875dc430f8",
    `2024` = "dc5ebd0342bef6981866475acd8ed1f9143855ed7ce712d609b476605ce3432f")
  for (year in 2023:2024) stopifnot(
    sha(paste0(args[2], "all_actor_keys_", year, ".csv")) == accepted_D_hashes[as.character(year)])
  stopifnot(sha(args[3]) == "56c45de0fefde398d74ca31763e56fd86b60c43dd2c3f3b20be566acb57241e1")
  v2_manifest <- sub("[.]json$", ".manifest.json", args[3])
  stopifnot(v2_manifest != args[3],
    sha(v2_manifest) == "a707dce3334864193fde79576c69940170b5cadb59ce3fa35df7b7b4f1878a62")
  old_counts <- jsonlite::fromJSON(args[3])$rows |>
    select(player_key, season, eligible_throws, eligible_games, dropbacks, dropback_games, sacks, scramble_runs)
  common <- intersect(filter(cohort, season == 2023)$player_key, filter(cohort, season == 2024)$player_key)
  stopifnot(length(common) == 20, nrow(old_counts) == 40, setequal(common, old_counts$player_key))

  flags <- c("qb_dropback", "qb_scramble", "sack", "qb_spike", "qb_kneel", "two_point_attempt",
    "pass_attempt", "rush_attempt", "penalty", "complete_pass", "incomplete_pass", "interception")
  required <- c("season", "season_type", "week", "game_id", "play_id", "game_date", "play_type",
    "posteam", "passer_player_id", "rusher_player_id", "passer_player_name", "rusher_player_name",
    "epa", "cp", "cpoe", "air_yards", "pass_location", "receiver_player_id", "desc",
    "total_home_score", "total_away_score", "replay_or_challenge", "replay_or_challenge_result", flags)
  # Reconcile accepted recent evidence first, then audit additional years in order.
  for (year in c(2023:2024, setdiff(years, 2023:2024))) {
    active_year <- year
    year_result <- tryCatch({
    stage <- "schema_keys_ledger_and_end_state"
    cat("COUNT-ONLY", year, "\n"); flush.console()
    file <- filter(sources, season == year)$file
    schema <- arrow::open_dataset(file)$schema
    emit(tibble(field = schema$names, arrow_type = vapply(schema$fields,
      function(f) f$type$ToString(), character(1))), paste0(year, "_schema"))
    stopifnot(all(required %in% schema$names))
    raw <- arrow::read_parquet(file, col_select = all_of(required))
    chars <- c("game_id", "play_type", "posteam", "passer_player_id", "rusher_player_id",
      "passer_player_name", "rusher_player_name", "pass_location", "receiver_player_id", "desc")
    stopifnot(all(vapply(raw[chars], is.character, logical(1))),
      all(vapply(raw[c(flags, "play_id", "epa", "cp", "cpoe", "air_yards")], is.numeric, logical(1))),
      all(raw$season == year), !anyNA(raw[c("game_id", "play_id")]),
      all(nonempty(raw$game_id)), all(is.finite(raw$play_id)),
      !anyDuplicated(raw[c("game_id", "play_id")]))
    reg <- filter(raw, season_type == "REG")
    sc <- filter(ledger, season == year, status == "completed")
    cancelled <- filter(ledger, season == year, status == "cancelled")$game_id
    emit(filter(reg, game_id %in% cancelled), paste0(year, "_cancelled_source_rows"))
    stopifnot(!any(reg$game_id %in% cancelled), setequal(unique(reg$game_id), sc$game_id))
    metadata_bad <- reg |> left_join(select(sc, game_id, ref_date = gameday, ref_week = week),
      by = "game_id", relationship = "many-to-one") |>
      filter(is.na(game_date) | as.Date(game_date) != as.Date(ref_date) | is.na(week) | week != ref_week)
    emit(metadata_bad, paste0(year, "_ledger_metadata_exceptions"))
    end <- filter(reg, grepl("^END GAME([[:space:]]|$)", desc))
    end_bad <- sc |> select(game_id, home_score, away_score) |>
      left_join(end |> select(game_id, total_home_score, total_away_score), by = "game_id",
        relationship = "one-to-many") |>
      filter(is.na(total_home_score) | is.na(total_away_score) |
        total_home_score != home_score | total_away_score != away_score)
    emit(end_bad, paste0(year, "_end_state_exceptions"))
    stopifnot(nrow(metadata_bad) == 0, nrow(end_bad) == 0, nrow(end) == nrow(sc), !anyDuplicated(end$game_id),
      nrow(reg) == filter(season_reference, season == year)$completed_rows)
    domains <- bind_rows(lapply(flags, function(f) count(reg, value = .data[[f]]) |> mutate(field = f)))
    emit(domains, paste0(year, "_flag_domains_missingness"))
    stopifnot(all(is.na(domains$value) | domains$value %in% c(0, 1)))

    stage <- "frozen_P_E_reconciliation"
    # Same accepted P/E predicates and receiver parser, with independent annual counts.
    receiver <- stringr::str_extract(reg$desc,
      "(?<=((to)|(for))\\s[:digit:]{0,2}\\-{0,1})[A-Z][A-z]*\\.\\s?[A-Z][A-z]+(\\s(I{2,3})|(IV))?")
    reg <- reg |> mutate(P = eq(play_type, "pass") & eq(pass_attempt, 1) & eq(sack, 0) &
      eq(qb_spike, 0) & eq(two_point_attempt, 0) & nonempty(passer_player_id) &
      !is.na(game_date) & !is.na(complete_pass) & !is.na(incomplete_pass) & !is.na(interception) &
      (eq(complete_pass, 1) | eq(incomplete_pass, 1) | eq(interception, 1)),
      E = P & is.finite(cp) & cp >= 0 & cp <= 1 & is.finite(cpoe) & !is.na(air_yards) &
        air_yards >= -15 & air_yards < 70 & !is.na(pass_location) &
        (!is.na(receiver) | !is.na(receiver_player_id)))
    normalized <- normalize_final_description(reg)
    reg <- mutate(reg, diagnostic_final_description = normalized$text,
      diagnostic_replay_exception_applied = normalized$applied)
    normalized_total <- normalized_total + sum(normalized$applied)
    emit(filter(reg, season == 2006,
      (game_id == "2006_03_ATL_NO" & play_id == 1374) | (game_id == "2006_05_KC_ARI" & play_id == 3501)),
      paste0(year, "_diagnostic_replay_normalization_trace"))
    P_bad <- filter(reg, P, (complete_pass == 1 & (incomplete_pass == 1 | interception == 1)) |
      grepl("\\bNo Play\\b", diagnostic_final_description, ignore.case = TRUE) |
      (!is.na(cp) & (!is.finite(cp) | cp < 0 | cp > 1)) |
      (!is.na(cpoe) & (!is.finite(cpoe) | is.na(cp) | abs(cpoe - 100 * (complete_pass - cp)) > 1e-8)))
    # Diagnostic labels do not alter P/E membership or clear the literal guard.
    P_bad <- P_bad |> mutate(
      contradictory_outcome = complete_pass == 1 & (incomplete_pass == 1 | interception == 1),
      invalid_CP = !is.na(cp) & (!is.finite(cp) | cp < 0 | cp > 1),
      invalid_CPOE_identity = !is.na(cpoe) & (!is.finite(cpoe) | is.na(cp) |
        abs(cpoe - 100 * (complete_pass - cp)) > 1e-8),
      guard_final_description = diagnostic_final_description,
      residual_No_Play = grepl("\\bNo Play\\b", guard_final_description, ignore.case = TRUE))
    emit(P_bad, paste0(year, "_P_identity_contradictions"))
    keys <- filter(reg, E) |> select(season, game_id, play_id, passer_player_id)
    frozen_E <- filter(all_E, season == year)
    stopifnot(nrow(P_bad) == 0, !anyNA(reg$P), !anyNA(reg$E),
      nrow(anti_join(keys, frozen_E, by = names(keys))) == 0,
      nrow(anti_join(frozen_E, keys, by = names(keys))) == 0)
    emit(count(reg, play_type, P, E), paste0(year, "_P_E_exclusion_counts"))
    actor_P <- filter(reg, P) |> count(passer_player_id, name = "observed_P")
    P_check <- filter(inventory, season == year) |> left_join(actor_P, by = "passer_player_id",
      relationship = "one-to-one") |> mutate(observed_P = coalesce(observed_P, 0L))
    stopifnot(all(P_check$P_rows == P_check$observed_P))

    stage <- "all_actor_D_identity_roles_and_selected_EPA_gate"
    expected <- reg$play_type == "pass" | (reg$play_type == "run" & reg$qb_scramble == 1)
    equivalence_bad <- is.na(expected) != is.na(reg$qb_dropback) |
      (!is.na(expected) & !is.na(reg$qb_dropback) & expected != reg$qb_dropback)
    emit(filter(reg, equivalence_bad), paste0(year, "_dropback_equivalence_contradictions"))
    reg <- reg |> mutate(D_exclusion = case_when(
      is.na(qb_dropback) ~ "unknown_dropback", qb_dropback != 1 ~ "not_recorded_dropback",
      is.na(play_type) ~ "unknown_play_type", !play_type %in% c("pass", "run") ~ "outside_played_pass_run",
      is.na(qb_spike) | is.na(qb_kneel) | is.na(two_point_attempt) ~ "unknown_special_play_flag",
      qb_spike != 0 ~ "spike", qb_kneel != 0 ~ "kneel", two_point_attempt != 0 ~ "two_point",
      TRUE ~ NA_character_))
    emit(count(reg, D_exclusion, play_type, penalty), paste0(year, "_D_exclusions"))
    D <- filter(reg, is.na(D_exclusion)) |> mutate(
      role = case_when(play_type == "pass" & sack == 0 ~ "other_pass",
        play_type == "pass" & sack == 1 ~ "sack",
        play_type == "run" & sack == 0 & qb_scramble == 1 ~ "scramble", TRUE ~ NA_character_),
      actor_id = if_else(play_type == "pass", passer_player_id, rusher_player_id),
      invalid_role = is.na(role), invalid_actor = !nonempty(actor_id) | !grepl("^00-[0-9]{7}$", actor_id),
      invalid_raw_attribution = if_else(play_type == "pass",
        !is.na(rusher_player_id) | is.na(pass_attempt) | pass_attempt != 1,
        !is.na(passer_player_id) | is.na(rush_attempt) | rush_attempt != 1),
      invalid_EPA = !is.finite(epa))
    # qb_scramble also records movement mentioned on passes; it does not
    # override the recorded pass/sack classification. Preserve every overlap.
    emit(filter(D, play_type == "pass", qb_scramble == 1),
      paste0(year, "_pass_scramble_flag_overlaps"))
    emit(filter(D, invalid_EPA), paste0(year, "_all_actor_missing_EPA"))
    bad_D <- filter(D, invalid_role | invalid_actor | invalid_raw_attribution)
    emit(bad_D, paste0(year, "_D_contradictions"))
    emit(count(D, role, invalid_role, invalid_actor, invalid_raw_attribution, invalid_EPA),
      paste0(year, "_all_actor_D_diagnostics"))
    if (any(equivalence_bad) || nrow(bad_D) > 0) stop("All-actor dropback contradiction; no estimation: ", year)
    D_keys <- D |> select(season, game_id, play_id, actor_id, role, passer_player_id, rusher_player_id) |>
      arrange(season, game_id, play_id, actor_id, role)
    if (year %in% 2023:2024) {
      accepted <- read_csv(paste0(args[2], "all_actor_keys_", year, ".csv"), show_col_types = FALSE)
      stopifnot(nrow(anti_join(D_keys, accepted, by = names(D_keys))) == 0,
        nrow(anti_join(accepted, D_keys, by = names(D_keys))) == 0)
    }
    D_file <- emit(D_keys, paste0(year, "_frozen_D_keys"))
    actor_games <- D |> group_by(season, actor_id, game_id) |> summarise(dropbacks = n(),
      sacks = sum(role == "sack"), scramble_runs = sum(role == "scramble"),
      other_pass = sum(role == "other_pass"), .groups = "drop") |> arrange(season, actor_id, game_id)
    stopifnot(all(actor_games$dropbacks == actor_games$sacks + actor_games$scramble_runs + actor_games$other_pass))
    game_file <- emit(actor_games, paste0(year, "_frozen_actor_game_counts"))
    counts <- actor_games |> group_by(season, actor_id) |> summarise(dropbacks = sum(dropbacks),
      dropback_games = n(), sacks = sum(sacks), scramble_runs = sum(scramble_runs), .groups = "drop")
    chosen <- filter(cohort, season == year) |> left_join(counts, by = c("season", "player_key" = "actor_id"),
      relationship = "one-to-one")
    # Eligibility was frozen using E exposure, independently of EPA availability.
    # No opportunity is removed from a selected player's denominator.
    selected_missing <- filter(D, actor_id %in% chosen$player_key, invalid_EPA)
    emit(selected_missing, paste0(year, "_selected_missing_EPA"))
    if (nrow(selected_missing) > 0)
      stop("Selected player-season has nonfinite EPA; metric availability needs review: ", year)
    stopifnot(!anyNA(chosen), all(chosen$dropbacks >= chosen$eligible_throws),
      all(chosen$dropback_games >= chosen$eligible_games))
    selected_E <- frozen_E |> filter(passer_player_id %in% chosen$player_key)
    orphan_E <- anti_join(selected_E, D_keys, by = c("season", "game_id", "play_id", "passer_player_id" = "actor_id"))
    emit(orphan_E, paste0(year, "_selected_E_outside_actor_D"))
    stopifnot(nrow(orphan_E) == 0)
    if (year %in% 2023:2024) {
      a <- chosen |> filter(player_key %in% common) |> arrange(player_key, season)
      b <- old_counts |> filter(season == year) |> arrange(player_key, season)
      a <- select(a, all_of(names(b)))
      stopifnot(isTRUE(all.equal(a, as_tibble(b), check.attributes = FALSE)))
    }
    emit(chosen, paste0(year, "_selected_count_reconciliation"))
    selected_counts[[as.character(year)]] <- chosen
    key_manifests[[as.character(year)]] <- tibble(season = year, D_file = D_file,
      D_sha256 = sha(D_file), actor_game_file = game_file, actor_game_sha256 = sha(game_file))
    summaries[[as.character(year)]] <- tibble(season = year, REG_rows = nrow(reg), completed_games = nrow(sc),
      E_rows = nrow(frozen_E), D_rows = nrow(D), D_actors = n_distinct(D$actor_id),
      other_pass = sum(D$role == "other_pass"), sacks = sum(D$role == "sack"),
      scramble_runs = sum(D$role == "scramble"), candidates = nrow(chosen),
      played_D_penalties = sum(D$penalty %in% 1), unknown_D_penalty = sum(is.na(D$penalty)),
      status = "count_gate_passed")
    emit(bind_rows(summaries), paste0("season_checkpoint_", year))
    NULL
    }, error = function(e) conditionMessage(e))
    if (!is.null(year_result)) {
      year_errors[[as.character(year)]] <- tibble(season = year, stage = stage, reason = year_result)
      emit(bind_rows(year_errors), paste0("blocked_year_checkpoint_", year))
      cat("BLOCKED YEAR", year, stage, year_result, "\n"); flush.console()
    }
  }
  emit(bind_rows(year_errors), "blocked_season_checks")
  stopifnot(normalized_total == 2L)
  if (length(year_errors) > 0) {
    failure <- paste("Per-season count gates remain blocked:", paste(names(year_errors), collapse = ", "))
    "blocked"
  } else {
  stopifnot(length(summaries) == 19, sum(bind_rows(selected_counts)$eligible_throws) == sum(cohort$eligible_throws),
    nrow(bind_rows(selected_counts)) == 560)
  "count_gate_passed"
  }
}, error = function(e) {
  failure <<- conditionMessage(e)
  "blocked"
})
emit(bind_rows(summaries), "completed_season_diagnostics")
emit(bind_rows(key_manifests), "frozen_D_key_manifest")
emit(bind_rows(selected_counts), "verified_selected_counts")
emit(tibble(season = 2006:2025, status = case_when(season == 2011 ~ "source_blocked",
  season %in% as.integer(names(summaries)) ~ "count_gate_passed",
  season %in% as.integer(names(year_errors)) ~ "contradiction_recorded",
  season == active_year & result == "blocked" ~ "new_contradiction_or_failed_check",
  TRUE ~ "not_reached")), "season_gate_status")
emit(tibble(status = result, active_season = active_year, stage = stage,
  reason = if (is.null(failure)) NA_character_ else failure,
  completed_seasons = length(summaries), estimation_performed = FALSE), "gate_result")
script <- sub("^--file=", "", grep("^--file=", commandArgs(), value = TRUE))
files <- list.files(out, pattern = paste0("^", run), full.names = TRUE)
emit(tibble(file = basename(files), bytes = file.info(files)$size,
  sha256 = vapply(files, sha, character(1))), "output_manifest")
saveRDS(list(status = result, active_season = active_year, stage = stage, reason = failure,
  script_sha256 = sha(script), design_version = "independent-annual-display-1.1",
  accepted_design_sha256 = "7d2f41e4ed11aa6f1a54ba2f6a456bd42073f0ecfd62eded09ea6a13eae10984",
  diagnostic_amendment = "D1: exact fingerprinted reversed2006 descriptions only",
  annual_display_amendment = "AD-1.1: recorded pass roles; EPA completeness on frozen eligible actor-seasons",
  annual_display_amendment_sha256 = "7d9c08e156c85fb7c69005b79c192c9b0e45d312ae3b8d5f94c4cdfcb8887ce1",
  diagnostic_normalizations_applied = normalized_total,
  generating_CP_EP_model_vintage = "unknown", no_performance_estimation = TRUE), path("run_record.rds"))
writeLines(capture.output(sessionInfo()), path("session.txt"))
cat("RESULT", result, "PREFIX", file.path(out, run), "\n")
if (!is.null(failure)) {cat("BLOCKER", active_year, stage, failure, "\n"); quit(status = 2)}
