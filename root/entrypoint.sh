#!/usr/bin/env bash

set -e

echo "Version: $AZOPSTFRUN_VERSION"

exit_abnormal() {
    echo "Fatal error: $1"
    exit 1
}

#for s in $(ls -1 /steps); do
#    if steps/$s; then
#        continue
#    else
#        exit_abnormal $?
#    fi
#done


install_terraform() {
    echo "Installing Terraform $TF_VERSION"
    curl -s "https://releases.hashicorp.com/terraform/${TF_VERSION}/terraform_${TF_VERSION}_linux_amd64.zip" \
        --output terraform_${TF_VERSION}_linux_amd64.zip

    unzip -qq terraform_${TF_VERSION}_linux_amd64.zip -d /usr/local/bin
    terraform -v
    echo "Installing Terraform $TF_VERSION (complete)"
}

parse_initial_azure_credentials() {
    if [ ! "$AZURE_CREDENTIALS" ]; then exit_abnormal "AZURE_CREDENTIALS not defined"; fi
    INITIAL_ARM_CLIENT_ID=$(echo $AZURE_CREDENTIALS | jq -r .clientId)
    INITIAL_ARM_CLIENT_SECRET=$(echo $AZURE_CREDENTIALS | jq -r .clientSecret)
    INITIAL_ARM_TENANT_ID=$(echo $AZURE_CREDENTIALS | jq -r .tenantId)
    INITIAL_ARM_SUBSCRIPTION_ID=$(echo $AZURE_CREDENTIALS | jq -r .subscriptionId)
    INITIAL_ACTIVE_DIRECTORY_ENDPOINT_URL=$(echo $AZURE_CREDENTIALS | jq -r .activeDirectoryEndpointUrl)
    INITIAL_RESOURCE_MANAGER_ENDPOINT_URL=$(echo $AZURE_CREDENTIALS | jq -r .resourceManagerEndpointUrl)
    if [ ! "$INITIAL_ARM_CLIENT_ID" ] \
        || [ ! "$INITIAL_ARM_CLIENT_SECRET" ] \
        || [ ! "$INITIAL_ARM_TENANT_ID" ] \
        || [ ! "$INITIAL_ARM_SUBSCRIPTION_ID" ] \
        || [ ! "$INITIAL_ACTIVE_DIRECTORY_ENDPOINT_URL" ] \
        || [ ! "$INITIAL_RESOURCE_MANAGER_ENDPOINT_URL" ]; then
        exit_abnormal "Cound not decode AZURE_CREDENTIALS"
    fi
}

get_azure_access_token() {
    AZURE_ACCESS_TOKEN=$(curl -s -X POST \
        -d "grant_type=client_credentials&client_id=${INITIAL_ARM_CLIENT_ID}&client_secret=${INITIAL_ARM_CLIENT_SECRET}&resource=https://vault.azure.net" \
        $INITIAL_ACTIVE_DIRECTORY_ENDPOINT_URL/$INITIAL_ARM_TENANT_ID/oauth2/token | jq -r .access_token)
    if [ ! "$AZURE_ACCESS_TOKEN" ]; then exit_abnormal "Unable to request access token"; fi
}

get_keyvault_secrets() {
    ARM_CLIENT_ID=$(curl -s "https://${KEYVAULT_NAME}.vault.azure.net/secrets/arm-client-id?api-version=7.0" \
        -H "Authorization: Bearer ${AZURE_ACCESS_TOKEN}" \
        | jq -r '.value')
    ARM_CLIENT_SECRET=$(curl -s "https://${KEYVAULT_NAME}.vault.azure.net/secrets/arm-client-secret?api-version=7.0" \
        -H "Authorization: Bearer ${AZURE_ACCESS_TOKEN}" \
        | jq -r '.value')
    ARM_TENANT_ID=$(curl -s "https://${KEYVAULT_NAME}.vault.azure.net/secrets/arm-tenant-id?api-version=7.0" \
        -H "Authorization: Bearer ${AZURE_ACCESS_TOKEN}" \
        | jq -r '.value')
    ARM_SUBSCRIPTION_ID=$(curl -s "https://${KEYVAULT_NAME}.vault.azure.net/secrets/arm-tenant-id?api-version=7.0" \
        -H "Authorization: Bearer ${AZURE_ACCESS_TOKEN}" \
        | jq -r '.value')
    TF_BACKEND_FILE=$(curl -s "https://${KEYVAULT_NAME}.vault.azure.net/secrets/tf-backend-file?api-version=7.0" \
        -H "Authorization: Bearer ${AZURE_ACCESS_TOKEN}" \
        | jq -r '.value')
    if [ ! "$ARM_CLIENT_ID" ] \
        || [ ! "$ARM_CLIENT_SECRET" ] \
        || [ ! "$ARM_TENANT_ID" ] \
        || [ ! "$ARM_SUBSCRIPTION_ID" ] \
        || [ ! "$TF_BACKEND_FILE" ]; then
        exit_abnormal "Cound not get Key Vault secrets"
    fi
}

create_tf_backend_file() {
    cat << EOF >backend.hcl
$TF_BACKEND_FILE
EOF
    if [ ! -f "backend.hcl" ]; then
        exit_abnormal "Could not create backend.hcl"
    fi
}

terraform_init() {
    ln -s ../backend.hcl
    terraform init -backend-config=backend.hcl -input=false
}

terraform_fmt() {
    terraform fmt -check
}

terraform_plan() {
    terraform plan -input=false
}

terraform_apply() {
    terraform apply -auto-approve -input=false
}


# Start here

install_terraform
parse_initial_azure_credentials
get_azure_access_token
get_keyvault_secrets
create_tf_backend_file

for dir in "$(ls -d1 tf-*)"; do
    echo "Entering $dir"
    pushd $dir
    terraform_init
    terraform_fmt
    terraform_plan
    if [ "$GITHUB_REF" == "refs/heads/main" ] && [ $GITHUB_EVENT_NAME == "push" ] \
        [ "$GITHUB_EVENT_NAME" == "workflow_dispatch" ] && [ "$GITHUB_EVENT_INPUTS_ACTION" == "apply" ]; then
        terraform_apply
    fi
    popd
done
