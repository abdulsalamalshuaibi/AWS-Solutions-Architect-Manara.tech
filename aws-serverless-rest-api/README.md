# Serverless REST API on AWS

## Overview
A serverless REST API using AWS Lambda, API Gateway, and DynamoDB to manage simple CRUD operations.

## Architecture
- API Gateway exposes REST endpoints
- Lambda functions handle API requests
- DynamoDB stores records
- Optional: S3 hosts front-end

![Architecture Diagram](docs/architecture-diagram.png)

## Deployment
1. Deploy the CloudFormation template in `infrastructure/cloudformation.yml`
2. Deploy Lambda functions
3. Test endpoints using Postman or curl

## Optional Demo
[Link to video demo or live deployment]
