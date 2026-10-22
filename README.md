

# Multi-Tenant AWS EKS Architecture: WordPress & MongoDB Stacks with Namespace RBAC, Hybrid EFS/EBS CSI Storage & Cross-Namespace Ingress
---

![Kubernetes](https://img.shields.io/badge/Kubernetes-326CE5?style=for-the-badge&logo=kubernetes&logoColor=white)
![AWS](https://img.shields.io/badge/AWS-FF9900?style=for-the-badge&logo=amazon-aws&logoColor=white)
![NGINX](https://img.shields.io/badge/NGINX-009639?style=for-the-badge&logo=nginx&logoColor=white)
![WordPress](https://img.shields.io/badge/WordPress-21759B?style=for-the-badge&logo=wordpress&logoColor=white)
![MongoDB](https://img.shields.io/badge/MongoDB-47A248?style=for-the-badge&logo=mongodb&logoColor=white)
![MySQL](https://img.shields.io/badge/MySQL-4479A1?style=for-the-badge&logo=mysql&logoColor=white)


---
## Executive Overview & Engineering Value

Modern cloud-native teams rarely run a single application in a flat Kubernetes cluster. In production environments, platform engineers must isolate multiple workloads on shared cluster infrastructure while preventing noisy-neighbor resource contention, storage deadlocks during pod rollouts, and over-privileged developer access (`cluster-admin` sprawl).

This project implements a complete, production-patterned **Multi-Tenant Kubernetes Architecture on AWS (EKS)** hosting two independent two-tier application stacks—**WordPress + MySQL** and **Mongo Express + MongoDB**—isolated across dedicated namespaces, dedicated EC2 worker nodes, hybrid AWS storage backends, and cryptographic X.509 RBAC boundaries, all exposed behind a single AWS Elastic Load Balancer via cross-namespace NGINX Ingress routing.



### What Value This Architecture Delivers to Engineering Teams

| Engineering Pillar | Real-World Problem Solved | How This Project Solves It | Business & Operational Impact |
| :--- | :--- | :--- | :--- |
| **Workload & Compute Isolation** | Noisy-neighbor CPU/memory spikes from one stack degrading another stack on shared nodes | Enforces hard **Node Affinity** (`requiredDuringSchedulingIgnoredDuringExecution`) paired with **Taints & Tolerations** (`NoSchedule`) for `app=wordpress` and `app=mongo` | Guarantees predictable compute performance and strict blast-radius containment per project |
| **Cloud-Native Hybrid Storage** | Stateless web tiers cannot scale horizontally on block storage, while databases corrupt data on shared file systems | Pairs **AWS EFS CSI (`ReadWriteMany`)** for the WordPress web tier with **AWS EBS CSI (`ReadWriteOnce` + `WaitForFirstConsumer`)** for MySQL and MongoDB | Enables multi-pod horizontal web scaling on EFS while preserving high-IOPS block storage integrity for databases |
| **Zero-Deadlock Stateful Updates** | Default `RollingUpdate` on `ReadWriteOnce` EBS volumes deadlocks with `Multi-Attach error` when a replacement pod lands on a second node | Configures explicit `strategy.type: Recreate` on stateful EBS database Deployments (`mysql-app` and `mongo-app`) | Eliminates stuck database rollouts and guarantees clean EBS volume detachment and re-attachment across restarts |
| **Cost-Efficient Edge Routing** | Provisioning a separate AWS Load Balancer per namespace wastes cloud budget ($18–$25+/month per extra ALB/NLB) | Bridges a single NGINX Ingress Controller in the `default` namespace to isolated app namespaces using **`ExternalName` Services** (`svc.cluster.local`) | Consolidates external traffic onto a single AWS ELB while maintaining strict namespace separation |
| **Least-Privilege Access (RBAC)** | Sharing global `cluster-admin` kubeconfig exposes `kube-system` and unrelated workloads to accidental deletion | Automates OpenSSL X.509 client certificate generation, Kubernetes CSR approval, and namespace-scoped `Role`/`RoleBinding` creation via `context-admin.sh` | Restricts developers strictly to `wordpress-ns` and `mongo-ns` with zero visibility into `default` or `kube-system` |
| **Day-2 Lifecycle Automation** | Orphaned `Retain`-policy PersistentVolumes and PVCs silently accumulate AWS storage charges after lab teardown | Provides an automated, dependency-ordered teardown script (`cleanup.sh`) that purges Ingresses, workloads, PVCs, retained PVs, and namespaces | Prevents cloud billing leaks and enables repeatable 1-command environment resets |

---

## Core Engineering Challenges Solved During Implementation

### 1. Cross-Namespace Ingress Routing via Kubernetes Internal DNS (`ExternalName`)
Kubernetes `Ingress` resources can only route traffic directly to `Service` objects residing in the same namespace. Rather than deploying duplicate Ingress Controllers in `wordpress-ns` and `mongo-ns`, this architecture places the Ingress layer in `default` and creates lightweight `ExternalName` Services (`wordpress-external-svc` and `mongoex-external-svc`) that resolve at the DNS level to:
* `wordpress-svc.wordpress-ns.svc.cluster.local` (Port `80`)
* `mongoex-svc.mongo-ns.svc.cluster.local` (Port `8081`)

### 2. Subpath Routing Mechanics: Regex Rewrites vs. Base-URL Prefixing
Exposing multiple applications under subpaths (`/wordpress` and `/mongo`) on a single AWS ELB hostname introduces two distinct application-layer routing challenges:
* **WordPress (`/wordpress`)**: The official `wordpress:6.6-apache` container serves files from the Apache document root (`/var/www/html/`), not `/var/www/html/wordpress/`. To prevent `404 Not Found` responses, `wordpress-ingress` applies `nginx.ingress.kubernetes.io/rewrite-target: /$2` with the regex path `/wordpress(/|$)(.*)` to strip the prefix before forwarding to Apache, while `WORDPRESS_CONFIG_EXTRA` dynamically sets `WP_HOME` and `WP_SITEURL` using `$_SERVER['HTTP_HOST']` so CSS, JS, and `/wp-admin` links remain intact on any ELB hostname.
* **Mongo Express (`/mongo`)**: Unlike WordPress, Mongo Express supports native subpath mounting via `ME_CONFIG_SITE_BASEURL: "/mongo/"`. Applying a `rewrite-target` to Mongo Express when `ME_CONFIG_SITE_BASEURL` is enabled would cause an infinite redirect loop. Splitting the routing into two dedicated Ingress objects (`wordpress-ingress` with rewrite and `mongo-ingress` without rewrite) allows both applications to coexist cleanly.

### 3. Bypassing Admission Webhook Snippet Restrictions Safely
Modern NGINX Ingress Controller releases disable `nginx.ingress.kubernetes.io/server-snippet` annotations by default (`validate.nginx.ingress.kubernetes.io`) to prevent configuration injection vulnerabilities. The Ingress manifests are structured to rely exclusively on native controller health checks and standard `networking.k8s.io/v1` rules so they pass strict admission webhook validation out of the box.

---

## Repository Structure

```text
Project/
├── ingressRouting/
│   ├── ingress.yaml              # Dedicated wordpress-ingress (rewrite) & mongo-ingress (prefix)
│   ├── mongo_exName.yaml         # ExternalName Service -> mongoex-svc.mongo-ns.svc.cluster.local
│   └── wordpress_exName.yaml     # ExternalName Service -> wordpress-svc.wordpress-ns.svc.cluster.local
├── mongo/
│   ├── mongo_deploy.yaml         # MongoDB 7.0 Deployment (Recreate strategy + Node Affinity/Toleration)
│   ├── mongo_pvc.yaml            # 5Gi ReadWriteOnce PVC bound to mongo-sc
│   ├── mongo_sc.yaml             # AWS EBS CSI StorageClass (WaitForFirstConsumer, Retain)
│   ├── mongo_sec.yaml            # Opaque Secret for MongoDB root credentials
│   └── mongo_svc.yaml            # ClusterIP Service (:27017)
├── mongoex/
│   ├── mongoex_cm.yaml           # ConfigMap pointing to mongo-svc
│   ├── mongoex_deploy.yaml       # Mongo Express 1.0.2 Deployment (ME_CONFIG_SITE_BASEURL=/mongo/)
│   └── mongoex_svc.yaml          # ClusterIP Service (:8081)
├── mysql/
│   ├── mysql_deploy.yaml         # MySQL 8.0 Deployment (Recreate strategy + Node Affinity/Toleration)
│   ├── mysql_pvc.yaml            # 5Gi ReadWriteOnce PVC bound to mysql-sc
│   ├── mysql_sc.yaml             # AWS EBS CSI StorageClass (WaitForFirstConsumer, Retain)
│   ├── mysql_sec.yaml            # Opaque Secret for MySQL password
│   └── mysql_svc.yaml            # ClusterIP Service (:3306)
├── wordpress/
│   ├── wordpress_cm.yaml         # ConfigMap pointing to mysql-svc
│   ├── wordpress_deploy.yaml     # WordPress 6.6-Apache Deployment + dynamic WP_HOME/WP_SITEURL
│   ├── wordpress_pv.yaml         # Static 5Gi ReadWriteMany PV backed by AWS EFS Access Point
│   ├── wordpress_pvc.yaml        # 5Gi ReadWriteMany PVC bound to efs-sc
│   ├── wordpress_sc.yaml         # AWS EFS CSI StorageClass (efs.csi.aws.com)
│   └── wordpress_svc.yaml        # ClusterIP Service (:80)
├── all.yaml                      # Unified single-file manifest for 1-command deployment
├── context-admin.sh              # Automated X.509 user cert, CSR, RBAC & kubeconfig generator
├── cleanup.sh                    # Automated teardown script for workloads, PVCs, PVs & namespaces
├── QuickTest.mp4                 # Short demo video (apply + test + cleanup)
└── test-context.png              # Screenshot proving restricted user RBAC (Forbidden on kube-system)
```

---

## Prerequisites for First-Time Deployment

Before deploying this architecture on your own AWS EKS cluster, ensure the following prerequisites are satisfied:

1. **AWS EKS Cluster with at least 2 Worker Nodes**: Required so you can dedicate one node to `wordpress` and another to `mongo`.
2. **AWS EBS CSI Driver & AWS EFS CSI Driver Installed**:
* The EBS CSI driver dynamically provisions the 5Gi block volumes for `mysql-pvc` and `mongo-pvc`.
* The EFS CSI driver mounts the shared AWS EFS Access Point for `wordpress-efs-pvc`.


3. **An Existing AWS EFS File System & Access Point**: Update the `volumeHandle` field inside `wordpress/wordpress_pv.yaml` (and `all.yaml`) with your own EFS File System ID and Access Point ID (`fs-xxxxxxxxxxxxxxxxx::fsap-xxxxxxxxxxxxxxxxx`).
4. **NGINX Ingress Controller Installed**: Deployed with an AWS LoadBalancer Service (`ingressClassName: nginx`).
5. **OpenSSL & `kubectl` Installed Locally**: Required if running `context-admin.sh` to generate scoped developer `kubeconfig` files.

---

## Step-by-Step Deployment Guide

### Step 1: Create the Isolated Namespaces

Create the two project namespaces before applying the manifests:

```bash
kubectl create namespace mongo-ns
kubectl create namespace wordpress-ns

```

### Step 2: Label and Taint Your Dedicated Worker Nodes

Because all Deployments enforce strict `nodeAffinity` and `NoSchedule` tolerations, label and taint one worker node for WordPress and a second worker node for MongoDB:

```bash
# List your cluster nodes
kubectl get nodes

# Dedicate Node 1 to the WordPress & MySQL stack
kubectl label nodes <NODE_1_NAME> app=wordpress
kubectl taint nodes <NODE_1_NAME> app=wordpress:NoSchedule

# Dedicate Node 2 to the MongoDB & Mongo Express stack
kubectl label nodes <NODE_2_NAME> app=mongo
kubectl taint nodes <NODE_2_NAME> app=mongo:NoSchedule

```

### Step 3: Deploy the Full Architecture

You can deploy the entire stack at once using the unified `all.yaml` manifest, or apply each component directory modularly:

**Option A — Single-Command Deployment:**

```bash
kubectl apply -f all.yaml

```

**Option B — Modular Directory Deployment:**

```bash
kubectl apply -f mongo/
kubectl apply -f mongoex/
kubectl apply -f mysql/
kubectl apply -f wordpress/
kubectl apply -f ingressRouting/

```

### Step 4: Verify Pods, Storage, and Ingress Routing

Confirm that all pods are `1/1 Running` and retrieve your AWS Load Balancer DNS address:

```bash
kubectl get all,pvc -n mongo-ns
kubectl get all,pvc -n wordpress-ns
kubectl get ingress,svc -n default

```

Open your browser using the `ADDRESS` shown under `kubectl get ingress -n default`:

* **WordPress Frontend**: `http://<YOUR_ELB_DNS_NAME>/wordpress`
* **Mongo Express UI**: `http://<YOUR_ELB_DNS_NAME>/mongo` 

---

## Onboarding a Namespace-Restricted User (`context-admin.sh`)

To provision a developer with X.509 certificate authentication restricted exclusively to `wordpress-ns` and `mongo-ns`:

```bash
chmod +x context-admin.sh
./context-admin.sh ahmed wordpress-ns mongo-ns

```

The script automatically:

1. Generates a 2048-bit RSA private key (`ahmed.key`) and Certificate Signing Request (`ahmed.csr`).
2. Submits a Kubernetes `CertificateSigningRequest`, approves it via the cluster CA, and exports the signed client certificate (`ahmed.crt`).
3. Creates `Role` and `RoleBinding` objects inside `wordpress-ns` and `mongo-ns`.
4. Outputs a standalone, portable `ahmed-kubeconfig` file.

Test the restricted user permissions:

```bash
# Allowed: Full access inside wordpress-ns and mongo-ns
kubectl --kubeconfig=ahmed-kubeconfig get pods -n wordpress-ns
kubectl --kubeconfig=ahmed-kubeconfig get pods -n mongo-ns

# Denied (Forbidden): Zero access to default or kube-system
kubectl --kubeconfig=ahmed-kubeconfig get pods -n kube-system

```

---

## Automated Environment Teardown (`cleanup.sh`)

To cleanly remove all Ingress rules, Deployments, Services, PVCs, retained PersistentVolumes, and namespaces without leaving orphaned AWS resources:

```bash
chmod +x cleanup.sh
./cleanup.sh

```

---

## Production Hardening Notes

For immediate portability across any reviewer's dynamically generated AWS ELB hostname, this repository intentionally omits the `host:` constraint on `wordpress-ingress` and `mongo-ingress` and uses dynamic `$_SERVER['HTTP_HOST']` detection in WordPress. When promoting this architecture to a live production environment:

* **Lock Ingress `host:` Rules & Enable TLS**: Bind each Ingress to an explicit Route 53 domain (such as `blog.example.com`) with automated TLS certificates via `cert-manager` or AWS ACM to prevent HTTP Host Header Injection attacks.
* **Restrict Database Admin UIs (`mongo-express`)**: Remove public Ingress exposure for `/mongo` and access `mongo-express` via VPN, an internal-only ALB, OAuth2 Proxy, or `kubectl port-forward svc/mongoex-svc -n mongo-ns 8081:8081`.
* **Externalize Secrets Management**: Replace base64-encoded `Secret` manifests with the **AWS Secrets Manager + External Secrets Operator (ESO)** or **SealedSecrets**.
* **Add NetworkPolicies & Resource Quotas**: Apply Kubernetes `NetworkPolicy` manifests to block cross-namespace pod-to-pod traffic at the CNI layer, and configure CPU/memory `requests`, `limits`, `livenessProbe`, and `readinessProbe` checks on all containers.
