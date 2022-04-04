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
# Copyright (c) 2022 Daniel Philippus.  This code is open-source and provided
# with ABSOLUTELY NO WARRANTY.  You are free to use, modify, and redistribute it
# under certain conditions, namely that any modifications are provided under
# the same or compatible terms.  This code is provided under the GNU General
# Public License v3; please see https://www.gnu.org/licenses/gpl-3.0.html
# for more information.

library(dplyr)
library(quantregForest)
library(purrr)

make.model <- function(td, MTRY=4, NTREE=3000, NTHREADS=1, ...) {
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
  # The arguments MTRY, NTREE, NTHREADS, and ... are passed on directly
  # to quantregForest.
  #
  # The output of this function is a list of monthly models, named by month
  # as a two-character string (e.g. "05").  This will actually subdivide by
  # whatever "time" happens to be, but by default, and as tested in the paper,
  # this should be monthly.  If needed, you could also use e.g. annual or
  # seasonal models simply by changing what "time" stores, but you should
  # investigate the accuracy if so.
  regl <- {}
  months <- unique(td$time)
  td <- drop_na(td) %>% urban
  for (month in months) {
    dat <- filter(td, time == month) %>%
      select(-start, -end, -id,
             -time, -year)
    x <- select(dat, -temperature)
    y <- dat$temperature
    mod <- if (nrow(dat) > 10) {
      quantregForest(x, y, mtry=MTRY, ntree=NTREE, nthreads=NTHREADS, ...)
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
  data <- drop_na(data) %>% urban
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
  cat("Num. urban gages: ", length(unique(td$id[urb])))
  if (isolate) {
    if (!nurb)
      td[urb,]
    else
      td[!urb,]
  } else {
    cat("\nNum. non-urban gages: ", length(unique(td$id[!urb])))
    td
  }
}