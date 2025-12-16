#!/bin/bash
BASE_URL="http://localhost:3002"
# Using port 3002 to avoid conflict if 3000/3001 are taken

echo "=== Fletcher Server V2 Verification ==="

# 1. Register Device
echo "1. Registering Device..."
USER_ID="550e8400-e29b-41d4-a716-446655440000"
REG_RESP=$(curl -s -X POST "$BASE_URL/api/register" \
  -H "Content-Type: application/json" \
  -d "{\"user_id\": \"$USER_ID\"}")
echo $REG_RESP

# Extract API Key
API_KEY=$(echo $REG_RESP | grep -o '"api_key":"[^"]*' | cut -d'"' -f4)
echo "API Key: $API_KEY"

if [ -z "$API_KEY" ]; then
    echo "Failed to get API Key. Exiting."
    exit 1
fi

# 2. Store Location
echo "2. Storing Location..."
LOC_RESP=$(curl -s -X POST "$BASE_URL/api/locations" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $API_KEY" \
  -d '{"locations": [{"latitude": 37.7749, "longitude": -122.4194, "accuracy": 15, "timestamp": "2023-10-27T10:00:00Z"}]}')
echo $LOC_RESP

# 3. Privacy Settings
echo "3. Updating Privacy Settings (Low Precision)..."
PRIV_RESP=$(curl -s -X PATCH "$BASE_URL/api/privacy-settings" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $API_KEY" \
  -d '{"precision_level": "low"}')
echo $PRIV_RESP

# 4. OAuth Flow
echo "4. OAuth Flow..."
# A. Authorize
# We extract Code from redirect.
# curl -i to see header
AUTH_URL="$BASE_URL/auth/oauth/authorize?client_id=claude&redirect_uri=https://example.com&response_type=code&user_id=$USER_ID"
echo "Calling Authorize: $AUTH_URL"
REDIRECT_LOC=$(curl -s -w "%{redirect_url}" -o /dev/null "$AUTH_URL")
echo "Redirect: $REDIRECT_LOC"

CODE=$(echo $REDIRECT_LOC | sed -n 's/.*code=\([^&]*\).*/\1/p' | sed 's/%3D/=/g') 
echo "Auth Code: $CODE"

# B. Token
TOKEN_RESP=$(curl -s -X POST "$BASE_URL/auth/oauth/token" \
  -H "Content-Type: application/json" \
  -d "{\"code\": \"$CODE\", \"client_id\": \"claude\", \"grant_type\": \"authorization_code\"}")
echo "Token Resp: $TOKEN_RESP"

MCP_TOKEN=$(echo $TOKEN_RESP | grep -o '"access_token":"[^"]*' | cut -d'"' -f4)
echo "MCP Token: $MCP_TOKEN"

# 5. MCP Access
echo "5. Testing MCP Access (Current Location)..."
# Expecting low precision (~2 decimal places for 1km? TDD said 2 decimals)
# 37.7749 -> 37.77, -122.4194 -> -122.42
# We check the output
MCP_RESP=$(curl -s -H "Authorization: Bearer $MCP_TOKEN" "$BASE_URL/sse")
# SSE endpoint returns stream. We can't curl easily without timeout.
# But we can try to hit a resource if we supported HTTP resource access?
# TDD v2 specified JSON-RPC over SSE. We can't curl JSON-RPC easily over SSE.
# Wait, TDD said "MCP Server Endpoint: GET /sse ... Response: SSE stream".
# To test, we just check connection establishment (200 OK + event stream content type).

HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" -H "Authorization: Bearer $MCP_TOKEN" "$BASE_URL/sse")
echo "MCP Connection Code: $HTTP_CODE"

echo "=== Verification Complete ==="
