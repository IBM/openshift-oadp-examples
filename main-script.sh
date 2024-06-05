#!/bin/bash

####################################################################################################

#  DRY_RUN=true USE_FILESYSTEM=false ./main-script.sh old-cluster-url backup-name
#  DRY_RUN=true USE_FILESYSTEM=true ./main-script.sh old-cluster-url backup-name

####################################################################################################

source ./scripts/restore-utilities.sh
source ./scripts/delete-secrets.sh
source ./scripts/delete-pods.sh
source ./scripts/search-replace-secrets.sh

# Main script

echo ""
# Get cluster info
get_cluster_info "$OLD_CLUSTER"
echo ""

# Apply the DataProtectionApplication
apply_other_resources_with_yaml DataProtectionApplication dpa-name ./yaml/dpa-and-backups/oadp-dpa.yaml openshift-adp
echo ""

read -p "Check that backup locations are in the OADP operator"
echo ""

# Apply resource modifier
apply_resource_modifier resource-modifier ./yaml/resource-modifier/resource-modifier.yaml
echo ""

# Apply restore
apply_restore_with_yaml restore-1-example ./yaml/restores/restore-1-example.yaml $BACKUP_NAME
echo ""

# Install operators
operators=("Name of 1st operator to install and version" "Name of 2nd operator to install and version")
install_operators "${operators[@]}"
echo ""

# Step 2 - Restore volumes from pods or snapshots 
if [ "$USE_FILESYSTEM" = true ]; then
    # # Step 2 - Restore volume from pod FILESYSTEM
    apply_restore_with_yaml restore-2-example-filesystem ./yaml/restores/restore-2-example-filesystem.yaml $BACKUP_NAME
    echo ""

    # Delete pods ... CSI 
    NAMESPACES=("namespace")
    delete_pods "${NAMESPACES[@]}"
    read -p "Hit Enter to continue."
    echo ""
else
#   Step 4 ... CSI
    apply_restore_with_yaml restore-2-example-csi ./yaml/restores/restore-2-example-csi.yaml $BACKUP_NAME
    echo ""

    # # Update PVC ... CSI
    read -p "PVC applied. Please check the resources and hit enter to continue."  
    echo ""

    read -p "Check that the Persistent Volume is in the bound state"
    echo ""
fi

# Step 23: Delete pods
NAMESPACES=("namespace")
delete_pods "${NAMESPACES[@]}"
echo ""

read -p "Check that all pods are in the running state in namespace."
echo ""

# Step 30 - Update secrets
patch_secrets_in_namespaces "$OLD_CLUSTER" "$NEW_CLUSTER" "namespace" "secret-name-1,secret-name-2,secret-name-3"
echo ""

read -p "Verify secrets are patched. Hit Enter"
echo ""

# Step  - Delete tls secrets so they regenerate
NAMESPACES=("namespace")
SECRET_TYPE="kubernetes.io/tls" # This can be changed to any secret type
delete_secrets_by_type "$SECRET_TYPE" "${NAMESPACES[@]}"
echo ""