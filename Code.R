## Load libraries
library(mlbench)
library(dplyr)
library(ggplot2)
library(leaps)
library(glmnet)
library(nclSLR)
library(MASS)
library(bestglm)
library(GGally)

## Load the data
data(BreastCancer)

## Data Cleaning - Remove NA values
Data_Raw <- BreastCancer %>%
  na.omit()

## Summary of the data
summary(Data_Raw)

## Convert ordered factor to numeric
Data_Numeric <- Data_Raw
sapply(2:10, function(i) {
  Data_Numeric[, i] <<- as.numeric(as.character(Data_Numeric[, i]))
})
Data_Numeric[,11] <- as.character(Data_Raw[,11])

# Check if correctly converted
unique(Data_Raw==Data_Numeric)

## Create an indicator variable for Class
Data_Indicator <- Data_Numeric %>%
  mutate("Class_Indicator"=if_else(Class == "benign",0,1))


## Exploratory Data Analysis

# Plot a bar chart showing the number of benign and malignant cases
ggplot(data=Data_Numeric) +
  geom_bar(mapping=aes(x=Class, fill=Class), width=0.25) +
  labs(title="Number of Benign and Malignant cases", x="Class", y="Count")

# Plot a scatterplot matrix between variables
ggpairs(Data_Numeric[2:11], aes(color=Class), lower=list(combo=wrap("facethist",bins=15)), 
        columnLabels = c("Clump Thickness", "Cell Size", "Cell Shape", "Marginal Adhesion", 
                         "Single Epithelial Cell Size", "Bare Nuclei", "Bland Chromatin", "Normal Nucleoli",
                         "Mitoses", "Class"))



## Classifiers

# Data Preparation
# Extract response variable
Y <- Data_Indicator[,12]

# Extract predictor variables
X_raw <- Data_Indicator[2:10]

# Scale the predictor variables (for comparison purposes)
X_scaled <- scale(X_raw)
Data_Scaled <- data.frame(X_scaled,Y)

# Split the data into a 70% training and 30% testing data
set.seed(850) # to make code reproducible
train_set <- sample(c(TRUE, FALSE), nrow(Data_Scaled), replace=TRUE, prob=c(0.70,0.30))
train_data <- Data_Scaled[train_set,]
test_data <- Data_Scaled[!train_set,]


## Logistic Regression with Best Subset Selection
# Best subset selection
bss_AIC <- bestglm(Data_Scaled, family=binomial, IC="AIC")
bss_BIC <- bestglm(Data_Scaled, family=binomial, IC="BIC")

# Identify best-fitting models
best_AIC <- bss_AIC$ModelReport$Bestk
best_BIC <- bss_BIC$ModelReport$Bestk

# Plot: Number of predictors vs Information Criterion with colors highlighting the minimum value
plot(0:9, bss_AIC$Subsets$AIC, xlab="Number of predictors", ylab="AIC", type="b")
points(best_AIC, bss_AIC$Subsets$AIC[best_AIC+1], col="#FF3399", pch=16)
title(main="Number of predictors vs AIC")
plot(0:9, bss_BIC$Subsets$BIC, xlab="Number of predictors", ylab="BIC", type="b")
points(best_BIC, bss_BIC$Subsets$BIC[best_BIC+1], col="#00B050", pch=16)
title(main="Number of predictors vs BIC")

# Number of predictors chosen
pstar = 6 
# Check the 6 variables found in the model
bss_AIC$Subsets[pstar+1,]

# Perform Logistic Regression with the 6 variables on the training data
lr_fit <- glm(Y ~ Cl.thickness + Cell.shape + Marg.adhesion + Bare.nuclei + Bl.cromatin + Normal.nucleoli,
              data=train_data, family="binomial")
summary(lr_fit)

# Compute fitted values for the validation data:
Lr_phat_test = predict(lr_fit, test_data[1:9], type="response")
Lr_yhat_test = ifelse(Lr_phat_test > 0.5, 1, 0)

# Compute test error
Lr_Test_Error <- 1 - mean(test_data$Y == Lr_yhat_test)

# Compute confusion matrix
Lr_matrix <- table(Observed=test_data[,10], Predicted=Lr_yhat_test)


## LASSO 
set.seed(850) # to make code reproducible

# convert training and test data to matrix class
train_data_matrix <- as.matrix(train_data[1:9])
results_train <- as.matrix(train_data[10])
test_data_matrix <- as.matrix(test_data[1:9])

# Choose grid of values for the tuning parameter
Lasso_grid = 10^seq(3, -6, length.out=100)
# Fit a model with LASSO penalty for each value of the tuning parameter
Lasso_fit = glmnet(train_data_matrix, results_train, family="binomial", alpha=1, standardize=FALSE, lambda=Lasso_grid)
# Examine the effect of the tuning parameter on the parameter estimates
plot(Lasso_fit, xvar="lambda", col=rainbow(9), label=TRUE)

# Perform 10-fold cross validation to find value for lambda
Lasso_cv = cv.glmnet(as.matrix(Data_Scaled[1:9]), as.matrix(Data_Scaled[10]), family="binomial", alpha=1, standardize=FALSE, 
                     lambda=Lasso_grid, type.measure="class")
plot(Lasso_cv)

# Identify the optimal value of lambda
Lasso_Lambda_min = Lasso_cv$lambda.min
Lasso_Lambda = which(Lasso_cv$lambda == Lasso_Lambda_min)

# Fit the final LASSO model with lambda=Lasso_Lambda_min
Lasso_final <- glmnet(train_data_matrix, results_train, family="binomial", alpha=1, standardize=FALSE, lambda=Lasso_Lambda_min)
coef(Lasso_final)

# Compute fitted values for the validation data:
Lasso_phat_test = predict(Lasso_final, test_data_matrix, s=Lasso_Lambda_min, type="response")
Lasso_yhat_test = ifelse(Lasso_phat_test > 0.5, 1, 0)

# Compute test error
Lasso_Test_Error <- 1 - mean(test_data$Y == Lasso_yhat_test)

# Compute confusion matrix
Lasso_matrix <- table(Observed=test_data[,10], Predicted=Lasso_yhat_test)



## LDA
set.seed(850) # to make code reproducible

# Fit the LDA classifier using the training data using M_6 from Best subset selection
lda_train <- lda(Y~Cl.thickness + Cell.shape + Marg.adhesion + Bare.nuclei + Bl.cromatin + Normal.nucleoli,
                 data=train_data)

# Compute fitted values for the validation data
lda_test <- predict(lda_train, test_data[1:9])
lda_yhat_test <- lda_test$class

## Calculate the test error
LDA_Test_error <- 1 - mean(test_data$Y == lda_yhat_test)

# Compute confusion matrix
lda_matrix <- table(Observed=test_data$Y, Predicted=lda_yhat_test)

# Converting group means to original scaling
Sample_Means <- attr(X_scaled,"scaled:center")
Sample_Variances <- attr(X_scaled, "scaled:scale")
GroupMeans_Original <- lda_train$means * Sample_Variances[c(1,3,4,6,7,8)] + Sample_Means[c(1,3,4,6,7,8)]


# Estimate Test error using cross validation
set.seed(850) # to make code reproducible

# 10-fold cross validation
nfolds = 10
# Sample fold-assignment index
fold_index = sample(nfolds, 683, replace=TRUE)

# function to estimate the average mean squared error (MSE) by general K-fold cross validation - logistic regression
reg_cv_log = function(X1, y, fold_ind) {
  Xy = data.frame(X1, y=y)
  nfolds = max(fold_ind)
  if(!all.equal(sort(unique(fold_ind)), 1:nfolds)) stop("Invalid fold partition.")
  cv_errors = numeric(nfolds)
  for(fold in 1:nfolds) {
    Log_cv_fit = glm(y ~ Cl.thickness + Cell.shape + Marg.adhesion + Bare.nuclei + Bl.cromatin + Normal.nucleoli, 
                     data=Xy[fold_ind!=fold,])
    yhat = predict(Log_cv_fit, Xy[fold_ind==fold,],type="response")
    yobs = y[fold_ind==fold]
    cv_errors[fold] = mean((yobs - yhat)^2)
  }
  fold_sizes = numeric(nfolds)
  for(fold in 1:nfolds) fold_sizes[fold] = length(which(fold_ind==fold))
  test_error = weighted.mean(cv_errors, w=fold_sizes)
  return(test_error)
}

# compute average MSE for logistic regression
lr_final_mse = reg_cv_log(Data_Scaled[,1:9], Data_Scaled[,10], fold_index)


# function to estimate the average mean squared error (MSE) by general K-fold cross validation - LASSO regression
reg_cv_lasso = function(X1, y, fold_ind) {
  Xy = data.frame(X1, y=y)
  nfolds = max(fold_ind)
  if(!all.equal(sort(unique(fold_ind)), 1:nfolds)) stop("Invalid fold partition.")
  cv_errors = numeric(nfolds)
  for(fold in 1:nfolds) {
    Lasso_cv_fit = glmnet(Xy[,1:9], Xy[,10], family="binomial", alpha=1, standardize=FALSE, lambda=Lasso_Lambda_min)
    yhat = predict(Lasso_cv_fit, as.matrix(X1[fold_ind==fold,]), s=Lasso_Lambda_min, type="response")
    yobs = y[fold_ind==fold]
    cv_errors[fold] = mean((yobs - yhat)^2)
  }
  fold_sizes = numeric(nfolds)
  for(fold in 1:nfolds) fold_sizes[fold] = length(which(fold_ind==fold))
  test_error = weighted.mean(cv_errors, w=fold_sizes)
  return(test_error)
}

# compute average MSE for lasso regression
lasso_final_mse = reg_cv_lasso(Data_Scaled[,1:9], Data_Scaled[,10], fold_index)


# function to estimate the average mean squared error (MSE) by general K-fold cross validation - LDA
reg_cv_lda = function(X1, y, fold_ind) {
  Xy = data.frame(X1, y=y)
  nfolds = max(fold_ind)
  if(!all.equal(sort(unique(fold_ind)), 1:nfolds)) stop("Invalid fold partition.")
  cv_errors = numeric(nfolds)
  for(fold in 1:nfolds) {
    Lda_cv_fit = lda(y~.,data=Xy)
    yhat = predict(Lda_cv_fit, X1[fold_ind==fold,], type="response")
    yhat_predictions = yhat$class
    yobs = y[fold_ind==fold]
    cv_errors[fold] = mean((as.numeric(as.character(yobs)) - as.numeric(as.character(yhat_predictions)))^2)
  }
  fold_sizes = numeric(nfolds)
  for(fold in 1:nfolds) fold_sizes[fold] = length(which(fold_ind==fold))
  test_error = weighted.mean(cv_errors, w=fold_sizes)
  return(test_error)
}

# compute average MSE for LDA
lda_final_mse = reg_cv_lda(Data_Scaled[,1:9], Data_Scaled[,10], fold_index)