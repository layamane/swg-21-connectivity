# Create input for SAM model
# Q, Qant, Rad
# Accounts for random effect of site (intercept-only, due to low sample size)


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

source("scripts/functions/f_make_bayes_mod05_dataset.R")
mod_df <- f_make_bayes_mod05_dataset()

# pull out datasets
chla_all <- mod_df$chla_all
covars <- mod_df$covars

# Visualize Data ----------------------------------------------------------

# check histogram of logged chlorophyll
hist(log(chla_all$chl))

# check sd among site mean chlorophyll, set as parameter for folded-t prior
sd(tapply(chla_all$chl, chla_all$station_id, mean))
# look at chl by station
ggplot(as.data.frame(chla_all), aes(x = station, y = log(chl))) + geom_boxplot()

# Create Model Datalist ---------------------------------------------------

datlist <- list(chl = log(chla_all$chl),
                Q = c(covars$Q),
                Srad_mwk = c(covars$Srad_mwk),
                station_id = chla_all$station_id,
                Nstation = length(unique(chla_all$station_id)),
                doy1998 = chla_all$doy1998,
                N = nrow(chla_all),
                pA = c(1, 3, 3, 7, 7),
                # mean of 1 day, mean of 3 days before that, etc
                nlagA = 5, # index for for loop
                alphaA = rep(1, 5)) # for prior


# Set up Initial Model Starts ---------------------------------------------

# Initials functions for root node parameters
inits <- function(){
  list(sig.eps = runif(1, 0, 15),
       tau = runif(1, 0, 1),
       B = rnorm(4, 0, 1000)) # for 4 B parameters, adjust as needed
}
initslist <- list(inits(), inits(), inits())

# run this if model has been successfully run already:

# Or load saved.state
load("bayes_models/mod05/inits/sstate.Rda")
inits_2 <- function(){
  list(sig.eps = runif(1, 0, 1),
       tau = runif(1, 0, 1),
       B = rnorm(4, 0, 1)) # for 3 B parameters, adjust as needed
}
initslist <- list(list(sig.eps = saved.state[[2]][[2]]$sig.eps, tau = saved.state[[2]][[2]]$tau, B = inits_2()$B), list(sig.eps = saved.state[[2]][[3]]$sig.eps, tau = saved.state[[2]][[3]]$tau, B = inits_2()$B), inits_2())

# Run Model ---------------------------------------------------------------

# Run model
jm <- jags.model("bayes_models/mod05/sam_model.JAGS",
                 data = datlist,
                 inits = initslist,
                 n.chains = 3)

update(jm, n.iter = 1000)

# Sample Posterior
jm_coda <- coda.samples(jm,
                        variable.names = c("deviance", "Dsum", "Bstar", "wA",
                                           "deltaA",
                                           "sig", "tau", "sig.eps", "tau.eps",
                                           "Estar"),
                        n.iter = 1000*15,
                        thin = 15)



# Load Saved Model --------------------------------------------------------

#load("bayes_models/mod05/run_20211207.rda")

# Visualize
mcmcplot(jm_coda)
# Look at R-hat values. >1.02 would indicate did not converge
gelman.diag(jm_coda, multivariate = FALSE)

# Save state for rerunning
newinits <- initfind(coda = jm_coda)
#saved.state <- removevars(initsin = newinits, variables=c(2:5, 8, 9))
saved.state <- newinits
save(saved.state, file = "bayes_models/mod05/inits/sstate_20211207.Rda")


# Look at Outputs ---------------------------------------------------------

# betas
caterplot(jm_coda,
          regex  = "Bstar",
          reorder = FALSE)

# stations
caterplot(jm_coda,
          parms = "Estar",
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

# intercept (interpreted as log(chlA) at average conditions, since covariates are standardized)
coda_sum %>%
  filter(grepl("Bstar\\[1", term)) %>%
  ggplot(aes(x = term, y = estimate)) +
  geom_hline(yintercept = 0, color = "red") +
  geom_pointrange(aes(ymin = conf.low, ymax = conf.high)) +
  scale_y_continuous("Intercept") +
  theme_bw()

# slope of Q, Qant
# can interpret relative influence of each covariate, since covariates are standardized
coda_sum %>%
  filter(grepl("Bstar\\[[2-4]{1}", term)) %>%
  ggplot(aes(x = term, y = estimate)) +
  geom_hline(yintercept = 0, color = "red") +
  geom_pointrange(aes(ymin = conf.low, ymax = conf.high)) +
  scale_x_discrete(labels = c("Q", "Qant", "Srad_mwk")) +
  scale_y_continuous("Slope of covariates") +
  theme_bw()
ggsave(filename = "bayes_models/mod05/fig_out/slope_of_betas_qant_20211207.png",
       dpi=300, width = 10, height = 8)

# weights of Qant
coda_sum %>%
  filter(grepl("wA", term)) %>%
  ggplot(aes(x = term, y = estimate)) +
  geom_hline(yintercept = 1/5, color = "red") +
  geom_pointrange(aes(ymin = conf.low, ymax = conf.high)) +
  scale_y_continuous("Weights of past Q") +
  theme_bw()
ggsave(filename = "bayes_models/mod05/fig_out/weights_of_qant_20211207.png",
       dpi=300, width = 10, height = 8)


# save model
save(jm_coda, coda_sum, file = "bayes_models/mod05/run_20211207.rda")

# save model summary
sink("bayes_models/mod05/fig_out/jm_coda_summary.txt")
summary(jm_coda)
sink()
