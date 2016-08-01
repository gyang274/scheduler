#------------------------------------------------------------------------------#
#--------------------------- scheduler::scheduler.r ---------------------------#
#------------------------- author: gyang274@gmail.com -------------------------#
#------------------------------------------------------------------------------#

#--------+---------+---------+---------+---------+---------+---------+---------#
#234567890123456789012345678901234567890123456789012345678901234567890123456789#

#------------------------------------------------------------------------------#
#------------------------------------ main ------------------------------------#
#------------------------------------------------------------------------------#

#' scheduler
#'
#' @description
#' scheduler is designed to fulfill scheduling process in the operation centers,
#' where the requirement are often the number of agents needed at each hour day,
#' and the constraint are often the availability of each agent at each hour day.
#'
#' @param ar agent requirement matrix
#'  a 48 x 7 matrix to specifiy number of agents needed at each 0.5 hr each day
#'
#' @param sm schedule module vector - allow 3 schedule modules:
#'
#'  schedule module 1: agent start any half hour window, say 8:30AM,
#'    work 3.5 hour, take 0.5 hour break, and work another 4.5 hour.
#'
#'  schedule module 2: agent start any half hour window, say 8:30AM,
#'    work 4.0 hour, take 0.5 hour break, and work another 4.0 hour.
#'
#'  schedule module 3: agent start any half hour window, say 8:30AM,
#'    work 4.5 hour, take 0.5 hour break, and work another 3.5 hour.
#'
#'  all agents any schedule assume to work consecutive 5 days given a start day
#'
#' @param cr constraints on starting hours
#'
#'  default is no agent will start work at 1:00AM, 1:30AM, ..., and 5:30AM
#'  on any day count 0:00AM as 1L and take a 0.5hr window so 1:00AM-5:30AM
#'  3L-12L, 51L-60L, 99L-108L, 147L-156L, 195L-204L, 243L-252L, 291L-300L.
#'
#' @param allow.half.hour.start allow start at none whole hour?
#'
#'  default is TRUE, so start at 7:00AM and start at 7:30AM are two schedule.
#'  if set FALSE, then no agent will start at 00:30AM, 01:30AM, ..., 23:30AM,
#'  this is a short cut for sepecifying all corresponding contraints with cr.
#'
#' @param write.model.into.file write out lp model into a file?
#'
#'  default is NULL not write out the model, otherwise a file name to write out
#'
#' @param timeout number of seconds to timeout the solving process
#'
#'  a parameter to pass into lpSolveAPI when solving the lp instance
#'
#' @return a list of 4 matrix and a solved lp model:
#'  s1, s2, s3, ss, and scheduleOptModel.
#'
#'  s1, s2 and s3 each is a 48 x 7 matrix of number of agents required to
#'  start at each hour each day, and s1, s2, and s3 are a coresponding to
#'  schedule module 1, schedule module 2, and schedule module 3.
#'
#'  ss is a 48 x 7 matrix and is a summarize of s1, s2 and s3 to show the
#'  number of agents avail at each half hour window - should all(ss > ar)
#'
#' @family scheduler
scheduler <- function(ar, sm = c(1L, 2L, 3L),
  cr = c(3L:12L, 51L:60L, 99L:108L, 147L:156L,
         195L:204L, 243L:252L, 291L:300L),
  allow.half.hour.start = TRUE,
  write.model.into.file = NULL, timeout = 60L) {

  sm <- sort(unique(sm))

  if ( is.null(sm) || !all(sm %in% c(1L, 2L, 3L)) ) {

    stop("scheduler: sm must be a vector of 1L, 2L, 3L.\n")

  }

  if ( !allow.half.hour.start ) {

    cr <- unique(c(cr, seq(from = 2L, to = 336L, by = 2L)))

  }

  #- initialize a lp model with nConstraints and nDecisionVariables
  nConstraints = 48L * 7L
  nDecisionVar = length(sm) * 48L * 7L # 336, 672 or 1008 decisionvar

  #- nConstraints: 48 x 7 constraints from agent requirement matrix
  ## additional length(cr) * 7 constraints will be added separately
  scheduleOptModel = make.lp(nrow = nConstraints)

  #- build the model column per column by adding agent active hours
  ## column - coefficients 1L on one schedule module one time start
  for ( a_sm in sm ) {

    for ( j in 0L:6L ) {

      for ( i in 0L:47L ) {

        agent_active_idx <- agentActiveHours(a_sm, j, i)

        ## agent_active_idx always in range 1L - 336L corresponding to half-hour indices in 7 days
        add.column(scheduleOptModel, x = rep(1L, length(agent_active_idx)), indices = agent_active_idx)

      }

    }

  }

  set.constr.type(scheduleOptModel, types = rep(">=", 336L))

  set.constr.value(scheduleOptModel, rhs = unlist(ar))

  #- add constraints with respect to cr on all schedule module
  ## default is no agent start between 01:00AM - 05:30AM on any day
  for (a_cr in cr) {

    for (a_sm_idx in 1L:length(sm)) {

      add.constraint(scheduleOptModel, xt = 1L, type = "=", rhs = 0L, indices = a_cr + (a_sm_idx - 1L) * 336L)

    }

  }

  #- set up objective - min total number of agents
  set.objfn(scheduleOptModel, obj = rep(1L, nDecisionVar))

  set.type(scheduleOptModel, columns = c(1L:nDecisionVar), type = "integer")

  lp.control(scheduleOptModel, sense = "min")

  #- write out the model (check)
  if ( !is.null(write.model.into.file) ) {

    write.lp(scheduleOptModel, filename = write.model.into.file, type = "lp")

  }

  # solve the model (pause)
  # solve using lp_solve_IDE
  lp.control(scheduleOptModel, timeout = timeout)

  message("scheduler: solving scheduleOptModel ...\n")

  .ptc <- proc.time()

  solve(scheduleOptModel)

  .ptd <- proc.time() - .ptc

  message("scheduler: solving scheduleOptModel consumes ", round(.ptd[3L], 2L),
          " seconds - compare with timeout set at ", timeout ,".\n")

  message("scheduler: solving scheduleOptModel ... done.\n")

  ss_lst <- scheduler_solution_constructor(scheduleOptModel, sm)

  return(list(
    s1 = ss_lst[["s1"]], s2 = ss_lst[["s2"]], s3 = ss_lst[["s3"]],
    ss = ss_lst[["ss"]], scheduleOptModel = scheduleOptModel
  ))

}

#' agentActiveHours
#' @description
#'  a subroutine in scheduler for calculating agent active hour given a starting
#'  half hour window and day, and the schedule module.
#'  for example, an agent start at 07:30AM Sunday and schedule module 1 would be
#'  available at 07:30AM - 11:00AM and 11:30AM - 16:00PM Monday - Friday, so the
#'  active half-hour indx would be 16-22, 24-32, 64-70, 72-80, 112-118, 120-128,
#'  160-166, 168-176, 208-214 and 216-224.
#' @param sm schedule module - single value:
#'  schedule module 1: agent start any half hour window, say 8:30AM,
#'    work 3.5 hour, take 0.5 hour break, and work another 4.5 hour.
#'  schedule module 2: agent start any half hour window, say 8:30AM,
#'    work 4.0 hour, take 0.5 hour break, and work another 4.0 hour.
#'  schedule module 3: agent start any half hour window, say 8:30AM,
#'    work 4.5 hour, take 0.5 hour break, and work another 3.5 hour.
#' @param j start day j = 0L Sunday, 1L Monday, ..., or 6L Saturday.
#' @param i start hour i = 0L 00:00AM, 2L 00:30AM, ..., or 47L 11:30AM.
#' @note
#'  note that there is a slight inconsistency that i is 0 - 47 half hour index
#'  and j is 0 - 6 day index, so the full half hour index produced should then
#'  be 0-335 but we add 1 and return 1-336 as lp model take row indexed from 1
#' @family scheduler
agentActiveHours <- function(sm, j, i) {

  if ( !(length(sm) == 1L && sm %in% c(1L, 2L, 3L)) ) {

    stop("agentActiveHours: sm schedule module must be a single value of 1L, 2L or 3L.\n")

  }

  #- build the model column per column by adding agent active hours
  ## each column C01, C02, ..., C1008 represent one schedule module start hour at a day,
  ## C01 represents schedule module 1 start at 00:00AM Monday, so C01 agent are avaiable
  ## at [00:00AM - 03:30AM) and [04:00AM - 8:30AM), Monday - Friday, so put +C01 on rows
  ## 1-7, 9-17, 49-55, 57-65, 97-103, 105-113, 145-151, 153-161, 193-199, and 201 - 209.

  ## schedule module 1L, 2L, 3L - hours when available
  if ( sm == 1L ) {

    # schedule 1 - 3.5 work hour + 0.5 break + 4.5 work hour
    i_active = c(i:(i + 6L), (i + 8L):(i + 16L))

  } else if ( sm == 2L ) {

    # schedule 2 - 4.0 work hour + 0.5 break + 4.0 work hour
    i_active = c(i:(i + 7L), (i + 9L):(i + 16L))

  } else if ( sm == 3L ) {

    # schedule 3 - 4.5 work hour + 0.5 break + 3.5 work hour
    i_active = c(i:(i + 8L), (i + 10L):(i + 16L))

  } else {

    stop("addAgentActiveHours: sm schedule module must be a single value of 1L, 2L or 3L.\n")

  }

  ## schedule module 1L, 2L, 3L - days when available
  j_active = (c(j:(j + 4L)) %% 7L)

  ## agent active half-hour index (move 0-335 => 1-336)
  agent_active_idx <- (i_active + rep(j_active * 48L, each = length(i_active))) %% 336L + 1L

  return( agent_active_idx )

}

#' scheduler_solution_constructor
#' @description
#'  a subroutine in scheduler for constructing scheduler solution from lp solution
#' @family scheduler
scheduler_solution_constructor <- function(scheduleOptModel, sm) {

  #- init solution matrix
  for ( a_sm_idx in 1L:3L ) {

    eval(parse(text = paste0('s', a_sm_idx, ' <- matrix(0L, 48L, 7L)')))

    eval(parse(text = paste0(
      'colnames(s', a_sm_idx, ') <- c("Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday")'
    )))

    eval(parse(text = paste0(
      'rownames(s', a_sm_idx, ') <- paste0(formatC(rep(0L:23L, each=2L), width=2L, flag="0"), ":", c("00", "30"))'
    )))

  }

  #- extract solution from lp solution
  lp_vec <- get.variables(scheduleOptModel)

  for ( a_sm_idx in 1L:length(sm) ) {

    eval(parse(text = paste0(
      's', sm[a_sm_idx], '[1L:336L] <- matrix(lp_vec[(a_sm_idx - 1L) * 336L + 1L:336L], 48L, 7L)'
    )))

  }

  #- schedule summarize view - a combined view of module 1L, 2L, 3L
  ss <- agentOnTimeFromSchedule(list(s1 = s1, s2 = s2, s3 = s3))

  return(list(s1 = s1, s2 = s2, s3 = s3, ss = ss))

}

#' agentOnTimeFromSchedule
#' @description
#'  a subroutine in scheduler_solution_constructor to construct ss from s1, s2, s3
#' @family scheduler
agentOnTimeFromSchedule <- function(ss_lst) {

  ss <- matrix(0L, 48L, 7L)

  for ( a_sm_idx in c(1L, 2L, 3L) ) {

    for ( j in 0L:6L ) {

      for ( i in 0L:47L ) {

        agent_active_idx <- agentActiveHours(a_sm_idx, j, i)

        ## num of agent available from schedule module sm start at half-hour index i day j
        ss[agent_active_idx] <- ss[agent_active_idx] + ss_lst[[a_sm_idx]][i + 1L, j + 1L]

      }

    }

  }

  colnames(ss) <- c("Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday")

  rownames(ss) <- paste0(formatC(rep(0L:23L, each=2L), width=2L, flag="0"), ":", c("00", "30"))

  return( ss )

}

#------------------------------------------------------------------------------#

#------------------------------------------------------------------------------#
#------------------------------------ plot ------------------------------------#
#------------------------------------------------------------------------------#

#' schedule_viewer
#' @description
#'  a visualization funtion to show agent requirement or schedules from
#'  48 x 7 matrix
#' @param m a 48 x 7 matrix
#' @return a ggplot object that plot 48 half hour window each day for 7 day
#' @family scheduler_viewer
schedule_viewer <- function(
  m, xlab_text = "Half-Hour Window", ylab_text = "Number of Agents",
  ggtitle_text = "Number of Agents by Half-Hour Window at Each Day",
  element_text_size = 22L
  ) {

  #- convert m 48 x 7 matrix into long format
  eval(parse(text = paste0(
    "mL <- c(", paste0(sprintf("m[ , %s]", c(1L:7L)), collapse = ", "), ")"
  )))

  #- add hours and days on mL long format
  mT <- data.frame(
    n = mL,
    i = 1L:336L,
    h = rep(paste0(formatC(rep(0L:23L, each = 2L), width = 2L, flag = "0"), ":", c("00", "30")), 7L),
    d = rep(
      factor(
        x = c("Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"),
        levels = c("Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday")
      ),
      each = 48L
    )
  )

  #- create a number of agent by each half-hour window each day plot
  g <- ggplot2::ggplot(data = mT) +
    ggplot2::geom_bar(aes(x = h, y = n), stat = "identity") + facet_wrap(~ d) +
    xlab(xlab_text) + ylab(ylab_text) + ggtitle(ggtitle_text) +
    theme(
      text = element_text(size = element_text_size),
      axis.text.x = element_text(angle = 270, hjust = 1, vjust = 0.5)
    )

  return(g)
}


#' schedule_viewer1
#' @description
#'  a visualization funtion to show agent requirement or schedules from
#'  48 x 7 matrix, a.k.a, schedule_viewer
#' @param m a 48 x 7 matrix
#' @return a ggplot object that plot 48 half hour window each day for 7 day
#' @family scheduler_viewer
schedule_viewer1 <- schedule_viewer

#' schedule_viewer2
#' @description
#'  a visualization funtion to show agent requirement or schedules from two
#'  48 x 7 matrices, compare requirement and schedule side by side
#' @param m1 a 48 x 7 matrix
#' @param m2 a 48 x 7 matrix
#' @return a ggplot object that plot 48 half hour window each day for 7 day
#' @family scheduler_viewer
schedule_viewer2 <- function(
  m1, m2, m1_label = "Agent Required", m2_label = "Agent Available",
  legend_title = "Legend",
  xlab_text = "Half-Hour Window", ylab_text = "Number of Agents",
  ggtitle_text = "Number of Agents by Half-Hour Window at Each Day",
  element_text_size = 22L
) {

  #- convert m1 m2 48 x 7 matrix into long format
  eval(parse(text = paste0(
    "m1L <- c(", paste0(sprintf("m1[ , %s]", c(1L:7L)), collapse = ", "), ")"
  )))

  eval(parse(text = paste0(
    "m2L <- c(", paste0(sprintf("m2[ , %s]", c(1L:7L)), collapse = ", "), ")"
  )))

  #- add hours and days on mL long format
  mT <- data.frame(
    n = c(m1L, m2L),
    l = rep(factor(x = c(m1_label, m2_label), levels = c(m1_label, m2_label)), each = 336L),
    i = rep(1L:336L, times = 2L),
    h = rep(rep(
      paste0(formatC(rep(0L:23L, each = 2L), width = 2L, flag = "0"), ":", c("00", "30")),
      times = 7L
      ),
      times = 2L
    ),
    d = rep(rep(
      factor(
        x = c("Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"),
        levels = c("Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday")
      ),
      each = 48L
      ),
      times = 2L
    )
  )

  #- create a number of agent by each half-hour window each day plot
  g <- ggplot2::ggplot(data = mT) +
    ggplot2::geom_bar(aes(x = h, y = n, fill = l), stat = "identity", position = "dodge") + facet_wrap(~ d) +
    ggtitle(ggtitle_text) + xlab(xlab_text) + ylab(ylab_text) +
    scale_fill_discrete(name = legend_title) +
    theme(
      text = element_text(size = element_text_size),
      axis.text.x = element_text(angle = 270, hjust = 1, vjust = 0.50)
    )

  return(g)
}

#' schedule_viewer3
#' @description
#'  a visualization funtion to show agent requirement or schedules from 3
#'  48 x 7 matrices, view details of 3 schedule modules side by side
#' @param m1 a 48 x 7 matrix
#' @param m2 a 48 x 7 matrix
#' @param m3 a 48 x 7 matrix
#' @return a ggplot object that plot 48 half hour window each day for 7 day
#' @family scheduler_viewer
schedule_viewer3 <- function(
  m1, m2, m3,
  m1_label = "Schedule Module 1",
  m2_label = "Schedule Module 2",
  m3_label = "Schedule Module 3",
  legend_title = "Legend",
  xlab_text = "Half-Hour Window", ylab_text = "Number of Agents",
  ggtitle_text = "Number of Agents by Half-Hour Window at Each Day",
  element_text_size = 22L
) {

  #- convert m1 m2 m3 48 x 7 matrix into long format
  for ( i in 1L:3L ) {

    eval(parse(text = paste0(
      "m", i, "L <- c(", paste0(sprintf(paste0("m", i, "[ , %s]"), c(1L:7L)), collapse = ", "), ")"
    )))

  }

  #- add hours and days on mL long format
  mT <- data.frame(
    n = c(m1L, m2L, m3L),
    l = rep(factor(
      x = c(m1_label, m2_label, m3_label),
      levels = c(m1_label, m2_label, m3_label))
      ,
      each = 336L
    ),
    i = rep(1L:336L, times = 3L),
    h = rep(rep(
      paste0(formatC(rep(0L:23L, each = 2L), width = 2L, flag = "0"), ":", c("00", "30")),
      times = 7L
    ),
    times = 3L
    ),
    d = rep(rep(
      factor(
        x = c("Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"),
        levels = c("Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday")
      ),
      each = 48L
    ),
    times = 3L
    )
  )

  #- create a number of agent by each half-hour window each day plot
  g <- ggplot2::ggplot(data = mT) +
    ggplot2::geom_bar(aes(x = h, y = n, fill = l), stat = "identity", position = "dodge") + facet_wrap(~ d) +
    ggtitle(ggtitle_text) + xlab(xlab_text) + ylab(ylab_text) +
    scale_fill_discrete(name = legend_title) +
    theme(
      text = element_text(size = element_text_size),
      axis.text.x = element_text(angle = 270, hjust = 1, vjust = 0.50)
    )

  return(g)
}
#------------------------------------------------------------------------------#


