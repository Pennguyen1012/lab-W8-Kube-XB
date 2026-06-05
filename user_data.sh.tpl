#!/bin/bash
set -e

# Ép biến môi trường chuẩn cho root
export HOME=/root
export KUBECONFIG=/root/.kube/config

# 1. Cài đặt Docker
apt-get update
apt-get install -y docker.io
systemctl enable --now docker
usermod -aG docker ubuntu

# 2. Cài đặt Kind
curl -Lo ./kind https://kind.sigs.k8s.io/dl/v0.22.0/kind-linux-amd64
chmod +x ./kind
mv ./kind /usr/local/bin/kind

# 3. Cài đặt kubectl
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
chmod +x kubectl
mv kubectl /usr/local/bin/

# 4. Tạo file cấu hình port mapping cho Kind (Host Port 80 -> Container Port 30080)
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

# 5. Khởi chạy cụm Kubernetes bằng Kind (Docker driver)
kind create cluster --config /root/kind-config.yaml --kubeconfig /root/.kube/config

# 6. Deploy App Nginx và Expose ra NodePort 30080
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

kubectl apply -f /root/app.yaml --kubeconfig /root/.kube/config