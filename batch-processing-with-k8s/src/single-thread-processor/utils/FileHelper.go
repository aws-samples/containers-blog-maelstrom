package utils

import (
	"encoding/csv"
	"fmt"
	"io"
	"log"
	"os"
	"os/exec"
	"strings"
)

const (
	S3BucketName     = "S3_BUCKET_NAME"
	S3Key            = "S3_KEY"
	EfsDirectoryPath = "EFS_DIRECTORY"
	StatusKey        = "STATUS_KEY"
	ReBuildTable     = "REBUILD_TABLE"

	MaxRecordsPerBatch = 25
)

var InputFilePath = getInputFile()

/*
	Append contents to an existing file
*/
func AppendFile(data map[string]string, file *os.File) error {

	// Create concatenated string
	var appendedString string
	for k, v := range data {
		appendedString += k + "," + v + "\n"
	}

	// Write to file
	if _, err := file.WriteString(appendedString); err != nil {
		log.Printf("Error while writing to file %s", err.Error())
		return err
	}
	return nil
}

/*
	Get file reference
*/
func GetFile(filePath string) (*os.File, error) {
	file, err := os.Open(filePath)
	if err != nil {
		log.Printf("Unable to open file " + err.Error())
		return nil, err
	}
	return file, nil
}

/*
	Delete and recreate the file, based on path specified in
	environment variable
*/
func TruncateFile(filePath string) (*os.File, error) {

	// Delete file and ignore error (if any)
	DeleteFile(filePath)

	// Create file based on file path
	file, err := os.Create(filePath)
	if err != nil {
		log.Printf("Unable to open file " + err.Error())
		return nil, err
	}
	return file, nil
}

/*
	Read output file and delete the records from DynamoDB based on 'OrderId' (HASH)
*/
func DeleteProcessedData() {
	outputFilePath := GetOutputFile(false)
	if Exists(outputFilePath) {
		outputFile, err := os.Open(outputFilePath)
		if err != nil {
			log.Printf("Error while opening the file %s", err.Error())
		}
		defer outputFile.Close()

		reader := csv.NewReader(outputFile)
		var orders []string
		index := 0
		for {
			record, errRead := reader.Read()
			if errRead == io.EOF {
				DeleteItems(orders)
				break
			}
			index++

			// Batch to 25 records at a time
			if index == MaxRecordsPerBatch {
				DeleteItems(orders)

				// Trim data
				orders = orders[:0]
				index = 0
			} else {
				orders = append(orders, record[0])
			}
		}
	}
}

/*
	Deletes file based on file path
*/
func DeleteFile(file string) {
	if Exists(file) {
		os.Remove(file)
	}
}

/*
	Check whether the file exists
*/
func Exists(filePath string) bool {
	if _, err := os.Stat(filePath); err != nil {
		if os.IsNotExist(err) {
			return false
		}
	}
	return true
}

/*
	Get file name from a file path
*/
func GetFileName(filePath string) string {
	s := strings.Split(filePath, "/")
	return s[len(s)-1]
}

/*
	Get output file based on env variable and input file name
*/
func GetOutputFile(overwrite bool) string {
	absoluteFileName := GetFileName(InputFilePath)
	dir := os.Getenv(EfsDirectoryPath) + "/" + os.Getenv(StatusKey) + "/" + "Output"
	mkDirs(dir)
	outputPath := dir + "/" + absoluteFileName

	var err error
	if !overwrite {
		if _, err := os.Stat(outputPath); os.IsNotExist(err) {
			_, err = os.Create(outputPath)
		}
	} else {
		_, err = os.Create(outputPath)
	}

	if err != nil {
		log.Printf("Unable to open file " + err.Error())
	}
	return outputPath
}

/*
	Equivalent to mkdirs() in unix
*/
func mkDirs(dir string) {
	err := os.MkdirAll(dir, 0777)
	if err != nil {
		log.Printf("Error while creating directories %s - %s", dir, err.Error())
	}
}

/*
	Delete output folder
*/
func DeleteOutputFolder() {
	err := os.RemoveAll(getOutputDir())
	if err != nil {
		log.Printf("Error while deleting output file %s", err.Error())
	}
}

/*
	Delete input file
*/
func DeleteInputFile() {
	err := os.RemoveAll(getInputFile())
	if err != nil {
		log.Printf("Error while deleting input file %s", err.Error())
	}
}

func CopyS3ToEfs() (*string, error) {
	efsDirectory := os.Getenv(EfsDirectoryPath)
	s3InputFilePath := fmt.Sprintf("s3://%s/%s", os.Getenv(S3BucketName), os.Getenv(S3Key))
	splitFileDirectory := fmt.Sprintf("%s/%s", efsDirectory, os.Getenv(StatusKey))

	os.RemoveAll(splitFileDirectory)
	os.MkdirAll(splitFileDirectory, os.ModePerm)

	// Copy files from S3 to EFS
	splitCommand := fmt.Sprintf("aws s3 cp %s %s", s3InputFilePath, InputFilePath)

	_, err := exec.Command("sh", "-c", splitCommand).Output()

	if err != nil {
		return nil, err
	}

	return &InputFilePath, nil
}

func getInputFile() string {
	efsDirectory := os.Getenv(EfsDirectoryPath)
	s3InputFilePath := fmt.Sprintf("s3://%s/%s", os.Getenv(S3BucketName), os.Getenv(S3Key))
	splitFileDirectory := fmt.Sprintf("%s/%s", efsDirectory, os.Getenv(StatusKey))
	return fmt.Sprintf("%s/%s", splitFileDirectory, GetFileName(s3InputFilePath))
}

func getOutputDir() string{
	return os.Getenv(EfsDirectoryPath) + "/" + os.Getenv(StatusKey) + "/" + "Output"
}
