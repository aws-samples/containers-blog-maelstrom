package main

import (
	"context"
	"lambda.map.parallel/main/utils"

	"github.com/aws/aws-lambda-go/lambda"
)

func main() {
	lambda.Start(handleRequest)
}

type StepFunctionEvent struct {
	StatusKey string `json:"StatusKey"`
}


func handleRequest(ctx context.Context, stepFunctionEvent StepFunctionEvent) ([]string, error){
	return utils.GetDataFromSet(stepFunctionEvent.StatusKey), nil
}