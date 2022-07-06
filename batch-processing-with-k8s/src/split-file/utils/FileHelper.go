package utils

import (
	"os"
	"path/filepath"
	"strings"
)

const (
	MaxLinesPerBatch   = "MAX_LINES_PER_BATCH"
	S3BucketName       = "S3_BUCKET_NAME"
	S3Key              = "S3_KEY"
	EfsDirectoryPath   = "EFS_DIRECTORY"
	StatusKey          = "STATUS_KEY"
	RedisCacheEndpoint = "REDIS_CACHE_ENDPOINT"
	RedisCachePort     = "REDIS_CACHE_PORT"
	ReBuildTable       = "REBUILD_TABLE"

	defaultMaxLines = "10000"
)

/*
	Get list of all the files in a directory
*/
func GetFileList(dir string) []string {
	var files []string

	// Walk and collect all the file paths
	err := filepath.Walk(dir, func(path string, info os.FileInfo, err error) error {
		if strings.Contains(path, ".csv") {
			files = append(files, path)
		}
		return nil
	})
	if err != nil {
		panic(err)
	}
	return files
}

/*
	Get maximum allowed per split file
*/
func GetMaxLinesPerBatch() string {
	maxLines := os.Getenv(MaxLinesPerBatch)
	if len(strings.TrimSpace(maxLines)) > 0 {
		return maxLines
	} else {
		return defaultMaxLines
	}
}

/*
	Get file name from a file path
*/
func GetFileName(filePath string) string {
	s := strings.Split(filePath, "/")
	return s[len(s)-1]
}
