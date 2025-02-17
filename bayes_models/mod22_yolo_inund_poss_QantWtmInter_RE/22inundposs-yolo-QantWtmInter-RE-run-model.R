# Create input for SAM model
# Qant, Rad, Wtemp_mwk (deseasonalized), Wtemprange_mwk, inund_days
# Try old lags (5; 1, 4, 7, 14, 21 daus prior to doy) for Qant's effect on chl

# Libraries ---------------------------------------------------------------

library(readr)
library(dplyr)
library(rjags)
library(zoo)
load.module('dic')
library(mcmcplots)
library(broom.mixed)
library(ggplot2)
library(naniar)
library(lubridate)
#devtools::install_github("fellmk/PostJAGS/postjags")
library(postjags)

# Bring in Data For Model -------------------------------------------------

source("scripts/functions/f_make_bayes_mod20inundposs_want_RE_dataset.R")
mod_df <- f_make_bayes_mod20inundposs_want_RE_dataset()

# pull out datasets
# to restrict analysis to yolo region
chla_yolo <- mod_df$chla_yolo
covars_yolo <- mod_df$covars_yolo

# Visualize Data ----------------------------------------------------------

# chlorophyll over time
chla_obs <- chla_yolo %>% ggplot(aes(doy1999, chlorophyll, color = station_wq_chl)) +
  geom_point()

chla_obs_log <- chla_yolo %>% ggplot(aes(doy1999, log(chlorophyll), color = station_wq_chl)) +
  geom_point()

q_obs <- covars_yolo %>% filter(doy1999 > 3500) %>% ggplot(aes(doy1999, Q)) +
  geom_point()

# Merge chl and q
chla_obs

# check histogram of logged chlorophyll
hist(log(chla_yolo$chlorophyll))

# check sd among site mean chlorophyll, set as parameter for folded-t prior
sd(tapply(chla_yolo$chlorophyll, chla_yolo$station_id, mean))
# look at chl by station
ggplot(as.data.frame(chla_yolo), aes(x = station_wq_chl, y = log(chlorophyll))) + geom_boxplot()
# Create Model Datalist ---------------------------------------------------

# Make inundation = 0 (not inundated) as category 1, and inundation = 1 (inundated) as category 2
covars_yolo$inundation <- as.integer(ifelse(covars_yolo$inundation == "0", 1, 2))
alphaA <- matrix(0, 7, 2)
alphaA[,1] <- rep(1, 7)
alphaA[,2] <- rep(1, 7)

datlist <- list(chl = log(chla_yolo$chlorophyll),
                Q = c(covars_yolo$Q),
                Wtmday = c(covars_yolo$Wtmday),
                inundation = c(covars_yolo$inundation),
                #station_id = chla_yolo$station_id,
                #Nstation = length(unique(chla_yolo$station_id)),
                doy1999 = chla_yolo$doy1999,
                N = nrow(chla_yolo),
                pA = c(1, 3, 3, 14, 14, 14, 14),
                # mean of 1 day, mean of 3 days before that, etc
                nlagA = 7, # index for for loop
                alphaA = alphaA)


# Set up Initial Model Starts ---------------------------------------------
B_mat <- matrix(0, 4, 2)
B_mat[,1] <- rnorm(4, 0, 1000)
B_mat[,2] <- rnorm(4, 0, 1000)

# Initials functions for root node parameters
inits <- function(){
  list(
       tau = runif(1, 0, 1),
       B = B_mat) #sig.eps = runif(1, 0, 15),
}
initslist <- list(inits(), inits(), inits())

# run this if model has been successfully run already:

# Or load saved.state
load("bayes_models/mod22_yolo_inund_poss_QantWtmInter_RE/inits/sstate_20220913.Rda")
inits_2 <- function(){
  list(
    tau = runif(1, 0, 1),
    B = B_mat) # for 4 B parameters * 2 inundation periods, adjust as needed
}
initslist <- list(list(tau = saved.state[[2]][[1]]$tau, B = inits_2()$B), list(tau = saved.state[[2]][[2]]$tau, B = inits_2()$B), inits_2())

# Run Model ---------------------------------------------------------------

# Run model
jm <- jags.model("bayes_models/mod22_yolo_inund_poss_QantWtmInter_RE/sam_model3.JAGS",
                 data = datlist,
                 inits = initslist,
                 n.chains = 3)

update(jm, n.iter = 1000)

# Sample Posterior
jm_coda <- coda.samples(jm,
                        variable.names = c("deviance", "Dsum", "Bstar", "wA",
                                           "deltaA",
                                           "sig", "tau") ,
                        n.iter = 1000*30,
                        thin = 30)
#, "sig.eps", "tau.eps","Estar")

# Load Saved Model --------------------------------------------------------

load("bayes_models/mod22_yolo_inund_poss_QantWtmInter_RE/run_20220913.rda")

mcmcplot(jm_coda, col = c("red", "blue", "green"))
# Look at R-hat values. >1.02 would indicate did not converge
gelman.diag(jm_coda, multivariate = FALSE)

# Save state for rerunning
newinits <- initfind(coda = jm_coda)
saved.state <- newinits
save(saved.state, file = "bayes_models/mod22_yolo_inund_poss_QantWtmInter_RE/inits/sstate_20220913.Rda")


# Look at Outputs ---------------------------------------------------------

# betas
caterplot(jm_coda,
          regex  = "Bstar",
          reorder = FALSE)

# time lags
caterplot(jm_coda,
          parms = "wA",
          reorder = FALSE)

# summarize and plot
coda_sum <- tidyMCMC(jm_coda,
                     conf.int = TRUE,
                     conf.level = 0.95,
                     conf.method = "HPDinterval")

# intercepts of not inundated vs. inundated (interpreted as log(chlA) at average conditions, since covariates are standardized)
coda_sum %>%
  filter(grepl("Bstar\\[1", term)) %>%
  ggplot(aes(x = term, y = estimate)) +
  geom_hline(yintercept = 0, color = "red") +
  geom_pointrange(aes(ymin = conf.low, ymax = conf.high)) +
  scale_y_continuous("Intercept") +
  scale_x_discrete(labels = c("not inundated", "inundated")) +
  theme_bw()
ggsave(filename = "bayes_models/mod22_yolo_inund_poss_QantWtmInter_RE/fig_out/slope_of_intercept_inund_20220913.png",
       dpi=300, width = 11, height = 8)

# slope of Qant, same day Water temp
# can interpret relative influence of each covariate, since covariates are standardized
coda_sum %>%
  filter(grepl("Bstar\\[[2-4]{1}", term)) %>%
  ggplot(aes(x = term, y = estimate)) +
  geom_hline(yintercept = 0, color = "red") +
  geom_pointrange(aes(ymin = conf.low, ymax = conf.high)) +
  scale_x_discrete(labels = c("NotInun:Qant", "Inun:Qant", "NotInun:Wtmday", "Inun:Wtmday", "NotInun:Qant*Wtmday", "Inun:Qant*Wtmday")) +
  scale_y_continuous("Slope of covariates") +
  theme_bw()
ggsave(filename = "bayes_models/mod22_yolo_inund_poss_QantWtmInter_RE/fig_out/slope_of_betas_qant_20220913.png",
       dpi=300, width = 11, height = 8)

# weights of Qant - Not inundated
coda_sum %>%
  filter(grepl("wA.*,1", term)) %>%
  ggplot(aes(x = term, y = estimate)) +
  geom_hline(yintercept = 1/7, color = "red") +
  geom_pointrange(aes(ymin = conf.low, ymax = conf.high)) +
  scale_x_discrete("Days into past", labels = c("1", "2-4", "5-7", "8-21", "22-35", "36-49", "50-63")) +
  scale_y_continuous("Weights of past Q for Not Inundated") +
  theme_bw()
ggsave(filename = "bayes_models/mod22_yolo_inund_poss_QantWtmInter_RE/fig_out/weights_of_qant_notinund_202200913.png",
       dpi=300, width = 10, height = 8)

# weights of Qant - Inundated
coda_sum %>%
  filter(grepl("wA.*,2", term)) %>%
  ggplot(aes(x = term, y = estimate)) +
  geom_hline(yintercept = 1/7, color = "red") +
  geom_pointrange(aes(ymin = conf.low, ymax = conf.high)) +
  scale_x_discrete("Days into past", labels = c("1", "2-4", "5-7", "8-21", "22-35", "36-49", "50-63")) +
  scale_y_continuous("Weights of past Q for Inundated") +
  theme_bw()
ggsave(filename = "bayes_models/mod22_yolo_inund_poss_QantWtmInter_RE/fig_out/weights_of_qant_inund_202200913.png",
       dpi=300, width = 10, height = 8)

# save model
save(jm_coda, coda_sum, file = "bayes_models/mod22_yolo_inund_poss_QantWtmInter_RE/run_20220913.rda")

# save model summary
sink("bayes_models/mod22_yolo_inund_poss_QantWtmInter_RE/fig_out/jm_coda_summary.txt")
summary(jm_coda)
sink()

# Look at the relationship between predicted model chl and actual data chl
## Need to monitor chl.rep directly
coda.rep <- coda.samples(jm, variable.names = "chl.rep", n.iter = 1000*15,
                         thin = 15)
coda.rep_sum <- tidyMCMC(coda.rep, conf.int = TRUE, conf.method = "HPDinterval") %>%
  rename(pd.mean = estimate, pd.lower = conf.low, pd.upper = conf.high)

# Check model fit
pred <- cbind.data.frame(chl = datlist$chl, coda.rep_sum)

m1 <- lm(pd.mean ~ chl, data = pred)
summary(m1) # Adjusted R2 = 0.41

pred %>%
  filter(!is.na(chl)) %>%
  ggplot(aes(x = chl, y = pd.mean)) +
  geom_abline(intercept = 0, slope = 1, col = "red") +
  geom_errorbar(aes(ymin = pd.lower, ymax = pd.upper,
                    alpha = 0.25)) +
  geom_point() +
  scale_x_continuous("Observed") +
  scale_y_continuous("Predicted") +
  theme_bw(base_size = 12)

ggsave(filename = "bayes_models/mod22_yolo_inund_poss_QantWtmInter_RE/fig_out/pred_vs_obs_20220913.png",
       dpi=300, width = 10, height = 8)

# Observed vs. predicted chlorophyll as a function of time
chl_obs_dates <- as.data.frame(chla_yolo) %>%
  select(date, doy1999)
pred_time <- cbind.data.frame(pred, chl_obs_dates)
pred_time$date <- as.Date(pred_time$date, format = "%Y-%m-%d")

pred_time %>%
  filter(!is.na(chl)) %>%
  ggplot(aes(x = date, y = pd.mean)) +
  geom_errorbar(aes(ymin = pd.lower, ymax = pd.upper),
                alpha = 0.25) +
  geom_point(aes(x = date, y = chl)) +
  scale_x_continuous("Date") +
  scale_y_continuous("Chlorophyll-a") +
  theme_bw(base_size = 12) +
  scale_x_date(date_labels = "%m-%Y")

ggsave(filename = "bayes_models/mod22_yolo_inund_poss_QantWtmInter_RE/fig_out/pred_obs_time_20220913.png",
       dpi=300, width = 10, height = 8)

