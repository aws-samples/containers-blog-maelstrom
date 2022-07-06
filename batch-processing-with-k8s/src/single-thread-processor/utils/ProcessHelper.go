package utils

import (
	"log"
	"os"
	"strconv"
)

/*
	Converts float64 to string
*/
func FormatFloat(v float64) string {
	return strconv.FormatFloat(v, 'E', -1, 64)
}

/*
	POJO representation of CSV records
*/
func MarshalRecord(record []string) *Record {
	return &Record{
		Region:        record[0],
		Country:       record[1],
		ItemType:      record[2],
		SalesChannel:  record[3],
		OrderPriority: record[4],
		OrderDate:     record[5],
		OrderId:       record[6],
		ShipDate:      record[7],
		UnitSold:      GetInt(record[8]),
		UnitPrice:     GetFloat(record[9]),
		TotalRevenue:  GetFloat(record[10]),
		TotalCost:     GetFloat(record[11]),
		TotalProfit:   GetFloat(record[12]),
	}
}

/*
	Get integer value from string
*/
func GetInt(value string) int {
	res, err := strconv.Atoi(value)

	// Ignore bad values or empty spaces
	if err != nil {
		log.Printf("Error while converting string to integer %s", err.Error())
		return 0
	}
	return res
}

/*
	Get float64 value out of a string
*/
func GetFloat(value string) float64 {
	res, err := strconv.ParseFloat(value, 64)

	// Ignore bad values or empty spaces
	if err != nil {
		log.Printf("Error while converting string to float %s", err.Error())
		return 0.0
	}
	return res
}

/*
	Env variable to determine to either ignore error while processing the batch or
	fail the workload in case of a single error
*/
func IsErrorTolerated() bool {
	tolerated, err := strconv.ParseBool(os.Getenv("ERROR_TOLERATED"))
	if err != nil {
		log.Printf("Error while converting toleration status %s", err.Error())
		return true
	}

	return tolerated
}
