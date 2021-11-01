from flask import Flask, render_template, request
from flask_cors import CORS, cross_origin
import os
import requests
import json
import time
import sys
import boto3
from datetime import datetime
import jwt
import base64


    

app = Flask(__name__)
cors = CORS(app)
app.config['CORS_HEADERS'] = 'Content-Type'


 
@app.route('/')
@cross_origin()
def index():
    response = ""
    region = os.environ.get('AWS_REGION')
    response +='<body text="blue" bgcolor="white"><head> <title>Yelb Sample Application </title> </head>'
    response += "<h2>User Identity Data from ALB / Cognito Integrated Authentication </h2> <hr/>"
    
    try:
      headers = dict(request.headers)
      encoded_jwt=""
      
      for k, v in headers.items():
        if k == 'X-Amzn-Oidc-Data':
          encoded_jwt=v
          break
      
      # Step 1: Get the key id from JWT headers (the kid field)
      jwt_headers = encoded_jwt.split('.')[0]
      decoded_jwt_headers = base64.b64decode(jwt_headers)
      decoded_jwt_headers = decoded_jwt_headers.decode("utf-8")
      decoded_json = json.loads(decoded_jwt_headers)
      kid = decoded_json['kid']
      
      # Step 2: Get the public key from regional endpoint
      url = 'https://public-keys.auth.elb.' + region + '.amazonaws.com/' + kid
      req = requests.get(url)
      pub_key = req.text
    
      
      # Step 3: Get the payload
      payload = jwt.decode(encoded_jwt, pub_key, algorithms=['ES256'])
      sub = payload['sub']
      email = payload['email']
      response += '<p style="color:green;"><b>'
      response += "sub={}  <br />".format(sub)
      response += "email={} <br />".format(email)

      
      
    except Exception as e:
      print(e)
      response += "\n error={} \n". format(str(e))

    return response


if __name__ == '__main__':
    print("Starting A Simple Web Service ...")
    app.run(port=80,host='0.0.0.0')
