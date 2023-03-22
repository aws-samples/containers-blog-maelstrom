package utils

/*
	POJO representation of CSV record
*/
type Record struct {
	Region string
	Country string
	ItemType string
	SalesChannel string
	OrderPriority string
	OrderDate string
	OrderId string
	ShipDate string
	UnitSold int
	UnitPrice float64
	TotalRevenue float64
	TotalCost float64
	TotalProfit float64
}