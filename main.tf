# 1. Fetch info about Default VPC and Subnets
data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

# 2. Wire providers: Produce SSH key via TLS provider and then store it via Local provider
resource "tls_private_key" "k8s_key" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_key_pair" "k8s_key_pair" {

  key_name   = "k8s-challenge-key"
  public_key = tls_private_key.k8s_key.public_key_openssh
}

resource "local_file" "private_key" {
  content         = tls_private_key.k8s_key.private_key_pem
  filename        = "${path.module}/k8s-challenge-key.pem"
  file_permission = "0400"
}

# 3. Security groups
resource "aws_security_group" "alb_sg" {
  name        = "k8s-alb-sg"
  description = "Allow HTTP inbound to ALB"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "ec2_sg" {
  name        = "k8s-ec2-sg"
  description = "Allow SSH and HTTP from ALB"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port       = 80
    to_port         = 80
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

# EC2 setup to run Kind K8s
resource "aws_instance" "k8s_node" {
  ami           = var.ami_id
  instance_type = var.instance_type
  key_name      = aws_key_pair.k8s_key_pair.key_name

  vpc_security_group_ids      = [aws_security_group.ec2_sg.id]
  associate_public_ip_address = true

  user_data = <<-EOF
    #!/bin/bash
    set -e
    
    # Ép biến môi trường chuẩn cho root
    export HOME=/root
    export KUBECONFIG=/root/.kube/config

    # Docker installation
    apt-get update
    apt-get install -y docker.io
    systemctl enable --now docker
    usermod -aG docker ubuntu

    # Kind installation
    curl -Lo ./kind https://kind.sigs.k8s.io/dl/v0.22.0/kind-linux-amd64
    chmod +x ./kind
    mv ./kind /usr/local/bin/kind

    # Kubectl installation
    curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
    chmod +x kubectl
    mv kubectl /usr/local/bin/

    # Create Kind config file mapping port 80 of the host to port 30080 of the cluster
    cat << 'EOT' > /root/kind-config.yaml
    kind: Cluster
    apiVersion: kind.x-k8s.io/v1alpha4
    nodes:
    - role: control-plane
      extraPortMappings:
      - containerPort: 30080
        hostPort: 80
        protocol: TCP
    EOT

    # Kind initialization (Ép lưu config vào đúng chỗ)
    kind create cluster --config /root/kind-config.yaml --kubeconfig /root/.kube/config

    # Manifest creation for App and Service
    cat << 'EOT' > /root/app.yaml
    apiVersion: apps/v1
    kind: Deployment
    metadata:
      name: hello-app
    spec:
      replicas: 1
      selector:
        matchLabels:
          app: hello
      template:
        metadata:
          labels:
            app: hello
        spec:
          containers:
          - name: hello
            image: nginxdemos/hello:plain-text
            ports:
            - containerPort: 80
    ---
    apiVersion: v1
    kind: Service
    metadata:
      name: hello-service
    spec:
      type: NodePort
      selector:
        app: hello
      ports:
      - port: 80
        targetPort: 80
        nodePort: 30080
    EOT

    # Deploy App into K8s
    kubectl apply -f /root/app.yaml --kubeconfig /root/.kube/config
  EOF

  tags = {
    Name = "K8s-Challenge-Node"
  }
}

# 5. ALB setup
resource "aws_lb" "k8s_alb" {
  name               = "k8s-challenge-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb_sg.id]
  subnets            = data.aws_subnets.default.ids
}

resource "aws_lb_target_group" "k8s_tg" {
  name     = "k8s-challenge-tg"
  port     = 80
  protocol = "HTTP"
  vpc_id   = data.aws_vpc.default.id

  health_check {
    path                = "/"
    protocol            = "HTTP"
    matcher             = "200"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }
}

resource "aws_lb_listener" "k8s_listener" {
  load_balancer_arn = aws_lb.k8s_alb.arn
  port              = 80
  protocol          = "HTTP"
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.k8s_tg.arn
  }
}

resource "aws_lb_target_group_attachment" "k8s_tg_attach" {
  target_group_arn = aws_lb_target_group.k8s_tg.arn
  target_id        = aws_instance.k8s_node.id
  port             = 80
}
