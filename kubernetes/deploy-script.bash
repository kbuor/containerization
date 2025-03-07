#!/bin/bash

# Commands to be executed on all nodes:
DEPLOY_CONTAINER_RUNTIME=$(cat <<'EOF'
echo "Running commands on $(hostname)..."
sudo apt update -y
swappoff -a
sudo sed -i '/ swap / s/^/#/' /etc/fstab

printf "overlay\nbr_netfilter\n" >> /etc/modules-load.d/containerd.conf
modprobe overlay
modprobe br_netfilter

printf "net.bridge.bridge-nf-call-iptables = 1\nnet.ipv4.ip_forward = 1\nnet.bridge.bridge-nf-call-ip6tables = 1\n" >> /etc/sysctl.d/99-kubernetes-cri.conf
sysctl --system

# Install "containerd"
wget https://github.com/containerd/containerd/releases/download/v1.7.24/containerd-1.7.24-linux-amd64.tar.gz -P /tmp/
tar Cxzvf /usr/local /tmp/containerd-1.7.24-linux-amd64.tar.gz
wget https://raw.githubusercontent.com/containerd/containerd/main/containerd.service -P /etc/systemd/system/
systemctl daemon-reload
systemctl enable --now containerd

# Install "runc"
wget https://github.com/opencontainers/runc/releases/download/v1.1.12/runc.amd64 -P /tmp/
install -m 755 /tmp/runc.amd64 /usr/local/sbin/runc

# Install "CNI plugin"
wget https://github.com/containernetworking/plugins/releases/download/v1.4.0/cni-plugins-linux-amd64-v1.4.0.tgz -P /tmp/
mkdir -p /opt/cni/bin
tar Cxzvf /opt/cni/bin /tmp/cni-plugins-linux-amd64-v1.4.0.tgz

# Modify "containerd" configure
mkdir -p /etc/containerd
containerd config default | tee /etc/containerd/config.toml
sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml

# Install Dependency
sudo apt-get update
sudo apt-get install -y apt-transport-https ca-certificates curl gpg
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.31/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.31/deb/ /' | sudo tee /etc/apt/sources.list.d/kubernetes.list
sudo apt-get update
reboot
EOF
)

# Commands to be executed on the first master nodes:
BOOTSTRAP_MASTER_NODE=$(cat <<'EOF'
echo "Running commands on $(hostname)..."
# Variables
declare -a ACES
count=1
read -p "Control Plane Endpoint: " CPE
read -p "Pod Network Cidr: " PNC
read -p "Service CIDR: " SC

while true; do
  read -p "API Server Cert Extra SANs $count (Enter to finish): " input
  if [[ -z "$input" ]]; then
    break
  fi
  ACES+=("$input")
  count=$((count + 1))
done
APISERVER_SANS=$(IFS=, ; echo "${ACES[*]}")

sudo apt-get install -y kubelet kubeadm kubectl
sudo apt-mark hold kubelet kubeadm kubectl
sudo systemctl enable --now kubelet

# Bootstrap Kubernetes Master
kubeadm init \
--control-plane-endpoint $CPE \
--pod-network-cidr $PNC \
--service-cidr $SC \
--upload-certs \
--apiserver-cert-extra-sans $APISERVER_SANS

mkdir -p $HOME/.kube
cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config

sleep 30

# Apply overlay networking
kubectl create -f https://raw.githubusercontent.com/projectcalico/calico/v3.27.2/manifests/tigera-operator.yaml
kubectl create -f https://raw.githubusercontent.com/projectcalico/calico/v3.27.2/manifests/custom-resources.yaml

kubeadm token create --print-join-command > /tmp/node-join-cmd
cp /tmp/node-join-cmd /tmp/master-join-cmd
certificatekey=$(kubeadm init phase upload-certs --upload-certs | tail -n 1)
sed -i "s/$/--control-plane --certificate-key $certificatekey/" /tmp/master-join-cmd

EOF
)

JOIN_MASTER=$(cat <<'EOF'
sudo apt-get install -y kubelet kubeadm kubectl
sudo apt-mark hold kubelet kubeadm kubectl
sudo systemctl enable --now kubelet
mkdir -p /etc/kubernetes/pki/etcd
mv /root/ca.crt /etc/kubernetes/pki/
mv /root/ca.key /etc/kubernetes/pki/
mv /root/sa.pub /etc/kubernetes/pki/
mv /root/sa.key /etc/kubernetes/pki/
mv /root/front-proxy-ca.crt /etc/kubernetes/pki/
mv /root/front-proxy-ca.key /etc/kubernetes/pki/
mv /root/etcd-ca.crt /etc/kubernetes/pki/etcd/ca.crt
mv /root/etcd-ca.key /etc/kubernetes/pki/etcd/ca.key
source /root/master-join-cmd
EOF
)

JOIN_WORKER=$(cat <<'EOF'
sudo apt-get install -y kubelet kubeadm kubectl
sudo apt-mark hold kubelet kubeadm kubectl
sudo systemctl enable --now kubelet
source /root/node-join-cmd
EOF
)

# Variable to store the list of Master Nodes
declare -a MASTER_NODES

# Input Master Node list
echo "Enter the list of Master Nodes (IP or hostname). Press Enter to finish."

while true; do
    read -p "Enter Master Node number $((${#MASTER_NODES[@]} + 1)): " NODE
    if [[ -z "$NODE" ]]; then
        echo "Input finished."
        break
    fi
    MASTER_NODES+=("$NODE")
done

# Check if the list is empty
if [[ ${#MASTER_NODES[@]} -eq 0 ]]; then
    echo "Master Node list is empty. Exiting script."
    exit 1
fi

# Display the Master Node list
echo "List of Master Nodes:"
for NODE in "${MASTER_NODES[@]}"; do
    echo "- $NODE"
done

# Commands to be executed on each Master Node

# SSH into each Master Node with 'root' user and execute commands
echo "Starting SSH into Master Nodes using 'root' user and running commands..."
for NODE in "${MASTER_NODES[@]}"; do
    echo "Connecting to $NODE with user 'root'..."
    ssh -t root@"$NODE" "$DEPLOY_CONTAINER_RUNTIME" &
done

wait

echo "SSH and command execution on all Master Nodes completed."

echo "Waiting for all node rebooting..."
sleep 100

FIRST_NODE=${MASTER_NODES[0]}
ssh -t root@"$FIRST_NODE" "$BOOTSTRAP_MASTER_NODE"

mkdir -p /tmp/cluster-certs
scp root@"$FIRST_NODE":/etc/kubernetes/pki/ca.crt /tmp/cluster-certs/
scp root@"$FIRST_NODE":/etc/kubernetes/pki/ca.key /tmp/cluster-certs/
scp root@"$FIRST_NODE":/etc/kubernetes/pki/sa.key /tmp/cluster-certs/
scp root@"$FIRST_NODE":/etc/kubernetes/pki/sa.pub /tmp/cluster-certs/
scp root@"$FIRST_NODE":/etc/kubernetes/pki/front-proxy-ca.crt /tmp/cluster-certs/
scp root@"$FIRST_NODE":/etc/kubernetes/pki/front-proxy-ca.key /tmp/cluster-certs/
scp root@"$FIRST_NODE":/etc/kubernetes/pki/etcd/ca.crt /tmp/cluster-certs/etcd-ca.crt
scp root@"$FIRST_NODE":/etc/kubernetes/pki/etcd/ca.key /tmp/cluster-certs/etcd-ca.key
scp root@"$FIRST_NODE":/tmp/master-join-cmd /tmp/cluster-certs/
scp root@"$FIRST_NODE":/tmp/node-join-cmd /tmp/cluster-certs/


for NODE in "${MASTER_NODES[@]}"; do
    scp /tmp/cluster-certs/ca.crt root@"$NODE":
    scp /tmp/cluster-certs/ca.key root@"$NODE":
    scp /tmp/cluster-certs/sa.key root@"$NODE":
    scp /tmp/cluster-certs/sa.pub root@"$NODE":
    scp /tmp/cluster-certs/front-proxy-ca.crt root@"$NODE":
    scp /tmp/cluster-certs/front-proxy-ca.key root@"$NODE":
    scp /tmp/cluster-certs/etcd-ca.crt root@"$NODE":
    scp /tmp/cluster-certs/etcd-ca.key root@"$NODE":
    scp /tmp/cluster-certs/master-join-cmd root@"$NODE":
    scp /tmp/cluster-certs/node-join-cmd root@"$NODE":
done

for NODE in "${MASTER_NODES[@]:1}"; do
    echo "Connecting to $NODE with user 'root'..."
    ssh -t root@"$NODE" "$JOIN_MASTER" &
done

wait

# Variable to store the list of Worker Nodes
declare -a WORKER_NODES

# Input Master Node list
echo "Enter the list of Worker Nodes (IP or hostname). Press Enter to finish."

while true; do
    read -p "Enter Worker Node number $((${#WORKER_NODES[@]} + 1)): " NODE
    if [[ -z "$NODE" ]]; then
        echo "Input finished."
        break
    fi
    WORKER_NODES+=("$NODE")
done

# Check if the list is empty
if [[ ${#WORKER_NODES[@]} -eq 0 ]]; then
    echo "Worker Node list is empty. Exiting script."
    exit 1
fi

# Display the Master Node list
echo "List of Worker Nodes:"
for NODE in "${WORKER_NODES[@]}"; do
    echo "- $NODE"
done

# Commands to be executed on each Master Node

# SSH into each Master Node with 'root' user and execute commands
echo "Starting SSH into Worker Nodes using 'root' user and running commands..."
for NODE in "${WORKER_NODES[@]}"; do
    echo "Connecting to $NODE with user 'root'..."
    ssh -t root@"$NODE" "$DEPLOY_CONTAINER_RUNTIME" &
done

wait

echo "SSH and command execution on all Worker Nodes completed."

echo "Waiting for all node rebooting..."
sleep 100

for NODE in "${WORKER_NODES[@]}"; do
    scp /tmp/cluster-certs/node-join-cmd root@"$NODE":
done

for NODE in "${WORKER_NODES[@]}"; do
    echo "Connecting to $NODE with user 'root'..."
    ssh -t root@"$NODE" "$JOIN_WORKER" &
done

wait
