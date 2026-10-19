# Display existing verified interval outputs; no estimation or raw-data access.
# Usage: Rscript plot_repeatability.R <pilot-prefix> <annual-prefix> <new-output.png>
# Prefixes include the trailing underscore emitted by the analysis scripts.
suppressPackageStartupMessages({library(dplyr); library(readr); library(ggplot2)})
args <- commandArgs(trailingOnly = TRUE)
if (length(args) != 3) stop("Supply pilot prefix, annual prefix, and a new PNG path.")
output <- args[[3]]
if (!dir.exists(dirname(output)) || file.exists(output) || !grepl("[.]png$", output, ignore.case = TRUE)) {
  stop("Output must be a new .png file in an existing directory.")
}
statistics <- c("r_C", "r_B", "Delta")
read_intervals <- function(file, label, scale_column, unavailable_status) {
  x <- read_csv(file, show_col_types = FALSE, col_types = cols(
    statistic = col_character(), estimate = col_double(), lower = col_double(),
    upper = col_double(), status = col_character()))
  if (nrow(problems(x)) > 0) stop("Unparseable interval values: ", file)
  required <- c("statistic", "estimate", "lower", "upper", "status", scale_column)
  if (!all(required %in% names(x)) || nrow(x) != 3 || anyDuplicated(x$statistic) ||
      !setequal(x$statistic, statistics)) stop("Invalid statistic identities/schema: ", file)
  if (!all(vapply(x[c("estimate", "lower", "upper")], is.numeric, logical(1)))) {
    stop("Estimate/interval columns must be numeric: ", file)
  }
  expected_scale <- if_else(x$statistic == "Delta", "raw_Delta", "Fisher_z")
  stopifnot(!anyNA(x$status), all(x[[scale_column]] == expected_scale),
    all(x$status %in% c("conditional_working_model_sensitivity", unavailable_status)))
  available <- x$status == "conditional_working_model_sensitivity"
  if (any(!is.finite(x$estimate[available])) || any(!is.finite(x$lower[available])) ||
      any(!is.finite(x$upper[available])) ||
      any(x$lower[available] > x$estimate[available] | x$estimate[available] > x$upper[available]) ||
      any(!is.na(x$estimate) & !is.finite(x$estimate)) ||
      any(!is.na(x$lower[!available]) | !is.na(x$upper[!available]))) {
    stop("Interval values contradict their availability status: ", file)
  }
  # Keep unavailable rows and source statuses; never turn them into zero estimates.
  x |> select(statistic, estimate, lower, upper, status) |>
    mutate(test = label, interval_available = available)
}
pilot_cohort <- read_csv(paste0(args[[1]], "cohort_counts.csv"),
  col_types = cols_only(passer_player_id = col_character(), qualifies = col_logical()))
annual_cohort <- read_csv(paste0(args[[2]], "cohort_counts.csv"),
  col_types = cols_only(passer_player_id = col_character(), season = col_integer(),
                       qualifies_both = col_logical()))
stopifnot(!anyNA(pilot_cohort), !anyDuplicated(pilot_cohort$passer_player_id),
  !anyNA(annual_cohort), !anyDuplicated(annual_cohort[c("passer_player_id", "season")]),
  setequal(annual_cohort$season, c(2023L, 2024L)))
common_2023 <- filter(annual_cohort, season == 2023, qualifies_both)$passer_player_id
common_2024 <- filter(annual_cohort, season == 2024, qualifies_both)$passer_player_id
stopifnot(setequal(common_2023, common_2024))
pilot_n <- sum(pilot_cohort$qualifies)
annual_n <- length(common_2023)
stopifnot(pilot_n > 1, annual_n > 1)
test_labels <- c(paste0("Interleaved 2023\n", pilot_n, " regular-use passers"),
  paste0("Chronological 2023\n", pilot_n, " regular-use passers"),
  paste0("Annual 2023 to 2024\n", annual_n, " common passers"))
plot_data <- bind_rows(
  read_intervals(paste0(args[[1]], "interleaved_intervals.csv"), test_labels[1],
    "se_scale", "degenerate_no_normal_theory_intervals"),
  read_intervals(paste0(args[[1]], "chronological_intervals.csv"), test_labels[2],
    "se_scale", "degenerate_no_normal_theory_intervals"),
  read_intervals(paste0(args[[2]], "conditional_intervals.csv"), test_labels[3],
    "variance_scale", "unavailable_degenerate_interval")) |>
  mutate(test = factor(test, levels = rev(test_labels)),
    quantity = factor(statistic, levels = statistics, labels = c("CPOE correlation (r)",
      "Completion correlation (r)", "Paired difference\nCPOE r - completion r")))
unavailable <- filter(plot_data, !interval_available) |>
  mutate(note = if_else(is.finite(estimate), "Interval unavailable", "Estimate and interval unavailable"))
caption <- paste(
  "Approximate conditional 95% game-jackknife working-model intervals; descriptive only.",
  "Serial dependence, persistent context and CP model-vintage uncertainty are not covered.",
  "PBP: nflverse/nflfastR (CC BY 4.0). nflfastR: Sebastian Carl and Ben Baldwin.", sep = "\n")
if (nrow(unavailable) > 0) caption <- paste(caption,
  "Open points have unavailable intervals; unavailable estimates are labelled explicitly.", sep = "\n")
figure <- ggplot(plot_data, aes(y = test)) +
  geom_blank(aes(x = 0)) +
  geom_vline(xintercept = 0, color = "grey55", linetype = "dashed", linewidth = 0.45) +
  geom_segment(data = filter(plot_data, interval_available),
    aes(x = lower, xend = upper, yend = test), linewidth = 0.85, color = "#304B63") +
  geom_point(data = filter(plot_data, interval_available), aes(x = estimate),
    size = 2.7, color = "#304B63") +
  geom_point(data = filter(plot_data, !interval_available, is.finite(estimate)),
    aes(x = estimate), shape = 1, size = 2.7, color = "#304B63") +
  geom_text(data = unavailable, aes(x = 0, label = note), vjust = -0.9, size = 3) +
  facet_grid(cols = vars(quantity), drop = FALSE) +
  scale_x_continuous(breaks = seq(-2, 2, by = 0.25), expand = expansion(mult = 0.08)) +
  scale_y_discrete(drop = FALSE, expand = expansion(add = 0.65)) +
  labs(title = "Split and annual associations: an evidence summary",
    subtitle = "Within-season splits and annual stability ask different questions and use different cohorts.",
    x = "Correlation or difference in correlations (dimensionless)", y = NULL, caption = caption) +
  theme_minimal(base_size = 12, base_family = "sans") +
  theme(plot.background = element_rect(fill = "white", color = NA),
    panel.grid.minor = element_blank(), panel.grid.major.y = element_blank(),
    panel.grid.major.x = element_line(color = "grey92", linewidth = 0.3),
    strip.text = element_text(size = 11, face = "bold", margin = margin(b = 10)),
    axis.text = element_text(color = "grey15"), axis.text.y = element_text(lineheight = 1.15),
    axis.title.x = element_text(margin = margin(t = 12)),
    plot.title = element_text(face = "bold", size = 17),
    plot.subtitle = element_text(size = 11, margin = margin(b = 18)),
    plot.caption = element_text(hjust = 0, size = 9, lineheight = 1.15, margin = margin(t = 18)),
    panel.spacing.x = grid::unit(1.2, "lines"), plot.margin = margin(16, 20, 16, 16))
ggsave(output, plot = figure, width = 12, height = 6.3, units = "in", dpi = 180,
       device = "png", bg = "white", limitsize = TRUE)
cat("Saved evidence-summary PNG:", normalizePath(output), "\n")
print(select(plot_data, test, statistic, estimate, lower, upper, status))
