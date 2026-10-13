---

# Enterprise-Grade & Production-Ready Multi-Namespace Kubernetes Architecture with Scoped RBAC & Centralized Ingress (AWS EKS / EC2)

A robust, enterprise-grade, multi-tier Kubernetes deployment orchestrated specifically for scalable production environments. This project hosts **WordPress (backed by MySQL & EFS)** and **MongoDB (with Mongo Express GUI)** across isolated namespaces (wordpress-ns and mongo-ns), governed by strict **Scoped RBAC Admin Management**, advanced node scheduling, and a centralized NGINX Ingress Controller backed by AWS ALB.

---

![Kubernetes](https://img.shields.io/badge/Kubernetes-326CE5?style=for-the-badge&logo=kubernetes&logoColor=white)
![AWS](https://img.shields.io/badge/AWS-FF9900?style=for-the-badge&logo=amazon-aws&logoColor=white)
![NGINX](https://img.shields.io/badge/NGINX-009639?style=for-the-badge&logo=nginx&logoColor=white)
![WordPress](https://img.shields.io/badge/WordPress-21759B?style=for-the-badge&logo=wordpress&logoColor=white)
![MongoDB](https://img.shields.io/badge/MongoDB-47A248?style=for-the-badge&logo=mongodb&logoColor=white)
![MySQL](https://img.shields.io/badge/MySQL-4479A1?style=for-the-badge&logo=mysql&logoColor=white)



## 🎯 Business Value & Problems Solved

In modern cloud-native infrastructures, deploying multi-tenant or multi-application environments on a single Kubernetes cluster introduces severe security, scalability, and maintenance challenges. This project directly addresses and solves critical enterprise pain points:

1. **Elimination of Resource Contention & Blast Radius (Namespace Isolation):**
* *The Problem:* Running unrelated applications in the default namespace risks accidental resource starvation, misconfigurations, and broad security breaches.
* *The Solution:* Enforces strict logical separation using isolated namespaces (`wordpress-ns` and `mongo-ns`), ensuring that a failure or vulnerability in one stack remains strictly contained.


2. **Granular Multi-Tenant Security & Least Privilege Access (Scoped Admin RBAC):**
* *The Problem:* Giving developers or project admins cluster-admin access is a massive security risk.
* *The Solution:* Implements a dedicated automated RBAC script (`context-admin.sh`) that provisions project-specific administrators with full management privileges **strictly confined to their assigned namespaces**, protecting cluster-wide core components from unauthorized modifications.


3. **Optimized Resource Allocation, Fault Tolerance & Scalability (Node Affinity & Taints):**
* *The Problem:* Uncontrolled pod scheduling can overload control plane nodes, cause downtime during node failures, or scatter workloads inefficiently across expensive EC2 instances.
* *The Solution:* Leverages Node Affinity and Taint Tolerations to ensure workloads land precisely on designated worker nodes, keeping control planes pristine. By utilizing Kubernetes Deployments, the architecture achieves high fault tolerance and dynamic elasticity—allowing seamless horizontal scaling (scale-out/scale-in) or zero-downtime rolling updates and version rollbacks on demand.


4. **Zero-Data-Loss Disaster Recovery & Persistent Storage (EBS & EFS):**
* *The Problem:* Pods are ephemeral by nature; if a pod crashes or is terminated, local data is permanently lost, leading to catastrophic application failures.
* *The Solution:* Decouples compute from storage entirely. State is preserved safely outside the pods using enterprise AWS storage drivers—**EBS (RWO)** for high-performance single-node database persistence (MySQL & MongoDB) and **EFS (RWX)** for shared WordPress multi-replica file systems. If any pod crashes or is destroyed, a new replica is instantly spawned by the deployment and automatically re-attached to the exact same persistent data with zero data loss.


5. **Simplified Traffic Management & Reduced Cloud Costs:**
* *The Problem:* Provisioning a separate AWS Load Balancer for every single application rapidly increases cloud bills and networking complexity.
* *The Solution:* Utilizes a centralized NGINX Ingress Controller paired with a single AWS ALB, routing path-based traffic efficiently through optimized NodePorts.



---

## 📂 Project Structure

```text
.
├── mongo/                  # MongoDB database manifests
│   ├── mongo_deploy.yaml
│   ├── mongo_pvc.yaml
│   ├── mongo_sc.yaml
│   ├── mongo_sec.yaml
│   └── mongo_svc.yaml
├── mongoex/                # Mongo Express GUI manifests
│   ├── mongoex_cm.yaml
│   ├── mongoex_deploy.yaml
│   └── mongoex_svc.yaml
├── mysql/                  # MySQL database manifests
│   ├── myspl_pvc.yaml
│   ├── mysql_deploy.yaml
│   ├── mysql_sc.yaml
│   ├── mysql_sec.yaml
│   └── mysql_svc.yaml
├── wordpress/              # WordPress manifests
│   ├── wordpress_cm.yaml
│   ├── wordpress_deploy.yaml
│   ├── wordpress_pv.yaml
│   ├── wordpress_pvc.yaml
│   ├── wordpress_sc.yaml
│   └── wordpress_svc.yaml
├── cleanup.sh              # Automated teardown script for complete cluster resource cleanup
├── context-admin.sh        # Automated RBAC script for scoped project-admin & kubeconfig generation
└── ingress.yaml            # Centralized Ingress routing rules for both projects

```

---

## ⚙️ Prerequisites & AWS Infrastructure Setup

### 1. EC2 Cluster Environment

* **Topology:** 1 Control Plane (master) and 2 Worker Nodes (node1, node2) running on AWS EC2.
* **Security Groups:** Ensure appropriate ingress rules for SSH (22), HTTP/HTTPS (80/443), and NodePort ranges (30000-32767) between the ALB and worker nodes.

### 2. AWS IAM Permissions & CSI Drivers

Create an IAM user / role with the following policies:

* `AmazonEBSCSIDriverPolicy`
* `AmazonElasticFileSystemFullAccess`

Create the AWS credentials secret in the cluster (`kube-system` namespace):

```bash
kubectl create secret generic aws-secret \
    --namespace kube-system \
    --from-literal "key_id=YOUR_AWS_ACCESS_KEY_ID" \
    --from-literal "access_key=YOUR_AWS_SECRET_ACCESS_KEY"

```

Verify CSI drivers are active:

```bash
kubectl get csidriver
kubectl get csinode

```

---

## 🔒 Security & Secrets Configuration

Database credentials are securely managed using Kubernetes Secrets encoded in Base64:

```bash
# Generate Base64 encoded password
echo -n 'your-secure-password' | base64

```

*Note: You can customize passwords in `mysql/mysql_sec.yaml` and `mongo/mongo_sec.yaml` prior to deployment.*

---

## 🚀 Deployment Guide

### Step 1: Create Namespaces

```bash
kubectl create namespace wordpress-ns
kubectl create namespace mongo-ns

```

### Step 2: Deploy MongoDB & Mongo Express (`mongo/` & `mongoex/`)

1. Apply Secrets & Storage Class:

```bash
kubectl apply -f mongo/mongo_sec.yaml -n mongo-ns
kubectl apply -f mongo/mongo_sc.yaml -n mongo-ns

```

2. Deploy PersistentVolumeClaim and MongoDB App:

```bash
kubectl apply -f mongo/mongo_pvc.yaml -n mongo-ns
kubectl apply -f mongo/mongo_deploy.yaml -n mongo-ns
kubectl apply -f mongo/mongo_svc.yaml -n mongo-ns

```

3. Deploy Mongo Express GUI:

```bash
kubectl apply -f mongoex/mongoex_cm.yaml -n mongo-ns
kubectl apply -f mongoex/mongoex_deploy.yaml -n mongo-ns
kubectl apply -f mongoex/mongoex_svc.yaml -n mongo-ns

```

### Step 3: Deploy MySQL & WordPress (`mysql/` & `wordpress/`)

1. Apply MySQL Secret & Storage:

```bash
kubectl apply -f mysql/mysql_sec.yaml -n wordpress-ns
kubectl apply -f mysql/mysql_sc.yaml -n wordpress-ns
kubectl apply -f mysql/myspl_pvc.yaml -n wordpress-ns

```

2. Deploy MySQL Database:

```bash
kubectl apply -f mysql/mysql_deploy.yaml -n wordpress-ns
kubectl apply -f mysql/mysql_svc.yaml -n wordpress-ns

```

3. Setup EFS PersistentVolume & Claim: *(Ensure EFS File System and Access Point `/wordpress` are created on AWS first)*

```bash
kubectl apply -f wordpress/wordpress_sc.yaml -n wordpress-ns
kubectl apply -f wordpress/wordpress_pv.yaml -n wordpress-ns
kubectl apply -f wordpress/wordpress_pvc.yaml -n wordpress-ns

```

4. Deploy WordPress Config & Frontend:

```bash
kubectl apply -f wordpress/wordpress_cm.yaml -n wordpress-ns
kubectl apply -f wordpress/wordpress_deploy.yaml -n wordpress-ns
kubectl apply -f wordpress/wordpress_svc.yaml -n wordpress-ns

```

### Step 4: Apply Central Ingress Routing

```bash
kubectl apply -f ingress.yaml

```

---

## 👥 Scoped Project-Admin Management (`context-admin.sh`)

To provision a dedicated project administrator with restricted full-access permissions across assigned namespaces:

```bash
./context-admin.sh <username> <namespace1> <namespace2>

# Example:
./context-admin.sh ahmed wordpress-ns mongo-ns

```

**What this automates:**

1. Generates an RSA private key and secure CSR.
2. Submits and auto-approves the Kubernetes `CertificateSigningRequest`.
3. Provisions `Role` and `RoleBinding`s granting full management permissions (`*`) strictly within the specified namespaces (`wordpress-ns` and `mongo-ns`).
4. Generates a standalone, ready-to-use `<username>-kubeconfig` file.

---

## 🧹 Automated Teardown & Cleanup (`cleanup.sh`)

To cleanly dismantle all workloads, PVCs, PVs, Ingress routes, and namespaces without leaving orphan resources or dangling EBS/EFS volumes on AWS:

```bash
chmod +x cleanup.sh
./cleanup.sh

```
