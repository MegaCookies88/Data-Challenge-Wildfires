# Loading libraries
library("doParallel")
library("parallel")
library("gbm")

# Loading the data in the current workspace
load("data_train.RData")

# Predict distribution for Poisson GBM on CNT
predict_cnt_prob_poisson = function(model, test){
  prediction = predict(model, test, type="response")
  cnt_probabilities = matrix(0, length(prediction), length(u_cnt))
  for (i in 1:length(prediction)){
    cnt_probabilities[i,] = ppois(u_cnt, lambda = prediction[i], log = FALSE)
  }
  cnt_probabilities
}

# Wind
data_train_DF$wind <- sqrt(data_train_DF$clim1^2 + data_train_DF$clim2^2)

# Relative humidity
data_train_DF$RH <- 100 * exp(17.625*(data_train_DF$clim3-273.15)/(data_train_DF$clim3-39.11)) /
  exp(17.625*(data_train_DF$clim4-273.15)/(data_train_DF$clim4-39.11))

# Removing NA
test <- data_train_DF[rowSums(is.na(data_train_DF)) > 0,]
new.test <- test[!is.na(test$CNT),]
test <- test[is.na(test$CNT),]
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

CNTmGBM_1 <- gbm(CNT ~ . -BA -clim1 -clim2, 
                distribution = "poisson",
                interaction.depth = 6,
                n.trees = 3000,
                n.minobsinnode = 10,
                shrinkage = 0.1,
                cv.folds = 0,
                n.cores = 10,
                data = train)

CNTmGBM_2 <- gbm(CNT ~ . -clim1 -clim2, 
                distribution = "poisson",
                interaction.depth = 6,
                n.trees = 3000,
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
prediction_cnt <- predict_cnt_prob_poisson(CNTmGBM_1, test)
prediction_cnt_2 <- predict_cnt_prob_poisson(CNTmGBM_2, test[!is.na(test$BA),])
prediction_cnt[!is.na(test$BA),] <- prediction_cnt_2

# Time to fit the model
print(elapsed.time)

# Saving prediction
save(prediction_cnt, file = "prediction_cnt.RData")

# Cleaning
rm(i,data_train_DF,u_ba,weights_ba,start.time,end.time,mean_CNT_voxel)


# SIMPLE TEST - TO REMOVE AFTER
get_score_cnt = function(prediction_cnt, obs, u_cnt, weights_cnt){ 
  distr_obs = c() 
  for(k in 1:length(u_cnt)){ 
    distr_obs = cbind(distr_obs, ifelse(u_cnt[k] < obs, 0, 1)) 
  } 
  weights_mat = matrix(weights_cnt, ncol = length(weights_cnt), nrow = length(obs), byrow = TRUE) 
  score_cnt = sum(weights_mat * (distr_obs - prediction_cnt)^2) 
  score_cnt = round(8e4*score_cnt/length(obs), digits=0)
  score_cnt
} 
test_ba0 <- test[test$BA==0 & !is.na(test$BA),]
test_ba0$CNT = 0
new.test <- rbind(new.test, test_ba0)
rm(test_ba0)
get_score_cnt(predict_cnt_prob_poisson(CNTmGBM_1, new.test), new.test$CNT, u_cnt, weights_cnt)
