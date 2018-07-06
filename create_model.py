from sklearn import svm, datasets
import pickle 
import numpy as np

iris = datasets.load_iris()

X = iris.data  
y = iris.target

svmModel = svm.SVC(kernel='poly', degree=3, C=1.0).fit(X, y)

with open('SVMModel.pckl', 'wb') as svmFile:
    pickle.dump(svmModel, svmFile)
