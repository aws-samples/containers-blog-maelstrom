package utils

import (
	"context"
	"fmt"
	"github.com/redis/go-redis/v9"
	"os"
)

const(
	RedisCacheEndpoint = "REDIS_CACHE_ENDPOINT"
	RedisCachePort     = "REDIS_CACHE_PORT"
)

var (
	ctx = context.Background()
	rdb = redis.NewClusterClient(&redis.ClusterOptions{
		Addrs:    []string{fmt.Sprintf("%s:%s", os.Getenv(RedisCacheEndpoint), os.Getenv(RedisCachePort))},
	})
)

/*
	Get data from REDIS set
*/
func GetDataFromSet(status string) []string {
	res, err := rdb.SMembers(ctx, status).Result()
	if err != nil {
		fmt.Println("Error while fetching set members " + err.Error())
	}

	return res
}
