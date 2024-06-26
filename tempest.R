# tempest.R: River Temperature Estimation from satellite-based spatial data
# 
# This script includes functions to train a Quantile Regression Forest on
# spatial data and use it to predict monthly mean river temperatures.
# With minimal modification, it could also use different submodels (i.e.
# not monthly) and different predictor variables.
# 
# Full documentation is provided in Philippus, Sytsma, and Hogue, (paper
# in progress, will update date and DOI when published.)  If you use this
# script for research, please cite that paper.
#
# Copyright (c) 2023 Daniel Philippus.  This code is open-source and provided
# with ABSOLUTELY NO WARRANTY.  You are free to use, modify, and redistribute it
# under certain conditions, namely that any modifications are provided under
# the same or compatible terms.  This code is provided under the GNU General
# Public License v3; please see https://www.gnu.org/licenses/gpl-3.0.html
# for more information.

library(dplyr)
library(tidyr)
library(quantregForest)
library(purrr)

make.model <- function(td, default.inputs=TRUE, ...) {
  # This function trains a temperature model on the provided dataset td.
  # In addition to a number of predictors for which the name is irrelevant
  # so long as it is consistent (see paper for specifics), the input should
  # include the named columns start, end, id, time, year, temperature,
  # and builtup.  You can modify the source code if needed to change these names.
  #
  # The dataset td should be a data frame.  Other than the above-specified
  # columns, predictor columns can have arbitrary names and can be a mix
  # of numerical and categorical inputs.
  #
  # If default.inputs = TRUE, the input data frame will be filtered to the columns
  # below and must have those columns.  Otherwise it only needs the first 6 and
  # will train on anything.  If default.inputs=TRUE, then all named columns
  # must also be present in prediction data (except temperature).
  # start, end, id, time, year, temperature,
  # avgtemp, landtemp, humidity,
  # lat, lon, elevation,
  # water, builtup, trees
  # 
  # The arguments ntree and ... are passed on directly
  # to quantregForest.
  # Suggested: specify `nthreads` for multi-threading
  #
  # The output of this function is a list of monthly models, named by month
  # as a two-character string (e.g. "05").  This will actually subdivide by
  # whatever "time" happens to be, but by default, and as tested in the paper,
  # this should be monthly.  If needed, you could also use e.g. annual or
  # seasonal models simply by changing what "time" stores, but you should
  # investigate the accuracy if so.
  td$time <- as.character(td$time)
  regl <- {}
  months <- unique(td$time)
  # Remove columns that are only NA (support for omitting predictors),
  # then drop rows that have NAs.
  td <- if (!default.inputs) {
    td
  } else {
    select(td,
           start, end, id, time, year, temperature,
           avgtemp, landtemp, humidity,
           lat, lon, elevation,
           water, builtup, trees)
  }
  td <- drop.all.na(td) %>% drop_na
  for (month in months) {
    dat <- filter(td, time == month) %>%
      select(-start, -end, -id,
             -time, -year)
    x <- select(dat, -temperature)
    y <- dat$temperature
    mod <- if (nrow(dat) > 10) {
      quantregForest(x, y, ...)
    } else NULL
    regl[[month]] <- mod
  }
  regl
}

predict.temperature <- function(mod, data, compare=F, preserve=F, what=NULL) {
  # This function predicts river temperatures for the provided predictor
  # dataset.  The input dataset, data, should have the same predictor names
  # and formats as provided to make.model above.  If preserve is FALSE,
  # it should also have the columns:
  # id, ecoregion, year, time, start, end
  #
  # The mod argument should be the model output from make.model above.
  #
  # The what argument, a vector, specifies which quantiles to predict.  The
  # default is 0.5.  This argument is useful for predicting e.g. confidence
  # intervals.
  #
  # If compare is TRUE, this function will keep the original temperature
  # data (which must be provided) as well, for use in investigating model
  # accuracy.
  #
  # If preserve is TRUE, the output will simply keep the input data frame
  # and add a predicted temperature column.  Otherwise, only the named
  # columns required above will be preserved.
  #
  # NOTE: rows with NAs will be dropped.
  data$time <- as.character(data$time)
  
  data <- drop.all.na(data) %>% drop_na
  wlabel <- !is.null(what)
  what <- if (!wlabel) 0.5 else what
  has.tmp <- "temperature" %in% names(data)
  
  # If compare, temperature must be provided
  if (compare && !has.tmp)
    stop("pred.mod: compare is true but there is no temperature column")
  
  # Should the modeled temperature column be called temperature or Modeled?
  basename <-
    if (compare || (preserve && has.tmp)) "Modeled" else "temperature"
  
  # Prepare prediction column names
  nms <-
    if (wlabel) {
      paste(basename, what, sep="_")
    } else {
      basename
    }
  
  map_dfr(unique(data$time), function(month) {
    tab <- filter(data, time == month)
    model <- mod[[month]]
    if (!is.null(model)) {
      # pred.mod.single(model, tab, preserve)
      prd <- data.frame(predict(model, tab, what=what))
      names(prd) <- nms
      tab <-
        if (preserve) {
          if (has.tmp)
            rename(tab, Actual=temperature)
          else
            tab
        } else if (compare) {
          select(tab, id, ecoregion, year, time, start, end, Actual=temperature)
        } else {
          select(tab, id, ecoregion, year, time, start, end)
        }
      cbind(
        tab,
        prd
      )
    } else NULL
  })
}


urban <- function(td, threshold=0.1, isolate=F, nurb=F) {
  # Divide temp data into urban/not urban
  # If isolate: return only urban gages
  # Otherwise, just add an urban column
  # Default threshold: 0.1
  urb <- td$builtup >= threshold
  td$urban <- urb
  # cat("Num. urban gages: ", length(unique(td$id[urb])))
  if (isolate) {
    if (!nurb)
      td[urb,]
    else
      td[!urb,]
  } else {
    # cat("\nNum. non-urban gages: ", length(unique(td$id[!urb])))
    td
  }
}

all.na <- function(x) {
  # Utility function: determine if a vector is entirely NA
  sum(!is.na(x)) == 0
}

drop.all.na <- function(data) {
  # Utility function: drop columns that are all NA
  select(data,
         where(~!all.na(.)))
}

error.bxp <- function(data) {
  # This function displays boxplots of error distributions by ecoregion
  # and gage.
  library(ggplot2)
  
  data %>%
    drop_na() %>%
    group_by(id, ecoregion) %>%
    summarize(
      `RMSE (K)` = sqrt(mean((Modeled - Actual)^2)),
      `Percent Bias` = 100 * sum(Modeled - Actual)/sum(Actual),
      `R2` = cor(Modeled, Actual)^2
    ) %>%
    pivot_longer(
      c("RMSE (K)", "Percent Bias", "R2"),
      names_to="GOF",
      values_to="Value"
    ) %>%
    ggplot() +
    aes(x=ecoregion, y=Value) +
    geom_boxplot() +
    facet_wrap(~GOF, strip.position="left", scales="free_y",
               nrow=1) +
    labs(
      x="Ecoregion",
      y=NULL,
      title="TempEst Validation Gage Error Distributions by Ecoregion"
    ) +
    theme_bw() +
    theme(axis.text.x = element_text(angle=60, vjust=1, hjust=1))
}

plot.temperature <- function(data) {
  # This function plots a spatial distribution of average point temperatures.
  # The data input must be run with `preserve=TRUE` so that lat/lon are present.
  data %>%
    drop_na() %>%
    group_by(id, lat, lon, time) %>%
    summarize(
      temperature = mean(temperature)
    ) %>%
    ggplot() +
    aes(x=lon, y=lat, color=temperature) +
    geom_point(size=2) +
    facet_wrap(~time, nrow=3) +
    theme_bw() +
    labs(
      x="Longitude",
      y="Latitude",
      color="Mean Monthly Temperature (K)",
      title="Spatial Distribution of TempEst Stream Temperatures"
    )
}

case.study <- function() {
  # This is the source code of the case study from the paper.
  # (Philippus, Sytsma and Hogue, not yet submitted.)
  # 
  # We retrieved river temperatures for 100 streams with an estimated
  # width of at least 1 m in the Colorado Rocky Mountains (2014-2021).
  # Then we evaluated trends in cutthroat trout suitability, based on
  # lethal temperature (20-24 C, using 20) and optimal reproduction
  # temperature (> 8 C in July).
  #
  # The model is trained on the calibration dataset provided.
  library(tidyverse)  # for data manipulation, plotting, etc
  source("util.R")  # helper functions: plot.theme(), print.and.png(), cal.data()
  
  cal <- cal.data()
  model <- make.model(cal, nthreads=16)  # nthreads to speed up training
  
  trout.data <- read_csv("TempestTrout.csv") %>%
    replace_na(list(barren=0, builtup=0, cropland=0, grassland=0,
                    mangrove=0, moss=0, shrubland=0, snow=0, trees=0,
                    water=0, wetland=0))  # missing land cover data - fixed in newer GEE script
  trout <- predict.temperature(model, trout.data)
  
  is.survivable <- function(year.temps) {
    # Boolean: assuming the data provided are for one full year,
    # is the river survivable for that year?
    max(year.temps, na.rm = TRUE) < 20
  }
  is.optimal <- function(months, year.temps) {
    # Boolean: is the July temperature in the optimal range?
    july <- year.temps[months == "07"]
    if (length(july) == 0)
      FALSE
    else {
      july[1] >= 8
    }
  }
  egg <- function(months, year.temps) {
    jan <- year.temps[months == "01"]
    if (length(jan) == 0)
      FALSE
    else {
      jan[1] >= 2
    }
  }
  
  suitability <- trout %>%
    group_by(id, year) %>%
    summarize(Survivable=is.survivable(temperature),
              Optimal=is.optimal(time, temperature),
              Eggs=egg(time, temperature),
              Both=Optimal & Survivable & Eggs) %>%
    group_by(year) %>%
    summarize(
      Survivable=mean(Survivable) * 100,
      Eggs=mean(Eggs) * 100,
      All=mean(Both) * 100,
      Optimal=mean(Optimal) * 100  # percentages
    )
  print(suitability)
  names(suitability) <-
    c("year",
      "Accute Maximum",
      "Optimal Egg Viability",
      "Suitable Year-Round",
      "Optimal Fry Survival"
      )
  suitability <- suitability %>%
    pivot_longer(
      c("Accute Maximum",
        "Optimal Fry Survival",
        "Optimal Egg Viability",
        "Suitable Year-Round"),
      names_to="Type",
      values_to="Suitability"
    )
  
  restab <- suitability %>%
    ungroup() %>%
    group_by(Type) %>%
    summarize(
      R2 = cor(year, Suitability)^2,
      pval = cor.test(year, Suitability)$p.value,
      Coeff = lm(Suitability ~ year)$coefficients[[2]]
    )
  print(restab)
  suitability %>%
    ggplot() +
    aes(x=year) +
    geom_col(aes(y=Suitability, fill=Type), position = "dodge") +
    plot.theme() +
    labs(
      x="Year",
      y="Percent of Streams in Suitability Range",
      fill="Suitability Type"
    )
}