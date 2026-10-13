#!/bin/bash

# Check cluster connection
if ! kubectl cluster-info &> /dev/null; then
    echo "Error: Cannot connect to Kubernetes cluster. Please check your kubeconfig."
    exit 1
fi

echo "=== 1. Deleting Ingress Resources ==="
if [ -f "ingress.yaml" ]; then
    kubectl delete -f ingress.yaml --ignore-not-found=true
else
    echo "Warning: ingress.yaml not found, skipping..."
fi

echo "=== 2. Deleting Workloads via Manifests Directories ==="
# Delete WordPress manifests
if [ -d "wordpress" ]; then
    echo "Deleting WordPress manifests..."
    kubectl delete -f wordpress/ --ignore-not-found=true
fi

# Delete MySQL manifests
if [ -d "mysql" ]; then
    echo "Deleting MySQL manifests..."
    kubectl delete -f mysql/ --ignore-not-found=true
fi

# Delete MongoDB manifests
if [ -d "mongo" ]; then
    echo "Deleting MongoDB manifests..."
    kubectl delete -f mongo/ --ignore-not-found=true
fi

# Delete Mongo Express manifests
if [ -d "mongoex" ]; then
    echo "Deleting Mongo Express manifests..."
    kubectl delete -f mongoex/ --ignore-not-found=true
fi

echo "=== 3. Cleaning up Persistent Volume Claims (PVCs) ==="
kubectl delete pvc --all -n wordpress-ns --ignore-not-found=true
kubectl delete pvc --all -n mongo-ns --ignore-not-found=true

echo "=== 4. Cleaning up Persistent Volumes (PVs) ==="
kubectl get pv --no-headers 2>/dev/null | grep -E "wordpress|mongo|mysql" | awk '{print $1}' | xargs -r kubectl delete pv --ignore-not-found=true

echo "=== 5. Deleting Namespaces (wordpress-ns & mongo-ns) ==="
kubectl delete namespace wordpress-ns --ignore-not-found=true
kubectl delete namespace mongo-ns --ignore-not-found=true

echo "================================================="
echo " Cleanup completed successfully! All cluster resources,"
echo " databases, PVCs, and namespaces have been removed."
echo "================================================="