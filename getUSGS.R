# Retrieve USGS data and merge with provided data frames.

library(dataRetrieval)
library(dplyr)
library(purrr)

get.usgs <- function(id, start, end) {
  # returns data frame with: id, year, time, temperature
  # year and temperature as dbl, id and time as chr
  
  tryCatch(
    readNWISdv(id, "00010", start, end) %>%
      select(id=site_no,
             Date,
             temperature = X_00010_00003) %>%
      mutate(
        year = as.double(format(Date, "%Y")),
        time = format(Date, "%m")
      ) %>%
      group_by(id, year, time) %>%
      summarize(temperature = mean(temperature, na.rm=T))
    , error = function(e) tibble(id=id, year=NA, time=NA, temperature=NA)
  )
    
}

add.temp <- function(data) {
  # data must have columns id, start, end, year, time
  # year -> dbl, time -> chr, start/end as dates
  selectors <- data %>%
    group_by(id) %>%
    summarize(start = min(start),
              end = max(end))
  
  usgs <- selectors %>%
    rowwise() %>%
    group_modify(
      ~get.usgs(.x$id, .x$start, .x$end)
    )
  
  left_join(data,
            usgs,
            by=c("id", "year", "time"))
}
# 
# list.gages <- function(states, print.gee=FALSE) {
#   # Retrieves a list of all USGS gage IDs and coordinates within
#   # the specified states.
#   data <- map_dfr(states,
#           ~select(
#             whatNWISsites(stateCd=.x,
#                           parameterCd="00010",
#                           service="dv"),
#             id=site_no,
#             lat=dec_lat_va,
#             lon=dec_long_va
#           )) %>%
#     filter(max(whatNWISdata(siteNumber=id, parameterCd="00010")$count_nu,
#                na.rm=T) > 0)
#   if (!print.gee) {
#     data
#   } else {
#     NULL
#   }
# }
