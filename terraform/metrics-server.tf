
resource "aws_eks_addon" "metrics_server" {
  cluster_name  = aws_eks_cluster.main.name
  addon_name    = "metrics-server"
  addon_version = "v0.9.0-eksbuild.14"

  depends_on = [
    aws_eks_node_group.main
  ]
}
