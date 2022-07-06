package utils

import (
	"errors"
	"github.com/aws/aws-sdk-go/aws"
	"github.com/aws/aws-sdk-go/aws/awserr"
	"github.com/aws/aws-sdk-go/aws/session"
	"github.com/aws/aws-sdk-go/service/dynamodb"
	"log"
	"os"
	"time"
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
	Recreates table and waits for its completion
*/
func RecreateTable() error {
	var (
		status *string
		err    error
	)

	// Get TableStatus
	status, _ = getTableStatus()

	// Delete table
	if os.Getenv(ReBuildTable) == "true" && *status == "ACTIVE" {
		err = deleteTable()
		if err != nil {
			log.Printf("Error while deleting table %s", err.Error())
			return err
		}
	}

	if status == nil || *status != "ACTIVE" {
		// Create table
		err = createTable()
		if err != nil {
			log.Printf("Error while creating table %s", err.Error())
			return err
		}
	}

	return nil
}

/*
	Deletes dynamodb table
*/
func deleteTable() error {
	_, err := svc.DeleteTable(&dynamodb.DeleteTableInput{TableName: aws.String(tableName)})
	if err != nil {
		if aerr, ok := err.(awserr.Error); ok {
			switch aerr.Code() {
			case dynamodb.ErrCodeResourceNotFoundException:
				return nil
			default:
				log.Printf(aerr.Error())
				return aerr
			}
		} else {
			log.Printf("Unknown error while deleting table %s", err)
			return err
		}
	}
	return pollForTableDeletion()
}

/*
	Creates dynamodb table
*/
func createTable() error {
	_, err := svc.CreateTable(&dynamodb.CreateTableInput{
		AttributeDefinitions: []*dynamodb.AttributeDefinition{
			{
				AttributeName: aws.String(hashKey),
				AttributeType: aws.String("S"),
			},
		},
		KeySchema: []*dynamodb.KeySchemaElement{
			{
				AttributeName: aws.String(hashKey),
				KeyType:       aws.String("HASH"),
			},
		},
		BillingMode: aws.String(dynamodb.BillingModePayPerRequest),
		TableName:   aws.String(tableName),
	})
	if err != nil {
		if aerr, ok := err.(awserr.Error); ok {
			switch aerr.Code() {
			case dynamodb.ErrCodeResourceInUseException:
				return nil
			default:
				log.Printf("Error while creating table: %s", err.Error())
				return aerr
			}
		}
	}

	return pollForTableCreation()
}

/*
	Keep polling till table becomes 'ACTIVE'
*/
func pollForTableCreation() error {
	index := 0
	var (
		status *string
		err    error
	)
	for index < RetryCounter {
		status, err = getTableStatus()
		if err != nil {
			log.Printf("Error while polling table %s", err.Error())
			return err
		} else {
			if *status == "ACTIVE" {
				break
			}
			time.Sleep(5 * time.Second)
			index++
		}
	}

	if index > RetryCounter {
		return errors.New("max retry exceeded for create table status change " + *status)
	}

	return nil
}

/*
	Delete tables and wait till deletion is complete
*/
func pollForTableDeletion() error {
	index := 0
	var err error
	for index < RetryCounter {
		_, err = getTableStatus()
		if err != nil {
			if aerr, ok := err.(awserr.Error); ok {
				switch aerr.Code() {
				case dynamodb.ErrCodeResourceNotFoundException:
					break
				default:
					log.Printf("Error while polling for delete status change %s", aerr.Error())
					return aerr
				}
			} else {
				log.Printf("Unknown error encountered, while polling for status %s", err.Error())
				return err
			}
		}
		time.Sleep(5 * time.Second)
		index++
	}

	if index > RetryCounter {
		return errors.New("max retry exceeded for checking for table deletion")
	}

	return nil
}

func getTableStatus() (*string, error) {
	res, err := svc.DescribeTable(&dynamodb.DescribeTableInput{TableName: aws.String(tableName)})
	if err != nil {
		log.Printf("Error while polling table %s", err.Error())
		return nil, err
	}

	return res.Table.TableStatus, err
}
