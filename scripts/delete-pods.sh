#!/bin/bash

# Define function to delete pods in specified namespaces
delete_pods() {
    # List of namespaces
    local NAMESPACES=("$@")

    # Loop through each namespace
    for namespace in "${NAMESPACES[@]}"
    do
        echo "Deleting pods in namespace: $namespace"

        # Get the list of pods in the namespace and delete them
        pod_list=$(oc get pods -n "$namespace" -o name)

        if [ -n "$pod_list" ]; then
            oc delete $pod_list -n "$namespace" $DRY_RUN_OPTION
        else
            echo "No pods found in namespace: $namespace"
        fi
    done
}