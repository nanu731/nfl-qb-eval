# Audit public 2023 regular-season inputs; no performance estimation.
# Run from the repository root with an existing, ignored or temporary workspace:
# Rscript audit_inputs.R <input-workspace>
# Downloads are retained unchanged. Each execution writes new timestamped checks.
# Sources: nflreadr load_pbp/load_ftn_charting/load_schedules and their dictionaries;
# https://nflreadr.nflverse.com/reference/load_ftn_charting.html
# https://github.com/nflverse/nflfastR/blob/master/R/helper_add_cp_cpoe.R
# PBP: nflverse-data CC BY 4.0. FTN: CC BY-SA 4.0, FTN Data via nflverse.
# Data permissions are separate from the license on this original audit code.

suppressPackageStartupMessages({
  library(dplyr)
  library(readr)
})
needed <- c("arrow", "curl", "digest", "jsonlite", "stringr")
stopifnot(all(vapply(needed, requireNamespace, logical(1), quietly = TRUE)))
args <- commandArgs(trailingOnly = TRUE)
if (length(args) != 1 || !dir.exists(args[[1]])) {
  stop("Supply one existing ignored or temporary input workspace.")
}
workspace <- normalizePath(args[[1]], mustWork = TRUE)
run <- format(Sys.time(), "%Y%m%dT%H%M%S", tz = "UTC")
output <- function(name) file.path(workspace, paste0(run, "_", name))
emit <- function(x, name) {
  path <- output(paste0(name, ".csv"))
  if (file.exists(path)) stop("Refusing to overwrite check output: ", path)
  write_csv(x, path, na = "NA")
}

# This small receipt preserves acquisition time and checksum on subsequent runs.
receipt_path <- file.path(workspace, "download_receipts.csv")
receipts <- if (file.exists(receipt_path)) {
  read_csv(receipt_path, col_types = cols(.default = col_character()))
} else {
  tibble(file = character(), url = character(), retrieved_utc = character(),
         bytes = character(), sha256 = character())
}
fetch <- function(url, name) {
  path <- file.path(workspace, name)
  if (!file.exists(path)) {
    curl::curl_download(url, path, quiet = TRUE)
    record <- tibble(file = name, url = url,
                    retrieved_utc = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
                    bytes = as.character(file.info(path)$size),
                    sha256 = digest::digest(file = path, algo = "sha256"))
    receipts <<- bind_rows(receipts, record)
    write_csv(receipts, receipt_path)
  } else if (!name %in% receipts$file) {
    stop("Existing input lacks a receipt; preserve it and use a fresh workspace: ", name)
  }
  record <- filter(receipts, file == name)
  stopifnot(nrow(record) == 1, identical(record$url, url),
            record$sha256 == digest::digest(file = path, algo = "sha256"),
            as.numeric(record$bytes) == file.info(path)$size)
  path
}

release_url <- "https://api.github.com/repos/nflverse/nflverse-data/releases/tags/"
provenance <- list()
for (tag in c("pbp", "ftn_charting")) {
  meta_path <- fetch(paste0(release_url, tag), paste0(tag, "_release_metadata.json"))
  meta <- jsonlite::fromJSON(meta_path)
  asset_name <- if (tag == "pbp") "play_by_play_2023.parquet" else "ftn_charting_2023.parquet"
  asset <- filter(as_tibble(meta$assets), .data$name == .env$asset_name)
  stopifnot(nrow(asset) == 1)
  path <- fetch(asset$browser_download_url, asset_name)
  checksum <- digest::digest(file = path, algo = "sha256")
  stopifnot(file.info(path)$size == asset$size)
  # Older assets may not have GitHub-provided digests; retain our computed SHA256.
  remote_digest <- if ("digest" %in% names(asset)) asset$digest else NA_character_
  if (!is.na(remote_digest)) stopifnot(paste0("sha256:", checksum) == remote_digest)
  provenance[[tag]] <- tibble(dataset = tag, file = asset_name,
    url = asset$browser_download_url, release_tag = meta$tag_name,
    release_id = as.character(meta$id), asset_id = as.character(asset$id),
    asset_updated_utc = asset$updated_at, provider_digest = remote_digest,
    bytes = asset$size, sha256 = checksum)
}

# Independently maintained schedule reference, not another play-level input.
# The official loader distributes a multi-year schedule; only 2023 REG is used.
schedule_meta_url <- paste0("https://api.github.com/repos/nflverse/nfldata/commits?",
                            "path=data/games.rds&per_page=1")
schedule_meta <- jsonlite::fromJSON(fetch(schedule_meta_url, "schedule_commit.json"))
schedule_commit <- schedule_meta$sha[[1]]
schedule_url <- paste0("https://raw.githubusercontent.com/nflverse/nfldata/",
                       schedule_commit, "/data/games.rds")
schedule_path <- fetch(schedule_url, "schedule_reference.rds")
provenance$schedule <- tibble(dataset = "schedule reference", file = "schedule_reference.rds",
  url = schedule_url, release_tag = schedule_commit,
  release_id = NA_character_, asset_id = NA_character_,
  asset_updated_utc = schedule_meta$commit$committer$date[[1]], provider_digest = NA_character_,
  bytes = file.info(schedule_path)$size,
  sha256 = digest::digest(file = schedule_path, algo = "sha256"))
emit(left_join(bind_rows(provenance), receipts, by = "file", suffix = c("", "_receipt")),
     "provenance")

pbp_all <- arrow::read_parquet(file.path(workspace, "play_by_play_2023.parquet"))
ftn_all <- arrow::read_parquet(file.path(workspace, "ftn_charting_2023.parquet"))
schedule_all <- readRDS(schedule_path)
schema <- function(x, source) tibble(source = source, field = names(x),
  type = vapply(x, function(z) paste(class(z), collapse = "/"), character(1)))
emit(bind_rows(schema(pbp_all, "pbp"), schema(ftn_all, "ftn"),
               schema(schedule_all, "schedule")), "schema")
emit(count(pbp_all, season, season_type), "pbp_file_scope")
emit(count(ftn_all, season, week), "ftn_file_scope")
emit(count(left_join(filter(ftn_all, season == 2023),
  select(filter(schedule_all, season == 2023), nflverse_game_id = game_id, game_type),
  by = "nflverse_game_id", relationship = "many-to-one"), game_type), "ftn_schedule_scope")
pbp <- filter(pbp_all, season == 2023, season_type == "REG")
schedule <- filter(schedule_all, season == 2023, game_type == "REG")
ftn_season <- filter(ftn_all, season == 2023)
# FTN has no season_type. Schedule membership determines REG, before any PBP join.
ftn <- semi_join(ftn_season, schedule, by = c("nflverse_game_id" = "game_id"))
emit(anti_join(ftn_season, schedule, by = c("nflverse_game_id" = "game_id")),
     "ftn_outside_regular_schedule")
emit(schedule, "schedule_2023_REG")

required_pbp <- c("game_id", "play_id", "posteam", "passer_player_id", "passer_player_name",
                  "play_type", "pass_attempt", "complete_pass", "incomplete_pass",
                  "interception", "cp", "cpoe", "air_yards", "pass_location",
                  "receiver_player_id", "receiver_player_name", "desc")
stopifnot(all(required_pbp %in% names(pbp)),
          all(c("nflverse_game_id", "nflverse_play_id", "is_catchable_ball") %in% names(ftn)))
keys <- function(x, game, play, source) {
  grouped <- count(x, .data[[game]], .data[[play]], name = "records")
  duplicates <- filter(grouped, records > 1)
  missing <- x[is.na(x[[game]]) | is.na(x[[play]]), ]
  emit(duplicates, paste0(source, "_duplicate_keys"))
  emit(missing, paste0(source, "_missing_keys"))
  tibble(source = source, rows = nrow(x), missing_key_rows = nrow(missing),
         duplicate_key_groups = nrow(duplicates), duplicate_rows = sum(duplicates$records))
}
key_checks <- bind_rows(keys(pbp, "game_id", "play_id", "pbp"),
  keys(ftn, "nflverse_game_id", "nflverse_play_id", "ftn"),
  keys(ftn, "ftn_game_id", "ftn_play_id", "ftn_native"),
  keys(pbp_all, "game_id", "play_id", "pbp_full_file"),
  keys(ftn_all, "nflverse_game_id", "nflverse_play_id", "ftn_full_file"))
emit(key_checks, "keys")
stopifnot(!anyDuplicated(schedule$game_id), !anyNA(schedule$game_id))
emit(anti_join(schedule, distinct(pbp, game_id), by = "game_id"), "scheduled_games_without_pbp")
emit(anti_join(distinct(pbp, game_id), schedule, by = "game_id"), "pbp_games_without_schedule")
emit(anti_join(schedule, distinct(ftn, nflverse_game_id),
               by = c("game_id" = "nflverse_game_id")), "scheduled_games_without_ftn")
team_games <- bind_rows(select(schedule, game_id, team = home_team),
                        select(schedule, game_id, team = away_team))
emit(count(team_games, team, name = "scheduled_games"), "team_schedule_counts")
emit(count(schedule, week, name = "scheduled_games"), "week_schedule_counts")
# IDs are join keys, not a reliable chronology after provider corrections.
endpoints <- filter(pbp, desc == "END GAME") |>
  select(game_id, endpoint_description = desc, total_home_score, total_away_score)
emit(count(endpoints, game_id, name = "end_game_records"), "end_game_record_counts")
emit(left_join(schedule, endpoints, by = "game_id", relationship = "one-to-one") |>
  transmute(game_id, endpoint_description, home_score, away_score,
    total_home_score, total_away_score,
    score_matches = total_home_score == home_score & total_away_score == away_score),
  "game_endpoint_checks")
if (any(key_checks$missing_key_rows > 0 | key_checks$duplicate_key_groups > 0)) {
  stop("Missing/duplicate keys prevent the expected one-to-one join; evidence retained.")
}
by_key <- c("game_id" = "nflverse_game_id", "play_id" = "nflverse_play_id")
unmatched_pbp <- anti_join(pbp, ftn, by = by_key)
unmatched_ftn <- anti_join(ftn, pbp, by = setNames(names(by_key), unname(by_key)))
emit(unmatched_pbp, "pbp_without_ftn")
emit(unmatched_ftn, "ftn_without_pbp")
joined <- left_join(pbp, mutate(ftn, ftn_match = TRUE), by = by_key,
                    suffix = c("", "_ftn"), relationship = "one-to-one", na_matches = "never")
stopifnot(nrow(joined) == nrow(pbp))
joined <- mutate(joined, ftn_match = !is.na(ftn_match),
                 recorded_attempt = !is.na(pass_attempt) & pass_attempt == 1,
                 observed_cpoe = !is.na(cpoe))
emit(count(joined, ftn_match, season_matches = season == season_ftn,
  week_matches = week == week_ftn), "joined_metadata_consistency")
emit(count(unmatched_pbp, play_type, desc, sort = TRUE), "unmatched_pbp_descriptions")
emit(count(ftn, ftn_game_id, nflverse_game_id), "ftn_game_id_mapping")
emit(tibble(field = c("game_id", "play_id", "passer_player_id", "nflverse_game_id",
  "nflverse_play_id"),
  type = c(class(pbp$game_id), class(pbp$play_id), class(pbp$passer_player_id),
           class(ftn$nflverse_game_id), class(ftn$nflverse_play_id))), "key_types")
stopifnot(is.character(pbp$game_id), is.character(pbp$passer_player_id),
  is.numeric(pbp$play_id), is.numeric(ftn$nflverse_play_id),
  all(pbp$play_id == floor(pbp$play_id)),
  all(ftn$nflverse_play_id == floor(ftn$nflverse_play_id)))
emit(filter(joined, !is.na(passer_player_id) &
  !grepl("^[0-9]{2}-[0-9]{7}$", passer_player_id)), "unexpected_passer_id_format")

# Formula identity only: no CP refit or performance metric is estimated.
comparable <- filter(joined, !is.na(cp), !is.na(cpoe), !is.na(complete_pass))
error <- abs(comparable$cpoe - 100 * (comparable$complete_pass - comparable$cp))
emit(tibble(comparable_rows = nrow(comparable), max_absolute_error = max(error),
  mismatches_at_1e_8 = sum(error > 1e-8), cp_below_zero = sum(joined$cp < 0, na.rm = TRUE),
  cp_above_one = sum(joined$cp > 1, na.rm = TRUE),
  cp_present_cpoe_missing = sum(!is.na(joined$cp) & is.na(joined$cpoe)),
  cpoe_present_cp_missing = sum(is.na(joined$cp) & !is.na(joined$cpoe))), "cpoe_identity")
# Match prepare_cp_data's documented predicate, including its description parsing.
# This checks current documented eligibility, not the unknown generating code revision.
receiver_from_description <- stringr::str_extract(joined$desc,
  "(?<=((to)|(for))\\s[:digit:]{0,2}\\-{0,1})[A-Z][A-z]*\\.\\s?[A-Z][A-z]+(\\s(I{2,3})|(IV))?")
joined <- mutate(joined, receiver_from_description = receiver_from_description,
  documented_cp_eligible =
  (complete_pass == 1 | incomplete_pass == 1 | interception == 1) &
  !is.na(air_yards) & air_yards >= -15 & air_yards < 70 &
  (!is.na(receiver_from_description) | !is.na(receiver_player_id)) & !is.na(pass_location))
emit(count(joined, documented_cp_eligible, observed_cpoe), "cpoe_eligibility")
emit(filter(joined, is.na(documented_cp_eligible) |
  documented_cp_eligible != observed_cpoe), "cpoe_eligibility_discrepancies")
emit(count(joined, play_type, pass_attempt, sack, qb_spike, qb_scramble,
  observed_cpoe, ftn_match), "population_by_play_flags")
emit(count(joined, recorded_attempt, observed_cpoe, ftn_match,
           catchability_observed = !is.na(is_catchable_ball)), "population_intersections")
emit(count(joined, play_type, pass_attempt, is_catchable_ball, read_thrown),
     "label_applicability_diagnostics")

# Missingness is separate from false. FTN FALSE outside pass attempts does not
# establish applicability; these outputs describe stored labels, not eligibility.
labels <- grep("^is_", names(ftn), value = TRUE)
stopifnot(all(vapply(ftn[labels], is.logical, logical(1))))
ftn_fields <- setdiff(names(ftn), c("season", "week"))
coverage_fields <- c(labels, "read_thrown", "n_defense_box", "n_pass_rushers",
                     "n_blitzers", "qb_location", "starting_hash", "n_offense_backfield",
                     "cp", "cpoe", "passer_player_id", "air_yards", "pass_location")
emit(bind_rows(lapply(labels, function(label) {
  count(joined, recorded_attempt, observed_cpoe, ftn_match,
        value = as.character(.data[[label]])) |> mutate(label = label, .before = 1)
})), "label_populations")
coverage <- function(x, groups) {
  x |> group_by(across(all_of(groups))) |> summarise(
    all_plays = n(), recorded_attempts = sum(recorded_attempt),
    cpoe_rows = sum(observed_cpoe), ftn_matches = sum(ftn_match),
    attempts_with_cpoe = sum(recorded_attempt & observed_cpoe),
    attempts_with_ftn = sum(recorded_attempt & ftn_match),
    attempts_with_catchability = sum(recorded_attempt & !is.na(is_catchable_ball)),
    missing_passer_id = sum(is.na(passer_player_id)),
    attempts_missing_passer_id = sum(recorded_attempt & is.na(passer_player_id)),
    across(all_of(setdiff(coverage_fields, groups)), list(observed = ~sum(!is.na(.x)),
      missing_among_matches = ~sum(ftn_match & is.na(.x)),
      missing_on_matched_attempts = ~sum(ftn_match & recorded_attempt & is.na(.x))),
      .names = "{.col}_{.fn}"), .groups = "drop")
}
emit(coverage(joined, "season"), "overall_coverage")
emit(coverage(joined, "game_id"), "coverage_by_game")
emit(coverage(joined, "posteam"), "coverage_by_team")
emit(coverage(joined, "passer_player_id"), "coverage_by_quarterback")
emit(coverage(joined, "play_type"), "coverage_by_play_type")
emit(distinct(joined, passer_player_id, passer_player_name), "passer_names")
emit(joined |> filter(!is.na(passer_player_id)) |> group_by(passer_player_id) |>
  summarise(distinct_names = n_distinct(passer_player_name, na.rm = TRUE),
            .groups = "drop") |> filter(distinct_names != 1), "passer_name_ambiguities")
emit(joined |> filter(!is.na(passer_player_id)) |> group_by(passer_player_id) |>
  summarise(games_with_recorded_attempt = n_distinct(game_id[recorded_attempt]),
    teams = paste(sort(unique(posteam[!is.na(posteam)])), collapse = "/"),
    .groups = "drop"), "passer_population")
emit(count(joined, passer_player_id, passer_id_missing = is.na(passer_player_id),
           name_missing = is.na(passer_player_name), recorded_attempt), "passer_id_coverage")
emit(bind_rows(lapply(ftn_fields, function(field) tibble(field = field,
  matched_rows = sum(joined$ftn_match),
  missing_on_matches = sum(joined$ftn_match & is.na(joined[[field]])),
  missing_on_matched_attempts = sum(joined$ftn_match & joined$recorded_attempt &
                                    is.na(joined[[field]]))))), "ftn_field_missingness")
emit(bind_rows(lapply(c("cp", "cpoe", "passer_player_id", "passer_player_name",
  "receiver_player_id", "air_yards", "pass_location"), function(field) tibble(
    field = field, missing_all_plays = sum(is.na(joined[[field]])),
    missing_recorded_attempts = sum(joined$recorded_attempt & is.na(joined[[field]]))))),
    "pbp_field_missingness")
emit(count(ftn, read_thrown, sort = TRUE), "read_thrown_values")
emit(count(joined, play_type, read_thrown), "read_thrown_by_play_type")
emit(joined |> filter(recorded_attempt, !observed_cpoe) |>
  count(play_type, sack, qb_spike, missing_air_yards = is.na(air_yards),
    air_yards_outside_domain = !is.na(air_yards) & (air_yards < -15 | air_yards >= 70),
    missing_receiver = is.na(receiver_from_description) & is.na(receiver_player_id),
    missing_pass_location = is.na(pass_location)), "cpoe_missing_attempt_patterns")
emit(joined |> filter(ftn_match, if_any(all_of(labels), is.na)) |>
  select(game_id, play_id, posteam, passer_player_id, passer_player_name, play_type,
    pass_attempt, cpoe, all_of(labels), desc), "missing_label_records")
emit(count(joined, pass_attempt, play_type, two_point_attempt, sack, qb_spike,
  complete_pass, incomplete_pass, interception), "recorded_attempt_semantics")
emit(tibble(source = c("pbp", "ftn"),
  first_upstream_date = c(as.character(min(pbp_all$game_date)),
                          as.character(min(ftn_all$date_pulled))),
  last_upstream_date = c(as.character(max(pbp_all$game_date)),
                         as.character(max(ftn_all$date_pulled)))), "upstream_dates")
writeLines(capture.output(sessionInfo()), output("sessionInfo.txt"))
cat("Audit completed. Evidence prefix:", file.path(workspace, run), "\n")
print(select(coverage(joined, "season"), season:attempts_with_catchability), width = Inf)
print(key_checks)
print(tibble(unmatched_pbp = nrow(unmatched_pbp), unmatched_ftn = nrow(unmatched_ftn)))
