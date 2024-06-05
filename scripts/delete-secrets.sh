#!/bin/bash

# Function to delete secrets of a certain type
function delete_secrets_in_namespace() {
    local namespace="$1"
    local SECRET_TYPE="$2"

    # Get list of secrets in the namespace
    secrets=$(oc get secrets -n "$namespace" -o jsonpath='{.items[*].metadata.name}')

    # Iterate over each secret
    for secret in $secrets; do
        # Check if the secret's type matches the specified type
        type=$(oc get secret "$secret" -n "$namespace" -o jsonpath='{.type}')
        if [[ "$type" == "$SECRET_TYPE" ]]; then
            echo "Deleting secret $secret in namespace $namespace"
            oc delete secret "$secret" -n "$namespace" $DRY_RUN_OPTION
        fi
    done
}

function delete_secrets_by_type() {
    local SECRET_TYPE="$1"
    local namespaces=("${@:2}")
# Iterate over each namespace
    for namespace in "${namespaces[@]}"; do
        echo "Deleting $SECRET_TYPE secrets in $namespace"
        delete_secrets_in_namespace "$namespace" "$SECRET_TYPE"
    done

}