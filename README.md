# Automated MongoDB & Mongo-Express Deployment on AWS EKS

![Kubernetes](https://img.shields.io/badge/Kubernetes-1.29-326CE5?style=for-the-badge&logo=kubernetes&logoColor=white)
![Terraform](https://img.shields.io/badge/Terraform-IaC-7B42BC?style=for-the-badge&logo=terraform&logoColor=white)
![AWS](https://img.shields.io/badge/AWS-EKS-FF9900?style=for-the-badge&logo=amazonaws&logoColor=white)
![GitHub Actions](https://img.shields.io/badge/GitHub_Actions-CI%2FCD-2088FF?style=for-the-badge&logo=githubactions&logoColor=white)
![MongoDB](https://img.shields.io/badge/MongoDB-Database-47A248?style=for-the-badge&logo=mongodb&logoColor=white)
![Rocky Linux](https://img.shields.io/badge/Rocky_Linux-Runner-10B981?style=for-the-badge&logo=rockylinux&logoColor=white)

> A production-grade, fully automated CI/CD pipeline that provisions an AWS EKS cluster using Terraform and deploys MongoDB with persistent EBS storage and a Mongo-Express web UI — triggered by a single `git push`.

---

## Table of Contents

- [Overview](#overview)
- [Architecture](#architecture)
- [Project Structure](#project-structure)
- [Prerequisites](#prerequisites)
- [Step-by-Step Deployment](#step-by-step-deployment)
  - [1. Bootstrap Remote State](#1-bootstrap-remote-state)
  - [2. Provision Infrastructure with Terraform](#2-provision-infrastructure-with-terraform)
  - [3. Configure Kubeconfig](#3-configure-kubeconfig)
  - [4. Deploy Kubernetes Manifests](#4-deploy-kubernetes-manifests)
- [Persistence Verification Test](#persistence-verification-test)
- [Accessing Mongo-Express](#accessing-mongo-express)
- [Lessons Learned](#lessons-learned)
- [Cleanup](#cleanup)
- [Author](#author)

---

## Overview

This project demonstrates a complete **GitOps workflow** for deploying a stateful database application on AWS. The entire lifecycle — from raw AWS infrastructure to a live web UI — is automated through a GitHub Actions pipeline running on a self-hosted Rocky Linux runner.

### What gets deployed:

| Layer | Technology | Purpose |
|-------|-----------|---------|
| Cloud Infrastructure | AWS EKS + VPC | Managed Kubernetes cluster |
| Infrastructure as Code | Terraform | Provision all AWS resources |
| Database | MongoDB + PVC | Persistent stateful storage on EBS GP3 |
| Web UI | Mongo-Express | Browser-based database management |
| Ingress | AWS ALB Controller | Public-facing Application Load Balancer |
| CI/CD | GitHub Actions | Fully automated deployment pipeline |
| State Management | AWS S3 + DynamoDB | Remote Terraform state + locking |

---

## Architecture

```
┌───────────────────────────────────────────────────────────────┐
│                        AWS (us-east-1)                        │
│                                                               │
│  ┌─────────────────────────────────────────────────────────┐  │
│  │                  VPC (10.0.0.0/16)                      │  │
│  │                                                         │  │
│  │  ┌──────────────────┐    ┌──────────────────┐           │  │
│  │  │ Public Subnet 1  │    │ Public Subnet 2  │           │  │
│  │  │  (us-east-1a)    │    │  (us-east-1b)    │           │  │
│  │  │                  │    │                  │           │  │
│  │  │  ┌────────────┐  │    │  ┌────────────┐  │           │  │
│  │  │  │  Worker    │  │    │  │  Worker    │  │           │  │
│  │  │  │  Node 1    │  │    │  │  Node 2    │  │           │  │
│  │  │  │ t3.medium  │  │    │  │ t3.medium  │  │           │  │
│  │  │  └────────────┘  │    │  └────────────┘  │           │  │
│  │  └──────────────────┘    └──────────────────┘           │  |
│  │                                                         │  │
│  │         EKS Control Plane (AWS Managed)                 │  │
│  └─────────────────────────────────────────────────────────┘  │
│                                                               │
│  ┌──────────┐   ┌──────────────┐   ┌───────────────────────┐  │
│  │ S3 Bucket│   │   DynamoDB   │   │      EBS GP3          │  │
│  │  (state) │   │    (lock)    │   │  (MongoDB Storage)    │  │
│  └──────────┘   └──────────────┘   └───────────────────────┘  │
└───────────────────────────────────────────────────────────────┘

Traffic Flow:
Internet → ALB (public) → Mongo-Express Service → Mongo-Express Pod
                                                        │
                                                        ▼
                                              MongoDB ClusterIP Service
                                                        │
                                                        ▼
                                                  MongoDB Pod
                                                        │
                                                        ▼
                                                  EBS GP3 Volume
```

### IAM & Security (IRSA)

```
OIDC Provider
     │
     ├── EBS CSI Driver Role  ──► AmazonEBSCSIDriverPolicy
     └── ALB Controller Role  ──► AWSLoadBalancerControllerPolicy
```

---

## Project Structure

```
CI-CD-MongoDB-Deployment-on-EKS-Using-Terraform/
│
├── terraform/                        # Infrastructure as Code
│   ├── backend.tf                    # S3 + DynamoDB remote state
│   ├── providers.tf                  # AWS + TLS providers
│   ├── variables.tf                  # Input variables
│   ├── vpc.tf                        # VPC, subnets, IGW, route tables
│   ├── roles.tf                      # All IAM roles, policies, OIDC
│   ├── eks.tf                        # EKS cluster, node group, EBS addon
│   └── outputs.tf                    # Cluster name, endpoint
│
├── k8s/                              # Kubernetes manifests
│   ├── storageclass.yaml             # GP3 EBS StorageClass
│   ├── mongo-secret.yaml             # MongoDB credentials (base64)
│   ├── mongo-pvc.yaml                # PersistentVolumeClaim for EBS
│   ├── mongo-deployment.yaml         # MongoDB Deployment
│   ├── mongo-service.yaml            # MongoDB ClusterIP Service
│   ├── mongoexpress-deployment.yaml  # Mongo-Express Deployment
│   ├── mongoexpress-service.yaml     # Mongo-Express Service
│   └── ingress.yaml                  # ALB Ingress (internet-facing)
│
└── .github/
    └── workflows/
        └── deploy.yaml               # GitHub Actions CI/CD pipeline
```

---

## Prerequisites

Before you begin, ensure you have the following:

- [ ] AWS account with programmatic access (Access Key + Secret Key)
- [ ] AWS CLI configured (`aws configure`)
- [ ] Terraform >= 1.3.0 installed
- [ ] kubectl installed
- [ ] Git installed
- [ ] GitHub repository created
- [ ] Self-hosted GitHub Actions runner registered on Rocky Linux

---

## Step-by-Step Deployment

### 1. Bootstrap Remote State

Create the S3 bucket and DynamoDB table for Terraform remote state **before** running any Terraform commands:

```bash
# Create S3 bucket for state storage
aws s3api create-bucket \
  --bucket eks-mongodb-terraform-state \
  --region us-east-1

# Enable versioning on the bucket
aws s3api put-bucket-versioning \
  --bucket eks-mongodb-terraform-state \
  --versioning-configuration Status=Enabled

# Create DynamoDB table for state locking
aws dynamodb create-table \
  --table-name terraform-state-lock \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST \
  --region us-east-1
```

---

### 2. Provision Infrastructure with Terraform

```bash
cd terraform/

# Initialize Terraform and connect to S3 backend
terraform init

# Preview all resources that will be created
terraform plan

# Apply and provision the EKS cluster (~15 minutes)
terraform apply
```

Terraform will create the following AWS resources:

- VPC with 2 public subnets across 2 Availability Zones
- Internet Gateway + Route Tables
- EKS Cluster (v1.29) with Managed Node Group (2x t3.medium)
- IAM Roles for cluster, nodes, EBS CSI Driver (IRSA)
- EBS CSI Driver addon
- OIDC Provider for IRSA

---

### 3. Configure Kubeconfig

After `terraform apply` completes, connect `kubectl` to the new cluster:

```bash
aws eks update-kubeconfig \
  --region us-east-1 \
  --name my-eks-cluster

# Verify nodes are Ready
kubectl get nodes -o wide
```

Expected output:
```
NAME                         STATUS   ROLES    AGE   VERSION
ip-10-0-0-xx.ec2.internal    Ready    <none>   5m    v1.29.x-eks-xxxxx
ip-10-0-1-xx.ec2.internal    Ready    <none>   5m    v1.29.x-eks-xxxxx
```

---

### 4. Deploy Kubernetes Manifests

Apply all manifests in order:

```bash
cd k8s/

# Storage
kubectl apply -f storageclass.yaml

# MongoDB
kubectl apply -f mongo-secret.yaml
kubectl apply -f mongo-pvc.yaml
kubectl apply -f mongo-deployment.yaml
kubectl apply -f mongo-service.yaml

# Mongo-Express
kubectl apply -f mongoexpress-deployment.yaml
kubectl apply -f mongoexpress-service.yaml

# Ingress (ALB)
kubectl apply -f ingress.yaml
```

Verify all pods are running:

```bash
kubectl get pods
kubectl get services
kubectl get ingress
```

---

### CI/CD — Automated via GitHub Actions

All of the above steps (Terraform + kubectl apply) are automated in `.github/workflows/deploy.yaml`.

Every push to the `main` branch triggers:

```
git push origin main
        │
        ▼
GitHub Actions (self-hosted Rocky Linux runner)
        │
        ├── terraform init
        ├── terraform plan
        ├── terraform apply    ──► EKS cluster created on AWS
        ├── aws eks update-kubeconfig
        └── kubectl apply -f k8s/  ──► MongoDB + Mongo-Express deployed
```

GitHub Secrets required:

| Secret | Description |
|--------|-------------|
| `AWS_ACCESS_KEY_ID` | AWS programmatic access key |
| `AWS_SECRET_ACCESS_KEY` | AWS secret access key |

---

## Persistence Verification Test

This test proves that MongoDB data survives pod restarts — confirming EBS persistent storage is working correctly.

**Step 1 — Insert test data into MongoDB:**

```bash
# Get the MongoDB pod name
kubectl get pods

# Connect to MongoDB shell
kubectl exec -it <mongodb-pod-name> -- mongosh -u root -p <password>

# Insert a test document
use testdb
db.users.insertOne({ name: "Abdelrhman", role: "DevOps Engineer" })
db.users.find()
```

**Step 2 — Delete the MongoDB pod:**

```bash
kubectl delete pod <mongodb-pod-name>
```

Kubernetes will automatically recreate the pod (managed by the Deployment).

**Step 3 — Verify data survived:**

```bash
# Wait for new pod to be Running
kubectl get pods -w

# Connect to the new pod
kubectl exec -it <new-mongodb-pod-name> -- mongosh -u root -p <password>

# Check data is still there
use testdb
db.users.find()
```

Expected output:
```json
{ "_id": ObjectId("..."), "name": "Abdelrhman", "role": "DevOps Engineer" }
```

Data persists because MongoDB writes to the EBS GP3 volume — not inside the container. ✅

---

## Accessing Mongo-Express

After the ALB Ingress is provisioned (takes ~3 minutes), get the public URL:

```bash
kubectl get ingress
```

Output:
```
NAME               CLASS   HOSTS   ADDRESS                                          PORTS
mongo-express-ing  alb     *       k8s-xxxx.us-east-1.elb.amazonaws.com            80
```

Open the `ADDRESS` URL in your browser to access the Mongo-Express web UI.

---

## Lessons Learned

### 1. STS 403 — `SignatureDoesNotMatch` Error

**Problem:** Terraform and AWS CLI commands were failing with a `SignatureDoesNotMatch` error when communicating with AWS STS.

**Root Cause:** System clock drift on the Rocky Linux controller machine. AWS request signatures are time-sensitive and will be rejected if the system clock is more than 5 minutes out of sync.

**Fix:**
```bash
# Sync system clock with NTP
sudo ntpdate pool.ntp.org

# Or enable chronyd permanently
sudo systemctl enable --now chronyd
```

---

### 2. ALB `TIMED_OUT` — Ingress Connectivity Issue

**Problem:** The ALB was provisioned and accessible, but all requests to Mongo-Express were timing out.

**Root Cause:** When using `target-type: ip` in the ALB Ingress, the load balancer routes traffic directly to the pod IP. The Ingress backend was configured to use the **Service port (80)** instead of the **actual application port that the pod listens on (8081)**.

**Fix:** Update the Ingress backend port to match the container's true listening port:

```yaml
# Wrong
backend:
  service:
    port:
      number: 80

# Correct
backend:
  service:
    port:
      number: 8081
```

---

### 3. Terraform `Unsupported attribute` Error

**Problem:** Terraform threw `Unsupported attribute` errors during the VPC build phase when referencing resource attributes that had not yet been created.

**Root Cause:** Incorrect resource reference path or attempting to use an attribute before the resource was fully defined.

**Fix:** Carefully trace all resource references back to their source definition and ensure `depends_on` is set where implicit dependencies are not automatically detected by Terraform.

---

### 4. EBS Cross-AZ Mounting Issue

**Problem:** MongoDB pod was stuck in `Pending` state due to an EBS volume being created in a different Availability Zone than the node trying to mount it.

**Root Cause:** The default `WaitForFirstConsumer` binding mode was not configured, causing the PVC to bind to an EBS volume in the wrong AZ before a pod was scheduled.

**Fix:** Use a custom `StorageClass` with `volumeBindingMode: WaitForFirstConsumer`:

```yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: ebs-gp3
provisioner: ebs.csi.aws.com
volumeBindingMode: WaitForFirstConsumer
parameters:
  type: gp3
```

---

## Cleanup

> ⚠️ Always destroy resources after testing to avoid unnecessary AWS charges.

**Step 1 — Delete Kubernetes resources:**

```bash
kubectl delete -f k8s/
```

**Step 2 — Destroy all AWS infrastructure:**

```bash
cd terraform/
terraform destroy
```

Type `yes` when prompted.

**Step 3 — Delete remote state resources (optional):**

```bash
# Delete S3 bucket
aws s3 rm s3://eks-mongodb-terraform-state --recursive
aws s3api delete-bucket --bucket eks-mongodb-terraform-state --region us-east-1

# Delete DynamoDB table
aws dynamodb delete-table --table-name terraform-state-lock --region us-east-1
```

### Estimated Cost for Testing:

| Resource | Cost/Hour | 5 Hours |
|----------|-----------|---------|
| EKS Control Plane | $0.10 | $0.50 |
| 2x t3.medium nodes | $0.0832 | $0.416 |
| EBS GP3 storage | ~$0.01 | ~$0.05 |
| **Total** | | **~$1.00** |

---

## Author

**Abdelrhman Mohamed**

> Built with a focus on real-world DevOps practices — Infrastructure as Code, GitOps automation, persistent storage, and production-grade security using IRSA.

![AWS](https://img.shields.io/badge/AWS-Certified_Ready-FF9900?style=flat-square&logo=amazonaws)
![GitOps](https://img.shields.io/badge/GitOps-Practitioner-2088FF?style=flat-square&logo=git)
![Kubernetes](https://img.shields.io/badge/Kubernetes-Engineer-326CE5?style=flat-square&logo=kubernetes)

