package utils

import (
	"errors"
	"github.com/aws/aws-sdk-go/aws"
	"github.com/aws/aws-sdk-go/aws/awserr"
	"github.com/aws/aws-sdk-go/aws/session"
	"github.com/aws/aws-sdk-go/service/dynamodb"
	"github.com/google/uuid"
	"log"
	"strconv"
)

const (
	RetryCounter = 10
	tableName    = "Order"
	hashKey      = "OrderId"
)

// Creates dynamodb session
var (
	sess = session.Must(session.NewSessionWithOptions(session.Options{
		SharedConfigState: session.SharedConfigEnable,
	}))
	svc = dynamodb.New(sess)
)



/*
	Batch delete items from DynamoDB based on `OrderId` (HASH)
*/
func DeleteItems(items []string) {
	var request []*dynamodb.WriteRequest
	for _, v := range items {
		request = append(request, &dynamodb.WriteRequest{
			DeleteRequest: &dynamodb.DeleteRequest{
				Key: map[string]*dynamodb.AttributeValue{
					hashKey: {
						S: aws.String(v),
					},
				},
			},
		})
	}

	/*
		Implement retry in case of throttledException and if the response contains
		any unprocessed results
	*/
	index := 0
	for index < RetryCounter {
		result, err := svc.BatchWriteItem(
			&dynamodb.BatchWriteItemInput{
				RequestItems: map[string][]*dynamodb.WriteRequest{
					tableName: request,
				}})

		if err != nil {
			if aerr, ok := err.(awserr.Error); ok {
				switch aerr.Code() {
				case dynamodb.ErrCodeProvisionedThroughputExceededException:
					index++
					if result != nil && len(result.UnprocessedItems[tableName]) > 0 {
						request = result.UnprocessedItems[tableName]
					}
				default:
					log.Printf("Error while performing batch delete %s", aerr.Error())
				}
			} else {
				log.Printf("Unknown error encountered %s", err.Error())
			}
		} else {
			break
		}
	}
}

/*
	Batch Dynamodb writes upto 25 items per request
*/
func BatchWriteItem(records []*Record) (map[string]string, error) {
	var request []*dynamodb.WriteRequest
	response := map[string]string{}
	for _, v := range records {
		confirmationId := uuid.NewString()
		response[v.OrderId] = confirmationId
		request = append(request, &dynamodb.WriteRequest{
			PutRequest: &dynamodb.PutRequest{Item: map[string]*dynamodb.AttributeValue{
				"Region": {
					S: aws.String(v.Region),
				},
				"Country": {
					S: aws.String(v.Country),
				},
				"ItemType": {
					S: aws.String(v.ItemType),
				},
				"SalesChannel": {
					S: aws.String(v.SalesChannel),
				},
				"OrderPriority": {
					S: aws.String(v.OrderPriority),
				},
				"OrderDate": {
					S: aws.String(v.OrderDate),
				},
				"OrderId": {
					S: aws.String(v.OrderId),
				},
				"ConfirmationId": {
					S: aws.String(confirmationId),
				},
				"ShipDate": {
					S: aws.String(v.ShipDate),
				},
				"UnitSold": {
					S: aws.String(strconv.Itoa(v.UnitSold)),
				},
				"UnitPrice": {
					S: aws.String(FormatFloat(v.UnitPrice)),
				},
				"TotalRevenue": {
					S: aws.String(FormatFloat(v.TotalRevenue)),
				},
				"TotalCost": {
					S: aws.String(FormatFloat(v.TotalCost)),
				},
				"TotalProfit": {
					S: aws.String(FormatFloat(v.TotalProfit)),
				},
			}},
		})
	}

	/*
		Implement retry in case of throttledException and if the response contains
		any unprocessed results
	*/
	index := 0
	for index < RetryCounter {
		result, err := svc.BatchWriteItem(
			&dynamodb.BatchWriteItemInput{
				RequestItems: map[string][]*dynamodb.WriteRequest{
					tableName: request,
				}})

		if err != nil {
			if aerr, ok := err.(awserr.Error); ok {
				switch aerr.Code() {
				case dynamodb.ErrCodeProvisionedThroughputExceededException:
					index++
					if result != nil && len(result.UnprocessedItems[tableName]) > 0 {
						request = result.UnprocessedItems[tableName]
					}
				default:
					log.Printf("Error while performing batch write %s", aerr.Error())
					return nil, aerr
				}
			} else {
				log.Printf("Unknown error encountered %s", err.Error())
				return nil, err
			}
		} else {
			if result != nil && len(result.UnprocessedItems[tableName]) > 0 {
				request = result.UnprocessedItems[tableName]
				index++
			} else {
				break
			}
		}
	}

	if index >= RetryCounter {
		return nil, errors.New("max retries exceeded, unable to process the batch")
	} else {
		return response, nil
	}
}
