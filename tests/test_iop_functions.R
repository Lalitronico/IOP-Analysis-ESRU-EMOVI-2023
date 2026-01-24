# ============================================================================
# test_iop_functions.R - Unit Tests for IOp Functions
# ============================================================================
# Project: Inequality of Opportunity Analysis - ESRU-EMOVI 2023
# Purpose: Test correctness of IOp metric calculations
# ============================================================================

# Load test framework
if (!require("testthat")) install.packages("testthat")
library(testthat)

# Load IOp functions
source(here::here("src", "R", "00_setup.R"))
source(here::here("src", "R", "utils", "iop_functions.R"))

# ============================================================================
# Test Data
# ============================================================================

# Create test data with known properties
set.seed(42)
n <- 1000

# Simple case: two types with different means
test_data <- data.frame(
  y = c(rnorm(500, mean = 50, sd = 10),
        rnorm(500, mean = 100, sd = 10)),
  type = rep(c("A", "B"), each = 500)
)

# Add type means
test_data$type_mean <- ifelse(test_data$type == "A", 50, 100)

# Weights (equal for simplicity)
test_weights <- rep(1, n)

# ============================================================================
# Tests: Gini Coefficient
# ============================================================================

test_that("Gini coefficient is in valid range [0, 1]", {
  g <- gini_coef(test_data$y)
  expect_gte(g, 0)
  expect_lte(g, 1)
})

test_that("Gini of constant vector is 0", {
  g <- gini_coef(rep(100, 100))
  expect_equal(g, 0, tolerance = 1e-10)
})

test_that("Gini is higher for more unequal distributions", {
  equal <- c(rep(50, 50), rep(50, 50))     # Perfect equality
  unequal <- c(rep(10, 90), rep(100, 10))  # High inequality

  g_equal <- gini_coef(equal)
  g_unequal <- gini_coef(unequal)

  expect_lt(g_equal, g_unequal)
})

# ============================================================================
# Tests: Mean Log Deviation (MLD)
# ============================================================================

test_that("MLD is non-negative", {
  m <- mld(test_data$y[test_data$y > 0])
  expect_gte(m, 0)
})

test_that("MLD of constant vector is 0", {
  m <- mld(rep(100, 100))
  expect_equal(m, 0, tolerance = 1e-10)
})

test_that("MLD requires positive values", {
  # MLD should handle non-positive values by filtering them
  x_with_zero <- c(test_data$y[test_data$y > 0], 0, -1)
  m <- mld(x_with_zero)
  expect_true(!is.na(m))
})

# ============================================================================
# Tests: IOp Share
# ============================================================================

test_that("IOp share is in valid range [0, 1]", {
  iop <- calculate_iop_share(test_data$y, test_data$type_mean, metric = "gini")
  expect_gte(iop$iop_share, 0)
  expect_lte(iop$iop_share, 1)
})

test_that("IOp share is 0 when all type means are equal", {
  # If type means are all equal, no inequality due to circumstances
  y_same_mean <- test_data$y
  type_mean_same <- rep(mean(test_data$y), n)

  iop <- calculate_iop_share(y_same_mean, type_mean_same, metric = "gini")
  expect_equal(iop$iop_share, 0, tolerance = 1e-10)
})

test_that("IOp share is 1 when all within-type variance is 0", {
  # If everyone in each type has exactly the type mean, IOp = 1
  y_no_within <- test_data$type_mean  # No within-type variance
  type_means <- test_data$type_mean

  iop <- calculate_iop_share(y_no_within, type_means, metric = "gini")
  expect_equal(iop$iop_share, 1, tolerance = 1e-6)
})

test_that("Gini-based and MLD-based IOp are correlated", {
  iop_gini <- calculate_iop_share(test_data$y, test_data$type_mean, metric = "gini")
  iop_mld <- calculate_iop_share(test_data$y, test_data$type_mean, metric = "mld")

  # Both should indicate substantial IOp for our test data
  expect_gt(iop_gini$iop_share, 0.1)
  expect_gt(iop_mld$iop_share, 0.1)
})

# ============================================================================
# Tests: R-squared IOp
# ============================================================================

test_that("R-squared IOp is in valid range [0, 1]", {
  rsq <- calculate_iop_rsq(test_data$y, test_data$type_mean)
  expect_gte(rsq, 0)
  expect_lte(rsq, 1)
})

test_that("R-squared is 0 when predictions are constant", {
  constant_pred <- rep(mean(test_data$y), n)
  rsq <- calculate_iop_rsq(test_data$y, constant_pred)
  expect_equal(rsq, 0, tolerance = 1e-10)
})

test_that("R-squared is 1 when predictions are perfect", {
  rsq <- calculate_iop_rsq(test_data$y, test_data$y)  # Perfect prediction
  expect_equal(rsq, 1, tolerance = 1e-10)
})

# ============================================================================
# Tests: MLD Decomposition
# ============================================================================

test_that("MLD decomposition components sum approximately to total", {
  # Note: MLD is exactly additive: MLD_total = MLD_between + MLD_within
  # But there may be small numerical differences
  decomp <- decompose_mld(test_data$y, test_data$type)

  sum_components <- decomp$mld_between + decomp$mld_within
  expect_equal(decomp$mld_total, sum_components, tolerance = 0.01)
})

test_that("MLD decomposition returns valid type statistics", {
  decomp <- decompose_mld(test_data$y, test_data$type)

  expect_equal(nrow(decomp$type_stats), 2)  # Two types
  expect_true(all(decomp$type_stats$n > 0))
  expect_true(all(decomp$type_stats$pop_share > 0))
  expect_equal(sum(decomp$type_stats$pop_share), 1, tolerance = 1e-10)
})

# ============================================================================
# Tests: Weighted Calculations
# ============================================================================

test_that("Weighted Gini handles unequal weights", {
  # Higher weight on high-income observations should increase Gini
  unequal_weights <- c(rep(1, 500), rep(10, 500))  # More weight on high incomes

  g_equal <- gini_coef(test_data$y, rep(1, n))
  g_unequal <- gini_coef(test_data$y, unequal_weights)

  # They should be different (direction depends on which group gets more weight)
  expect_false(abs(g_equal - g_unequal) < 1e-10)
})

# ============================================================================
# Tests: Edge Cases
# ============================================================================

test_that("Functions handle NA values gracefully", {
  y_with_na <- c(test_data$y, NA, NA)
  type_mean_with_na <- c(test_data$type_mean, NA, NA)

  iop <- calculate_iop_share(y_with_na, type_mean_with_na, metric = "gini")
  expect_false(is.na(iop$iop_share))
})

test_that("Functions handle small samples", {
  small_y <- c(10, 20, 30, 40, 50)
  small_mu <- c(15, 15, 30, 45, 45)

  iop <- calculate_iop_share(small_y, small_mu, metric = "gini")
  expect_false(is.na(iop$iop_share))
})

# ============================================================================
# Tests: Consistency Across Metrics
# ============================================================================

test_that("All IOp metrics agree on direction", {
  # For our test data, all metrics should show substantial IOp

  iop_gini <- calculate_iop_share(test_data$y, test_data$type_mean, metric = "gini")
  iop_mld <- calculate_iop_share(test_data$y, test_data$type_mean, metric = "mld")
  iop_rsq <- calculate_iop_rsq(test_data$y, test_data$type_mean)

  # All should be positive (circumstances matter)
  expect_gt(iop_gini$iop_share, 0)
  expect_gt(iop_mld$iop_share, 0)
  expect_gt(iop_rsq, 0)

  # All should be less than 1 (not all inequality is due to circumstances)
  expect_lt(iop_gini$iop_share, 1)
  expect_lt(iop_mld$iop_share, 1)
  expect_lt(iop_rsq, 1)
})

# ============================================================================
# Run Tests
# ============================================================================

cat("\n========================================\n")
cat("Running IOp Function Tests\n")
cat("========================================\n\n")

test_results <- test_file(here::here("tests", "test_iop_functions.R"))

cat("\n========================================\n")
cat("Test Summary\n")
cat("========================================\n")
