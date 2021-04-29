# Loading libraries
library("doParallel")
library("parallel")
library("gbm")

# Loading the data in the current workspace
load("data_train.RData")

# Predict distribution for Gaussian GBM on log(BA+1)
predict_ba_prob_gaussian_gbm1 = function(model, test){
  prediction = predict(model, test, type="response")
  sd = sd(prediction)
  ba_probabilities = matrix(0, nrow(test), length(u_ba))
  for (i in 1:nrow(test)){
    mu = prediction[i]
    ba_probabilities[i,] = pnorm(log(u_ba+1), mean = mu, sd = sd)
  }
  ba_probabilities
}

# Wind
data_train_DF$wind <- sqrt(data_train_DF$clim1^2 + data_train_DF$clim2^2)

# Relative humidity
data_train_DF$RH <- 100 * exp(17.625*(data_train_DF$clim3-273.15)/(data_train_DF$clim3-39.11)) /
  exp(17.625*(data_train_DF$clim4-273.15)/(data_train_DF$clim4-39.11))

# Scaling : Standard Scale for continuous variables
for (i in 8:length(data_train_DF)) {
  data_train_DF[,i] = scale(data_train_DF[,i])
}

# Removing NA
test <- data_train_DF[rowSums(is.na(data_train_DF)) > 0,]
new.test <- test[!is.na(test$BA),]
test <- test[is.na(test$BA),]
train <- data_train_DF[rowSums(is.na(data_train_DF)) == 0,]
rm(i,data_train_DF,u_cnt,weights_cnt)


# Generalized Boosted Regression on log(BA+1)
set.seed(42)
registerDoParallel(6)

# Start clock and fit
start.time <- Sys.time()

BAmGBM <- gbm(log1p(BA) ~ . -CNT -clim1 -clim2, 
              distribution = "gaussian",
              interaction.depth = 5,
              n.trees = 500,
              n.minobsinnode = 10,
              shrinkage = 0.1,
              cv.folds = 10,
              n.cores = 6,
              data = train)

# End clock and clusters
end.time <- Sys.time()
elapsed.time <- round((end.time - start.time), 3)
stopImplicitCluster()

# Prediction
prediction_ba <- predict_ba_prob_gaussian_gbm1(BAmGBM, test)

# Time to fit the model
rm(start.time,end.time)
print(elapsed.time)

# Saving prediction
save(prediction_ba, file = "prediction_ba.RData")

# SIMPLE TEST - TO REMOVE AFTER
test_cnt0 <- test[test$CNT==0 & !is.na(test$CNT),]
test_cnt0$BA = 0
new.test <- rbind(new.test, test_cnt0)
rm(test_cnt0)
get_score_ba(predict_ba_prob_gaussian_gbm1(BAmGBM, new.test), new.test$BA, u_ba, weights_ba)