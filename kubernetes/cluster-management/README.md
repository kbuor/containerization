# Deploy Master
## Prepare Linux
- Update linux repository
```shell
apt update -y
```
- Disable Swap
```shell
swapoff -a
vi /etc/fstab
```
> Remove `swap` from `/etc/fstab` file

## Install Container Runtime
- Tải các module kernel cần thiết:

```shell
printf "overlay\nbr_netfilter\n" >> /etc/modules-load.d/containerd.conf
modprobe overlay
modprobe br_netfilter
```
> Lệnh đầu tiên thêm các module overlay và br_netfilter vào file cấu hình `/etc/modules-load.d/containerd.conf` để đảm bảo chúng sẽ được tải khi khởi động hệ thống.

> `modprobe overlay` và `modprobe br_netfilter` được sử dụng để tải ngay lập tức các module này vào kernel. Module overlay hỗ trợ hệ thống file overlayFS, cần thiết cho containerd, và module br_netfilter cho phép kiểm soát lưu lượng mạng giữa các container.

- Cấu hình các thông số mạng hệ thống:

```shell
printf "net.bridge.bridge-nf-call-iptables = 1\nnet.ipv4.ip_forward = 1\nnet.bridge.bridge-nf-call-ip6tables = 1\n" >> /etc/sysctl.d/99-kubernetes-cri.conf
sysctl --system
```
> Thêm các cấu hình liên quan đến mạng vào file `/etc/sysctl.d/99-kubernetes-cri.conf`:

> `net.bridge.bridge-nf-call-iptables = 1`: Cho phép iptables kiểm soát lưu lượng mạng qua các bridge.

> `net.ipv4.ip_forward = 1`: Cho phép chuyển tiếp IP, cần thiết để forward các gói IP giữa các mạng.

> `net.bridge.bridge-nf-call-ip6tables = 1`: Tương tự như iptables, nhưng cho IPv6.

- Cài đặt containerd:

```shell
wget https://github.com/containerd/containerd/releases/download/v1.7.13/containerd-1.7.13-linux-amd64.tar.gz -P /tmp/
tar Cxzvf /usr/local /tmp/containerd-1.7.13-linux-amd64.tar.gz
wget https://raw.githubusercontent.com/containerd/containerd/main/containerd.service -P /etc/systemd/system/
systemctl daemon-reload
systemctl enable --now containerd
```

- Cài đặt runc:

```shell
wget https://github.com/opencontainers/runc/releases/download/v1.1.12/runc.amd64 -P /tmp/
install -m 755 /tmp/runc.amd64 /usr/local/sbin/runc
```

- Cài đặt các plugin mạng CNI:

```shell
wget https://github.com/containernetworking/plugins/releases/download/v1.4.0/cni-plugins-linux-amd64-v1.4.0.tgz -P /tmp/
mkdir -p /opt/cni/bin
tar Cxzvf /opt/cni/bin /tmp/cni-plugins-linux-amd64-v1.4.0.tgz
```
> Tạo thư mục `/opt/cni/bin` và giải nén các plugin vào đó. Các plugin này cung cấp các chức năng mạng cơ bản cho Kubernetes, như cấu hình địa chỉ IP, routing, và các quy tắc iptables.

- Cấu hình containerd:

```shell
mkdir -p /etc/containerd
containerd config default | tee /etc/containerd/config.toml
vi /etc/containerd/config.toml
```
> Tạo thư mục cấu hình `/etc/containerd`.

> `containerd config default | tee /etc/containerd/config.toml` tạo file cấu hình mặc định cho containerd.

> Sử dụng `vi` để chỉnh sửa file `/etc/containerd/config.toml`, thay đổi giá trị `SystemdCgroup` thành `true` ở dòng 137 để containerd sử dụng cgroup của systemd, giúp quản lý tài nguyên hệ thống một cách hiệu quả hơn.


## Install Dependency

> Dependency need to install: docker, kubeadm, kubelet

- Add GPG key for Kubernetes repository
```shell
apt-get install ca-certificates curl gnupg lsb-release apt-transport-https gpg
sudo mkdir -m 0755 -p /etc/apt/keyrings
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.29/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
```
- Add Kubernetes repository
```shell
echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.29/deb/ /' | sudo tee /etc/apt/sources.list.d/kubernetes.list
```

- Update repository
```shell
apt update -y
reboot
```
- Install dependency components
```shell
apt install -y kubelet=1.29.1-1.1 kubeadm=1.29.1-1.1 kubectl=1.29.1-1.1
```
- Hold Kubernetes components version
```shell
apt-mark hold kubelet kubeadm kubectl
```
- Enable `kubelet` service
```shell
systemctl enable --now kubelet
```
## Bootstraping Master
- Bootstraping master using `kubeadm`
```shell
kubeadm init --pod-network-cidr 192.168.0.0/16 --kubernetes-version 1.29.1 --node-name k8s-master --apiserver-cert-extra-sans 103.141.177.132 --apiserver-cert-extra-sans k8s.kbuor.tech --apiserver-cert-extra-sans k8s-master
```
- Configure token
```shell
mkdir -p $HOME/.kube
cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config
```
- Apply overlay networking
```shell
kubectl create -f https://raw.githubusercontent.com/projectcalico/calico/v3.27.2/manifests/tigera-operator.yaml
kubectl create -f https://raw.githubusercontent.com/projectcalico/calico/v3.27.2/manifests/custom-resources.yaml
```
## Optional command
- Get node information
```shell
kubectl get nodes
```
- Get node health
```shell
kubectl get componentstatuses
```
- Get system pods status
```shell
kubectl get pods --all-namespaces
```
- Show join command
```shell
kubeadm token create --print-join-command
```

--------------

# Deploy Node

## Prepare Linux
- Update linux repository
```shell
apt update -y
apt upgrade -y
```
- Disable Swap
```shell
swapoff -a
```

## Install Container Runtime
- Tải các module kernel cần thiết:

```shell
printf "overlay\nbr_netfilter\n" >> /etc/modules-load.d/containerd.conf
modprobe overlay
modprobe br_netfilter
```
> Lệnh đầu tiên thêm các module overlay và br_netfilter vào file cấu hình `/etc/modules-load.d/containerd.conf` để đảm bảo chúng sẽ được tải khi khởi động hệ thống.

> `modprobe overlay` và `modprobe br_netfilter` được sử dụng để tải ngay lập tức các module này vào kernel. Module overlay hỗ trợ hệ thống file overlayFS, cần thiết cho containerd, và module br_netfilter cho phép kiểm soát lưu lượng mạng giữa các container.

- Cấu hình các thông số mạng hệ thống:

```shell
printf "net.bridge.bridge-nf-call-iptables = 1\nnet.ipv4.ip_forward = 1\nnet.bridge.bridge-nf-call-ip6tables = 1\n" >> /etc/sysctl.d/99-kubernetes-cri.conf
sysctl --system
```
> Thêm các cấu hình liên quan đến mạng vào file `/etc/sysctl.d/99-kubernetes-cri.conf`:

> `net.bridge.bridge-nf-call-iptables = 1`: Cho phép iptables kiểm soát lưu lượng mạng qua các bridge.

> `net.ipv4.ip_forward = 1`: Cho phép chuyển tiếp IP, cần thiết để forward các gói IP giữa các mạng.

> `net.bridge.bridge-nf-call-ip6tables = 1`: Tương tự như iptables, nhưng cho IPv6.

- Cài đặt containerd:

```shell
wget https://github.com/containerd/containerd/releases/download/v1.7.13/containerd-1.7.13-linux-amd64.tar.gz -P /tmp/
tar Cxzvf /usr/local /tmp/containerd-1.7.13-linux-amd64.tar.gz
wget https://raw.githubusercontent.com/containerd/containerd/main/containerd.service -P /etc/systemd/system/
systemctl daemon-reload
systemctl enable --now containerd
```

- Cài đặt runc:

```shell
wget https://github.com/opencontainers/runc/releases/download/v1.1.12/runc.amd64 -P /tmp/
install -m 755 /tmp/runc.amd64 /usr/local/sbin/runc
```

- Cài đặt các plugin mạng CNI:

```shell
wget https://github.com/containernetworking/plugins/releases/download/v1.4.0/cni-plugins-linux-amd64-v1.4.0.tgz -P /tmp/
mkdir -p /opt/cni/bin
tar Cxzvf /opt/cni/bin /tmp/cni-plugins-linux-amd64-v1.4.0.tgz
```
> Tạo thư mục `/opt/cni/bin` và giải nén các plugin vào đó. Các plugin này cung cấp các chức năng mạng cơ bản cho Kubernetes, như cấu hình địa chỉ IP, routing, và các quy tắc iptables.

- Cấu hình containerd:

```shell
mkdir -p /etc/containerd
containerd config default | tee /etc/containerd/config.toml
vi /etc/containerd/config.toml
```
> Tạo thư mục cấu hình `/etc/containerd`.

> `containerd config default | tee /etc/containerd/config.toml` tạo file cấu hình mặc định cho containerd.

> Sử dụng `vi` để chỉnh sửa file `/etc/containerd/config.toml`, thay đổi giá trị `SystemdCgroup` thành `true` ở dòng 137 để containerd sử dụng cgroup của systemd, giúp quản lý tài nguyên hệ thống một cách hiệu quả hơn.


## Install Dependency

> Dependency need to install: docker, kubeadm, kubelet

- Add GPG key for Kubernetes repository
```shell
apt-get install ca-certificates curl gnupg lsb-release apt-transport-https gpg
sudo mkdir -m 0755 -p /etc/apt/keyrings
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.29/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
```
- Add Kubernetes repository
```shell
echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.29/deb/ /' | sudo tee /etc/apt/sources.list.d/kubernetes.list
```

- Update repository
```shell
apt update -y
reboot
```
- Install dependency components
```shell
apt install -y kubelet=1.29.1-1.1 kubeadm=1.29.1-1.1 kubectl=1.29.1-1.1
```
- Hold Kubernetes components version
```shell
apt-mark hold kubelet kubeadm kubectl
```
- Enable `kubelet` service
```shell
systemctl enable --now kubelet
```
## Join Node to Master
> Run the join command. This command can be find by `kubeadm token create --print-join-command` command run from master.


-----------

# Deploy Kubernetes Dashboard
Deploy the dashboard for kubernetes
> Ref. Link: https://kubernetes.io/docs/tasks/access-application-cluster/web-ui-dashboard/

## Deploying the dashboard UI

> Download the dashboard.yaml manifest
```shell
wget https://raw.githubusercontent.com/kbuor/Kubernetes/main/manifest/dashboard.yaml
```

> Create the workload and services
```shell
kubectl apply -f dashboard.yaml
```

## Create `kubernetes-dashboard-certs`
> Using OpenSSL to generate SSL self-Certificate
```shell
mkdir certs
chmod -R 777 certs
openssl req -nodes -newkey rsa:2048 -keyout certs/dashboard.key -out certs/dashboard.csr -subj "/C=/ST=/L=/O=/OU=/CN=kubernetes-dashboard"
openssl x509 -req -sha256 -days 365 -in certs/dashboard.csr -signkey certs/dashboard.key -out certs/dashboard.crt
```

> Create secret for `kubernetes-dashboard-certs`
```shell
kubectl create secret generic kubernetes-dashboard-certs --from-file=certs -n kubernetes-dashboard
```

## Create User and Get Token to Login
> Create Service Account
```shell
wget https://raw.githubusercontent.com/kbuor/Kubernetes/main/manifest/service-account.yaml
kubectl apply -f service-account.yaml
```
> Create ClusterRoleBinding
```shell
wget https://raw.githubusercontent.com/kbuor/Kubernetes/main/manifest/cluster-role-binding.yaml
kubectl apply -f cluster-role-binding.yaml
```
> Get token
```shell
kubectl -n kubernetes-dashboard create token admin-user
```

> (Optional) Install K9s
```shell
curl -sS https://webinstall.dev/k9s | bash
```
-----------

# Upgrade Master

> Check current version of `kubeadm`
```shell
kubeadm version -o short
```

> Check current version of `kubectl` `api & master components`
```shell
kubectl version --short
```


## Upgrade `kubeadm` package

> Upgrade `kubeadm` package
```shell
apt-mark unhold kubeadm
apt install -y kubeadm=1.27.3-00
apt-mark hold kubeadm
```

## Check upgrade plan

> Check upgrade plan using `kubeadm`: docker, kubeadm, kubelet

```shell
kubeadm upgrade plan
```

## Upgrade Master and Components

> Run the recommand command receive from upgrade plan

```shell
kubeadm upgrade apply <plan>
```

## Upgrade `kubelet` package

> Upgrade `kubelet` package
```shell
apt-mark unhold kubelet
apt install -y kubelet=1.27.3-00
apt-mark hold kubelet
```

## Upgrade `kubectl` package

> Upgrade `kubectl` package
```shell
apt-mark unhold kubectl
apt install -y kubeadm=1.27.3-00
apt-mark hold kubectl
```

> Check current version of `kubeadm`
```shell
kubeadm version -o short
```

> Check current version of `kubectl` `api & master components`
```shell
kubectl version --short
```
-----------
# Upgrade Node
Upgrade the Master by upgrade `kubelet`

> Check current version of `kubeadm`
```shell
kubeadm version -o short
```

> Check current version of `kubectl` `api & master components`
```shell
kubectl version --short
```

## Cordon the Node

> Cordon the Node using `kubectl` command
```shell
kubectl cordon k8s-node-01
```

## Drain the Node

> Drain the Node using `kubectl` command

```shell
kubectl drain k8s-node-01
```

## Upgrade `kubelet` package

> Upgrade `kubelet` package
```shell
apt-mark unhold kubelet
apt install -y kubelet=1.27.3-00
apt-mark hold kubelet
```

## Upgrade `kubectl` package

> Upgrade `kubectl` package
```shell
apt-mark unhold kubectl
apt install -y kubeadm=1.27.3-00
apt-mark hold kubectl
```

## UnCordon the Node

> UnCordon the Node using `kubectl` command
```shell
kubectl uncordon k8s-node-01
```
> Check current version of `kubeadm`
```shell
kubeadm version -o short
```

> Check current version of `kubectl` `api & master components`
```shell
kubectl version --short
```
