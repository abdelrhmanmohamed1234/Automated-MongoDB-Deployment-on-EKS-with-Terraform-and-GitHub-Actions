# 1. Data source to get the EKS cluster name (if not already defined)
data "aws_eks_cluster" "target" {
  name = aws_eks_cluster.main.name
}

# 2. Install the AWS Load Balancer Controller using Helm
resource "helm_release" "aws_lbc" {
  name       = "aws-load-balancer-controller"
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-load-balancer-controller"
  namespace  = "kube-system"
  version    = "1.7.1" # Use the latest stable version

  # Ensure the controller starts only after the EKS Node Group is ready
  depends_on = [aws_eks_node_group.main]

  set {
    name  = "clusterName"
    value = data.aws_eks_cluster.target.name
  }

  set {
    name  = "serviceAccount.create"
    value = "true"
  }

  set {
    name  = "serviceAccount.name"
    value = "aws-load-balancer-controller"
  }

  set {
    name  = "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
    value = aws_iam_role.aws_lbc_role.arn
  }

  # This setting is important for Fargate or specific VPC CNI setups, 
  # but safe to keep for standard EC2 nodes as well.
  set {
    name  = "region"
    value = var.region
  }

  set {
    name  = "vpcId"
    value = aws_vpc.main.id
  }
}
