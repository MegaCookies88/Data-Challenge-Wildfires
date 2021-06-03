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

# Removing NA
test <- data_train_DF[rowSums(is.na(data_train_DF)) > 0,]
new.test <- test[!is.na(test$BA),]
test <- test[is.na(test$BA),]
train <- data_train_DF[rowSums(is.na(data_train_DF)) == 0,]

# Scaling : Standard Scale for continuous variables
for (i in 8:length(data_train_DF)) {
  train[,i] = scale(train[,i])
  test[,i] = scale(test[,i])
  new.test[,i] = scale(new.test[,i])
}

# Adding mean fire per voxels
mean_CNT_voxel <- aggregate(train[,1], by=list(train$lon,train$lat), mean)
train$mean_fire <- mapply(function(x,y) mean_CNT_voxel[mean_CNT_voxel$Group.1==x & mean_CNT_voxel$Group.2==y,3],
                          train$lon, train$lat)
test$mean_fire <- mapply(function(x,y) mean_CNT_voxel[mean_CNT_voxel$Group.1==x & mean_CNT_voxel$Group.2==y,3],
                         test$lon, test$lat)
new.test$mean_fire <- mapply(function(x,y) mean_CNT_voxel[mean_CNT_voxel$Group.1==x & mean_CNT_voxel$Group.2==y,3],
                             new.test$lon, new.test$lat)


# Generalized Boosted Regression on log(BA+1)
set.seed(42)

# Start clock and clusters
registerDoParallel(10)
start.time <- Sys.time()

BAmGBM_1 <- gbm(log1p(BA) ~ . -CNT -clim1 -clim2, 
                distribution = "gaussian",
                interaction.depth = 5,
                n.trees = 1000,
                n.minobsinnode = 10,
                shrinkage = 0.1,
                cv.folds = 0,
                n.cores = 10,
                data = train)

BAmGBM_2 <- gbm(log1p(BA) ~ . -clim1 -clim2, 
                distribution = "gaussian",
                interaction.depth = 5,
                n.trees = 1000,
                n.minobsinnode = 10,
                shrinkage = 0.1,
                cv.folds = 0,
                n.cores = 10,
                data = train)

# End clock and clusters
end.time <- Sys.time()
elapsed.time <- round((end.time - start.time), 3)
stopImplicitCluster()

# Prediction
prediction_ba <- predict_ba_prob_gaussian_gbm1(BAmGBM_1, test)
prediction_ba_2 <- predict_ba_prob_gaussian_gbm1(BAmGBM_2, test[!is.na(test$CNT),])
prediction_ba[!is.na(test$CNT),] <- prediction_ba_2

# Time to fit the model
print(elapsed.time)

# Saving prediction
save(prediction_ba, file = "prediction_ba.RData")

# Cleaning
rm(i,data_train_DF,u_cnt,weights_cnt,start.time,end.time,mean_CNT_voxel)


# SIMPLE TEST - TO REMOVE AFTER
get_score_ba = function(prediction_ba, obs, u_ba, weights_ba){ 
  distr_obs = c() 
  for(k in 1:length(u_ba)){ 
    distr_obs = cbind(distr_obs, ifelse(u_ba[k] < obs, 0, 1)) 
  } 
  weights_mat = matrix(weights_ba, ncol = length(weights_ba), nrow = length(obs), byrow = TRUE) 
  score_ba = sum(weights_mat * (distr_obs - prediction_ba)^2) 
  score_ba = round(1.19*8e4*score_ba/length(obs), digits=0) # this is just to scale with previous results
  score_ba 
}
test_cnt0 <- test[test$CNT==0 & !is.na(test$CNT),]
test_cnt0$BA = 0
new.test <- rbind(new.test, test_cnt0)
rm(test_cnt0)
get_score_ba(predict_ba_prob_gaussian_gbm1(BAmGBM_1, new.test), new.test$BA, u_ba, weights_ba)
