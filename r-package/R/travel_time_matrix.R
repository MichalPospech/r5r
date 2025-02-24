#' Calculate travel time matrix between origin destination pairs
#'
#' @description Fast computation of travel time estimates between one or
#'              multiple origin destination pairs.
#'
#' @param r5r_core a rJava object to connect with R5 routing engine
#' @param origins,destinations a spatial sf POINT object with WGS84 CRS, or a
#'                             data.frame containing the columns 'id', 'lon',
#'                             'lat'.
#' @param mode string. Transport modes allowed for the trips. Defaults to
#'             "WALK". See details for other options.
#' @param mode_egress string. Transport mode used after egress from public
#'                    transport. It can be either 'WALK', 'BICYCLE', or 'CAR'.
#'                    Defaults to "WALK".
#' @param departure_datetime POSIXct object. If working with public transport
#'                           networks, please check \code{calendar.txt} within
#'                           the GTFS file for valid dates. See details for
#'                           further information on how datetimes are parsed.
#' @param time_window numeric. Time window in minutes for which r5r will
#'                    calculate multiple travel time matrices departing each
#'                    minute. By default, the number of simulations is 5 times
#'                    the size of 'time_window' set by the user. Defaults window
#'                    size to '1', the function only considers 5 departure
#'                    times. This parameter is only used with frequency-based
#'                    GTFS files. See details for further information.
#' @param percentiles numeric vector. Defaults to '50', returning the median
#'                    travel time for a given time_window. If a numeric vector is passed,
#'                    for example c(25, 50, 75), the function will return
#'                    additional columns with the travel times within percentiles
#'                    of trips. For example, if the 25 percentile of trips between
#'                    A and B is 15 minutes, this means that 25% of all trips
#'                    taken between A and B within the set time window are shorter
#'                    than 15 minutes. Only the first 5 cut points of the percentiles
#'                    are considered. For more details, see R5 documentation at
#'                    'https://docs.conveyal.com/analysis/methodology#accounting-for-variability'
#' @param breakdown logic. If `FALSE` (default), the function returns a simple
#'                  output with columns origin, destination and travel time
#'                  percentiles. If `TRUE`, r5r breaks down the trip information
#'                  and returns more columns with estimates of `access_time`,
#'                  `waiting_time`, `ride_time`, `transfer_time`, `total_time` , `n_rides`
#'                  and `route`. Warning: Setting `TRUE` makes the function
#'                  significantly slower.
#'
#' @param breakdown_stat string. If `min`, all the brokendown trip informantion
#'        is based on the trip itinerary with the smallest waiting time in the
#'        time window. If `breakdown_stat = mean`, the information is based on
#'        the trip itinerary whose waiting time is the closest to the average
#'        waiting time in the time window.
#' @param max_walk_dist numeric. Maximum walking distance (in meters) to access
#'                      and egress the transit network, or to make transfers
#'                      within the network. Defaults to no restrictions as long
#'                      as `max_trip_duration` is respected. The max distance is
#'                      considered separately for each leg (e.g. if you set
#'                      `max_walk_dist` to 1000, you could potentially walk up
#'                      to 1 km to reach transit, and up to _another_  1 km to
#'                      reach the destination after leaving transit). Obs: if you
#'                      want to set the maximum walking distance considering
#'                      walking-only trips you have to set the `max_trip_duration`
#'                      accordingly (e.g. to set a distance of 1 km assuming a
#'                      walking speed of 3.6 km/h you have to set `max_trip_duration = 1 / 3.6 * 60`).
#' @param max_bike_dist numeric. Maximum cycling distance (in meters) to access
#'                      and egress the transit network. Defaults to no
#'                      restrictions as long as `max_trip_duration` is respected.
#'                      The max distance is considered separately for each leg
#'                      (e.g. if you set `max_bike_dist` to 1000, you could
#'                      potentially cycle up to 1 km to reach transit, and up
#'                      to _another_ 1 km to reach the destination after leaving
#'                      transit). Obs: if you want to set the maximum cycling
#'                      distance considering cycling-only trips you have to set
#'                      the `max_trip_duration` accordingly (e.g. to set a
#'                      distance of 5 km assuming a cycling speed of 12 km/h you
#'                      have to set `max_trip_duration = 5 / 12 * 60`).
#' @param max_trip_duration numeric. Maximum trip duration in minutes. Defaults
#'                          to 120 minutes (2 hours).
#' @param walk_speed numeric. Average walk speed in km/h. Defaults to 3.6 km/h.
#' @param bike_speed numeric. Average cycling speed in km/h. Defaults to 12 km/h.
#' @param max_rides numeric. The max number of public transport rides allowed in
#'                  the same trip. Defaults to 3.
#' @param max_lts  numeric (between 1 and 4). The maximum level of traffic stress
#'                 that cyclists will tolerate. A value of 1 means cyclists will
#'                 only travel through the quietest streets, while a value of 4
#'                 indicates cyclists can travel through any road. Defaults to 2.
#'                 See details for more information.
#' @param n_threads numeric. The number of threads to use in parallel computing.
#'                  Defaults to use all available threads (Inf).
#' @param verbose logical. `TRUE` to show detailed output messages (the default).
#' @param progress logical. `TRUE` to show a progress counter. Only works when
#'                `verbose` is set to `FALSE`, so the progress counter does not
#'                interfere with R5's output messages. Setting `progress` to `TRUE`
#'                may impose a small penalty for computation efficiency, because
#'                the progress counter must be synchronized among all active
#'                threads.
#'
#' @return A data.table with travel time estimates (in minutes) between origin
#' destination pairs by a given transport mode. Note that origins/destinations
#' that were beyond the maximum travel time, and/or origins that were far from
#' the street network are not returned in the data.table.
#'
#' @details
#'  # Transport modes:
#'  R5 allows for multiple combinations of transport modes. The options include:
#'
#'   ## Transit modes
#'   TRAM, SUBWAY, RAIL, BUS, FERRY, CABLE_CAR, GONDOLA, FUNICULAR. The option
#'   'TRANSIT' automatically considers all public transport modes available.
#'
#'   ## Non transit modes
#'   WALK, BICYCLE, CAR, BICYCLE_RENT, CAR_PARK
#'
#' # max_lts, Maximum Level of Traffic Stress:
#' When cycling is enabled in R5, setting `max_lts` will allow cycling only on
#' streets with a given level of danger/stress. Setting `max_lts` to 1, for example,
#' will allow cycling only on separated bicycle infrastructure or low-traffic
#' streets; routing will revert to walking when traversing any links with LTS
#' exceeding 1. Setting `max_lts` to 3 will allow cycling on links with LTS 1, 2,
#' or 3.
#'
#' The default methodology for assigning LTS values to network edges is based on
#' commonly tagged attributes of OSM ways. See more info about LTS in the original
#' documentation of R5 from Conveyal at \url{https://docs.conveyal.com/learn-more/traffic-stress}.
#' In summary:
#'
#'- **LTS 1**: Tolerable for children. This includes low-speed, low-volume streets,
#'  as well as those with separated bicycle facilities (such as parking-protected
#'  lanes or cycle tracks).
#'- **LTS 2**: Tolerable for the mainstream adult population. This includes streets
#'  where cyclists have dedicated lanes and only have to interact with traffic at
#'  formal crossing.
#'- **LTS 3**: Tolerable for “enthused and confident” cyclists. This includes streets
#'  which may involve close proximity to moderate- or high-speed vehicular traffic.
#'- **LTS 4**: Tolerable for only “strong and fearless” cyclists. This includes streets
#'  where cyclists are required to mix with moderate- to high-speed vehicular traffic.
#'
#'  For advanced users, you can provide custom LTS values by adding a tag
#'  <key = "lts> to the `osm.pbf` file
#'
#' # Routing algorithm:
#' The travel_time_matrix function uses an R5-specific extension to the RAPTOR
#' routing algorithm (see Conway et al., 2017). This RAPTOR extension uses a
#' systematic sample of one departure per minute over the time window set by the
#' user in the 'time_window' parameter. A detailed description of base RAPTOR
#' can be found in Delling et al (2015).
#' - Conway, M. W., Byrd, A., & van der Linden, M. (2017). Evidence-based transit
#'  and land use sketch planning using interactive accessibility methods on
#'  combined schedule and headway-based networks. Transportation Research Record,
#'  2653(1), 45-53.
#'  - Delling, D., Pajor, T., & Werneck, R. F. (2015). Round-based public transit
#'  routing. Transportation Science, 49(3), 591-604.
#'
#' # Datetime parsing
#'
#' `r5r` ignores the timezone attribute of datetime objects when parsing dates
#' and times, using the study area's timezone instead. For example, let's say
#' you are running some calculations using Rio de Janeiro, Brazil, as your study
#' area. The datetime `as.POSIXct("13-05-2019 14:00:00",
#' format = "%d-%m-%Y %H:%M:%S")` will be parsed as May 13th, 2019, 14:00h in
#' Rio's local time, as expected. But `as.POSIXct("13-05-2019 14:00:00",
#' format = "%d-%m-%Y %H:%M:%S", tz = "Europe/Paris")` will also be parsed as
#' the exact same date and time in Rio's local time, perhaps surprisingly,
#' ignoring the timezone attribute.
#'
#' @family routing
#' @examples if (interactive()) {
#' library(r5r)
#'
#' # build transport network
#' data_path <- system.file("extdata/spo", package = "r5r")
#' r5r_core <- setup_r5(data_path = data_path, temp_dir = TRUE)
#'
#' # load origin/destination points
#' points <- read.csv(file.path(data_path, "spo_hexgrid.csv"))[1:5,]
#'
#' departure_datetime <- as.POSIXct("13-05-2019 14:00:00", format = "%d-%m-%Y %H:%M:%S")
#'
#' # estimate travel time matrix
#' ttm <- travel_time_matrix(r5r_core,
#'                           origins = points,
#'                           destinations = points,
#'                           mode = c("WALK", "TRANSIT"),
#'                           departure_datetime = departure_datetime,
#'                           max_walk_dist = Inf,
#'                           max_trip_duration = 120L)
#'
#' stop_r5(r5r_core)
#'
#' }
#' @export

travel_time_matrix <- function(r5r_core,
                               origins,
                               destinations,
                               mode = "WALK",
                               mode_egress = "WALK",
                               departure_datetime = Sys.time(),
                               time_window = 1L,
                               percentiles = 50L,
                               breakdown = FALSE,
                               breakdown_stat = "MEAN",
                               max_walk_dist = Inf,
                               max_bike_dist = Inf,
                               max_trip_duration = 120L,
                               walk_speed = 3.6,
                               bike_speed = 12,
                               max_rides = 3,
                               max_lts = 2,
                               n_threads = Inf,
                               verbose = TRUE,
                               progress = TRUE) {


  # set data.table options --------------------------------------------------

  old_options <- options()
  old_dt_threads <- data.table::getDTthreads()

  on.exit({
    options(old_options)
    data.table::setDTthreads(old_dt_threads)
  })

  options(datatable.optimize = Inf)


  # check inputs ------------------------------------------------------------

  # r5r_core
  checkmate::assert_class(r5r_core, "jobjRef")

  # modes
  mode_list <- select_mode(mode, mode_egress)

  # departure time
  departure <- posix_to_string(departure_datetime)

  # max trip duration
  checkmate::assert_numeric(max_trip_duration, lower=1)
  max_trip_duration <- as.integer(max_trip_duration)

  # max_walking_distance, max_bike_distance, and max_street_time
  max_walk_time <- set_max_street_time(max_walk_dist,
                                       walk_speed,
                                       max_trip_duration)
  max_bike_time <- set_max_street_time(max_bike_dist,
                                       bike_speed,
                                       max_trip_duration)

  # origins and destinations
  origins      <- assert_points_input(origins, "origins")
  destinations <- assert_points_input(destinations, "destinations")

  checkmate::assert_subset("id", names(origins))
  checkmate::assert_subset("id", names(destinations))

  # time window
  checkmate::assert_numeric(time_window, lower=1)
  time_window <- as.integer(time_window)
  draws <- time_window *5
  draws <- as.integer(draws)

  # percentiles
  percentiles <- percentiles[1:5]
  percentiles <- percentiles[!is.na(percentiles)]
  checkmate::assert_numeric(percentiles)
  percentiles <- as.integer(percentiles)

  # travel times breakdown
  checkmate::assert_logical(breakdown)
  breakdown_stat <- assert_breakdown_stat(breakdown_stat)


  # set r5r_core options ----------------------------------------------------

  # time window
  r5r_core$setTimeWindowSize(time_window)
  r5r_core$setPercentiles(percentiles)
  r5r_core$setNumberOfMonteCarloDraws(draws)

  # travel times breakdown
  r5r_core$setTravelTimesBreakdown(breakdown)
  r5r_core$setTravelTimesBreakdownStat(breakdown_stat)

  # set bike and walk speed
  set_speed(r5r_core, walk_speed, "walk")
  set_speed(r5r_core, bike_speed, "bike")

  # set max transfers
  set_max_rides(r5r_core, max_rides)

  # set max lts (level of traffic stress)
  set_max_lts(r5r_core, max_lts)

  # set number of threads to be used by r5 and data.table
  set_n_threads(r5r_core, n_threads)

  # set verbose
  set_verbose(r5r_core, verbose)

  # set progress
  set_progress(r5r_core, progress)

  # call r5r_core method ----------------------------------------------------

  travel_times <- r5r_core$travelTimeMatrix(origins$id,
                                            origins$lat,
                                            origins$lon,
                                            destinations$id,
                                            destinations$lat,
                                            destinations$lon,
                                            mode_list$direct_modes,
                                            mode_list$transit_mode,
                                            mode_list$access_mode,
                                            mode_list$egress_mode,
                                            departure$date,
                                            departure$time,
                                            max_walk_time,
                                            max_bike_time,
                                            max_trip_duration)


  # process results ---------------------------------------------------------

  # convert travel_times from java object to data.table
  if (!verbose & progress) { cat("Preparing final output...") }

  travel_times <- java_to_dt(travel_times)

  # only perform following operations when result is not empty
  if (nrow(travel_times) > 0) {
    # replace travel-times of nonviable trips with NAs
    #   the first column with travel time information is column 3, because
    #     columns 1 and 2 contain the id's of OD point (hence from = 3)
    #   the percentiles parameter indicates how many travel times columns we'll,
    #     have, with a minimum of 1 (in which case, to = 3).
    for(j in seq(from = 3, to = (length(percentiles) + 2))){
      data.table::set(travel_times, i=which(travel_times[[j]]>max_trip_duration), j=j, value=NA_integer_)
    }
  }

  if (!verbose & progress) { cat(" DONE!\n") }
  return(travel_times)
}
