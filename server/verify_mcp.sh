#!/bin/bash

BASE_URL="http://localhost:3000"
USER_ID=$(uuidgen)

echo "1. Registering User..."
REGISTER_RES=$(curl -s -X POST "$BASE_URL/api/register" \
  -H "Content-Type: application/json" \
  -d "{\"user_id\": \"$USER_ID\"}")

API_KEY=$(echo $REGISTER_RES | jq -r '.api_key')
echo "API Key: $API_KEY"

if [ "$API_KEY" == "null" ]; then
    echo "Registration failed: $REGISTER_RES"
    exit 1
fi

echo "2. Generating Cursor Token..."
CURSOR_RES=$(curl -s -X POST "$BASE_URL/api/mcp/generate-token" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $API_KEY" \
  -d "{\"assistant_type\": \"cursor\", \"token_name\": \"Test Cursor\"}")

INSTRUCTIONS=$(echo $CURSOR_RES | jq -r '.instructions')
echo "Full Response: $CURSOR_RES"
echo "Instructions for Cursor: $INSTRUCTIONS"

if [[ "$INSTRUCTIONS" == *"Open Cursor Settings"* ]]; then
    echo "PASS: Cursor instructions correct."
else
    echo "FAIL: Unexpected instructions."
fi

echo "3. Generating Other Token..."
OTHER_RES=$(curl -s -X POST "$BASE_URL/api/mcp/generate-token" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $API_KEY" \
  -d "{\"assistant_type\": \"other\", \"token_name\": \"Test Other\"}")

INSTRUCTIONS_OTHER=$(echo $OTHER_RES | jq -r '.instructions')
echo "Instructions for Other: $INSTRUCTIONS_OTHER"

if [[ "$INSTRUCTIONS_OTHER" == *"Configure your MCP client"* ]]; then
    echo "PASS: Other instructions correct."
else
    echo "FAIL: Unexpected instructions."
fi
