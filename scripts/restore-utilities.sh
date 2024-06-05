#!/bin/bash


# Specify using filesystem or CSI. If you are using filesystem set to true, if using CSI set to false. This is also a parameter that will be specified when running the script. 
OLD_CLUSTER="$1"
BACKUP_NAME="$2"
export USE_FILESYSTEM="${USE_FILESYSTEM:-true}" # Default value for DRY_RUN is true
if [ "$USE_FILESYSTEM" = "true" ]; then
    export USE_FILESYSTEM='true'
else
    export USE_FILESYSTEM='false'
fi

# You are able to run this script in a dry run mode, so you are able to test the script without making any real changes to the cluster. This is a parameter that will need to be specified when running the script.
export DRY_RUN="${DRY_RUN:-true}" # Default value for DRY_RUN is true
if [ "$DRY_RUN" = "true" ]; then
    export DRY_RUN_OPTION='--dry-run=client'
else
    export DRY_RUN_OPTION=''
fi

# Check if parameters are provided
if [ -z "$DRY_RUN" ] || [ -z "$USE_FILESYSTEM" ] || [ -z "$OLD_CLUSTER" ] || [ -z "$BACKUP_NAME" ]; then
    echo "Please provide all parameters: DRY_RUN, USE_FILESYSTEM, OLD_CLUSTER, and BACKUP_NAME"
    exit 1
fi

# Check if DRY_RUN is set to empty
if [ -z "$DRY_RUN_OPTION" ]; then
    read -p "Changes will be made to the cluster. Press enter to continue."
fi

# Retrieve the cluster domain of your new cluster 
function get_cluster_info() {
    FULL_HOSTNAME="$1"
    OLD_CLUSTER=$(echo $FULL_HOSTNAME | sed 's/.containers.*//')
    NEW_CLUSTER=$(oc get Ingress.config.openshift.io/cluster -o template --template '{{.spec.domain}}' | sed 's/.containers.*//')
    echo "Old cluster: $OLD_CLUSTER"
    echo "New cluster: $NEW_CLUSTER"
}

# Fuction to install operators 
function install_operators() {
    local operators=("$@") # List of operaotrs 

    for operator in "${operators[@]}"; do
        read -p "Please install $operator to the closest version as possible to the one listed. Make sure to select upgrade as manual. Hit Enter when done: "
        echo ""
    done 
}

# Check for and apply restore yamls
function apply_restore_with_yaml() {
    local resource="$1"
    local yaml_file="$2"
    local BACKUP_NAME="$3"

    oc get Restore | grep "$resource" >/dev/null 2>&1
    if [ $? -eq 0 ]; then
        echo "Resource Restore $resource already exists. Skipping..."
    else
        sed -E "s/backupName: .*/backupName: $BACKUP_NAME/" "$yaml_file" | oc apply $DRY_RUN_OPTION -f -
        echo "Applied yaml file $yaml_file using backupName: $BACKUP_NAME"        
        read -p "Resource applied. Please check the resources and hit enter to continue."
    fi
}

# Check for and apply resource modifier
function apply_resource_modifier() {
    local resource="$1"
    local yaml_file="$2"
    local NEW_CLUSTER=$(oc get Ingress.config.openshift.io/cluster -o template --template '{{.spec.domain}}')

    oc get ConfigMap "$resource" >/dev/null 2>&1
    if [ $? -eq 0 ]; then
        echo "Resource ConfigMap $resource already exists. Skipping..."
    else
        sed -E "s/PLACEHOLD-URL/$NEW_CLUSTER/g" "$yaml_file" | oc apply $DRY_RUN_OPTION -f -
        echo "Applied yaml file $yaml_file and updated cluster url: $NEW_CLUSTER"    
        read -p "Resource applied. Please check the resources and hit enter to continue."
    fi
}

# Check for an apply other resources 
function apply_other_resources_with_yaml() {
    local resource_type="$1"
    local resource="$2"
    local resource_yaml="$3"
    local namespace="$4"

    local get_command="oc get $resource_type $resource"
    if [ -n "$namespace" ]; then
        get_command="$get_command -n $namespace"
    fi

    # Check if resource exists
    $get_command >/dev/null 2>&1

    if [ $? -ne 0 ]; then
        oc apply -f $resource_yaml $DRY_RUN_OPTION
        read -p "$resource_type applied. Please check the resources and hit enter to continue."
    else
        if [ -n "$namespace" ]; then
            echo "Resource $resource_type $resource already exists in namespace $namespace. Skipping..."
        else
            echo "Resource $resource_type $resource already exists. Skipping..."
        fi
    fi
}

# Update the requested size of a persistent volume claim
function update_pvc() {
    local PVC_NAME=$1
    local STORAGE_SIZE=$2
    local NAMESPACE=$3

    # Get the PVC in json form and update the json
    local PVC="$(oc get -n $NAMESPACE pvc/$PVC_NAME -o json 2>/dev/null)"

    local CURRENT_STORAGE_SIZE=$(echo -E "$PVC" | jq -r '.spec.resources.requests.storage')

    if [[ "$CURRENT_STORAGE_SIZE" == "$STORAGE_SIZE" ]]; then
        echo "Storage size is already correct $PVC_NAME"
        return
    fi

    # Store the modified YAML to a temporary file
    echo -E "$PVC" | jq --arg size "$STORAGE_SIZE" 'del(.metadata.uid) | del(.metadata.resourceVersion) | del(.metadata.creationTimestamp) | .spec.resources.requests.storage = $size' > modified_pvc.yaml

    oc delete pvc $PVC_NAME -n $NAMESPACE > /dev/null 2>&1 $DRY_RUN_OPTION

    # Reapply modified YAML from the temporary file
    oc apply -f modified_pvc.yaml $DRY_RUN_OPTION

    # Remove the temporary file
    rm modified_pvc.yaml

    # Remove the claimRef to make PV available
    oc patch pv $(echo -E "$PVC" | jq -r '.spec.volumeName') -p '{"spec": {"claimRef":null}}' > /dev/null 2>&1 $DRY_RUN_OPTION
}