#!/bin/bash

BASE_URL="http://localhost:3000"
# Use a static ID for repro if possible, or generate new
USER_ID=$(uuidgen)

echo "1. Registering..."
REGISTER_RES=$(curl -s -X POST "$BASE_URL/api/register" \
  -H "Content-Type: application/json" \
  -d "{\"user_id\": \"$USER_ID\"}")

API_KEY=$(echo $REGISTER_RES | jq -r '.api_key')
echo "API Key: $API_KEY"

echo "2. Fetching Tokens..."
TOKENS_RES=$(curl -v -X GET "$BASE_URL/api/mcp/tokens" \
  -H "Authorization: Bearer $API_KEY")

echo "Response Body:"
echo $TOKENS_RES
