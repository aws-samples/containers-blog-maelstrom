package main

import (
	"encoding/csv"
	"fmt"
	"io"
	"log"
	"os"
	"os/exec"
	"single.threaded.processor/main/utils"
	"strings"
)

/*
	Entry point for batch file processor
*/
func main() {
	if !strings.HasSuffix(os.Getenv(utils.S3Key), "csv") {
		fmt.Println("Only CSV file formats are supported")
		return
	}

	tolerated := utils.IsErrorTolerated()
	inputFile, outputFile, err := initialize()
	if err != nil {
		failure("Pre-requisites failed unable to proceed further " + err.Error())
	}
	if inputFile != nil {
		defer inputFile.Close()
	}
	if outputFile != nil {
		defer outputFile.Close()
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
				processRecords(records, tolerated, outputFile)
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
			processRecords(records, tolerated, outputFile)

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
	// Copy contents from source to destination
	sourceFile := utils.GetOutputFile(false)

	copyCmd := fmt.Sprintf("aws s3 cp %s s3://%s/%s_Single_Output", sourceFile,
		os.Getenv(utils.S3BucketName), os.Getenv(utils.S3Key))

	_, err := exec.Command("sh", "-c", copyCmd).Output()

	if err != nil {
		failure(err.Error())
	}

	utils.DeleteOutputFolder()
	utils.DeleteInputFile()
}

/*
	Cleanup output file
*/
func failure(msg string) {
	utils.DeleteProcessedData()
	utils.DeleteFile(utils.GetOutputFile(false))
	utils.DeleteOutputFolder()
	utils.DeleteInputFile()
	fmt.Println(msg)
	panic(msg)
}

/*
	Run pre-requisites before executing the batch
*/
func initialize() (*os.File, *os.File, error) {
	// Get input file
	inputFilePath, err := utils.CopyS3ToEfs()
	if err != nil {
		return nil, nil, err
	}

	inputFile, err := utils.GetFile(*inputFilePath)
	if err != nil {
		log.Printf("Error while getting the input file " + err.Error())
		return nil, nil, err
	}

	// Delete and recreate output file
	outputFile, err := utils.TruncateFile(utils.GetOutputFile(true))
	if err != nil {
		log.Printf("Error while creating output file " + err.Error())
		return nil, nil, err
	}

	// Delete and recreate table
	err = utils.RecreateTable()
	if err != nil {
		log.Printf("Error while creating dynamodb tables " + err.Error())
		return nil, nil, err
	}

	return inputFile, outputFile, nil
}
