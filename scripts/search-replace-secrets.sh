#!/bin/bash

# Function to decode and replace secrets
function decode_and_replace_secrets_in_namespace() {
    local OLD_CLUSTER="$1"
    local NEW_CLUSTER="$2"
    local NAMESPACE=("$3")
    local SECRET_NAME=("$4")


    # Get the list of secrets in the namespace
    secrets=$(oc get secrets -n "$NAMESPACE" -o jsonpath='{.items[*].metadata.name}')

    # Loop through each secret
    for secret in $secrets; do
        # Check if the current secret matches the desired name
        if [[ "$secret" == *"$SECRET_NAME"* ]]; then
            # Decode the secret
            decoded_secret=$(oc get secret "$secret" -n "$NAMESPACE" -o json | jq -r '.data | map_values(@base64d)')

            # Replace values in the secret
            modified_secret="$decoded_secret"
            modified_secret=$(echo "$modified_secret" | sed "s/$OLD_CLUSTER/$NEW_CLUSTER/g")

            # Encode the modified secret
            encoded_secret=$(echo "$modified_secret" | jq -r 'map_values(@base64)')

            # Patch the secret with the modified value
            oc patch secret "$secret" -n "$NAMESPACE" --type='json' -p='[{"op": "replace", "path": "/data", "value": '"$encoded_secret"'}]' $DRY_RUN_OPTION
        fi
    done
}

function patch_secrets_in_namespaces() {
    # Old and new strings to search and replace
    local OLD_CLUSTER="$1"
    local NEW_CLUSTER="$2"

    # Array of namespaces
    local -a NAMESPACES=()

    # Array of secret names
    local -a SECRET_NAMES=()

    IFS=',' read -ra NAMESPACES <<< "$3"

    IFS=',' read -ra SECRET_NAMES <<< "$4"

    # Loop through each namespace and secret
    for NAMESPACE in "${NAMESPACES[@]}"; do
        for SECRET_NAME in "${SECRET_NAMES[@]}"; do
            echo "Searching for $SECRET_NAME in $NAMESPACE"
            # Decode and replace secret
            decode_and_replace_secrets_in_namespace "$OLD_CLUSTER" "$NEW_CLUSTER" "$NAMESPACE" "$SECRET_NAME" 
        done
    done
}
