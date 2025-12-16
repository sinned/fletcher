#!/bin/bash
BASE_URL="http://localhost:3001"
USER_A="11111111-1111-1111-1111-111111111111"
USER_B="22222222-2222-2222-2222-222222222222"

echo "1. Storing location for User A..."
# Save location and capture output
RESPONSE=$(curl -s -X POST "$BASE_URL/api/locations" \
  -H "Content-Type: application/json" \
  -H "X-User-Id: $USER_A" \
  -d '{"locations": [{"latitude": 37.7749, "longitude": -122.4194, "accuracy": 10, "timestamp": "2023-10-27T10:00:00Z"}]}')
echo $RESPONSE

echo "2. Getting Token for User A..."
# 1. Approve (Get Code)
# POST /auth/oauth/approve needs form body or json? Check source. 
# fastify.post('/oauth/approve') uses request.body. We registered @fastify/formbody.
# We'll send JSON for simplicity if it supports it, or form.
# Route uses `request.body as any`. Fastify parses based on content-type.
AUTH_CODE_LOC=$(curl -s -w "%{redirect_url}" -o /dev/null -X POST "$BASE_URL/auth/oauth/approve" \
  -H "Content-Type: application/json" \
  -d "{\"redirect_uri\": \"https://example.com\", \"user_id\": \"$USER_A\"}")
echo "Redirect: $AUTH_CODE_LOC"

# Extract code from redirect URL
CODE=$(echo $AUTH_CODE_LOC | sed -n 's/.*code=\([^&]*\).*/\1/p' | sed 's/%3D/=/g') 
# Note: base64 might have url encoding. 
echo "Code: $CODE"

# 2. Get Token
TOKEN_RESP=$(curl -s -X POST "$BASE_URL/auth/oauth/token" \
  -H "Content-Type: application/json" \
  -d "{\"code\": \"$CODE\", \"client_id\": \"foo\", \"grant_type\": \"authorization_code\"}")
echo "Token Resp: $TOKEN_RESP"
TOKEN=$(echo $TOKEN_RESP | grep -o '"access_token":"[^"]*' | cut -d'"' -f4)
echo "Token: $TOKEN"

echo "3. Testing SSE Auth..."
# Good Token
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" -H "Authorization: Bearer $TOKEN" "$BASE_URL/sse")
if [ "$HTTP_CODE" == "200" ]; then
    echo "SSE Auth Success (200)"
else
    echo "SSE Auth Failed ($HTTP_CODE)"
fi

# Bad Token
HTTP_CODE_BAD=$(curl -s -o /dev/null -w "%{http_code}" -H "Authorization: Bearer BAD_TOKEN" "$BASE_URL/sse")
if [ "$HTTP_CODE_BAD" == "403" ]; then
    echo "SSE Bad Token Rejected (403)"
else
    echo "SSE Bad Token Check Failed ($HTTP_CODE_BAD)"
fi

echo "4. Deletion Test..."
# We need an ID to delete. 
# Since POST /locations doesn't return IDs (it's batch), we have to trust the DB or modify endpoint.
# But for verification we can delete by ID if we knew it.
# We can't query IDs easily via API for MVP (McpServer hides it in protocol).
# We'll skip specific DELETE verification via script unless we query DB directly.
# But we can verify 404 on random ID.
DEL_RESP=$(curl -s -o /dev/null -w "%{http_code}" -X DELETE "$BASE_URL/api/locations/00000000-0000-0000-0000-000000000000" -H "X-User-Id: $USER_A")
echo "Delete Random ID: $DEL_RESP (Expect 404)"

echo "Verification Complete"
