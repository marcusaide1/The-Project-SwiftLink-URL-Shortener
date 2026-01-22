package main

import (
	"context"
	"crypto/rand"
	"encoding/base64"
	"fmt" // Added for formatting strings

	"github.com/aws/aws-lambda-go/events"
	"github.com/aws/aws-lambda-go/lambda"
	"github.com/aws/aws-sdk-go-v2/aws" // Added for aws.String
	"github.com/aws/aws-sdk-go-v2/config"
	"github.com/aws/aws-sdk-go-v2/feature/dynamodb/attributevalue" // Added for Marshal/Unmarshal
	"github.com/aws/aws-sdk-go-v2/service/dynamodb"
	"github.com/aws/aws-sdk-go-v2/service/dynamodb/types" // Added for AttributeValue types
)

type URLItem struct {
	ShortID string `dynamodbav:"short_id"`
	LongURL string `dynamodbav:"long_url"`
}

func generateShortID() string {
	b := make([]byte, 4)
	rand.Read(b)
	return base64.RawURLEncoding.EncodeToString(b)[:6]
}

func handler(ctx context.Context, request events.APIGatewayProxyRequest) (events.APIGatewayProxyResponse, error) {
	cfg, _ := config.LoadDefaultConfig(ctx)
	db := dynamodb.NewFromConfig(cfg)
	tableName := "SwiftLink_URLs"

	// --- SHORTEN LOGIC (POST) ---
	if request.HTTPMethod == "POST" {
		longURL := request.Body // Simplified for this example
		shortID := generateShortID()

		item := URLItem{ShortID: shortID, LongURL: longURL}
		av, _ := attributevalue.MarshalMap(item)

		_, err := db.PutItem(ctx, &dynamodb.PutItemInput{
			TableName: aws.String(tableName),
			Item:      av,
		})

		if err != nil {
			return events.APIGatewayProxyResponse{StatusCode: 500, Body: "Error saving to DB"}, nil
		}
		return events.APIGatewayProxyResponse{StatusCode: 201, Body: fmt.Sprintf("Shortened: %s", shortID)}, nil
	}

	// --- REDIRECT LOGIC (GET) ---
	if request.HTTPMethod == "GET" {
		shortID := request.PathParameters["id"]

		result, err := db.GetItem(ctx, &dynamodb.GetItemInput{
			TableName: aws.String(tableName),
			Key: map[string]types.AttributeValue{
				"short_id": &types.AttributeValueMemberS{Value: shortID},
			},
		})

		if err != nil || result.Item == nil {
			return events.APIGatewayProxyResponse{StatusCode: 404, Body: "URL not found"}, nil
		}

		var item URLItem
		attributevalue.UnmarshalMap(result.Item, &item)

		return events.APIGatewayProxyResponse{
			StatusCode: 301,
			Headers:    map[string]string{"Location": item.LongURL},
		}, nil
	}

	return events.APIGatewayProxyResponse{StatusCode: 405}, nil
}

func main() {
	lambda.Start(handler)
}
