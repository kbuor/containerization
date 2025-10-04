
# Triển khai Kubernetes HA Cluster với 3 Master Node và nhiều Worker Node

**CNI:** Calico  
**Container Runtime:** containerd  
**Hệ điều hành:** Ubuntu 22.04+

---

## 1️⃣ Chuẩn bị trước

**Yêu cầu:**
- 3 Master Nodes và >=1 Worker Node
- Có thể SSH với quyền `root` hoặc `sudo`
- Các node kết nối mạng nội bộ với nhau
- Swap đã tắt hoàn toàn
- Đồng bộ thời gian (NTP)

---

## 2️⃣ Cài containerd và Kubernetes packages trên tất cả các node

**Thực hiện các bước sau trên từng node (Master & Worker):**

```bash
sudo apt update -y
sudo swapoff -a
sudo sed -i '/ swap / s/^/#/' /etc/fstab

echo -e "overlay\nbr_netfilter" | sudo tee /etc/modules-load.d/containerd.conf
sudo modprobe overlay
sudo modprobe br_netfilter

cat <<EOF | sudo tee /etc/sysctl.d/99-kubernetes-cri.conf
net.bridge.bridge-nf-call-iptables = 1
net.ipv4.ip_forward = 1
net.bridge.bridge-nf-call-ip6tables = 1
EOF
sudo sysctl --system

wget https://github.com/containerd/containerd/releases/download/v1.7.24/containerd-1.7.24-linux-amd64.tar.gz -P /tmp/
sudo tar -C /usr/local -xzf /tmp/containerd-1.7.24-linux-amd64.tar.gz

sudo wget https://raw.githubusercontent.com/containerd/containerd/main/containerd.service -O /etc/systemd/system/containerd.service
sudo systemctl daemon-reload
sudo systemctl enable --now containerd

wget https://github.com/opencontainers/runc/releases/download/v1.1.12/runc.amd64 -O /tmp/runc
sudo install -m 755 /tmp/runc /usr/local/sbin/runc

wget https://github.com/containernetworking/plugins/releases/download/v1.4.0/cni-plugins-linux-amd64-v1.4.0.tgz -P /tmp/
sudo mkdir -p /opt/cni/bin
sudo tar -C /opt/cni/bin -xzf /tmp/cni-plugins-linux-amd64-v1.4.0.tgz

sudo mkdir -p /etc/containerd
containerd config default | sudo tee /etc/containerd/config.toml
sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
sudo systemctl restart containerd

sudo apt install -y apt-transport-https ca-certificates curl gpg
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.31/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.31/deb/ /' | sudo tee /etc/apt/sources.list.d/kubernetes.list
sudo apt update
sudo apt install -y kubelet kubeadm kubectl
sudo apt-mark hold kubelet kubeadm kubectl

sudo reboot
```

---

## 3️⃣ Khởi tạo Master node đầu tiên

```bash
# Bạn cần chuẩn bị:
# - Control Plane Endpoint (VD: 10.10.10.11:6443)
# - Pod Network CIDR (VD: 192.168.0.0/16)
# - Service CIDR (VD: 10.96.0.0/12)
# - Danh sách các SAN (DNS hoặc IP)
```

```bash
sudo kubeadm init \
  --pod-network-cidr "<POD_CIDR>" \
  --control-plane-endpoint "<ENDPOINT:PORT>" \
  --apiserver-cert-extra-sans "<SAN1>,<SAN2>,..." \
  --upload-certs
```

```bash
mkdir -p $HOME/.kube
sudo cp /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config
```

---

## 4️⃣ Cài Calico làm CNI plugin

```bash
kubectl create -f https://raw.githubusercontent.com/projectcalico/calico/v3.30.0/manifests/tigera-operator.yaml
kubectl create -f https://raw.githubusercontent.com/projectcalico/calico/v3.30.0/manifests/custom-resources.yaml
```

---

## 5️⃣ Tạo lệnh join và chứng chỉ

```bash
kubeadm token create --print-join-command > /tmp/node-join-cmd
cp /tmp/node-join-cmd /tmp/master-join-cmd

CERT_KEY=$(kubeadm init phase upload-certs --upload-certs 2>/dev/null | grep -E '^[a-f0-9]{64}$')
sed -i "s/\$/ --control-plane --certificate-key $CERT_KEY/" /tmp/master-join-cmd
```

```bash
mkdir -p /tmp/cluster-certs/etcd
cp /etc/kubernetes/pki/{ca.*,sa.*,front-proxy-ca.*} /tmp/cluster-certs/
cp /etc/kubernetes/pki/etcd/ca.* /tmp/cluster-certs/etcd
cp /tmp/master-join-cmd /tmp/node-join-cmd /tmp/cluster-certs/
```

---

## 6️⃣ Thêm các Master node còn lại

**Trên các master node 2 và 3:**

```bash
scp -r ubuntu@<MASTER1_IP>:/tmp/cluster-certs ~/
sudo mkdir -p /etc/kubernetes/pki/etcd/
sudo cp ~/cluster-certs/*.crt ~/cluster-certs/*.key ~/cluster-certs/*.pub /etc/kubernetes/pki/
sudo cp ~/cluster-certs/etcd/ca.* /etc/kubernetes/pki/etcd/
bash ~/cluster-certs/master-join-cmd
```

---

## 7️⃣ Thêm các Worker node

**Trên mỗi worker node:**

```bash
scp root@<MASTER1_IP>:~/cluster-certs/node-join-cmd ~/
bash ~/node-join-cmd
```

---

## 8️⃣ Kiểm tra Cluster

```bash
kubectl get nodes -o wide
kubectl get pods -A
```
