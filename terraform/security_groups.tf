# Security Group for the Application Load Balancer (ALB)
resource "aws_security_group" "alb_sg" {
  name        = "${var.cluster_name}-alb-sg"
  vpc_id      = aws_vpc.main.id

  # Allow your browser to access the ALB on Port 80
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] 
  }

  # Allow ALB to send traffic out to the nodes
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# Security Group for the EKS Worker Nodes
resource "aws_security_group" "node_sg" {
  name        = "${var.cluster_name}-node-sg"
  vpc_id      = aws_vpc.main.id

  # IMPORTANT: Allow the ALB to talk to the Nodes
  ingress {
    from_port       = 0
    to_port         = 65535
    protocol        = "tcp"
    security_groups = [aws_security_group.alb_sg.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}
