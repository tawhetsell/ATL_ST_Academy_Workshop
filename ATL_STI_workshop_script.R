# ATL Science & Technology Policy Workshop: Inferential Network Analysis on International Research Collaboration Networks in Artificial Intelligence from 2003-2023 ----

# author: "Travis Whetsell, PhD"
# date: May 20, 2026

# This workshop demonstrates network analysis techniques, from descriptive visualization to longitudinal inferential models including ERGM, TERGM, BTERGM, VERGM, and RSIENA. The data used in this workshop are derived from bibliometric records pulled from the Web of Science (WoS) XML database, which were used to generate international research collaboration (IRC) networks for 2003, 2008, 2013, 2018, and 2023. 

# The workshop excludes the data pre-processing steps used to pull data from the WoS XML database. This process relied on python scripting to transform XML paper records (articles and conference proceedings) into country-country matrices. The matrices are weighted, meaning the cell values represent the number of times two countries are listed together on a record. Network analysis of this type generally always features signficant name disambiguation problems, even something as standardized as a country name suffers from this problem. The data processing includes a python script to standardize names before sending to the matrices.   

# This script starts from the prepared country-by-country WoS collaboration matrices and builds the R-side workflow for visualization, descriptive statistics, ERGM-family models, TERGM/BTERGM models, and RSiena setup.

# The model sections are written as plain sequential RStudio code. After the data import steps, students can highlight and run one model block at a time instead of sourcing the entire file in one pass, as doing so would take a very long time to execute.

# If your R installation is missing any packages, install them before running the modeling sections: install.packages(c("tidyr", "dplyr", "ggplot2", "scales", "knitr", "network", "sna", "GGally", "patchwork", "RColorBrewer", "ergm", "ergm.count", "tergm", "btergm", "backbone", "RSiena"))

# Clear the existing R workspace so this lesson starts from known objects.
rm(list = ls())

# Before running this script, set your working directory to the folder where you downloaded the workshop files.
# The working directory should contain ATL_STI_workshop_script.R, IRC_network_data/, and country_covariate_data/.
# Example:
# setwd("path/to/ATL_ST_Academy_Workshop")
# mac Option + Command + C copies the folder path

# Load dplyr for readable data manipulation verbs such as select, mutate, and left_join.
library(dplyr)

# Load tidyr for completing country-year panels and reshaping data.
library(tidyr)

# Load ggplot2 for plot titles, themes, captions, and other figure formatting.
library(ggplot2)

# Load scales so node sizes can be mapped into useful plotting ranges.
library(scales)

# Load knitr so descriptive tables print nicely in RStudio.
library(knitr)

# Load network so R can create network objects for ERGM-family models.
library(network)

# Load sna for descriptive network statistics such as degree, density, transitivity, and components.
library(sna)

# Load GGally for ggnet2 network visualizations.
library(GGally)

# Load patchwork for combining several ggplot objects into one multi-panel figure.
library(patchwork)

# The script loads the packages above, but many calls still use package::function notation so students can see which package provides each tool.

# 1. Import Harmonized Matrices ----

# Network analysis in ERGM models requires specific data structures. We will be using matrix structure for the networks, rather than edgelist format. The matrices must be sorted identically along the columns and edges. The matrices are largely formatted already from the pre-processing during the WoS data parsing and extraction steps.

# Read the 2003 harmonized country-by-country collaboration matrix.
matrix_2003_csv <- read.csv("IRC_network_data/2003_ai_country_matrix_harmonized.csv", check.names = FALSE)
weighted_matrix_2003 <- as.matrix(matrix_2003_csv[, -1])
rownames(weighted_matrix_2003) <- matrix_2003_csv[[1]]
storage.mode(weighted_matrix_2003) <- "numeric"

# Read the 2008 harmonized country-by-country collaboration matrix.
matrix_2008_csv <- read.csv("IRC_network_data/2008_ai_country_matrix_harmonized.csv", check.names = FALSE)
weighted_matrix_2008 <- as.matrix(matrix_2008_csv[, -1])
rownames(weighted_matrix_2008) <- matrix_2008_csv[[1]]
storage.mode(weighted_matrix_2008) <- "numeric"

# Read the 2013 harmonized country-by-country collaboration matrix.
matrix_2013_csv <- read.csv("IRC_network_data/2013_ai_country_matrix_harmonized.csv", check.names = FALSE)
weighted_matrix_2013 <- as.matrix(matrix_2013_csv[, -1])
rownames(weighted_matrix_2013) <- matrix_2013_csv[[1]]
storage.mode(weighted_matrix_2013) <- "numeric"

# Read the 2018 harmonized country-by-country collaboration matrix.
matrix_2018_csv <- read.csv("IRC_network_data/2018_ai_country_matrix_harmonized.csv", check.names = FALSE)
weighted_matrix_2018 <- as.matrix(matrix_2018_csv[, -1])
rownames(weighted_matrix_2018) <- matrix_2018_csv[[1]]
storage.mode(weighted_matrix_2018) <- "numeric"

# Read the 2023 harmonized country-by-country collaboration matrix.
matrix_2023_csv <- read.csv("IRC_network_data/2023_ai_country_matrix_harmonized.csv", check.names = FALSE)
weighted_matrix_2023 <- as.matrix(matrix_2023_csv[, -1])
rownames(weighted_matrix_2023) <- matrix_2023_csv[[1]]
storage.mode(weighted_matrix_2023) <- "numeric"

# Store the shared ISO3 country roster from the first matrix. Notice that 3 letter ISO codes are chosen as the unique country identifier. This has become the standard in IRC network research. 
country_roster <- rownames(weighted_matrix_2003)

# Count the number of countries in the harmonized roster.
country_count <- length(country_roster)

# Store the five weighted matrices in a named list for the later workshop sections.
weighted_matrices <- list(
  "2003" = weighted_matrix_2003,
  "2008" = weighted_matrix_2008,
  "2013" = weighted_matrix_2013,
  "2018" = weighted_matrix_2018,
  "2023" = weighted_matrix_2023
)

# Print a short import check for students.
message("Imported ", length(weighted_matrices), " weighted matrices with ", country_count, " countries each.")

# 2. Import And Align Exogenous Covariates ----

# In network analysis, exogenous covariates are contained in separate files from the matrices, often referred to as 'node lists'. The node list corresponding to each year of data takes either regular, rectangular, format. Or in the case of RSIENA, the nodelist is contained in a wide-panel type format. Importantly, the node list identifiers (name of countries in this case) must match the matrix structure. In other words, the nodelist and matrix must have the same number of nodes and the same node identifies, sorted identically. Generally, there must also be no missing covariate data. 

# In this workshop, I am including some basic covariates which I have often found are significant antecedents to IRC tie formation across science and technology, the social sciences, and the arts and humanities. 

# If you are interested in prior work showing these effects, see Whetsell, Sidorova, and Yang (2025) and Whetsell (2023).

# Store the five workshop years in one vector so the covariates, descriptive statistics, and model sections all use the same time points.
workshop_years <- c(2003, 2008, 2013, 2018, 2023)

# The covariate data were pulled from API/package calls then saved as csv files in order to ensure stability in the workshop (sometimes APIs are down). The R script for pulling the data from the API/package calls is contained in ai_wos_irc_data_import_formatting.R. Using the API calls approach ensures that you are always working with the most current data. However, for replicability after publication, I recommend saving the files in the form used for the analysis presented in your articles. 

# Read GDP from the saved World Bank source snapshot.
world_bank_gdp <- read.csv(
  file.path("country_covariate_data", "world_bank_gdp_current_usd.csv"),
  stringsAsFactors = FALSE
)

# Read population from the saved World Bank source snapshot.
world_bank_population <- read.csv(
  file.path("country_covariate_data", "world_bank_population.csv"),
  stringsAsFactors = FALSE
)

# Read V-Dem polyarchy from the saved V-Dem source snapshot.
vdem_polyarchy <- read.csv(
  file.path("country_covariate_data", "vdem_polyarchy.csv"),
  stringsAsFactors = FALSE
)

# Keep the source snapshots data corresponding to the five workshop years.
world_bank_gdp <- world_bank_gdp %>%
  filter(year %in% workshop_years)

world_bank_population <- world_bank_population %>%
  filter(year %in% workshop_years)

vdem_polyarchy <- vdem_polyarchy %>%
  filter(year %in% workshop_years)

# Merge the World Bank GDP and population indicators into one country-year table. Even though not all models use this format, this will be a useful format for pulling from later. 
world_bank_covariates <- full_join(
  world_bank_gdp,
  world_bank_population,
  by = c("iso3", "year")
)

# Build a long country-year covariate table where each row is one country in one workshop year; ERGM, TERGM, and BTERGM later split this table by year so each yearly network object can carry that year's node attributes, while RSiena later reshapes the same information into actor-by-wave matrices.
node_covariates <- tidyr::expand_grid(iso3 = country_roster, year = workshop_years) %>%
  left_join(world_bank_covariates, by = c("iso3", "year")) %>%
  left_join(vdem_polyarchy, by = c("iso3", "year"))

# Convert raw scale variables into logged variables for modeling skewed country size effects.
node_covariates <- node_covariates %>%
  mutate(
    log_gdp = ifelse(!is.na(gdp_current_usd) & gdp_current_usd > 0, log(gdp_current_usd), NA_real_),
    log_population = ifelse(!is.na(population) & population > 0, log(population), NA_real_)
  )

# Print a compact missing-data check; this matters because ERGM-family models and RSiena generally cannot estimate effects for node covariates that contain missing values, so the next step keeps only countries with complete covariate data across all five waves.
covariate_missing_summary <- node_covariates %>%
  group_by(year) %>%
  summarise(
    missing_polyarchy = sum(is.na(polyarchy)),
    missing_gdp = sum(is.na(gdp_current_usd)),
    missing_population = sum(is.na(population)),
    .groups = "drop"
  )

# Show the missing-data summary in the console.
print(covariate_missing_summary)

# Identify countries with complete covariate data for every workshop year.
complete_country_roster <- node_covariates %>%
  group_by(iso3) %>%
  summarise(
    complete_covariates = all(!is.na(polyarchy) & !is.na(log_gdp) & !is.na(log_population)),
    complete_year_count = sum(!is.na(polyarchy) & !is.na(log_gdp) & !is.na(log_population)),
    .groups = "drop"
  ) %>%
  filter(complete_covariates) %>%
  arrange(iso3) %>%
  pull(iso3)

# Keep only countries with complete covariate data in all five years.
node_covariates <- node_covariates %>%
  filter(iso3 %in% complete_country_roster)

# Replace the original network roster with the complete-case roster.
country_roster <- complete_country_roster

# Update the country count after complete-case filtering.
country_count <- length(country_roster)

# Subset every weighted matrix to the complete-case country roster; this small anonymous function is applied once to each yearly matrix in the list.
weighted_matrices <- lapply(weighted_matrices, function(weighted_matrix) {
  weighted_matrix[country_roster, country_roster, drop = FALSE]
})

# Split the complete-case node covariate table into a list indexed by year.
covariates_by_year <- split(node_covariates, node_covariates$year)

# Reorder every yearly covariate table to match the complete-case matrix row and column order; this anonymous function is applied once to each yearly covariate table.
covariates_by_year <- lapply(covariates_by_year, function(year_data) {
  # Match the complete-case country roster exactly so vertex attributes align with matrix rows.
  year_data[match(country_roster, year_data$iso3), ]
})

# Keep the complete-case node covariate table as the object node_covariates for inspection.
node_covariates

# Confirm that the complete-case model covariates contain no missing values; these should all be zero before fitting models with polyarchy, GDP, or population as node covariates.
model_covariate_missing_summary <- node_covariates %>%
  group_by(year) %>%
  summarise(
    missing_model_polyarchy = sum(is.na(polyarchy)),
    missing_model_log_gdp = sum(is.na(log_gdp)),
    missing_model_log_population = sum(is.na(log_population)),
    .groups = "drop"
  )

# Show the complete-case model-covariate missing-data summary in the console.
print(model_covariate_missing_summary)

# Print the complete-case roster size for students.
message("Complete-case network roster contains ", country_count, " countries.")

# 3. Visualize Networks ----

# Make a network object, remove isolates, choose a Fruchterman-Reingold layout, and let ggnet2 handle the drawing. Here, I am removing isolates to make the network easier to look at. However, you may interested in understanding the isolates and so may choose to keep them in your visualiations. I typically use the network visualization layout called Fructerman-Reingold, which is based on the principle of gravity, and so generally produces spherical type visualizations. However, you may be interested in other types of layouts, such as Kamada-Kawai, hierarchical, or circular layouts designed with different principles in mind. We are using ggnet2 to visualize the network, but there are other options here too.

# You can choose different network properties and exogenous covariates as the basis for visualization characteristics. Here we will use node size = degree and node color = V-Dem polyarchy; edge width is held constant so the plot stays readable.

# Pick one year to visualize. Change this value and rerun the block to compare years. You can also produce large panels of networks to visualize, see Whetsell (2023).
plot_year <- 2023

# Pull the weighted matrix and matching covariates for the selected year.
plot_matrix <- weighted_matrices[[as.character(plot_year)]]
plot_covariates <- covariates_by_year[[as.character(plot_year)]]

# Keep only countries with at least one collaboration tie in this year. This is what ensures we have no network isolates represented in the visualization (again this is up to your research needs). 
active_countries <- rowSums(plot_matrix) > 0
plot_matrix <- plot_matrix[active_countries, active_countries, drop = FALSE]
plot_covariates <- plot_covariates[active_countries, ]

# Convert the weighted matrix to a binary matrix for the network layout; the binary matrix says which country pairs have any collaboration tie.
plot_binary_matrix <- (plot_matrix > 0) * 1

# Since ggnet2 doesn't take simple matrices, convert the binary matrix into a network object for ggnet2.
plot_network <- network::network(
  plot_binary_matrix,
  directed = FALSE,
  matrix.type = "adjacency"
)

# Create node colors from V-Dem polyarchy.
polyarchy_bins <- cut(plot_covariates$polyarchy, breaks = 9)
polyarchy_palette <- RColorBrewer::brewer.pal(9, "RdYlBu")
plot_node_color <- polyarchy_palette[as.numeric(polyarchy_bins)]

# Label only the largest countries by weighted degree.
plot_labels <- ifelse(
  rank(-rowSums(plot_matrix), ties.method = "first") <= 15,
  rownames(plot_matrix),
  ""
)

# Draw the network. ggnet2 uses Fruchterman-Reingold layout by default; 
set.seed(20260507 + plot_year)
GGally::ggnet2(
  plot_network,
  mode = "fruchtermanreingold",
  layout.par = list(vcount = network::network.size(plot_network)),
  size = "degree",
  alpha = 0.55,
  color = plot_node_color,
  label = plot_labels,
  label.size = 3,
  label.color = "white",
  edge.size = 0.35,
  edge.color = "gray45",
  edge.alpha = 0.45,
  legend.position = "none"
) +
  ggplot2::ggtitle(paste0("AI International Research Collaboration, ", plot_year)) +
  ggplot2::labs(caption = "Node size = degree; edge width is constant; color = V-Dem polyarchy") +
  ggplot2::theme_void() +
  ggplot2::theme(plot.title = ggplot2::element_text(hjust = 0.5), legend.position = "none") +
  ggplot2::guides(size = "none", color = "none", alpha = "none")

# The above code can be repeated for each year. Alternatively, you can produce a multi-panel visualization plot that shows all five years together. See Whetsell (2023) for an example of this type of multi-panel visualization. 

# It can be tricky to get the aesthetics right for a multi-panel network visualization, the nodes tend to overlap, and the labels are not clearly legible. In this figure the node sizes are scaled down, the gravitational repulsion is scaled up, and the labels are white instead of black in order to create contrast. There are also fewer labels.

years <- c(2003, 2008, 2013, 2018, 2023)

# This helper makes the same network plot for any requested year: it pulls that year's matrix and covariates, removes isolates for readability, builds a binary network object for the layout, assigns node color, node size, and labels, and returns one ggnet2 plot.
generate_network_plot <- function(yr) {
  plot_matrix <- weighted_matrices[[as.character(yr)]]
  plot_covariates <- covariates_by_year[[as.character(yr)]]

  active_countries <- rowSums(plot_matrix) > 0
  plot_matrix <- plot_matrix[active_countries, active_countries, drop = FALSE]
  plot_covariates <- plot_covariates[active_countries, ]

  plot_binary_matrix <- (plot_matrix > 0) * 1

  plot_network <- network::network(
    plot_binary_matrix,
    directed = FALSE,
    matrix.type = "adjacency"
  )

  polyarchy_bins <- cut(plot_covariates$polyarchy, breaks = 9)
  polyarchy_palette <- RColorBrewer::brewer.pal(9, "RdYlBu")
  plot_node_color <- polyarchy_palette[as.numeric(polyarchy_bins)]

  plot_labels <- ifelse(
    rank(-rowSums(plot_matrix), ties.method = "first") <= 10,
    rownames(plot_matrix),
    ""
  )

  node_count <- network::network.size(plot_network)

  set.seed(20260507 + yr)

  GGally::ggnet2(
    plot_network,
    mode = "fruchtermanreingold",
    layout.par = list(
      vcount = node_count,
      area = node_count^2.8,
      repulse.rad = node_count^3
    ),
    size = "degree",
    max_size = 4.5,
    alpha = 0.55,
    color = plot_node_color,
    label = plot_labels,
    label.size = 2.6,
    label.color = "white",
    edge.size = 0.35,
    edge.color = "gray45",
    edge.alpha = 0.45,
    legend.position = "none"
  ) +
    ggplot2::ggtitle(as.character(yr)) +
    ggplot2::theme_void() +
    ggplot2::theme(
      plot.title = ggplot2::element_text(hjust = 0.5, size = 12, face = "bold"),
      plot.margin = ggplot2::margin(t = 8, r = 4, b = 4, l = 4),
      legend.position = "none"
    ) +
    ggplot2::guides(size = "none", color = "none", alpha = "none")
}

network_plots <- lapply(years, generate_network_plot)

combined_network_panel <- patchwork::wrap_plots(network_plots, ncol = 3, nrow = 2) +
  patchwork::plot_annotation(
    title = "Evolution of AI International Research Collaboration Networks, 2003-2023",
    caption = "Node size = degree; edge width is constant; color = V-Dem polyarchy",
    theme = ggplot2::theme(
      plot.title = ggplot2::element_text(hjust = 0.5, size = 14, face = "bold", margin = ggplot2::margin(b = 10)),
      plot.caption = ggplot2::element_text(hjust = 0.5, size = 9.5, color = "gray35", margin = ggplot2::margin(t = 10))
    )
  )

print(combined_network_panel)

# Optional save
# ggsave(
#   "AI_collaboration_networks_2003_2023.png",
#   combined_network_panel,
#   width = 11,
#   height = 7,
#   dpi = 300,
#   bg = "white"
# )

# 4. Descriptive Network Statistics ----

# After visualizing a network I typically include a table of descriptive statistics corresponding to the network. If I have multiple years of networks or multiple different types of networks, I will typically also show those networks and include descriptive statistics in a single corresponding table. I usually include basic descriptive statistics such as number of nodes, number of edges, total weight (if weighted network), average degree, density, and something for transitivity such as clustering coefficient. Other metrics might include things like modularity, number of components, etc. See Wagner, Horlings, Whetsell, Mattsson, Nordqvist (2015) and Wagner, Whetsell, Leydesdorff (2017).

# Use existing statnet/sna tools for common network summaries. The only manual calculation below is total edge weight, because that is the sum of collaboration counts rather than a binary network statistic.

# 2003 network statistics.
weighted_matrix_2003 <- weighted_matrices[["2003"]]
binary_matrix_2003 <- (weighted_matrix_2003 > 0) * 1
full_network_2003 <- network::network(binary_matrix_2003, directed = FALSE, matrix.type = "adjacency")

network_statistics_2003 <- data.frame(
  year = 2003,
  nodes = network::network.size(full_network_2003),
  edges = network::network.edgecount(full_network_2003),
  number_components = sna::components(full_network_2003, connected = "weak"),
  total_edge_weight = sum(weighted_matrix_2003[upper.tri(weighted_matrix_2003)]),
  network_density = as.numeric(sna::gden(full_network_2003, mode = "graph")),
  average_degree = mean(sna::degree(full_network_2003, gmode = "graph")),
  average_weighted_degree = mean(sna::degree(weighted_matrix_2003, gmode = "graph", ignore.eval = FALSE)),
  global_transitivity = as.numeric(sna::gtrans(full_network_2003, mode = "graph"))
)

# 2008 network statistics.
weighted_matrix_2008 <- weighted_matrices[["2008"]]
binary_matrix_2008 <- (weighted_matrix_2008 > 0) * 1
full_network_2008 <- network::network(binary_matrix_2008, directed = FALSE, matrix.type = "adjacency")

network_statistics_2008 <- data.frame(
  year = 2008,
  nodes = network::network.size(full_network_2008),
  edges = network::network.edgecount(full_network_2008),
  number_components = sna::components(full_network_2008, connected = "weak"),
  total_edge_weight = sum(weighted_matrix_2008[upper.tri(weighted_matrix_2008)]),
  network_density = as.numeric(sna::gden(full_network_2008, mode = "graph")),
  average_degree = mean(sna::degree(full_network_2008, gmode = "graph")),
  average_weighted_degree = mean(sna::degree(weighted_matrix_2008, gmode = "graph", ignore.eval = FALSE)),
  global_transitivity = as.numeric(sna::gtrans(full_network_2008, mode = "graph"))
)

# 2013 network statistics.
weighted_matrix_2013 <- weighted_matrices[["2013"]]
binary_matrix_2013 <- (weighted_matrix_2013 > 0) * 1
full_network_2013 <- network::network(binary_matrix_2013, directed = FALSE, matrix.type = "adjacency")

network_statistics_2013 <- data.frame(
  year = 2013,
  nodes = network::network.size(full_network_2013),
  edges = network::network.edgecount(full_network_2013),
  number_components = sna::components(full_network_2013, connected = "weak"),
  total_edge_weight = sum(weighted_matrix_2013[upper.tri(weighted_matrix_2013)]),
  network_density = as.numeric(sna::gden(full_network_2013, mode = "graph")),
  average_degree = mean(sna::degree(full_network_2013, gmode = "graph")),
  average_weighted_degree = mean(sna::degree(weighted_matrix_2013, gmode = "graph", ignore.eval = FALSE)),
  global_transitivity = as.numeric(sna::gtrans(full_network_2013, mode = "graph"))
)

# 2018 network statistics.
weighted_matrix_2018 <- weighted_matrices[["2018"]]
binary_matrix_2018 <- (weighted_matrix_2018 > 0) * 1
full_network_2018 <- network::network(binary_matrix_2018, directed = FALSE, matrix.type = "adjacency")

network_statistics_2018 <- data.frame(
  year = 2018,
  nodes = network::network.size(full_network_2018),
  edges = network::network.edgecount(full_network_2018),
  number_components = sna::components(full_network_2018, connected = "weak"),
  total_edge_weight = sum(weighted_matrix_2018[upper.tri(weighted_matrix_2018)]),
  network_density = as.numeric(sna::gden(full_network_2018, mode = "graph")),
  average_degree = mean(sna::degree(full_network_2018, gmode = "graph")),
  average_weighted_degree = mean(sna::degree(weighted_matrix_2018, gmode = "graph", ignore.eval = FALSE)),
  global_transitivity = as.numeric(sna::gtrans(full_network_2018, mode = "graph"))
)

# 2023 network statistics.
weighted_matrix_2023 <- weighted_matrices[["2023"]]
binary_matrix_2023 <- (weighted_matrix_2023 > 0) * 1
full_network_2023 <- network::network(binary_matrix_2023, directed = FALSE, matrix.type = "adjacency")

network_statistics_2023 <- data.frame(
  year = 2023,
  nodes = network::network.size(full_network_2023),
  edges = network::network.edgecount(full_network_2023),
  number_components = sna::components(full_network_2023, connected = "weak"),
  total_edge_weight = sum(weighted_matrix_2023[upper.tri(weighted_matrix_2023)]),
  network_density = as.numeric(sna::gden(full_network_2023, mode = "graph")),
  average_degree = mean(sna::degree(full_network_2023, gmode = "graph")),
  average_weighted_degree = mean(sna::degree(weighted_matrix_2023, gmode = "graph", ignore.eval = FALSE)),
  global_transitivity = as.numeric(sna::gtrans(full_network_2023, mode = "graph"))
)

# Stack the five yearly rows into one long table.
network_statistics_long <- bind_rows(
  network_statistics_2003,
  network_statistics_2008,
  network_statistics_2013,
  network_statistics_2018,
  network_statistics_2023
)

# Convert the descriptive statistics into a table with years as columns and statistics as rows.
network_statistics_table <- network_statistics_long %>%
  tidyr::pivot_longer(-year, names_to = "statistic", values_to = "value") %>%
  mutate(value = round(value, 3)) %>%
  tidyr::pivot_wider(names_from = year, values_from = value)

# Print the descriptive statistics table.
print(knitr::kable(network_statistics_table, align = "lccccc"))

# 5. Weighted-To-Binary Backbone Conversion ----

# We use the backbone package to convert the dense weighted collaboration matrices into sparser binary networks that are easier to model with standard binary ERGMs, TERGMs, and BTERGMs. The disparity filter compares each edge weight to the distribution of weights around its incident nodes and keeps ties that are unusually strong relative to those local weighted-degree profiles, so a tie can be retained even if its raw count is not globally large and a high-count tie can be dropped if it is not unusually important for either endpoint. The alpha level controls how selective the filter is: smaller alpha values produce stricter, sparser backbones, while larger values retain more ties; results can also change depending on the backbone model, whether the network is treated as signed or unsigned, whether the output keeps only the backbone or preserves additional values, and whether the researcher wants a conservative statistical filter or a more inclusive exploratory simplification of the weighted network.

# Load backbone so R can apply the disparity filter to weighted networks.
library(backbone)

# Apply the disparity filter to the 2003 weighted matrix and convert the result to a binary matrix.
binary_backbone_2003 <- backbone::backbone_from_weighted(
  weighted_matrices[["2003"]],
  model = "disparity",
  alpha = 0.05,
  signed = FALSE,
  narrative = FALSE,
  backbone_only = TRUE
)

# Apply the disparity filter to the 2008 weighted matrix and convert the result to a binary matrix.
binary_backbone_2008 <- backbone::backbone_from_weighted(
  weighted_matrices[["2008"]],
  model = "disparity",
  alpha = 0.05,
  signed = FALSE,
  narrative = FALSE,
  backbone_only = TRUE
)

# Apply the disparity filter to the 2013 weighted matrix and convert the result to a binary matrix.
binary_backbone_2013 <- backbone::backbone_from_weighted(
  weighted_matrices[["2013"]],
  model = "disparity",
  alpha = 0.05,
  signed = FALSE,
  narrative = FALSE,
  backbone_only = TRUE
)

# Apply the disparity filter to the 2018 weighted matrix and convert the result to a binary matrix.
binary_backbone_2018 <- backbone::backbone_from_weighted(
  weighted_matrices[["2018"]],
  model = "disparity",
  alpha = 0.05,
  signed = FALSE,
  narrative = FALSE,
  backbone_only = TRUE
)

# Apply the disparity filter to the 2023 weighted matrix and convert the result to a binary matrix.
binary_backbone_2023 <- backbone::backbone_from_weighted(
  weighted_matrices[["2023"]],
  model = "disparity",
  alpha = 0.05,
  signed = FALSE,
  narrative = FALSE,
  backbone_only = TRUE
)

# Store the binary backbone matrices in one named list.
binary_backbone_matrices <- list(
  "2003" = binary_backbone_2003,
  "2008" = binary_backbone_2008,
  "2013" = binary_backbone_2013,
  "2018" = binary_backbone_2018,
  "2023" = binary_backbone_2023
)

# Create a binary network object for 2003.
binary_network_2003 <- network::network(binary_backbone_2003, directed = FALSE, matrix.type = "adjacency")
network::set.vertex.attribute(binary_network_2003, "iso3", covariates_by_year[["2003"]]$iso3)
network::set.vertex.attribute(binary_network_2003, "polyarchy", covariates_by_year[["2003"]]$polyarchy)
network::set.vertex.attribute(binary_network_2003, "log_gdp", covariates_by_year[["2003"]]$log_gdp)
network::set.vertex.attribute(binary_network_2003, "log_population", covariates_by_year[["2003"]]$log_population)

# Create a binary network object for 2008.
binary_network_2008 <- network::network(binary_backbone_2008, directed = FALSE, matrix.type = "adjacency")
network::set.vertex.attribute(binary_network_2008, "iso3", covariates_by_year[["2008"]]$iso3)
network::set.vertex.attribute(binary_network_2008, "polyarchy", covariates_by_year[["2008"]]$polyarchy)
network::set.vertex.attribute(binary_network_2008, "log_gdp", covariates_by_year[["2008"]]$log_gdp)
network::set.vertex.attribute(binary_network_2008, "log_population", covariates_by_year[["2008"]]$log_population)

# Create a binary network object for 2013.
binary_network_2013 <- network::network(binary_backbone_2013, directed = FALSE, matrix.type = "adjacency")
network::set.vertex.attribute(binary_network_2013, "iso3", covariates_by_year[["2013"]]$iso3)
network::set.vertex.attribute(binary_network_2013, "polyarchy", covariates_by_year[["2013"]]$polyarchy)
network::set.vertex.attribute(binary_network_2013, "log_gdp", covariates_by_year[["2013"]]$log_gdp)
network::set.vertex.attribute(binary_network_2013, "log_population", covariates_by_year[["2013"]]$log_population)

# Create a binary network object for 2018.
binary_network_2018 <- network::network(binary_backbone_2018, directed = FALSE, matrix.type = "adjacency")
network::set.vertex.attribute(binary_network_2018, "iso3", covariates_by_year[["2018"]]$iso3)
network::set.vertex.attribute(binary_network_2018, "polyarchy", covariates_by_year[["2018"]]$polyarchy)
network::set.vertex.attribute(binary_network_2018, "log_gdp", covariates_by_year[["2018"]]$log_gdp)
network::set.vertex.attribute(binary_network_2018, "log_population", covariates_by_year[["2018"]]$log_population)

# Create a binary network object for 2023.
binary_network_2023 <- network::network(binary_backbone_2023, directed = FALSE, matrix.type = "adjacency")
network::set.vertex.attribute(binary_network_2023, "iso3", covariates_by_year[["2023"]]$iso3)
network::set.vertex.attribute(binary_network_2023, "polyarchy", covariates_by_year[["2023"]]$polyarchy)
network::set.vertex.attribute(binary_network_2023, "log_gdp", covariates_by_year[["2023"]]$log_gdp)
network::set.vertex.attribute(binary_network_2023, "log_population", covariates_by_year[["2023"]]$log_population)

# Store the binary network objects in a named list for panel models. This will be used in the ERGM family models. The RSIENA models will take a different approach. 
binary_networks <- list(
  "2003" = binary_network_2003,
  "2008" = binary_network_2008,
  "2013" = binary_network_2013,
  "2018" = binary_network_2018,
  "2023" = binary_network_2023
)

# 6. Binary ERGMs On Backbone Networks ----

# Use a binary ERGM when the research question is about the presence or absence of ties in one observed network, here whether two countries have a statistically important collaboration tie after the weighted network has been reduced to a sparse backbone. The model estimates how structural features such as density, degree concentration, and transitivity, along with node covariates and dyadic differences, change the log-odds of a tie; in the summary output, positive coefficients mean the corresponding feature is associated with a higher probability of observing a tie, while negative coefficients mean the feature is associated with a lower probability. The network must be a network-package object with binary ties and node attributes attached to the vertices using matching country order; convergence can become difficult when the network is very dense or very sparse, when structural terms are highly collinear, when covariates contain missing values, when the model includes too many endogenous terms for the observed network, or when the fitted model drifts toward degeneracy where simulated networks look nothing like the observed network.

# Load ergm so R can estimate exponential-family random graph models.
library(ergm)

# Interpret endogenous ERGM terms as conditional structural tendencies, not as ordinary independent regression effects. The edges term is the baseline tendency for ties, gwdegree captures the degree distribution and is often non-intuitive because, once edges are controlled, a negative gwdegree coefficient can indicate degree concentration or centralization around highly connected nodes, while a positive coefficient can indicate a less centralized degree distribution. The gwesp term is a transitivity or shared-partner term: positive values mean ties are more likely when two countries share collaboration partners, which corresponds to triadic closure or clustering. Actor covariate terms such as nodecov("polyarchy") describe whether countries with higher values of a covariate tend to have more ties, while absdiff terms are homophily terms: negative coefficients mean countries with similar values are more likely to be tied, and positive coefficients mean countries with different values are more likely to be tied.

# Estimate the 2003 binary ERGM. Use 1000 sample size for workshop speed; increase this for degeneracy checks and publication-ready models. Use 5000 as a moderate workshop burn-in; increase this when checking final model stability. Parallel estimation can speed up MCMC, but set this no higher than the number of cores available on your machine. PSOCK is a portable parallel backend that works across operating systems, though it may be slower than multicore on macOS/Linux. In the past I have noticed that speed gains top out after 8 cores. 
binary_ergm_2003 <- ergm::ergm(
  binary_network_2003 ~
    edges +
    gwdegree(0.50, fixed = TRUE) +
    gwesp(0.50, fixed = TRUE) +
    nodecov("polyarchy") +
    nodecov("log_gdp") +
    nodecov("log_population") +
    absdiff("polyarchy") +
    absdiff("log_gdp") +
    absdiff("log_population"),
  control = ergm::control.ergm(
    MCMC.samplesize = 1000,
    MCMC.burnin = 5000,
    MCMLE.maxit = 20,
    parallel = 8,
    parallel.type = "PSOCK"
  )
)

# Show the 2003 binary ERGM results.
summary(binary_ergm_2003)

# Estimate the 2008 binary ERGM.
binary_ergm_2008 <- ergm::ergm(
  binary_network_2008 ~
    edges +
    gwdegree(0.50, fixed = TRUE) +
    gwesp(0.50, fixed = TRUE) +
    nodecov("polyarchy") +
    nodecov("log_gdp") +
    nodecov("log_population") +
    absdiff("polyarchy") +
    absdiff("log_gdp") +
    absdiff("log_population"),
  control = ergm::control.ergm(
    MCMC.samplesize = 1000,
    MCMC.burnin = 5000,
    MCMLE.maxit = 20,
    parallel = 8,
    parallel.type = "PSOCK"
  )
)

# Show the 2008 binary ERGM results.
summary(binary_ergm_2008)

# Estimate the 2013 binary ERGM.
binary_ergm_2013 <- ergm::ergm(
  binary_network_2013 ~
    edges +
    gwdegree(0.50, fixed = TRUE) +
    gwesp(0.50, fixed = TRUE) +
    nodecov("polyarchy") +
    nodecov("log_gdp") +
    nodecov("log_population") +
    absdiff("polyarchy") +
    absdiff("log_gdp") +
    absdiff("log_population"),
  control = ergm::control.ergm(
    MCMC.samplesize = 1000,
    MCMC.burnin = 5000,
    MCMLE.maxit = 20,
    parallel = 8,
    parallel.type = "PSOCK"
  )
)

# Show the 2013 binary ERGM results.
summary(binary_ergm_2013)

# Estimate the 2018 binary ERGM.
binary_ergm_2018 <- ergm::ergm(
  binary_network_2018 ~
    edges +
    gwdegree(0.50, fixed = TRUE) +
    gwesp(0.50, fixed = TRUE) +
    nodecov("polyarchy") +
    nodecov("log_gdp") +
    nodecov("log_population") +
    absdiff("polyarchy") +
    absdiff("log_gdp") +
    absdiff("log_population"),
  control = ergm::control.ergm(
    MCMC.samplesize = 1000,
    MCMC.burnin = 5000,
    MCMLE.maxit = 20,
    parallel = 8,
    parallel.type = "PSOCK"
  )
)

# Show the 2018 binary ERGM results.
summary(binary_ergm_2018)

# Estimate the 2023 binary ERGM.
binary_ergm_2023 <- ergm::ergm(
  binary_network_2023 ~
    edges +
    gwdegree(0.50, fixed = TRUE) +
    gwesp(0.50, fixed = TRUE) +
    nodecov("polyarchy") +
    nodecov("log_gdp") +
    nodecov("log_population") +
    absdiff("polyarchy") +
    absdiff("log_gdp") +
    absdiff("log_population"),
  control = ergm::control.ergm(
    MCMC.samplesize = 1000,
    MCMC.burnin = 5000,
    MCMLE.maxit = 20,
    parallel = 8,
    parallel.type = "PSOCK"
  )
)

# Show the 2023 binary ERGM results.
summary(binary_ergm_2023)

# Use ERGM goodness-of-fit plots to compare the observed network to networks simulated from the fitted model. The black observed statistic should generally fall inside or near the simulated distribution shown in the plots; if the observed network is far outside the simulated envelope for degree distribution, shared partners, geodesic distances, or other diagnostics, the model is missing important structure even if individual coefficients look statistically significant. GOF plots are therefore a model adequacy check rather than a coefficient table: they ask whether the fitted model can reproduce important features of the network it was meant to explain.

# Compute goodness-of-fit diagnostics for the 2003 binary ERGM.
binary_ergm_gof_2003 <- ergm::gof(binary_ergm_2003)

# Plot goodness-of-fit diagnostics for the 2003 binary ERGM.
par(mfrow = c(1, 4), mar = c(4, 4, 3, 1))
plot(binary_ergm_gof_2003, main = "Binary ERGM GOF, 2003")
par(mfrow = c(1, 1))

# Compute goodness-of-fit diagnostics for the 2008 binary ERGM.
binary_ergm_gof_2008 <- ergm::gof(binary_ergm_2008)

# Plot goodness-of-fit diagnostics for the 2008 binary ERGM.
par(mfrow = c(1, 4), mar = c(4, 4, 3, 1))
plot(binary_ergm_gof_2008, main = "Binary ERGM GOF, 2008")
par(mfrow = c(1, 1))

# Compute goodness-of-fit diagnostics for the 2013 binary ERGM.
binary_ergm_gof_2013 <- ergm::gof(binary_ergm_2013)

# Plot goodness-of-fit diagnostics for the 2013 binary ERGM.
par(mfrow = c(1, 4), mar = c(4, 4, 3, 1))
plot(binary_ergm_gof_2013, main = "Binary ERGM GOF, 2013")
par(mfrow = c(1, 1))

# Compute goodness-of-fit diagnostics for the 2018 binary ERGM.
binary_ergm_gof_2018 <- ergm::gof(binary_ergm_2018)

# Plot goodness-of-fit diagnostics for the 2018 binary ERGM.
par(mfrow = c(1, 4), mar = c(4, 4, 3, 1))
plot(binary_ergm_gof_2018, main = "Binary ERGM GOF, 2018")
par(mfrow = c(1, 1))

# Compute goodness-of-fit diagnostics for the 2023 binary ERGM.
binary_ergm_gof_2023 <- ergm::gof(binary_ergm_2023)

# Plot goodness-of-fit diagnostics for the 2023 binary ERGM.
par(mfrow = c(1, 4), mar = c(4, 4, 3, 1))
plot(binary_ergm_gof_2023, main = "Binary ERGM GOF, 2023")
par(mfrow = c(1, 1))

# The 2003 model fits the observed network structure more cleanly. By 2023, the collaboration network is denser and more structurally differentiated, so the ERGM captures the main degree and distance patterns but does less well reproducing local clustering around shared partners.

# 7. TERGM Panel Model ----

# Use a TERGM when the research question is about tie formation, persistence, or dissolution across an ordered panel of networks observed at multiple time points. The model treats the sequence of networks as a dependent temporal process and estimates how structural features and covariates predict changes in ties from one wave to the next; in the summary output, coefficients are interpreted like ERGM coefficients but conditional on the temporal specification, so formation terms refer to tie creation and persistence or dissolution terms refer to tie survival or disappearance. The data should be a list of network-package objects with the same actors in the same order at each wave and year-specific vertex attributes attached before estimation; convergence problems are more likely when waves are far apart in time, networks change too little or too much between waves, structural terms are too ambitious for the number of waves, covariates are missing or misaligned across years, or the formation and persistence/dissolution processes are not well separated by the observed panel.

# Load tergm so R can estimate temporal ERGMs for network panels.
library(tergm)

# Estimate a standard TERGM with formation and persistence components. The formation side models ties that appear between observed network years.The persistence side models ties that survive between observed network years. This is the direct replacement for the old stergm() dissolution formula.Use 5000 as a moderate workshop burn-in; increase this when checking final model stability. Put ERGM MCMC settings inside CMLE.ergm because tergm passes CMLE fitting through ergm. Use 1000 for workshop speed; increase this for degeneracy checks and publication-ready models.
tergm_form_persist_fit <- tergm::tergm(
  binary_networks ~
    Form(
      ~ edges +
        gwdegree(0.50, fixed = TRUE) +
        gwesp(0.50, fixed = TRUE) +
        nodecov("polyarchy") +
        nodecov("log_gdp") +
        nodecov("log_population") +
        absdiff("polyarchy") +
        absdiff("log_gdp") +
        absdiff("log_population")
    ) +
    Persist(
      ~ edges +
        gwdegree(0.50, fixed = TRUE) +
        gwesp(0.50, fixed = TRUE) +
        nodecov("polyarchy") +
        nodecov("log_gdp") +
        nodecov("log_population") +
        absdiff("polyarchy") +
        absdiff("log_gdp") +
        absdiff("log_population")
    ),
  estimate = "CMLE",
  control = tergm::control.tergm(
    CMLE.MCMC.burnin = 5000,
    CMLE.MCMC.interval = 1000,
    CMLE.ergm = ergm::control.ergm(
      MCMC.samplesize = 1000
    ),
    parallel = 8,
    parallel.type = "PSOCK"
  )
)

# Show the formation-persistence TERGM results.
summary(tergm_form_persist_fit)

# Compute goodness-of-fit diagnostics for the formation-persistence TERGM.
tergm_form_persist_gof <- ergm::gof(tergm_form_persist_fit)

# Plot goodness-of-fit diagnostics for the formation-persistence TERGM. The TERGM GOF suggests the model reproduces the main observed network features reasonably well: degree distribution, shared-partner structure, and geodesic distances. That does not prove the model is “true,” but it gives us more confidence that the fitted temporal model is not generating networks that look totally unlike the observed IRC panel.
par(mfrow = c(1, 4), mar = c(4, 4, 3, 1))
plot(tergm_form_persist_gof, main = "Formation-Persistence TERGM GOF")
par(mfrow = c(1, 1))


# 8. BTERGM Panel Model ----

# Use a BTERGM when the research question is about repeated network observations but the inferential strategy should rely on bootstrapped uncertainty rather than the TERGM CMLE workflow. Despite the name, btergm is not Bayesian; it estimates temporal ERGM-style effects and uses bootstrap replications to approximate uncertainty, which can be attractive when CMLE-based TERGM fitting is difficult, when the researcher wants a more flexible resampling-based uncertainty estimate, or when the focus is on pooled temporal dependence rather than explicit formation and dissolution equations. In the summary output, coefficient signs are interpreted like ERGM effects on tie probability, while the bootstrap confidence intervals and p-values summarize how stable those effects are across resampled temporal information. The data format is also a list of network-package objects with the same actors and aligned vertex attributes across waves; difficulties can arise when there are too few time points for stable bootstrapping, when networks are extremely sparse or dense, when covariates are missing or not attached consistently, when structural terms create degeneracy-like simulated networks, or when parallel processing behaves differently across operating systems and package versions.

# Load btergm after the ERGM GOF plots because btergm registers its own plot.gof method, which can interfere with re-plotting ERGM GOF objects later in the same R session.

# Load btergm so R can estimate bootstrapped temporal ERGMs.
library(btergm)

# Estimate a BTERGM with the same approximate structural and exogenous terms. Use 1000 bootstrap replications for workshop speed; increase this for publication-ready uncertainty estimates.Use multicore on macOS/Linux; snow can fail in btergm 1.11.1 with object 'xsparse' not found.
btergm_fit <- btergm::btergm(
  binary_networks ~
    edges +
    gwdegree(0.50, fixed = TRUE) +
    gwesp(0.50, fixed = TRUE) +
    nodecov("polyarchy") +
    nodecov("log_gdp") +
    nodecov("log_population") +
    absdiff("polyarchy") +
    absdiff("log_gdp") +
    absdiff("log_population"),
  R = 1000,
  parallel = "multicore",
  ncpus = 8
)

# Show the BTERGM results.
summary(btergm_fit)

# Goodness-of-fit plots for BTERGM. The model reproduces degree and shared-partner structure reasonably well, but may still miss some higher-level community structure. GOF plots are not pass/fail tests; they show which network features the fitted model can and cannot reproduce.
btergm_gof <- btergm::gof(btergm_fit)
plot(btergm_gof)

# 9. RSiena Setup And Model ----

# Use RSiena when the research question is about actor-oriented network evolution, where actors are modeled as making small changes to outgoing ties over time in response to structural tendencies and actor covariates. Unlike ERGM-family models that condition on whole-network configurations, RSiena simulates a sequence of micro-steps between observed waves and estimates rate and effect parameters; in the summary output, positive effects mean the simulated actors tend to create or maintain ties that increase that statistic, and convergence is judged not only by significance but also by whether convergence t-ratios are close to zero. RSiena requires a wide actor-by-actor-by-wave network array and actor-by-wave covariate matrices, with actors in exactly the same order across all objects; convergence can be difficult when networks are undirected but modeled through directed data structures, waves are too far apart or show abrupt change, the model includes too many effects for the number of waves, actor covariates are missing or poorly scaled, or endogenous effects such as degree and transitive closure create unstable simulations.

# Load RSiena so R can build stochastic actor-oriented model objects.
library(RSiena)

# Before conducting RSIENA analysis, researchers often perform a Jaccard analysis to see how much change there is between waves of data. We are looking for a number above 0.2 or 0.3 to ensure there is enough variability across waves.
jaccard_2003_2008 <- sum(binary_backbone_2003 == 1 & binary_backbone_2008 == 1) /
  sum(binary_backbone_2003 == 1 | binary_backbone_2008 == 1)

jaccard_2008_2013 <- sum(binary_backbone_2008 == 1 & binary_backbone_2013 == 1) /
  sum(binary_backbone_2008 == 1 | binary_backbone_2013 == 1)

jaccard_2013_2018 <- sum(binary_backbone_2013 == 1 & binary_backbone_2018 == 1) /
  sum(binary_backbone_2013 == 1 | binary_backbone_2018 == 1)

jaccard_2018_2023 <- sum(binary_backbone_2018 == 1 & binary_backbone_2023 == 1) /
  sum(binary_backbone_2018 == 1 | binary_backbone_2023 == 1)

jaccard_2003_2008
jaccard_2008_2013
jaccard_2013_2018
jaccard_2018_2023

# Build a three-dimensional array with dimensions country x country x year.
rsiena_network_array <- array(
  data = NA_real_,
  dim = c(country_count, country_count, length(workshop_years)),
  dimnames = list(country_roster, country_roster, workshop_years)
)

# Fill the RSiena network array with the 2003 binary backbone matrix.
rsiena_network_array[, , "2003"] <- binary_backbone_2003

# Fill the RSiena network array with the 2008 binary backbone matrix.
rsiena_network_array[, , "2008"] <- binary_backbone_2008

# Fill the RSiena network array with the 2013 binary backbone matrix.
rsiena_network_array[, , "2013"] <- binary_backbone_2013

# Fill the RSiena network array with the 2018 binary backbone matrix.
rsiena_network_array[, , "2018"] <- binary_backbone_2018

# Fill the RSiena network array with the 2023 binary backbone matrix.
rsiena_network_array[, , "2023"] <- binary_backbone_2023

# This helper converts one node covariate from the long country-year table into the wide actor-by-wave matrix RSiena expects: rows are countries, columns are workshop years, and values are ordered to match the network array.
make_rsiena_covariate_matrix <- function(variable_name) {
  # Pull the requested variable in the exact country and year order needed by RSiena; sapply repeats the same extraction once for each workshop year.
  covariate_matrix <- sapply(workshop_years, function(year) {
    # Select the covariate table for this year.
    year_covariates <- covariates_by_year[[as.character(year)]]

    # Return the requested variable as a numeric vector.
    as.numeric(year_covariates[[variable_name]])
  })

  # Set country row names for readability.
  rownames(covariate_matrix) <- country_roster

  # Set year column names for readability.
  colnames(covariate_matrix) <- workshop_years

  # Return the actor-by-wave covariate matrix.
  covariate_matrix
}

# Create the RSiena actor covariate matrix for polyarchy.
rsiena_polyarchy_matrix <- make_rsiena_covariate_matrix("polyarchy")

# Create the RSiena actor covariate matrix for logged GDP.
rsiena_gdp_matrix <- make_rsiena_covariate_matrix("log_gdp")

# Create the RSiena actor covariate matrix for logged population.
rsiena_population_matrix <- make_rsiena_covariate_matrix("log_population")

# Create the RSiena dependent network object from the binary backbone array.
ai_network <- sienaDependent(rsiena_network_array)

# Create a time-varying actor covariate for polyarchy.
polyarchy <- varCovar(rsiena_polyarchy_matrix)

# Create a time-varying actor covariate for logged GDP.
gdp <- varCovar(rsiena_gdp_matrix)

# Create a time-varying actor covariate for logged population.
pop <- varCovar(rsiena_population_matrix)

# Combine the network and actor covariates into one RSiena data object.
rsiena_data <- sienaDataCreate(ai_network, polyarchy, gdp, pop)

# Start from RSiena's default effects table for this data object.
rsiena_effects <- getEffects(rsiena_data)

# Add direct country-level and similarity effects for polyarchy.
rsiena_effects <- includeEffects(rsiena_effects, egoPlusAltX, simX, interaction1 = "polyarchy")

# Add direct country-level and similarity effects for logged GDP.
rsiena_effects <- includeEffects(rsiena_effects, egoPlusAltX, simX, interaction1 = "gdp")

# Add direct country-level and similarity effects for logged population.
rsiena_effects <- includeEffects(rsiena_effects, egoPlusAltX, simX, interaction1 = "pop")

# Add endogenous degree concentration and transitive closure effects. degPlus is similar in spirit to degree concentration terms in ERGM models, while gwesp is the RSiena analogue to the geometrically weighted shared-partner transitivity term used above.
rsiena_effects <- includeEffects(rsiena_effects, degPlus)
rsiena_effects <- includeEffects(rsiena_effects, gwesp)

# Create the RSiena algorithm settings for the five-wave AI network.
rsiena_algorithm <- sienaAlgorithmCreate(
  # Write RSiena's required text output to a temporary file instead of Siena.txt in the workspace.
  projname = tempfile("rsiena_ai_workshop_"),
  # Use 1000 iterations for workshop speed; increase this for convergence checks and publication-ready SAOMs.
  n3 = 1000,
  seed = 101,
  modelType = c(ai_network = 3)
)

# Estimate the RSiena model with a conservative number of parallel workers.
rsiena_fit <- siena07(
  rsiena_algorithm,
  data = rsiena_data,
  effects = rsiena_effects,
  batch = TRUE,
  useCluster = TRUE,
  nbrNodes = 8,
  returnDeps = TRUE
)

# Show the RSiena model results.
summary(rsiena_fit)

# As a rule of thumb, RSiena convergence is evaluated with the individual convergence t-ratios and the overall maximum convergence ratio. Individual convergence t-ratios should be close to zero, with absolute values below 0.10 generally considered good and values below 0.20 often considered acceptable. The overall maximum convergence ratio should ideally be below 0.25; values above this suggest the model may need more iterations, a simpler specification, different starting values, or closer inspection of problematic effects. These are diagnostics for whether the estimation algorithm has settled, not substantive tests of whether the hypotheses are supported.

# 10. Bonus: Valued ERGMs With ergm.count ----

# Use ergm.count when the research question is about tie strength rather than tie presence, here the number of observed collaborations between two countries. Valued ERGMs extend ERGM logic by adding a response edge attribute and a reference distribution for edge values, so summary coefficients describe how model terms change the distribution of counts or transformed scores rather than simple tie log-odds; Poisson specifications are the most direct count model, while transformed binomial specifications can be more stable when counts are extremely skewed. The data must be a network-package object with numeric edge values stored under the response name, usually "weight", and the chosen reference distribution must match the scale of those values; convergence is often fragile when raw counts are highly overdispersed, a few dyads dominate the weight distribution, valued structural terms are computationally expensive or collinear, the model tries to explain both tie existence and tie magnitude at once, or the reference distribution puts too much probability on unrealistic simulated edge weights.

# This bonus section returns to the original weighted collaboration counts. Valued ERGMs are useful because they model tie strength directly, but raw collaboration counts are usually highly skewed: most country pairs collaborate rarely, while a few pairs collaborate hundreds or thousands of times. That heavy-tailed distribution can make Poisson-reference valued ERGMs difficult to estimate.

# Load ergm.count so valued ERGMs can use count-valued reference distributions.
library(ergm.count)

# Pick one year for the bonus valued ERGM example.
bonus_year <- 2023

# Pull the weighted matrix and covariates for the selected bonus year.
bonus_weighted_matrix <- weighted_matrices[[as.character(bonus_year)]]
bonus_covariates <- covariates_by_year[[as.character(bonus_year)]]

# Create a weighted network object from the raw collaboration-count matrix.
bonus_weighted_network <- network::network(
  bonus_weighted_matrix,
  directed = FALSE,
  matrix.type = "adjacency",
  ignore.eval = FALSE,
  names.eval = "weight"
)

# Attach the same country-level covariates used in the binary ERGM models.
network::set.vertex.attribute(bonus_weighted_network, "iso3", bonus_covariates$iso3)
network::set.vertex.attribute(bonus_weighted_network, "polyarchy", bonus_covariates$polyarchy)
network::set.vertex.attribute(bonus_weighted_network, "log_gdp", bonus_covariates$log_gdp)
network::set.vertex.attribute(bonus_weighted_network, "log_population", bonus_covariates$log_population)

# First try the direct Poisson-valued specification. This is the most literal count model, but it may struggle when the edge weights are very overdispersed.
bonus_poisson_ergm <- ergm::ergm(
  bonus_weighted_network ~
    sum +
    nonzero +
    nodecovar(center = FALSE, transform = "sqrt") +
    nodecov("polyarchy") +
    nodecov("log_gdp") +
    nodecov("log_population") +
    absdiff("polyarchy") +
    absdiff("log_gdp") +
    absdiff("log_population"),
  response = "weight",
  reference = ~Poisson,
  control = ergm::control.ergm(
    MCMC.samplesize = 1000,
    MCMC.burnin = 5000,
    MCMLE.maxit = 20,
    parallel = 8,
    parallel.type = "PSOCK"
  )
)

# Show the Poisson-valued ERGM results.
summary(bonus_poisson_ergm)

# As an alternative, transform the raw counts with log(weight + 1), round them to integer scores, and model those bounded scores with a binomial reference distribution.
# bonus_binomial_matrix <- round(log1p(bonus_weighted_matrix))
# diag(bonus_binomial_matrix) <- 0
# bonus_binomial_trials <- max(bonus_binomial_matrix)

# Create a weighted network object from the transformed, bounded collaboration scores.
# bonus_binomial_network <- network::network(
#  bonus_binomial_matrix,
#  directed = FALSE,
#  matrix.type = "adjacency",
#  ignore.eval = FALSE,
#  names.eval = "weight"
# )

# Attach the same country-level covariates to the transformed-valued network.
# network::set.vertex.attribute(bonus_binomial_network, "iso3", bonus_covariates$iso3)
# network::set.vertex.attribute(bonus_binomial_network, "polyarchy", bonus_covariates$polyarchy)
# network::set.vertex.attribute(bonus_binomial_network, "log_gdp", bonus_covariates$log_gdp)
# network::set.vertex.attribute(bonus_binomial_network, "log_population", bonus_covariates$log_population)

# Estimate the transformed-valued ERGM using a binomial reference with the observed maximum transformed score as the number of trials.
# bonus_binomial_ergm <- ergm::ergm(
#  bonus_binomial_network ~
#    sum +
#    nonzero +
#    nodecovar(center = FALSE, transform = "sqrt") +
#    nodecov("polyarchy") +
#    nodecov("log_gdp") +
#    nodecov("log_population") +
#    absdiff("polyarchy") +
#    absdiff("log_gdp") +
#    absdiff("log_population"),
#  response = "weight",
#  reference = ~Binomial(trials = bonus_binomial_trials),
#  control = ergm::control.ergm(
#    MCMC.samplesize = 1000,
#    MCMC.burnin = 5000,
#    MCMLE.maxit = 20,
#    parallel = 8,
#    parallel.type = "PSOCK"
#  )
# )

# Show the transformed-binomial valued ERGM results.
# summary(bonus_binomial_ergm)


