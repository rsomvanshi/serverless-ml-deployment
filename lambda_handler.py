import os
import pickle

import boto3
import numpy as np
from sklearn import svm, datasets


print('Loading function')  

model = None
def load_model():
    s3 = boto3.client('s3')
    s3_bucket = os.environ['S3_BUCKET']
    s3.download_file(s3_bucket, 'SVMModel.pckl', '/tmp/SVMModel.pckl')
    with open('/tmp/SVMModel.pckl', 'rb') as contents:
        model = pickle.load(contents)
    print("Model is now loaded in container")
    return model

# Cold start initialization
model = load_model()

def model_handler(event, context):
    global model
    # /tmp is a transient storage for Lambda execution context
    # If container is being reused, model should already be available
    # This avoids model deserialization per request
    if os.path.exists('/tmp/SVMModel.pckl'):
        print("Model is already loaded")
    else:
        # New lambda execution context, reload model again.
        print("Model is not loaded")
        model = load_model()

    sepal_length = event['queryStringParameters']['sepal_length']
    sepal_width  = event['queryStringParameters']['sepal_width']
    petal_length = event['queryStringParameters']['petal_length']
    petal_width  = event['queryStringParameters']['petal_width']

    user_input = np.array([sepal_length, sepal_width, petal_length, petal_width]).reshape(1,4)
    class_prediced = int(model.predict(user_input)[0])

    return {"statusCode": 200, \
        "headers": {"Content-Type": "application/json"}, \
        "body": "{\"PredictedIrisClass\": " + str(class_prediced) + "}"}
