#!/bin/bash

function usage {
    echo "Usage: ./ibm-ocp-template-uninstall.sh --apikey=<api_key> --resource-group-id=<resource_group_id> --cluster-name=<cluster_name> [--template-file=template_file] [--full-uninstall]"
    echo "Defaults to the template file located in /openshift/templates."
    echo "If --full-uninstall is specified, all associated operators will also be uninstalled. Otherwise, only the specified or default template will be uninstalled."
}

function check_input {
    if [[ -z "$1" ]]; then
        echo "$2"
        usage
        exit 1
    fi
}

function check_exit {
    check_exit_custom $? $2
}

function check_exit_custom {
    if [[ $1 -ne 0 ]]; then
        echo -e "\n$2"
        exit 1
    fi
}

for arg in "$@"
do
    if [ "$arg" == "--help" ] || [ "$arg" == "-h" ]; then
        usage
        exit 0
    fi

    if [[ $arg == --apikey=* ]]; then
        API_KEY=$( echo $arg | cut -d'=' -f 2 )
    fi

    if [[ $arg == --resource-group-id=* ]]; then
        RESOURCE_GROUP=$( echo $arg | cut -d'=' -f 2 )
    fi

    if [[ $arg == --cluster-name=* ]]; then
        CLUSTER_NAME=$( echo $arg | cut -d'=' -f 2 )
    fi

    if [[ $arg == --template-file=* ]]; then
        TEMPLATE_FILE=$( echo $arg | cut -d'=' -f 2 )
    fi

    if [[ $arg == "--full-uninstall" ]]; then
        TEMPLATE_FULL_UNINSTALL=true
    fi
done

if [[ -z "$TEMPLATE_FILE" ]]; then
    TEMPLATE_FILE=./../templates/clone.json
fi
echo "Using template file $TEMPLATE_FILE"

check_input "$API_KEY" "No API key was supplied. A valid IBM Cloud API key is required to login to the IBM Cloud."
check_input "$RESOURCE_GROUP" "No resource group ID was supplied. Execute 'ibmcloud resource groups' to list resource groups."
check_input "$CLUSTER_NAME" "No cluster name was supplied. Execute 'ibmcloud ks clusters' to list available clusters."
check_input "$TEMPLATE_FILE" "No template file was supplied."

echo "Logging in"
ibmcloud login --apikey $API_KEY
ibmcloud target --cf -g $RESOURCE_GROUP
oc login -u apikey -p $API_KEY

echo -e "\nApplying cluster configuration for cluster $CLUSTER_NAME"
$( ibmcloud ks cluster config $CLUSTER_NAME --admin | grep export)

if [[ -n "$TEMPLATE_FULL_UNINSTALL" ]]; then
    echo -e "\nUninstalling all operators"
    echo -e "\nUninstalling Operator Lifecycle Manager"
    kubectl delete -f https://github.com/operator-framework/operator-lifecycle-manager/releases/download/0.11.0/crds.yaml
    kubectl delete -f https://github.com/operator-framework/operator-lifecycle-manager/releases/download/0.11.0/olm.yaml

    echo -e "\nUninstalling Operator Marketplace"
    OM_TEMP_DIR=om_temp
    mkdir $OM_TEMP_DIR
    cd $OM_TEMP_DIR
    git clone https://github.com/operator-framework/operator-marketplace.git
    GIT_CLONE_EXIT=$?
    oc delete -f operator-marketplace/deploy/upstream/
    OC_APPLY_EXIT=$?
    cd ..
    rm -rf ./$OM_TEMP_DIR
    check_exit_custom $GIT_CLONE_EXIT "Failed to download Operator Marketplace resource definitions. Ensure that you are connected to the Internet and can access GitHub."
    check_exit_custom $OC_APPLY_EXIT "Failed to uninstall Operator Marketplace. Check the command output and try again."

    echo -e "\nUninstalling IBM Cloud Operator"
    kubectl delete -f https://operatorhub.io/install/ibmcloud-operator.yaml
    check_exit "Failed to uninstall IBM Cloud Operator. Ensure the $CLUSTER_NAME cluster is available."
fi

echo -e "\nUninstalling template $TEMPLATE_FILE"
oc -n openshift delete -f "$TEMPLATE_FILE"
check_exit "Failed to uninstall template $TEMPLATE_FILE. Ensure the template definition is valid and try again."
