package utils

import (
	"context"
	"fmt"
	"github.com/redis/go-redis/v9"
	"os"
)

var (
	ctx = context.Background()
	rdb = redis.NewClusterClient(&redis.ClusterOptions{
		Addrs: []string{fmt.Sprintf("%s:%s", os.Getenv(RedisCacheEndpoint), os.Getenv(RedisCachePort))},
	})
)

/*
	Remove from value from set
*/
func RemoveFromCache(value string) error{
	_, err := rdb.SRem(ctx, os.Getenv(StatusKey), value).Result()
	if err != nil {
		return err
	}

	return nil
}

/*
	Get data from REDIS set
*/
func GetDataFromSet() []string {
	res, err := rdb.SMembers(ctx, os.Getenv(StatusKey)).Result()
	if err != nil {
		fmt.Println("Error while fetching set members " + err.Error())
	}

	return res
}
