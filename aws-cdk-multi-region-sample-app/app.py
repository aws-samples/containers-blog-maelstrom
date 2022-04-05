from flask import Flask
import requests
import json
# from ec2_metadata import ec2_metadata

app = Flask('hello-cloudbuild')

@app.route('/')
def hello():
  res = requests.get('http://169.254.169.254/latest/dynamic/instance-identity/document')
  data = json.loads(res.text)
  region = data['region']
  return ("Hello World from "+region)

  
if __name__ == '__main__':
  app.run(host = '0.0.0.0', port = 8080)