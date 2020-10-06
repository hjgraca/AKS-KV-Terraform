#!/bin/bash

POD_NAME="kv-test-$(uuidgen | head -c 8)"
VOLUME_NAME="secrets-store-inline"
MOUNT_PATH="/mnt/secrets-store"
SECRET_NAME="demo-secret"
SECRET_ALIAS="demo_alias"
rg_name="rg-451vvb"
aks_cluster_name="aks-451vvb"
aad_pod_id_binding_selector="aad-pod-id-binding-selector"
key_vault_name="kv-451vvb"
tenant_id="72f988bf-86f1-41af-91ab-2d7cd011db47"
sub_id="b7850030-db6f-4bce-8f14-f56820faa1aa"
SECRET_VALUE="demo-value"

#az aks get-credentials -g $rg_name -n $aks_cluster_name --overwrite-existing

#Deploy SecretProviderClass
read -r -d '' Secret_Prov_YAML << EOM
apiVersion: secrets-store.csi.x-k8s.io/v1alpha1
kind: SecretProviderClass
metadata:
  name: azure-kvname
spec:
  provider: azure                   
  parameters:
    usePodIdentity: "true"         # [OPTIONAL for Azure] if not provided, will default to "false"
    useVMManagedIdentity: "false"   # [OPTIONAL available for version > 0.0.4] if not provided, will default to "false"
    userAssignedIdentityID: ""  # [OPTIONAL available for version > 0.0.4] use the client id to specify which user assigned managed identity to use. If using a user assigned identity as the VM's managed identity, then specify the identity's client id. If empty, then defaults to use the system assigned identity on the VM
    keyvaultName: "$key_vault_name"          # the name of the KeyVault
    objects:  |
      array:
        - |
          objectName: "$SECRET_NAME"
          objectAlias: "$SECRET_ALIAS"     # [OPTIONAL available for version > 0.0.4] object alias
          objectType: secret                # object types: secret, key or cert. For Key Vault certificates, refer to https://github.com/Azure/secrets-store-csi-driver-provider-azure/blob/master/docs/getting-certs-and-keys.md for the object type to use
          objectVersion: ""                 # [OPTIONAL] object versions, default to latest if empty
    resourceGroup: "$rg_name"            # [REQUIRED for version < 0.0.4] the resource group of the KeyVault
    subscriptionId: "$sub_id"         # [REQUIRED for version < 0.0.4] the subscription ID of the KeyVault
    tenantId: "$tenant_id"                 # the tenant ID of the KeyVault
EOM

if ! echo "$Secret_Prov_YAML" | kubectl apply -f -
then
    echo "Unable to deploy SecretProviderClass into the cluster."
    exit 1
fi

# Deploy test pod
read -r -d '' KV_POD_YAML << EOM
kind: Pod
apiVersion: v1
metadata:
  name: $POD_NAME
  labels:
    aadpodidbinding: "$aad_pod_id_binding_selector"
spec:
  containers:
    - name: $POD_NAME
      image: nginx
      volumeMounts:
      - name: $VOLUME_NAME
        mountPath: "$MOUNT_PATH"
        readOnly: true
  volumes:
    - name: $VOLUME_NAME
      csi:
        driver: secrets-store.csi.k8s.io
        readOnly: true
        volumeAttributes:
          secretProviderClass: "azure-kvname"
EOM

if ! echo "$KV_POD_YAML" | kubectl apply -f -
then
    echo "Unable to deploy test pod into the cluster."
    exit 1
fi

kubectl wait --for=condition=Ready --timeout=120s pod/$POD_NAME
kubectl describe pod/$POD_NAME
kubectl exec -i $POD_NAME -- ls $MOUNT_PATH

ACTUAL_VALUE=$(kubectl exec -i $POD_NAME -- cat $MOUNT_PATH/$SECRET_ALIAS)

#kubectl delete pod $POD_NAME

if [ "$SECRET_VALUE" == "$ACTUAL_VALUE" ]; then
    echo "AKS - Key Vault test passed - secret: $ACTUAL_VALUE"
else
    echo "AKS - Key Vault test failed"
    exit 1
fi