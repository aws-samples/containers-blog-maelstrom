package utils

import (
	"context"
	"fmt"
	"github.com/go-redis/redis/v8"
	"os"
)

var (
	ctx = context.Background()
	rdb = redis.NewClusterClient(&redis.ClusterOptions{
		Addrs:    []string{fmt.Sprintf("%s:%s", os.Getenv(RedisCacheEndpoint), os.Getenv(RedisCachePort))},
	})
)

/*
	Add items to the set
*/
func AddItemsToSet(values []string) {
	rdb.SAdd(ctx, os.Getenv(StatusKey), values)
}

/*
	Remove set from the REDIS
*/
func RemoveSet() {
	rdb.Del(ctx, os.Getenv(StatusKey))
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
