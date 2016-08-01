## ---- warning=FALSE, message=FALSE---------------------------------------
#- load scheduler package
library(scheduler)

#- attach data in package
data("agent_requirement")

knitr::kable(agent_requirement)

## ---- fig.align='center', fig.cap='scheduler - visulation', fig.show='hold', out.width='100%'----
#- visualize the requirement
scheduler::schedule_viewer1(m = agent_requirement, element_text_size = 4L)

## ---- cache=FALSE, message=FALSE-----------------------------------------
#- suppose we want a schedule with default setting
(ss_list_01 <- scheduler(ar = agent_requirement, sm = c(1L, 2L, 3L)))

## num of agent needed in total with this schedule
with(ss_list_01, sum(s1 + s2 + s3))

## a comparision on schedule and requirement side by side
scheduler::schedule_viewer2(
  m1 = agent_requirement, m2 = ss_list_01[["ss"]], 
  m1_label = "Agent Required", m2_label = "Agent Available",
  element_text_size = 4L
)

## view of agent start time distribution on 3 schedule module side by side
scheduler::schedule_viewer3(
  m1 = ss_list_01[["s1"]], 
  m2 = ss_list_01[["s2"]], 
  m3 = ss_list_01[["s3"]],
  m1_label = "Schedule Module 1",
  m2_label = "Schedule Module 2",
  m3_label = "Schedule Module 3",
  element_text_size = 4L
)

## ---- cache=FALSE, message=FALSE-----------------------------------------
#- suppose we want a schedule allow shedule module 2L and 3L only, 
## and disable half-hour start, more constraints - less effective.
ss_list_02 <- scheduler(
  ar = agent_requirement, sm = c(2L, 3L),
  allow.half.hour.start = FALSE)

## compare the num of total agent required by solution ss_list_02
## with solution ss_list_01
with(ss_list_02, sum(s1 + s2 + s3)) - with(ss_list_01, sum(s1 + s2 + s3))

