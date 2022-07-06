package main

import (
	"encoding/csv"
	"file.processor/main/utils"
	"fmt"
	"io"
	"io/ioutil"
	"log"
	"os"
)

/*
	Entry point for batch file processor
*/
func main() {
	tolerated := utils.IsErrorTolerated()
	inputFile, outputFile, tmpFile, err := initialize()
	if err != nil {
		failure("Pre-requisites failed unable to proceed further " + err.Error())
	}
	if inputFile != nil {
		defer inputFile.Close()
	}
	if outputFile != nil {
		defer outputFile.Close()
	}
	if tmpFile != nil {
		defer tmpFile.Close()
	}

	// Start parsing the inputFile
	totalRecords := 0
	reader := csv.NewReader(inputFile)
	var records []*utils.Record
	index := 0

	// Skip first row header
	record, errRead := reader.Read()
	for {
		record, errRead = reader.Read()
		if errRead == io.EOF {
			if len(records) > 0 {
				processRecords(records, tolerated, tmpFile)
			}

			success()
			break
		}
		if errRead != nil {
			failure("Error while reading the inputFile records " + errRead.Error())
		}
		index++
		totalRecords++

		if index == utils.MaxRecordsPerBatch {
			processRecords(records, tolerated, tmpFile)

			// Trim data
			records = records[:0]
			index = 0
			log.Printf("Total records so far - %v", totalRecords)
		} else {
			records = append(records, utils.MarshalRecord(record))
		}
	}
}

/*
	Process records, append to tmp file and save the records in DynamoDB
*/
func processRecords(records []*utils.Record, tolerated bool, tmpFile *os.File) {
	response, err := utils.BatchWriteItem(records)
	if err != nil && !tolerated {
		failure("Error while saving data to dynamodb")
	}
	err = utils.AppendFile(response, tmpFile)
	if err != nil {
		failure("Error while appending output file")
	}
}

func success() {
	err := utils.RemoveFromCache(os.Getenv(utils.InputFile))
	if err != nil {
		failure("Error while removing items from cache " + err.Error())
	}

	// Copy contents from source to destination
	sourceFile := utils.GetTmpFile()
	destinationFile := utils.GetOutputFile()
	input, err := ioutil.ReadFile(sourceFile)
	if err != nil {
		failure(err.Error())
	}

	err = ioutil.WriteFile(destinationFile, input, 0644)
	if err != nil {
		failure("Error creating" + err.Error())
	}

	cacheItems := utils.GetDataFromSet()
	if len(cacheItems) == 0 {
		err = utils.MoveFilesToS3()
		if err != nil {
			failure("Error while copying files to S3 " + err.Error())
		}
	}

	utils.DeleteTmpFile()
}

/*
	Cleanup output file
*/
func failure(msg string) {
	utils.DeleteProcessedData()
	utils.DeleteFile(utils.GetOutputFile())
	utils.DeleteTmpFile()
	fmt.Println(msg)
	panic(msg)
}

/*
	Run pre-requisites before executing the batch
*/
func initialize() (*os.File, *os.File, *os.File, error) {
	// Get input file
	inputEnv := os.Getenv(utils.InputFile)
	inputFile, err := utils.GetFile(inputEnv)
	if err != nil {
		log.Printf("Error while getting the input file " + err.Error())
		return nil, nil, nil, err
	}

	// Delete and recreate output file
	outputFile, err := utils.TruncateFile(utils.GetOutputFile())
	if err != nil {
		log.Printf("Error while creating output file " + err.Error())
		return nil, nil, nil, err
	}

	// Delete and recreate output file
	tmpFile, err := utils.TruncateFile(utils.GetTmpFile())
	if err != nil {
		log.Printf("Error while creating temp file " + err.Error())
		return nil, nil, nil, err
	}

	return inputFile, outputFile, tmpFile, nil
}
