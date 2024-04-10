#!/bin/bash

# It would be best storing it as secrets in e.g. jenkins
CLIENT_ID=""
CLIENT_SECRET=""
API_USER=""
API_PASSWORD=""
INSTANCE_ID=""

response=$(curl -s -d "client_id=$CLIENT_ID" \
                -d "client_secret=$CLIENT_SECRET" \
                --data-urlencode "username=$API_USER" \
                --data-urlencode "password=$API_PASSWORD" \
                -d 'grant_type=password' \
                'https://auth.contabo.com/auth/realms/contabo/protocol/openid-connect/token')

ACCESS_TOKEN=$(echo $response | jq -r '.access_token')

# Check if the token was obtained successfully
if [ -z "$ACCESS_TOKEN" ]; then
    echo "Failed to obtain access token"
    exit 1
fi

X_REQUEST_ID=$(uuidgen)
UPDATE_SNAPSHOTS_RESPONSE=$(curl -s -X GET "https://api.contabo.com/v1/compute/instances/$INSTANCE_ID/snapshots" \
                                  -H 'Content-Type: application/json' \
                                  -H "Authorization: Bearer ${ACCESS_TOKEN}" \
                                  -H "x-request-id: $X_REQUEST_ID")

echo "Snapshot List Update Response: $UPDATE_SNAPSHOTS_RESPONSE"

X_REQUEST_ID=$(uuidgen)
SNAPSHOT_NAME="snapshot-$(date +%Y-%m-%d)"
echo $SNAPSHOT_NAME

CREATE_SNAPSHOT_RESPONSE=$(curl -X POST "https://api.contabo.com/v1/compute/instances/$INSTANCE_ID/snapshots" \
                            -H 'Content-Type: application/json' \
                            -H "Authorization: Bearer ${ACCESS_TOKEN}" \
                            -H "x-request-id: $X_REQUEST_ID" \
                            -d "{\"name\":\"$SNAPSHOT_NAME\",\"description\":\"Snapshot-Description\"}")

echo "Snapshot Creation Response: $CREATE_SNAPSHOT_RESPONSE"

X_REQUEST_ID=$(uuidgen)
if [[ "$CREATE_SNAPSHOT_RESPONSE" == *"201"* ]]; then
    echo "Snapshot created successfully"
    NEW_SNAPSHOT_ID=$(echo $CREATE_SNAPSHOT_RESPONSE | jq -r '.data[0].snapshotId')
    LIST_SNAPSHOTS_RESPONSE=$(curl -s -X GET "https://api.contabo.com/v1/compute/instances/$INSTANCE_ID/snapshots" \
                                -H 'Content-Type: application/json' \
                                -H "Authorization: Bearer ${ACCESS_TOKEN}" \
                                -H "x-request-id: $X_REQUEST_ID") 
                                
    echo $LIST_SNAPSHOTS_RESPONSE      
    echo $NEW_SNAPSHOT_ID
    
    if [ "$(echo $LIST_SNAPSHOTS_RESPONSE | jq '.data | length')" -gt 0 ]; then
      echo "Snapshots found. Processing for deletion..."
      for snapshot in $(echo $LIST_SNAPSHOTS_RESPONSE | jq -r '.data[].snapshotId'); do
          if [[ "$snapshot" != "$NEW_SNAPSHOT_ID" ]]; then
              # Generate a new x-request-id for each delete request
              X_REQUEST_ID=$(uuidgen)
              DELETE_RESPONSE=$(curl -s -X DELETE "https://api.contabo.com/v1/compute/instances/$INSTANCE_ID/snapshots/$snapshot" \
                                  -H 'Content-Type: application/json' \
                                  -H "Authorization: Bearer ${ACCESS_TOKEN}" \
                                  -H "x-request-id: $X_REQUEST_ID") 
              echo "Deleted snapshot $snapshot: $DELETE_RESPONSE"
          fi
      done
    else
        echo "Failed to list snapshots"
    fi
else
    echo "Failed to create snapshot"
    exit 1
fi
