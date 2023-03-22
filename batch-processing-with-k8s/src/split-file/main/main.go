package main

import (
	"log"
	"os"
	"os/exec"
	"split.file/main/utils"
	"strings"
)

import (
	"fmt"
)

/*
	Entry point for file splitter
*/
func main() {
	inputKey := os.Getenv(utils.S3Key)
	if !strings.HasSuffix(inputKey, "csv") {
		fmt.Println("Only CSV file formats are supported")
		return
	}

	// Delete and recreate table
	err := utils.RecreateTable()
	if err != nil {
		log.Printf("Error while creating dynamodb tables " + err.Error())
		panic(err)
	}

	efsDirectory := os.Getenv(utils.EfsDirectoryPath)
	s3InputFilePath := fmt.Sprintf("s3://%s/%s", os.Getenv(utils.S3BucketName), os.Getenv(utils.S3Key))
	splitFileDirectory := fmt.Sprintf("%s/%s", efsDirectory, os.Getenv(utils.StatusKey))

	// Cleanup
	utils.RemoveSet()
	os.RemoveAll(splitFileDirectory)
	os.MkdirAll(splitFileDirectory, os.ModePerm)

	// Split large file into smaller files to EFS
	splitCommand := fmt.Sprintf("aws s3 cp %s - | split -l %s - %s/%s.",
		s3InputFilePath, utils.GetMaxLinesPerBatch(), splitFileDirectory, utils.GetFileName(s3InputFilePath))

	fmt.Println(splitCommand)
	_, err = exec.Command("sh", "-c", splitCommand).Output()

	if err != nil {
		failure(err)
	}

	// Update REDIS cache with the split file information
	splitFiles := utils.GetFileList(splitFileDirectory)
	utils.AddItemsToSet(splitFiles)

	fmt.Printf("Split stage complete and items in REDIS cache %s", utils.GetDataFromSet())
}

/*
	Failure handler
*/
func failure(err error) {
	fmt.Printf("Error while processing the file %s", err.Error())
	panic(err)
}
