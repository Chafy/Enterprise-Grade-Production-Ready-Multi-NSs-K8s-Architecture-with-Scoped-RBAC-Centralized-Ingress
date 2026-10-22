#!/bin/bash

if [ -z "$1" ] || [ -z "$2" ] || [ -z "$3" ]; then
    echo "Usage: $0 <username> <namespace1> <namespace2>"
    echo "Example: $0 ahmed dev test"
    exit 1
fi

USERNAME=$1
NS1=$2
NS2=$3
EXPIRATION_DAYS=365

check_role_exists() {
    local ns=$1
    kubectl get role "${USERNAME}-full-access-role" -n "${ns}" &> /dev/null
    return $?
}

check_rolebinding_exists() {
    local ns=$1
    kubectl get rolebinding "${USERNAME}-role-binding" -n "${ns}" &> /dev/null
    return $?
}

check_csr_exists() {
    kubectl get csr "${USERNAME}-csr" &> /dev/null
    return $?
}

echo "=== Checking if resources for user '$USERNAME' already exist in namespaces '$NS1' and '$NS2' ==="

RESOURCES_EXIST=false

if check_role_exists "$NS1" || check_role_exists "$NS2"; then
    echo "Warning: Role '${USERNAME}-full-access-role' already exists in one or both namespaces."
    RESOURCES_EXIST=true
fi

if check_rolebinding_exists "$NS1" || check_rolebinding_exists "$NS2"; then
    echo "Warning: RoleBinding '${USERNAME}-role-binding' already exists in one or both namespaces."
    RESOURCES_EXIST=true
fi

if check_csr_exists; then
    echo "Warning: CSR '${USERNAME}-csr' already exists."
    RESOURCES_EXIST=true
fi

if [ "$RESOURCES_EXIST" = true ]; then
    read -p "Some or all resources already exist. Do you want to continue and overwrite/create them? (y/n): " confirm
    if [[ ! "$confirm" =~ ^[Yy]([Ee][Ss])?$ ]]; then
        echo "Operation cancelled by user."
        exit 0
    fi
    echo "Proceeding with the script..."
fi

echo "=== 1. Creating Private Key and CSR for user: $USERNAME ==="
openssl genrsa -out ${USERNAME}.key 2048
openssl req -new -key ${USERNAME}.key -out ${USERNAME}.csr -subj "/CN=${USERNAME}/O=dev-team"

CSR_BASE64=$(cat ${USERNAME}.csr | base64 | tr -d '\n')

echo "=== 2. Submitting CertificateSigningRequest to Kubernetes ==="
kubectl delete csr ${USERNAME}-csr --ignore-not-found=true
cat <<EOF | kubectl apply -f -
apiVersion: certificates.k8s.io/v1
kind: CertificateSigningRequest
metadata:
  name: ${USERNAME}-csr
spec:
  request: ${CSR_BASE64}
  signerName: kubernetes.io/kube-apiserver-client
  expirationSeconds: $((EXPIRATION_DAYS * 86400))
  usages:
  - client auth
EOF

echo "=== 3. Approving CSR ==="
kubectl certificate approve ${USERNAME}-csr

echo "=== 4. Extracting Approved Certificate ==="
sleep 2
kubectl get csr ${USERNAME}-csr -o jsonpath='{.status.certificate}' | base64 --decode > ${USERNAME}.crt

echo "=== 5. Setting up Role and RoleBinding in namespace: $NS1 ==="
cat <<EOF | kubectl apply -f -
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  namespace: ${NS1}
  name: ${USERNAME}-full-access-role
rules:
- apiGroups: ["", "apps", "batch"]
  resources: ["*"]
  verbs: ["*"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: ${USERNAME}-role-binding
  namespace: ${NS1}
subjects:
- kind: User
  name: ${USERNAME}
  apiGroup: rbac.authorization.k8s.io
roleRef:
  kind: Role
  name: ${USERNAME}-full-access-role
  apiGroup: rbac.authorization.k8s.io
EOF

echo "=== 5b. Setting up Role and RoleBinding in namespace: $NS2 ==="
cat <<EOF | kubectl apply -f -
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  namespace: ${NS2}
  name: ${USERNAME}-full-access-role
rules:
- apiGroups: ["", "apps", "batch"]
  resources: ["*"]
  verbs: ["*"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: ${USERNAME}-role-binding
  namespace: ${NS2}
subjects:
- kind: User
  name: ${USERNAME}
  apiGroup: rbac.authorization.k8s.io
roleRef:
  kind: Role
  name: ${USERNAME}-full-access-role
  apiGroup: rbac.authorization.k8s.io
EOF

echo "=== 6. Generating Kubeconfig file for user ==="
CLUSTER_NAME=$(kubectl config view --minify -o jsonpath='{.clusters[0].name}')
CLUSTER_SERVER=$(kubectl config view --minify -o jsonpath='{.clusters[0].cluster.server}')
CLUSTER_CA=$(kubectl config view --minify --raw -o jsonpath='{.clusters[0].cluster.certificate-authority-data}')

cat <<EOF > ${USERNAME}-kubeconfig
apiVersion: v1
kind: Config
preferences: {}
clusters:
- cluster:
    certificate-authority-data: ${CLUSTER_CA}
    server: ${CLUSTER_SERVER}
  name: ${CLUSTER_NAME}
contexts:
- context:
    cluster: ${CLUSTER_NAME}
    namespace: ${NS1}
    user: ${USERNAME}
  name: ${USERNAME}-context
current-context: ${USERNAME}-context
users:
- name: ${USERNAME}
  user:
    client-certificate-data: $(cat ${USERNAME}.crt | base64 | tr -d '\n')
    client-key-data: $(cat ${USERNAME}.key | base64 | tr -d '\n')
EOF

echo "================================================="
echo "Done! Generated files:"
echo " 1. ${USERNAME}.key (Private Key)"
echo " 2. ${USERNAME}.crt (Signed Certificate)"
echo " 3. ${USERNAME}-kubeconfig (Ready to send to the user!)"
echo "================================================="