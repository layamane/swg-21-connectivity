# changed x-axis per Shruti's request (5/12/23)

# library
library(ggplot2)
library(dplyr)
library(mgcv)
library(tidymv)
library(patchwork)

# data

load("data_model/gams_origdata.Rdata")
downstream <- alldata %>% filter(region == "below")
unique(downstream$station)

#gamu6d prediction
#range(downstream$log_qsdy)
#new_dat<- data.frame(log_qsdy = rep(seq(4.5, 11.5, length.out = 75), 3),
#                     WTmwk = c(rep(8, 25), rep(12, 25), rep(16, 25), rep(8, 25), rep(12, 25), rep(16, 25), rep(8, 25), rep(12, 25), rep(16, 25)),
#                      inund_fac2 = c(rep("none", 75), rep("short", 75), rep("long", 75)), station = rep(NA, 225))

#new_pred <- predict(gamd6d, newdata=new_dat, se.fit = TRUE)

#model_p <- predict_gam(gamd6d, exclude_terms = "s(station)", values = list(WTmwk = c(8, 12, 16))) # exclude doesn't seem to be working, can't find anything online

#model_p_station <- predict_gam(gamd6d, values = c(list(WTmwk = c(8, 12, 16)), list(station = c("D22", "NZ068", "16", "34", "653", "657", "USGS-11455478"))))

#alternate
model_p_station <- predict_gam(gamd6d, values = c(WTmwk = 12, list(station = c("D22", "NZ068", "16", "34", "653", "657", "USGS-11455478"))))

model_p_station$lower <- model_p_station$fit - model_p_station$se.fit
model_p_station$upper <- model_p_station$fit + model_p_station$se.fit

# need to remove unrealistic values
downstream %>%
  group_by(inund_fac2) %>%
  summarise(max = max(log_qsdy), min = min(log_qsdy))

model_p_station$corr <- ifelse(model_p_station$inund_fac2 == "none" & model_p_station$log_qsdy > 11.1, "no",
                               ifelse(model_p_station$inund_fac2 == "short" & model_p_station$log_qsdy < 10.3 , "no",
                                      ifelse(model_p_station$inund_fac2 == "short" & model_p_station$log_qsdy > 12 , "no",
                                             ifelse(model_p_station$inund_fac2 == "long" & model_p_station$log_qsdy < 11 , "no",
                                                   "yes"))))

model_p_station_sub <- subset(model_p_station, corr == "yes")
#model_p_station_sub <- !duplicated(model_p_station_sub)

# plot
downstream_plot <- ggplot(model_p_station_sub, aes(log_qsdy, fit, colour = inund_fac2)) +
  geom_point(size=1.25) +
  geom_ribbon(data = model_p_station_sub, aes(ymin = lower, ymax = upper, fill = inund_fac2),linetype=2, alpha=0.1) +
  scale_x_continuous(name ="log(daily flow (cfs))", limits = c(8.5, 12)) +
  ylab("Predicted Chlorophyll") +
  #facet_grid(.~ WTmwk, scales="free", space="free") +
  #theme_vis +
  theme_classic() +
  theme(legend.position = "none") +
  ggtitle("Downstream")

# found this online (https://cran.r-project.org/web/packages/tidymv/vignettes/predict-gam.html) slight different looking
predict_gam(gamd6d, values = list (WTmwk = c(8, 12, 16)), exclude_terms = "station") %>%
  ggplot(aes(log_qsdy, fit, colour = inund_fac2)) +
  geom_smooth_ci(inund_fac2) +
  facet_grid(.~ WTmwk, scales="free", space="free")

# gamu6d
upstream <- alldata %>% filter(region == "above")
unique(upstream$station)

#model_p_upstream <- predict_gam(gamu6d, exclude_terms = "s(station)", values = list (WTmwk = c(8, 12, 16)), station = NULL)

#model_p_upstream <- predict_gam(gamu6d, values = c(list (WTmwk = c(8, 12, 16)), list (station = c("USGS-11447650", "SHR"))))

#alternate
model_p_upstream <- predict_gam(gamu6d, values = c(WTmwk = 12, list (station = c("USGS-11447650", "SHR"))))

model_p_upstream$lower <- model_p_upstream$fit - model_p_upstream$se.fit
model_p_upstream$upper <- model_p_upstream$fit + model_p_upstream$se.fit

# need to remove unrealistic values
upstream %>%
  group_by(inund_fac2) %>%
  summarise(max = max(log_qsdy), min = min(log_qsdy))

model_p_upstream$corr <- ifelse(model_p_upstream$inund_fac2 == "none" & model_p_upstream$log_qsdy > 10.9, "no",
                               ifelse(model_p_upstream$inund_fac2 == "short" & model_p_upstream$log_qsdy < 10.3 , "no",
                                      ifelse(model_p_upstream$inund_fac2 == "short" & model_p_upstream$log_qsdy > 11.2 , "no",
                                             ifelse(model_p_upstream$inund_fac2 == "long" & model_p_upstream$log_qsdy < 10.8 , "no",
                                                    "yes"))))

model_p_upstream_sub <- subset(model_p_upstream, corr == "yes")

# plot
upstream_plot <- ggplot(model_p_upstream_sub, aes(log_qsdy, fit, colour = inund_fac2)) +
  geom_point(size=1.25) +
  geom_ribbon(data = model_p_upstream_sub, aes(ymin = lower, ymax = upper, fill = inund_fac2),linetype=2, alpha=0.1) +
  scale_x_continuous(name ="log(daily flow (cfs))", limits = c(9, 11)) +
  ylab("Predicted Chlorophyll") +
  #facet_grid(.~ WTmwk, scales="free", space="free") +
  #theme_vis +
  theme_classic() +
  theme(legend.position = "top") +
  labs(fill="Inundation Duration (categorical)", color="Inundation Duration (categorical)") +
  ggtitle("Mainstem")

# gamyo6d
yolo <- alldata %>% filter(region == "yolo")
unique(yolo$station)

#model_p_yolo <- predict_gam(gamyo6d, exclude_terms = 's(station)', values = list (WTmwk = c(8, 12, 16)))

#model_p_yolo_station <- predict_gam(gamyo6d, exclude_terms = 's(station)', values = c(list (WTmwk = c(8, 12, 16)), list (station = c("USGS-11455139", "LIS", "STTD"))))

#alternate
model_p_yolo_station <- predict_gam(gamyo6d, values = c(WTmwk = 12, list (station = c("USGS-11455139", "LIS", "STTD"))))

model_p_yolo_station$lower <- model_p_yolo_station$fit - model_p_yolo_station$se.fit
model_p_yolo_station$upper <- model_p_yolo_station$fit + model_p_yolo_station$se.fit

# need to remove unrealistic values
yolo %>%
  group_by(inund_fac2) %>%
  summarise(max = max(log_qsdy), min = min(log_qsdy))

model_p_yolo_station$corr <- ifelse(model_p_yolo_station$inund_fac2 == "none" & model_p_yolo_station$log_qsdy > 8.41, "no",
                                ifelse(model_p_yolo_station$inund_fac2 == "short" & model_p_yolo_station$log_qsdy < 7.86 , "no",
                                       ifelse(model_p_yolo_station$inund_fac2 == "short" & model_p_yolo_station$log_qsdy > 12.1 , "no",
                                              ifelse(model_p_yolo_station$inund_fac2 == "long" & model_p_yolo_station$log_qsdy < 8.29, "no",
                                                     "yes"))))

model_p_yolo_station_sub <- subset(model_p_yolo_station, corr == "yes")

# plot

yolo_plot <- ggplot(model_p_yolo_station_sub, aes(log_qsdy, fit, colour = inund_fac2)) +
  geom_point(size=1.25) +
  geom_ribbon(data = model_p_yolo_station_sub, aes(ymin = lower, ymax = upper, fill = inund_fac2),linetype=2, alpha=0.1) +
  scale_x_continuous(name ="log(daily flow (cfs))", limits = c(4, 12)) +
  ylab("Predicted Chlorophyll") +
  #facet_grid(.~ WTmwk, scales="free", space="free") +
  #theme_vis +
  theme_classic() +
  theme(legend.position = "none") +
  ggtitle("Floodplain")

# stack plots
png("predict_plot.png", width = 8, height = 11, units = "in", pointsize = 12,
    bg = "white", res = 350)

upstream_plot + yolo_plot + downstream_plot +
  plot_layout(ncol = 1)

dev.off()
