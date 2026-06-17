# Buổi 06 - Helm, MetalLB và Ingress NGINX Controller trên Kubernetes v1.35

## 1. Mục tiêu của buổi học

Ở các buổi trước,  đã biết cách triển khai một cụm Kubernetes bằng `kubeadm`, hiểu các workload như Pod, Deployment, DaemonSet, StatefulSet, Job, CronJob; biết Service nội bộ như `ClusterIP`, `NodePort`, `Headless`, `ExternalName`; biết cách sử dụng ConfigMap, Secret, Volume, PVC, StorageClass và CSI NFS.

Buổi này mở khóa một nhóm kiến thức mới: cách triển khai các thành phần mở rộng vào cluster bằng Helm, cách cấp địa chỉ IP truy cập từ bên ngoài cho môi trường bare-metal/on-premise bằng MetalLB, và cách đưa ứng dụng web ra ngoài thông qua Ingress NGINX Controller.

Sau buổi học,  cần nắm được:

- Helm là gì và vì sao Helm thường được dùng để cài các thành phần phức tạp trong Kubernetes.
- Các khái niệm cơ bản của Helm: Chart, Repository, Release, Values.
- MetalLB giải quyết vấn đề gì trong môi trường Kubernetes on-premise.
- Vì sao Service type `LoadBalancer` trên on-premise thường bị trạng thái `<pending>` nếu không có thành phần cấp IP.
- Cách cài MetalLB bằng Helm.
- Cách cấu hình `IPAddressPool` và `L2Advertisement` cho MetalLB ở Layer 2 mode.
- Ingress là gì và khác gì so với Service.
- Vì sao chỉ tạo Ingress object là chưa đủ, mà phải có Ingress Controller.
- Cách cài Ingress NGINX Controller bằng Helm.
- Cách publish một ứng dụng web ra ngoài qua HTTP.
- Cách publish một ứng dụng web ra ngoài qua HTTPS bằng TLS Secret.
- Cách kiểm tra, troubleshoot và dọn dẹp tài nguyên sau bài lab.

## 2. Phạm vi kiến thức của buổi học

### 2.1. Kiến thức đã được phép sử dụng từ các buổi trước

Buổi này được phép sử dụng lại các kiến thức đã học:

- Cluster, Node, Control Plane, Worker Node.
- kube-apiserver, kubelet, scheduler, controller-manager, etcd ở mức kiến trúc.
- Namespace.
- Pod.
- Deployment.
- DaemonSet.
- Service `ClusterIP`, `NodePort`.
- DNS nội bộ qua CoreDNS.
- ConfigMap.
- Secret.
- Volume.
- YAML manifest.
- `kubectl apply`, `kubectl get`, `kubectl describe`, `kubectl logs`, `kubectl exec`.

### 2.2. Kiến thức mới được mở khóa trong buổi này

Buổi này mở khóa thêm:

- Helm.
- Helm Chart.
- Helm Repository.
- Helm Release.
- Helm Values.
- `helm install`.
- `helm upgrade --install`.
- `helm list`.
- `helm status`.
- `helm show values`.
- Service type `LoadBalancer` trong ngữ cảnh on-premise.
- MetalLB.
- MetalLB Controller.
- MetalLB Speaker.
- `IPAddressPool`.
- `L2Advertisement`.
- Ingress.
- Ingress Controller.
- IngressClass.
- Ingress NGINX Controller.
- TLS Secret cho Ingress.

### 2.3. Những nội dung chưa đi sâu trong buổi này

Để giữ đúng tiến trình kiến thức, buổi này chưa đi sâu vào:

- Gateway API.
- cert-manager.
- ExternalDNS.
- Cloud Controller Manager của AWS, Azure, GCP.
- AWS Load Balancer Controller.
- Azure Application Gateway Ingress Controller.
- GKE Ingress/Gateway.
- NGINX rewrite nâng cao.
- Canary Ingress.
- Sticky session.
- WAF/ModSecurity.
- mTLS.
- Ingress multi-controller phức tạp.
- Production hardening chi tiết.

Các nội dung này nên để các buổi nâng cao sau.

## 3. Mô hình lab của buổi học

### 3.1. Mô hình cluster

Bài lab tiếp tục sử dụng cụm Kubernetes đã triển khai từ Buổi 02.

```text
+-------------------------------+
|        Kubernetes Cluster      |
|        Version: v1.35          |
+-------------------------------+

Control Plane:
  master-01
  Ubuntu 24.04
  containerd
  kubeadm
  kubelet
  kubectl

Worker Nodes:
  worker-01
  Ubuntu 24.04
  containerd
  kubelet

  worker-02
  Ubuntu 24.04
  containerd
  kubelet

CNI:
  Calico

Storage từ buổi trước:
  nfs-01
  Ubuntu 24.04
  NFS Server
```

### 3.2. Ví dụ địa chỉ IP trong bài lab

> Lưu ý: Dải IP bên dưới chỉ là ví dụ. Khi triển khai trong lớp học thật, giảng viên cần thay bằng dải IP thực tế của môi trường lab.

```text
master-01    10.10.10.11
worker-01    10.10.10.21
worker-02    10.10.10.22
nfs-01       10.10.10.31

MetalLB IP Pool:
  10.10.10.240 - 10.10.10.250
```

Dải IP dành cho MetalLB phải thỏa các điều kiện:

- Cùng Layer 2 network với các node Kubernetes nếu dùng Layer 2 mode.
- Không trùng IP của node.
- Không trùng IP của gateway.
- Không trùng IP của DNS server.
- Không nằm trong dải DHCP đang tự động cấp cho máy khác.
- Nên được reserve riêng cho Kubernetes LoadBalancer Service.

Ví dụ nếu mạng lab là `10.10.10.0/24`, gateway là `10.10.10.254`, các VM dùng IP từ `10.10.10.11` đến `10.10.10.31`, thì có thể dành `10.10.10.240-10.10.10.250` cho MetalLB.

## 4. Bức tranh tổng thể của buổi học

Sau khi hoàn tất bài lab, luồng truy cập ứng dụng sẽ như sau:

```text
Client / Browser
      |
      | HTTP/HTTPS
      v
MetalLB External IP
10.10.10.240
      |
      v
Service type LoadBalancer
ingress-nginx-controller
      |
      v
Ingress NGINX Controller Pod
      |
      v
Ingress Rule
host: web.lab.local
path: /
      |
      v
Service ClusterIP của ứng dụng
lesson-06-web-svc
      |
      v
Pod ứng dụng web
lesson-06-web
```

Điểm quan trọng cần hiểu:

- Client không truy cập trực tiếp vào Pod.
- Client cũng không cần biết IP của Pod.
- Client truy cập vào một IP bên ngoài do MetalLB cấp.
- IP đó đang gắn với Service type `LoadBalancer` của Ingress NGINX Controller.
- Ingress NGINX Controller nhận HTTP/HTTPS request.
- Ingress rule quyết định request đó được chuyển đến Service nào.
- Service tiếp tục chuyển traffic đến Pod phù hợp.

## 5. Vấn đề cần giải quyết: đưa ứng dụng web ra ngoài cluster

Ở Buổi 04,  đã biết `NodePort` có thể expose ứng dụng ra ngoài cluster.

Ví dụ:

```text
http://<Node-IP>:30080
```

Cách này đơn giản nhưng có nhiều điểm bất tiện:

- Phải dùng port cao trong dải NodePort, mặc định thường là `30000-32767`.
- Không thân thiện với người dùng cuối.
- Nếu có nhiều ứng dụng web, mỗi ứng dụng cần một NodePort riêng.
- Không xử lý tốt routing theo domain.
- Không xử lý tốt routing theo path.
- Không phải cách tự nhiên để publish nhiều website dùng chung port 80/443.
- Nếu dùng nhiều worker node, client cần biết nên truy cập node nào.
- Nếu node bị down, cần có cơ chế chuyển hướng bên ngoài.

Ingress giúp giải quyết bài toán routing HTTP/HTTPS theo domain và path.

MetalLB giúp giải quyết bài toán cấp IP truy cập từ bên ngoài cho môi trường on-premise/bare-metal.

Helm giúp triển khai các thành phần như MetalLB và Ingress NGINX Controller một cách gọn gàng hơn.

## 6. Helm

## 6.1. Helm là gì?

Helm là package manager cho Kubernetes.

Nếu xem Kubernetes manifest là các file YAML riêng lẻ, thì Helm giúp đóng gói nhiều manifest liên quan thành một gói triển khai gọi là Chart.

Một ứng dụng hoặc một thành phần hạ tầng trong Kubernetes thường không chỉ có một YAML duy nhất. Ví dụ Ingress NGINX Controller có thể bao gồm:

- Namespace.
- ServiceAccount.
- ClusterRole.
- ClusterRoleBinding.
- Role.
- RoleBinding.
- Deployment.
- Service.
- ConfigMap.
- ValidatingWebhookConfiguration.
- Job tạo certificate cho webhook.
- IngressClass.
- Các label/annotation liên quan.

Nếu phải quản lý tất cả file YAML này thủ công, việc cài đặt, nâng cấp và gỡ bỏ sẽ rất dễ sai.

Helm giúp gom các tài nguyên đó lại thành một chart, cho phép người vận hành cài đặt bằng một lệnh và tùy chỉnh bằng values.

## 6.2. Các khái niệm cốt lõi của Helm

### Chart

Chart là một gói chứa template Kubernetes manifest.

Một chart có thể đại diện cho:

- Một ứng dụng web.
- Một database.
- Một monitoring stack.
- Một ingress controller.
- Một storage driver.
- Một load balancer implementation.

Ví dụ:

```text
ingress-nginx/ingress-nginx
metallb/metallb
bitnami/nginx
```

### Repository

Repository là nơi lưu trữ các chart.

Ví dụ repository của Ingress NGINX Controller:

```bash
https://kubernetes.github.io/ingress-nginx
```

Ví dụ repository của MetalLB:

```bash
https://metallb.github.io/metallb
```

### Release

Release là một lần cài đặt chart vào cluster.

Một chart có thể được cài nhiều lần với nhiều release name khác nhau.

Ví dụ cùng một chart `nginx`, có thể cài thành:

```text
web-dev
web-staging
web-production
```

Mỗi release có cấu hình, lifecycle và revision riêng.

### Values

Values là dữ liệu đầu vào dùng để tùy chỉnh chart.

Ví dụ khi cài Ingress NGINX Controller, ta có thể tùy chỉnh Service type:

```bash
--set controller.service.type=LoadBalancer
```

Hoặc dùng file values riêng:

```bash
helm upgrade --install ingress-nginx ingress-nginx/ingress-nginx \
  --namespace ingress-nginx \
  --values ingress-nginx-values.yaml
```

## 6.3. Vì sao cần học Helm ở thời điểm này?

Tới Buổi 06,  đã đủ nền tảng để hiểu:

- Helm thực chất vẫn tạo ra Kubernetes objects.
- Các object đó vẫn là Deployment, Service, ConfigMap, Secret, DaemonSet, ClusterRole...
- Helm không thay thế Kubernetes.
- Helm chỉ giúp quản lý manifest theo dạng package.

Đây là thời điểm phù hợp để đưa Helm vào vì các thành phần như MetalLB và Ingress NGINX Controller có nhiều manifest phức tạp. Nếu cài bằng YAML raw ngay từ đầu,  dễ bị ngợp bởi số lượng object.

## 6.4. Cài Helm trên Ubuntu 24.04

Thực hiện trên máy dùng để quản trị cluster, thường là `master-01`.

### Cách 1: cài từ Apt repository

```bash
sudo apt-get update
sudo apt-get install -y curl gpg apt-transport-https

curl -fsSL https://packages.buildkite.com/helm-linux/helm-debian/gpgkey \
  | gpg --dearmor \
  | sudo tee /usr/share/keyrings/helm.gpg > /dev/null

echo "deb [signed-by=/usr/share/keyrings/helm.gpg] https://packages.buildkite.com/helm-linux/helm-debian/any/ any main" \
  | sudo tee /etc/apt/sources.list.d/helm-stable-debian.list

sudo apt-get update
sudo apt-get install -y helm
```

Kiểm tra:

```bash
helm version
```

Kết quả kỳ vọng:

```text
version.BuildInfo{Version:"v4.x.x", ...}
```

Hoặc:

```text
version.BuildInfo{Version:"v3.x.x", ...}
```

Tùy thời điểm cài đặt, hệ thống có thể dùng Helm v3 hoặc Helm v4. Trong phạm vi bài học này, các lệnh cơ bản như `repo add`, `repo update`, `upgrade --install`, `list`, `status`, `uninstall` có cùng ý nghĩa vận hành.

### Cách 2: cài bằng script chính thức

```bash
curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-4
chmod 700 get_helm.sh
./get_helm.sh
```

Kiểm tra:

```bash
helm version
```

Trong môi trường production, nên kiểm tra kỹ script trước khi chạy và ưu tiên quy trình cài đặt đã được tổ chức phê duyệt.

## 6.5. Các lệnh Helm cơ bản

### Thêm chart repository

```bash
helm repo add <repo-name> <repo-url>
```

Ví dụ:

```bash
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
```

### Cập nhật danh sách chart

```bash
helm repo update
```

### Tìm chart trong repo

```bash
helm search repo ingress-nginx
```

### Xem values mặc định của chart

```bash
helm show values ingress-nginx/ingress-nginx
```

### Cài đặt hoặc nâng cấp release

```bash
helm upgrade --install <release-name> <chart-name> \
  --namespace <namespace> \
  --create-namespace
```

`upgrade --install` có ý nghĩa:

- Nếu release chưa tồn tại, Helm sẽ cài mới.
- Nếu release đã tồn tại, Helm sẽ nâng cấp release đó.

Đây là cách dùng phổ biến trong thực tế vì chạy lại lệnh nhiều lần vẫn an toàn hơn so với chỉ dùng `helm install`.

### Xem danh sách release

```bash
helm list -A
```

### Xem trạng thái release

```bash
helm status <release-name> -n <namespace>
```

### Gỡ release

```bash
helm uninstall <release-name> -n <namespace>
```

## 7. Service type LoadBalancer trong môi trường on-premise

## 7.1. Nhắc lại Service từ Buổi 04

Ở Buổi 04,  đã học:

- `ClusterIP`: expose Service bên trong cluster.
- `NodePort`: expose Service qua một port trên mỗi node.
- `Headless`: không cấp ClusterIP, thường dùng cho stable DNS identity.
- `ExternalName`: ánh xạ Service sang DNS name bên ngoài.

Buổi này mở khóa thêm `LoadBalancer`, nhưng chỉ trong ngữ cảnh cần thiết để chạy MetalLB và Ingress Controller trên on-premise.

## 7.2. Service type LoadBalancer là gì?

Service type `LoadBalancer` là cách Kubernetes yêu cầu hạ tầng bên ngoài cấp một địa chỉ IP hoặc load balancer để đưa Service ra ngoài cluster.

Trên các cloud như AWS, Azure, GCP, Service type `LoadBalancer` thường cần cloud provider integration. Khi tạo Service type `LoadBalancer`, cloud-controller-manager hoặc cloud-specific controller sẽ tương tác với cloud provider để tạo load balancer tương ứng.

Ví dụ trong cloud:

```text
Kubernetes Service type LoadBalancer
          |
          v
Cloud Controller / Cloud LB Controller
          |
          v
AWS NLB / Azure Load Balancer / GCP Load Balancer
```

Trong môi trường kubeadm on-premise, nếu không có thành phần cấp IP, Service type `LoadBalancer` thường sẽ bị:

```text
EXTERNAL-IP: <pending>
```

Điều này không có nghĩa cluster bị lỗi. Nó chỉ có nghĩa là Kubernetes chưa có thành phần nào đứng ra cấp external IP cho Service.

## 7.3. MetalLB giải quyết vấn đề gì?

MetalLB là một load-balancer implementation cho Kubernetes bare-metal/on-premise.

Trong bài lab này, MetalLB sẽ làm nhiệm vụ:

- Theo dõi các Service type `LoadBalancer`.
- Cấp IP từ một pool đã cấu hình sẵn.
- Quảng bá IP đó ra mạng bên ngoài.
- Cho phép client trong cùng mạng truy cập Service qua IP đó.

Với mô hình lab Layer 2, MetalLB hoạt động theo hướng đơn giản:

```text
Client trong mạng LAN
      |
      | ARP hỏi: Ai đang giữ IP 10.10.10.240?
      v
MetalLB Speaker trên một node trả lời
      |
      v
Traffic đi vào node đó
      |
      v
kube-proxy chuyển traffic đến Service/Pod phù hợp
```

## 7.4. MetalLB gồm những thành phần nào?

### Controller

MetalLB Controller là thành phần quản lý cấp phát IP.

Nhiệm vụ chính:

- Theo dõi Service type `LoadBalancer`.
- Chọn IP từ `IPAddressPool`.
- Gán IP đó vào `.status.loadBalancer.ingress`.
- Quản lý logic cấp phát IP.

Controller thường chạy dạng Deployment.

### Speaker

MetalLB Speaker là thành phần chạy trên node và quảng bá IP ra mạng.

Nhiệm vụ chính:

- Quảng bá IP Service ra bên ngoài.
- Ở Layer 2 mode, Speaker trả lời ARP/NDP.
- Ở BGP mode, Speaker thiết lập BGP session với router.

Trong bài này chỉ dùng Layer 2 mode.

Speaker thường chạy dạng DaemonSet để có mặt trên các node.

## 7.5. Layer 2 mode là gì?

Layer 2 mode là cách triển khai đơn giản nhất của MetalLB.

Đặc điểm:

- Không cần router hỗ trợ BGP.
- Không cần cấu hình dynamic routing.
- Chỉ cần các node và client nằm trong cùng Layer 2 network.
- MetalLB dùng ARP để làm cho một IP trong pool trỏ về một node.
- Tại một thời điểm, một IP thường được một node “đại diện” trả lời.

Phù hợp cho:

- Lab.
- On-premise nhỏ.
- Môi trường không có BGP.
- Môi trường đào tạo.

Hạn chế:

- Không phân tán traffic theo kiểu ECMP như BGP.
- Một node có thể trở thành điểm nhận traffic cho một external IP cụ thể.
- Cần chọn IP pool cẩn thận để tránh trùng IP.
- Phụ thuộc vào cùng Layer 2 network.

## 8. Cài MetalLB bằng Helm

## 8.1. Chuẩn bị namespace cho MetalLB

MetalLB Speaker cần quyền mạng cao hơn bình thường. Vì vậy, namespace `metallb-system` nên được gán Pod Security label ở mức `privileged`.

Tạo namespace:

```bash
kubectl create namespace metallb-system
```

Gán label:

```bash
kubectl label namespace metallb-system \
  pod-security.kubernetes.io/enforce=privileged \
  pod-security.kubernetes.io/audit=privileged \
  pod-security.kubernetes.io/warn=privileged \
  --overwrite
```

Kiểm tra namespace:

```bash
kubectl get namespace metallb-system --show-labels
```

Kết quả kỳ vọng có các label:

```text
pod-security.kubernetes.io/enforce=privileged
pod-security.kubernetes.io/audit=privileged
pod-security.kubernetes.io/warn=privileged
```

## 8.2. Thêm Helm repository của MetalLB

```bash
helm repo add metallb https://metallb.github.io/metallb
helm repo update
```

Kiểm tra chart:

```bash
helm search repo metallb
```

## 8.3. Cài MetalLB

```bash
helm upgrade --install metallb metallb/metallb \
  --namespace metallb-system \
  --wait
```

Giải thích:

```text
helm upgrade --install
```

Cài mới nếu release chưa tồn tại, nâng cấp nếu release đã tồn tại.

```text
metallb
```

Tên release.

```text
metallb/metallb
```

Chart cần cài, nằm trong repo `metallb`.

```text
--namespace metallb-system
```

Cài vào namespace `metallb-system`.

```text
--wait
```

Yêu cầu Helm chờ đến khi các resource chính sẵn sàng hoặc timeout.

## 8.4. Kiểm tra MetalLB

```bash
kubectl get all -n metallb-system
```

Kết quả kỳ vọng:

```text
NAME                                      READY   STATUS    RESTARTS   AGE
pod/metallb-controller-xxxxxxxxxx-xxxxx   1/1     Running   0          1m
pod/metallb-speaker-xxxxx                 4/4     Running   0          1m
pod/metallb-speaker-yyyyy                 4/4     Running   0          1m
pod/metallb-speaker-zzzzz                 4/4     Running   0          1m

NAME                         TYPE        CLUSTER-IP      EXTERNAL-IP   PORT(S)
service/metallb-webhook-service ClusterIP ...
```

Kiểm tra release Helm:

```bash
helm list -n metallb-system
```

Xem trạng thái release:

```bash
helm status metallb -n metallb-system
```

## 8.5. Cấu hình IPAddressPool và L2Advertisement

Sau khi cài MetalLB, chỉ cài component thôi là chưa đủ. MetalLB sẽ chưa cấp IP cho Service nếu chưa có cấu hình IP pool.

Tạo file:

```bash
cat <<'EOF' > metallb-l2-pool.yaml
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: lab-pool
  namespace: metallb-system
spec:
  addresses:
    - 10.10.10.240-10.10.10.250
---
apiVersion: metallb.io/v1beta1
kind: L2Advertisement
metadata:
  name: lab-l2-advertisement
  namespace: metallb-system
spec:
  ipAddressPools:
    - lab-pool
EOF
```

Apply manifest:

```bash
kubectl apply -f metallb-l2-pool.yaml
```

Kiểm tra:

```bash
kubectl get ipaddresspool -n metallb-system
kubectl get l2advertisement -n metallb-system
```

## 8.6. Giải thích manifest MetalLB

```yaml
apiVersion: metallb.io/v1beta1
```

Sử dụng API group của MetalLB. Đây không phải API object mặc định của Kubernetes core, mà là Custom Resource Definition do MetalLB cài vào cluster.

```yaml
kind: IPAddressPool
```

Khai báo một pool địa chỉ IP để MetalLB dùng cấp cho Service type `LoadBalancer`.

```yaml
metadata:
  name: lab-pool
  namespace: metallb-system
```

Tạo object tên `lab-pool` trong namespace `metallb-system`.

```yaml
spec:
  addresses:
    - 10.10.10.240-10.10.10.250
```

Dải IP MetalLB được phép cấp. Trong lab này, các Service type `LoadBalancer` có thể nhận một IP trong khoảng `10.10.10.240` đến `10.10.10.250`.

```yaml
kind: L2Advertisement
```

Khai báo cách MetalLB quảng bá IP ra mạng ở Layer 2 mode.

```yaml
spec:
  ipAddressPools:
    - lab-pool
```

Chỉ định rằng các IP trong pool `lab-pool` sẽ được advertise bằng Layer 2.

## 8.7. Test nhanh MetalLB bằng Service LoadBalancer

Trước khi cài Ingress NGINX Controller, có thể test MetalLB bằng một ứng dụng nginx đơn giản.

Tạo namespace:

```bash
kubectl create namespace metallb-test
```

Tạo Deployment:

```bash
kubectl create deployment nginx-test \
  --image=nginx:1.27 \
  --replicas=2 \
  -n metallb-test
```

Expose bằng Service type `LoadBalancer`:

```bash
kubectl expose deployment nginx-test \
  --port=80 \
  --target-port=80 \
  --type=LoadBalancer \
  -n metallb-test
```

Kiểm tra Service:

```bash
kubectl get svc -n metallb-test
```

Kết quả kỳ vọng:

```text
NAME         TYPE           CLUSTER-IP      EXTERNAL-IP     PORT(S)
nginx-test   LoadBalancer   10.96.x.x       10.10.10.240    80:xxxxx/TCP
```

Test từ máy client hoặc từ node:

```bash
curl http://10.10.10.240
```

Kết quả kỳ vọng:

```html
Welcome to nginx!
```

Dọn test:

```bash
kubectl delete namespace metallb-test
```

Nếu `EXTERNAL-IP` vẫn là `<pending>`, cần kiểm tra:

```bash
kubectl get ipaddresspool -n metallb-system
kubectl get l2advertisement -n metallb-system
kubectl logs -n metallb-system deploy/metallb-controller
kubectl get pods -n metallb-system -o wide
```

## 9. Ingress

## 9.1. Ingress là gì?

Ingress là Kubernetes API object dùng để quản lý truy cập HTTP và HTTPS từ bên ngoài cluster vào các Service bên trong cluster.

Ingress cho phép định nghĩa các rule theo:

- Hostname.
- Path.
- Backend Service.
- TLS.

Ví dụ:

```text
http://web.lab.local/
      |
      v
Ingress rule host: web.lab.local
      |
      v
Service: lesson-06-web-svc
      |
      v
Pod ứng dụng web
```

Ingress phù hợp cho ứng dụng web vì nó hiểu các khái niệm HTTP/HTTPS như:

- Host header.
- URL path.
- TLS termination.
- Virtual hosting.
- Reverse proxy.

## 9.2. Ingress khác gì Service?

Service chịu trách nhiệm expose một nhóm Pod thông qua một endpoint ổn định.

Ingress chịu trách nhiệm routing HTTP/HTTPS từ bên ngoài vào Service.

So sánh đơn giản:

```text
Service:
  "Ứng dụng này nằm ở đâu trong cluster?"

Ingress:
  "Request HTTP/HTTPS với domain/path này nên đi đến Service nào?"
```

Service hoạt động ở mức L3/L4 nhiều hơn.

Ingress hoạt động ở mức L7 HTTP/HTTPS.

## 9.3. Vì sao chỉ tạo Ingress object là chưa đủ?

Ingress object chỉ là một cấu hình mong muốn.

Để cấu hình đó có tác dụng, cluster phải có một Ingress Controller đang chạy.

Nếu chỉ tạo Ingress mà không có Ingress Controller:

- Không có thành phần nào nhận traffic HTTP/HTTPS từ bên ngoài.
- Không có thành phần nào đọc Ingress rule và cấu hình reverse proxy.
- Ứng dụng sẽ không thật sự được publish ra ngoài.

Vì vậy cần phân biệt:

```text
Ingress:
  API object chứa rule routing.

Ingress Controller:
  Thành phần thực thi rule đó.
```

Trong bài này, Ingress Controller được sử dụng là Ingress NGINX Controller.

## 9.4. Ingress NGINX Controller là gì?

Ingress NGINX Controller là một Ingress Controller dùng NGINX làm reverse proxy/load balancer cho HTTP/HTTPS traffic.

Nó làm các việc chính:

- Watch các Ingress object trong cluster.
- Watch các Service và EndpointSlice liên quan.
- Sinh cấu hình NGINX tương ứng.
- Reload/cập nhật NGINX khi rule thay đổi.
- Nhận traffic từ bên ngoài.
- Chuyển request vào Service backend phù hợp.

## 9.5. Vai trò của IngressClass

`IngressClass` cho Kubernetes biết Ingress object nên được xử lý bởi controller nào.

Ví dụ:

```yaml
spec:
  ingressClassName: nginx
```

Nghĩa là Ingress này sẽ được xử lý bởi Ingress Controller có class `nginx`.

Trong môi trường có nhiều Ingress Controller, `ingressClassName` rất quan trọng để tránh nhầm controller.

Trong bài lab, ta sẽ dùng class:

```text
nginx
```

## 10. Cài Ingress NGINX Controller bằng Helm

## 10.1. Thêm Helm repository

```bash
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo update
```

Kiểm tra chart:

```bash
helm search repo ingress-nginx
```

## 10.2. Xem values mặc định

```bash
helm show values ingress-nginx/ingress-nginx > ingress-nginx-default-values.yaml
```

Có thể xem nhanh các giá trị liên quan đến Service:

```bash
grep -n "type:" ingress-nginx-default-values.yaml | head
```

Trong lab này, ta sẽ cài Ingress NGINX Controller với Service type `LoadBalancer` để MetalLB cấp IP.

## 10.3. Cài Ingress NGINX Controller

```bash
helm upgrade --install ingress-nginx ingress-nginx/ingress-nginx \
  --namespace ingress-nginx \
  --create-namespace \
  --set controller.service.type=LoadBalancer \
  --set controller.ingressClassResource.name=nginx \
  --set controller.ingressClass=nginx \
  --set controller.ingressClassResource.default=true \
  --wait
```

Giải thích:

```text
helm upgrade --install ingress-nginx ingress-nginx/ingress-nginx
```

Cài hoặc nâng cấp release tên `ingress-nginx` từ chart `ingress-nginx/ingress-nginx`.

```text
--namespace ingress-nginx
```

Cài vào namespace `ingress-nginx`.

```text
--create-namespace
```

Tạo namespace nếu chưa tồn tại.

```text
--set controller.service.type=LoadBalancer
```

Service của Ingress NGINX Controller sẽ là type `LoadBalancer`. Trên on-premise, IP sẽ do MetalLB cấp.

```text
--set controller.ingressClassResource.name=nginx
```

Tạo IngressClass tên `nginx`.

```text
--set controller.ingressClass=nginx
```

Controller xử lý Ingress class `nginx`.

```text
--set controller.ingressClassResource.default=true
```

Đặt class `nginx` làm default IngressClass. Trong lab, điều này giúp đơn giản hóa, nhưng trong production có nhiều controller thì cần cân nhắc kỹ.

```text
--wait
```

Chờ tài nguyên sẵn sàng.

## 10.4. Kiểm tra Ingress NGINX Controller

```bash
kubectl get pods -n ingress-nginx -o wide
```

Kết quả kỳ vọng:

```text
NAME                                        READY   STATUS    RESTARTS
ingress-nginx-controller-xxxxxxxxxx-xxxxx   1/1     Running   0
```

Kiểm tra Service:

```bash
kubectl get svc -n ingress-nginx
```

Kết quả kỳ vọng:

```text
NAME                                 TYPE           CLUSTER-IP      EXTERNAL-IP     PORT(S)
ingress-nginx-controller             LoadBalancer   10.96.x.x       10.10.10.240    80:xxxxx/TCP,443:xxxxx/TCP
ingress-nginx-controller-admission   ClusterIP      10.96.x.x       <none>          443/TCP
```

Lưu lại IP được cấp:

```bash
export INGRESS_IP=$(kubectl get svc ingress-nginx-controller \
  -n ingress-nginx \
  -o jsonpath='{.status.loadBalancer.ingress[0].ip}')

echo $INGRESS_IP
```

Ví dụ:

```text
10.10.10.240
```

Kiểm tra IngressClass:

```bash
kubectl get ingressclass
```

Kết quả kỳ vọng:

```text
NAME    CONTROLLER             PARAMETERS   AGE
nginx   k8s.io/ingress-nginx   <none>       1m
```

## 10.5. Kiểm tra log controller

```bash
kubectl logs -n ingress-nginx deploy/ingress-nginx-controller
```

Theo dõi realtime:

```bash
kubectl logs -n ingress-nginx deploy/ingress-nginx-controller -f
```

## 11. Lab 01 - Publish ứng dụng web bằng HTTP qua Ingress

## 11.1. Tạo namespace cho bài lab

```bash
kubectl create namespace lesson-06
```

## 11.2. Tạo ConfigMap chứa nội dung web

Từ Buổi 05,  đã biết ConfigMap có thể chứa file cấu hình hoặc nội dung text. Ở đây ta dùng ConfigMap để cung cấp file `index.html` cho nginx.

Tạo file:

```bash
cat <<'EOF' > web-configmap.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: lesson-06-web-content
  namespace: lesson-06
data:
  index.html: |
    <!DOCTYPE html>
    <html>
    <head>
      <title>Kubernetes Lesson 06</title>
    </head>
    <body>
      <h1>Hello from Kubernetes Ingress</h1>
      <p>This web application is exposed through Ingress NGINX Controller.</p>
      <p>Protocol: HTTP</p>
    </body>
    </html>
EOF
```

Apply:

```bash
kubectl apply -f web-configmap.yaml
```

## 11.3. Tạo Deployment chạy nginx

Tạo file:

```bash
cat <<'EOF' > web-deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: lesson-06-web
  namespace: lesson-06
  labels:
    app: lesson-06-web
spec:
  replicas: 2
  selector:
    matchLabels:
      app: lesson-06-web
  template:
    metadata:
      labels:
        app: lesson-06-web
    spec:
      containers:
        - name: nginx
          image: nginx:1.27
          ports:
            - containerPort: 80
          volumeMounts:
            - name: web-content
              mountPath: /usr/share/nginx/html/index.html
              subPath: index.html
      volumes:
        - name: web-content
          configMap:
            name: lesson-06-web-content
EOF
```

Apply:

```bash
kubectl apply -f web-deployment.yaml
```

Kiểm tra Pod:

```bash
kubectl get pods -n lesson-06 -o wide
```

## 11.4. Giải thích Deployment manifest

```yaml
apiVersion: apps/v1
kind: Deployment
```

Tạo Deployment. Kiến thức này đã học ở Buổi 03.

```yaml
metadata:
  name: lesson-06-web
  namespace: lesson-06
```

Deployment được tạo trong namespace `lesson-06`.

```yaml
labels:
  app: lesson-06-web
```

Label dùng để nhận diện workload và liên kết với Service.

```yaml
replicas: 2
```

Chạy 2 Pod nginx để minh họa backend có nhiều replica.

```yaml
selector:
  matchLabels:
    app: lesson-06-web
```

Deployment quản lý các Pod có label `app=lesson-06-web`.

```yaml
template:
  metadata:
    labels:
      app: lesson-06-web
```

Pod được tạo ra cũng có label `app=lesson-06-web`.

```yaml
containers:
  - name: nginx
    image: nginx:1.27
```

Container sử dụng image nginx.

```yaml
ports:
  - containerPort: 80
```

Container nginx lắng nghe port 80.

```yaml
volumeMounts:
  - name: web-content
    mountPath: /usr/share/nginx/html/index.html
    subPath: index.html
```

Mount file `index.html` từ ConfigMap vào đúng vị trí nginx dùng để phục vụ web.

```yaml
volumes:
  - name: web-content
    configMap:
      name: lesson-06-web-content
```

Khai báo volume lấy dữ liệu từ ConfigMap `lesson-06-web-content`.

## 11.5. Tạo Service ClusterIP cho ứng dụng

Ingress không route trực tiếp vào Pod. Ingress route vào Service.

Tạo file:

```bash
cat <<'EOF' > web-service.yaml
apiVersion: v1
kind: Service
metadata:
  name: lesson-06-web-svc
  namespace: lesson-06
spec:
  type: ClusterIP
  selector:
    app: lesson-06-web
  ports:
    - name: http
      port: 80
      targetPort: 80
EOF
```

Apply:

```bash
kubectl apply -f web-service.yaml
```

Kiểm tra Service:

```bash
kubectl get svc -n lesson-06
```

Kiểm tra EndpointSlice:

```bash
kubectl get endpointslice -n lesson-06
```

## 11.6. Giải thích Service manifest

```yaml
kind: Service
```

Tạo Service để expose nhóm Pod.

```yaml
metadata:
  name: lesson-06-web-svc
```

Tên Service. Ingress sẽ trỏ đến tên này.

```yaml
type: ClusterIP
```

Service chỉ expose bên trong cluster. Ingress Controller nằm trong cluster nên có thể truy cập Service này.

```yaml
selector:
  app: lesson-06-web
```

Service chọn các Pod có label `app=lesson-06-web`.

```yaml
ports:
  - name: http
    port: 80
    targetPort: 80
```

Service nhận traffic ở port 80 và chuyển đến port 80 của Pod.

## 11.7. Tạo Ingress HTTP

Trong lab này dùng domain giả lập:

```text
web.lab.local
```

Tạo file:

```bash
cat <<'EOF' > web-http-ingress.yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: lesson-06-web-http
  namespace: lesson-06
spec:
  ingressClassName: nginx
  rules:
    - host: web.lab.local
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: lesson-06-web-svc
                port:
                  number: 80
EOF
```

Apply:

```bash
kubectl apply -f web-http-ingress.yaml
```

Kiểm tra Ingress:

```bash
kubectl get ingress -n lesson-06
```

Kết quả kỳ vọng:

```text
NAME                 CLASS   HOSTS           ADDRESS        PORTS
lesson-06-web-http   nginx   web.lab.local   10.10.10.240   80
```

## 11.8. Giải thích Ingress HTTP manifest

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
```

Tạo Ingress object thuộc API group `networking.k8s.io`.

```yaml
metadata:
  name: lesson-06-web-http
  namespace: lesson-06
```

Ingress nằm cùng namespace với Service backend.

```yaml
spec:
  ingressClassName: nginx
```

Chỉ định Ingress này được xử lý bởi Ingress Controller class `nginx`.

```yaml
rules:
  - host: web.lab.local
```

Rule áp dụng cho HTTP request có Host header là `web.lab.local`.

```yaml
http:
  paths:
    - path: /
      pathType: Prefix
```

Mọi request có path bắt đầu bằng `/` sẽ match rule này.

```yaml
backend:
  service:
    name: lesson-06-web-svc
    port:
      number: 80
```

Request sau khi match rule sẽ được chuyển đến Service `lesson-06-web-svc` port 80.

## 11.9. Cấu hình phân giải tên miền cho lab

Vì `web.lab.local` là domain lab, máy client cần phân giải domain này về IP của Ingress Controller.

Lấy IP của Ingress NGINX Controller:

```bash
kubectl get svc ingress-nginx-controller -n ingress-nginx
```

Ví dụ:

```text
EXTERNAL-IP = 10.10.10.240
```

### Cách 1: sửa file hosts trên máy client Linux/macOS

```bash
sudo sh -c 'echo "10.10.10.240 web.lab.local" >> /etc/hosts'
```

### Cách 2: sửa file hosts trên Windows

Mở Notepad bằng quyền Administrator và sửa file:

```text
C:\Windows\System32\drivers\etc\hosts
```

Thêm dòng:

```text
10.10.10.240 web.lab.local
```

### Cách 3: dùng curl --resolve không cần sửa hosts

```bash
curl --resolve web.lab.local:80:10.10.10.240 http://web.lab.local/
```

## 11.10. Test HTTP

Từ máy client:

```bash
curl http://web.lab.local/
```

Hoặc:

```bash
curl --resolve web.lab.local:80:10.10.10.240 http://web.lab.local/
```

Kết quả kỳ vọng:

```html
<h1>Hello from Kubernetes Ingress</h1>
<p>This web application is exposed through Ingress NGINX Controller.</p>
<p>Protocol: HTTP</p>
```

Kiểm tra log Ingress Controller:

```bash
kubectl logs -n ingress-nginx deploy/ingress-nginx-controller --tail=50
```

## 12. Lab 02 - Publish ứng dụng web bằng HTTPS qua Ingress

## 12.1. HTTPS trong Ingress hoạt động như thế nào?

Khi dùng HTTPS với Ingress, TLS thường được terminate tại Ingress Controller.

Luồng traffic:

```text
Client Browser
      |
      | HTTPS
      v
Ingress NGINX Controller
      |
      | HTTP nội bộ trong cluster
      v
Service ClusterIP
      |
      v
Pod ứng dụng
```

Điều này nghĩa là:

- Client kết nối HTTPS đến Ingress Controller.
- Ingress Controller dùng certificate trong Kubernetes Secret để bắt tay TLS.
- Sau đó Ingress Controller chuyển request vào Service backend.
- Traffic từ Ingress Controller đến Pod thường là HTTP nội bộ, trừ khi cấu hình backend HTTPS riêng.

Trong bài này chỉ làm TLS termination tại Ingress Controller.

## 12.2. Tạo self-signed certificate cho domain lab

Trong môi trường production, certificate nên được cấp bởi CA tin cậy như Let's Encrypt hoặc CA nội bộ doanh nghiệp.

Trong lab, ta dùng self-signed certificate.

Tạo certificate:

```bash
openssl req -x509 -nodes -days 365 \
  -newkey rsa:2048 \
  -keyout web.lab.local.key \
  -out web.lab.local.crt \
  -subj "/CN=web.lab.local/O=Kubernetes Lab" \
  -addext "subjectAltName=DNS:web.lab.local"
```

Kiểm tra file:

```bash
ls -l web.lab.local.*
```

Kết quả kỳ vọng:

```text
web.lab.local.crt
web.lab.local.key
```

## 12.3. Tạo TLS Secret

Tạo Secret trong namespace `lesson-06`:

```bash
kubectl create secret tls web-lab-local-tls \
  --cert=web.lab.local.crt \
  --key=web.lab.local.key \
  -n lesson-06
```

Kiểm tra Secret:

```bash
kubectl get secret web-lab-local-tls -n lesson-06
```

Xem loại Secret:

```bash
kubectl get secret web-lab-local-tls -n lesson-06 -o yaml
```

Kết quả sẽ có:

```yaml
type: kubernetes.io/tls
```

## 12.4. Cập nhật nội dung web để hiển thị HTTPS

Cập nhật ConfigMap:

```bash
cat <<'EOF' > web-configmap-https.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: lesson-06-web-content
  namespace: lesson-06
data:
  index.html: |
    <!DOCTYPE html>
    <html>
    <head>
      <title>Kubernetes Lesson 06 HTTPS</title>
    </head>
    <body>
      <h1>Hello from Kubernetes HTTPS Ingress</h1>
      <p>This web application is exposed through Ingress NGINX Controller.</p>
      <p>Protocol: HTTPS</p>
      <p>TLS is terminated at the Ingress Controller.</p>
    </body>
    </html>
EOF
```

Apply:

```bash
kubectl apply -f web-configmap-https.yaml
```

Vì ConfigMap được mount dạng file, đôi khi Pod cần được restart để nội dung cập nhật rõ ràng trong lab.

Restart Deployment:

```bash
kubectl rollout restart deployment lesson-06-web -n lesson-06
kubectl rollout status deployment lesson-06-web -n lesson-06
```

## 12.5. Tạo Ingress HTTPS

Có thể thay Ingress HTTP bằng Ingress có TLS.

Tạo file:

```bash
cat <<'EOF' > web-https-ingress.yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: lesson-06-web-https
  namespace: lesson-06
spec:
  ingressClassName: nginx
  tls:
    - hosts:
        - web.lab.local
      secretName: web-lab-local-tls
  rules:
    - host: web.lab.local
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: lesson-06-web-svc
                port:
                  number: 80
EOF
```

Apply:

```bash
kubectl apply -f web-https-ingress.yaml
```

Có thể xóa Ingress HTTP cũ để tránh nhiễu:

```bash
kubectl delete ingress lesson-06-web-http -n lesson-06
```

Kiểm tra:

```bash
kubectl get ingress -n lesson-06
```

Kết quả kỳ vọng:

```text
NAME                  CLASS   HOSTS           ADDRESS        PORTS
lesson-06-web-https   nginx   web.lab.local   10.10.10.240   80, 443
```

## 12.6. Giải thích Ingress HTTPS manifest

```yaml
tls:
  - hosts:
      - web.lab.local
    secretName: web-lab-local-tls
```

Khai báo TLS cho host `web.lab.local`.

```yaml
secretName: web-lab-local-tls
```

Ingress Controller sẽ lấy certificate và private key từ Secret này.

Secret phải:

- Nằm cùng namespace với Ingress.
- Có type `kubernetes.io/tls`.
- Chứa key `tls.crt`.
- Chứa key `tls.key`.

```yaml
rules:
  - host: web.lab.local
```

Host trong `rules` phải khớp với host trong `tls.hosts` để HTTPS hoạt động đúng.

```yaml
backend:
  service:
    name: lesson-06-web-svc
    port:
      number: 80
```

Dù bên ngoài dùng HTTPS, backend Service vẫn dùng port 80. Đây là mô hình TLS termination tại Ingress Controller.

## 12.7. Test HTTPS

Vì certificate là self-signed, dùng `curl -k` để bỏ qua kiểm tra CA:

```bash
curl -k https://web.lab.local/
```

Hoặc không cần sửa hosts:

```bash
curl -k --resolve web.lab.local:443:10.10.10.240 https://web.lab.local/
```

Kết quả kỳ vọng:

```html
<h1>Hello from Kubernetes HTTPS Ingress</h1>
<p>This web application is exposed through Ingress NGINX Controller.</p>
<p>Protocol: HTTPS</p>
<p>TLS is terminated at the Ingress Controller.</p>
```

Kiểm tra certificate:

```bash
openssl s_client -connect web.lab.local:443 -servername web.lab.local
```

Hoặc:

```bash
openssl s_client -connect 10.10.10.240:443 -servername web.lab.local
```

## 12.8. Kiểm tra redirect HTTP sang HTTPS

Ingress NGINX thường có hành vi redirect HTTP sang HTTPS khi Ingress có cấu hình TLS.

Test:

```bash
curl -I http://web.lab.local/
```

Có thể thấy response dạng:

```text
HTTP/1.1 308 Permanent Redirect
Location: https://web.lab.local/
```

Nếu muốn tắt redirect trong lab, có thể thêm annotation:

```yaml
metadata:
  annotations:
    nginx.ingress.kubernetes.io/ssl-redirect: "false"
```

Ví dụ:

```bash
cat <<'EOF' > web-https-no-redirect-ingress.yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: lesson-06-web-https
  namespace: lesson-06
  annotations:
    nginx.ingress.kubernetes.io/ssl-redirect: "false"
spec:
  ingressClassName: nginx
  tls:
    - hosts:
        - web.lab.local
      secretName: web-lab-local-tls
  rules:
    - host: web.lab.local
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: lesson-06-web-svc
                port:
                  number: 80
EOF
```

Apply:

```bash
kubectl apply -f web-https-no-redirect-ingress.yaml
```

Test lại:

```bash
curl -I http://web.lab.local/
curl -k -I https://web.lab.local/
```

## 13. Lab 03 - Publish hai ứng dụng web bằng cùng một IP Ingress

## 13.1. Mục tiêu

Lab này giúp  thấy giá trị thật sự của Ingress:

- Nhiều ứng dụng web.
- Dùng chung một external IP.
- Phân biệt bằng hostname.
- Vẫn dùng port chuẩn 80/443.

Ví dụ:

```text
app1.lab.local -> lesson-06-app1-svc
app2.lab.local -> lesson-06-app2-svc
```

Cả hai domain cùng trỏ về:

```text
10.10.10.240
```

## 13.2. Tạo ứng dụng app1

```bash
cat <<'EOF' > app1.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: app1-content
  namespace: lesson-06
data:
  index.html: |
    <h1>Application 1</h1>
    <p>This is app1 served through Kubernetes Ingress.</p>
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: app1
  namespace: lesson-06
spec:
  replicas: 2
  selector:
    matchLabels:
      app: app1
  template:
    metadata:
      labels:
        app: app1
    spec:
      containers:
        - name: nginx
          image: nginx:1.27
          ports:
            - containerPort: 80
          volumeMounts:
            - name: content
              mountPath: /usr/share/nginx/html/index.html
              subPath: index.html
      volumes:
        - name: content
          configMap:
            name: app1-content
---
apiVersion: v1
kind: Service
metadata:
  name: app1-svc
  namespace: lesson-06
spec:
  type: ClusterIP
  selector:
    app: app1
  ports:
    - name: http
      port: 80
      targetPort: 80
EOF
```

Apply:

```bash
kubectl apply -f app1.yaml
```

## 13.3. Tạo ứng dụng app2

```bash
cat <<'EOF' > app2.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: app2-content
  namespace: lesson-06
data:
  index.html: |
    <h1>Application 2</h1>
    <p>This is app2 served through Kubernetes Ingress.</p>
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: app2
  namespace: lesson-06
spec:
  replicas: 2
  selector:
    matchLabels:
      app: app2
  template:
    metadata:
      labels:
        app: app2
    spec:
      containers:
        - name: nginx
          image: nginx:1.27
          ports:
            - containerPort: 80
          volumeMounts:
            - name: content
              mountPath: /usr/share/nginx/html/index.html
              subPath: index.html
      volumes:
        - name: content
          configMap:
            name: app2-content
---
apiVersion: v1
kind: Service
metadata:
  name: app2-svc
  namespace: lesson-06
spec:
  type: ClusterIP
  selector:
    app: app2
  ports:
    - name: http
      port: 80
      targetPort: 80
EOF
```

Apply:

```bash
kubectl apply -f app2.yaml
```

## 13.4. Tạo Ingress host-based routing

```bash
cat <<'EOF' > multi-host-ingress.yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: multi-host-ingress
  namespace: lesson-06
spec:
  ingressClassName: nginx
  rules:
    - host: app1.lab.local
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: app1-svc
                port:
                  number: 80
    - host: app2.lab.local
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: app2-svc
                port:
                  number: 80
EOF
```

Apply:

```bash
kubectl apply -f multi-host-ingress.yaml
```

Kiểm tra:

```bash
kubectl get ingress -n lesson-06
```

## 13.5. Cấu hình hosts

Nếu dùng `/etc/hosts`:

```bash
sudo sh -c 'echo "10.10.10.240 app1.lab.local app2.lab.local" >> /etc/hosts'
```

Hoặc test bằng `curl --resolve`:

```bash
curl --resolve app1.lab.local:80:10.10.10.240 http://app1.lab.local/
curl --resolve app2.lab.local:80:10.10.10.240 http://app2.lab.local/
```

Kết quả kỳ vọng:

```text
Application 1
```

và:

```text
Application 2
```

## 13.6. Ý nghĩa của lab này

Cùng một IP `10.10.10.240`, cùng port 80, nhưng Ingress Controller route đến các backend khác nhau dựa trên HTTP Host header.

```text
Host: app1.lab.local
  -> app1-svc

Host: app2.lab.local
  -> app2-svc
```

Đây là lý do Ingress rất phù hợp để publish nhiều ứng dụng web trong cùng một cluster.

## Phần bổ sung chuyên sâu - Ingress HTTPS/TLS, pathType và path-based routing

Phần này bổ sung thêm cho Buổi 06 để học viên hiểu kỹ hơn ba nhóm vấn đề thường gặp khi đưa ứng dụng web ra ngoài Kubernetes:

- Ingress dùng HTTPS, SSL/TLS và TLS Secret.
- Routing theo `path` với `pathType: Exact`, `Prefix`, `ImplementationSpecific`.
- Demo nhiều backend dùng chung một domain/IP nhưng tách traffic theo đường dẫn như `/`, `/api`, `/admin`.

Nội dung này nên được dạy sau khi học viên đã hoàn tất các phần:

- Cài Helm.
- Cài MetalLB.
- Cài Ingress NGINX Controller.
- Tạo được Ingress HTTP cơ bản.
- Biết Service `ClusterIP` dùng để đứng trước Pod backend.

### A. Hiểu đúng về HTTPS, SSL và TLS trong Ingress

Trong thực tế, nhiều người vẫn nói “cài SSL cho website”, “SSL certificate”, hoặc “Ingress SSL”. Về mặt kỹ thuật hiện đại, giao thức đang dùng là TLS, không còn là SSL cũ.

Trong Kubernetes Ingress, trường cấu hình chính thức là:

```yaml
spec:
  tls:
```

Vì vậy khi làm lab hoặc triển khai thực tế, nên hiểu như sau:

```text
Cách gọi phổ biến:
  SSL certificate
  SSL for website
  HTTPS SSL

Ý nghĩa kỹ thuật hiện đại:
  TLS certificate
  HTTPS sử dụng TLS
  TLS termination tại Ingress Controller
```

Trong bài này, ta vẫn có thể nói “SSL/TLS” để học viên dễ liên hệ với cách gọi ngoài thực tế, nhưng khi đọc YAML thì cần nhớ Kubernetes dùng khái niệm `tls`.

### B. HTTPS qua Ingress hoạt động như thế nào?

Khi một client truy cập:

```text
https://web.lab.local/
```

Luồng xử lý trong mô hình lab là:

```text
Client / Browser
      |
      | HTTPS TCP/443
      | TLS handshake
      v
MetalLB External IP
10.10.10.240
      |
      v
Service LoadBalancer
ingress-nginx-controller
      |
      v
Ingress NGINX Controller
      |
      | Đọc TLS Secret
      | Terminate TLS tại đây
      |
      | HTTP nội bộ
      v
Service ClusterIP backend
      |
      v
Pod ứng dụng
```

Điểm quan trọng:

- Certificate không nằm trong Pod ứng dụng.
- Certificate nằm trong Kubernetes Secret.
- Secret phải nằm cùng namespace với Ingress object.
- Ingress NGINX Controller đọc Secret đó để phục vụ HTTPS.
- Client nói chuyện HTTPS với Ingress Controller.
- Ingress Controller có thể nói chuyện HTTP với backend Service.
- Đây gọi là TLS termination tại Ingress Controller.

Mô hình này rất phổ biến vì:

- Ứng dụng backend không cần tự quản lý certificate.
- Việc gia hạn/thay certificate được gom ở tầng Ingress.
- Nhiều ứng dụng web có thể dùng chung Ingress Controller.
- Dễ áp dụng policy redirect HTTP sang HTTPS.

### C. TLS Secret trong Kubernetes

TLS Secret là Secret có type:

```yaml
type: kubernetes.io/tls
```

Bên trong Secret có hai key dữ liệu bắt buộc:

```text
tls.crt
tls.key
```

Trong đó:

- `tls.crt`: certificate public.
- `tls.key`: private key tương ứng với certificate.

Tạo TLS Secret bằng `kubectl`:

```bash
kubectl create secret tls web-lab-local-tls \
  --cert=web.lab.local.crt \
  --key=web.lab.local.key \
  -n lesson-06
```

Kiểm tra:

```bash
kubectl get secret web-lab-local-tls -n lesson-06
kubectl get secret web-lab-local-tls -n lesson-06 -o yaml
```

Kết quả cần thấy:

```yaml
type: kubernetes.io/tls
```

Lưu ý quan trọng:

```text
Ingress namespace: lesson-06
TLS Secret namespace: lesson-06
```

Nếu Ingress ở namespace `lesson-06` nhưng Secret lại nằm ở namespace `default`, Ingress NGINX sẽ không dùng được Secret đó.

### D. Certificate phải khớp domain

Khi tạo certificate cho HTTPS, certificate phải chứa domain mà client truy cập.

Ví dụ client truy cập:

```text
https://web.lab.local/
```

Certificate nên có SAN:

```text
DNS:web.lab.local
```

Trong lab, tạo self-signed certificate:

```bash
openssl req -x509 -nodes -days 365 \
  -newkey rsa:2048 \
  -keyout web.lab.local.key \
  -out web.lab.local.crt \
  -subj "/CN=web.lab.local/O=Kubernetes Lab" \
  -addext "subjectAltName=DNS:web.lab.local"
```

Kiểm tra certificate:

```bash
openssl x509 -in web.lab.local.crt -noout -text | grep -A2 "Subject Alternative Name"
```

Kết quả kỳ vọng:

```text
DNS:web.lab.local
```

Nếu certificate không có SAN đúng domain, browser hoặc `curl` sẽ báo lỗi certificate name mismatch.

### E. Ingress HTTPS manifest đầy đủ

Ví dụ Ingress HTTPS cơ bản:

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: lesson-06-web-https
  namespace: lesson-06
spec:
  ingressClassName: nginx
  tls:
    - hosts:
        - web.lab.local
      secretName: web-lab-local-tls
  rules:
    - host: web.lab.local
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: lesson-06-web-svc
                port:
                  number: 80
```

Giải thích nhanh:

```yaml
ingressClassName: nginx
```

Ingress này được xử lý bởi Ingress NGINX Controller.

```yaml
tls:
  - hosts:
      - web.lab.local
    secretName: web-lab-local-tls
```

Khi client truy cập HTTPS tới `web.lab.local`, Ingress Controller dùng Secret `web-lab-local-tls` để terminate TLS.

```yaml
rules:
  - host: web.lab.local
```

Rule routing áp dụng cho request có HTTP Host header là `web.lab.local`.

```yaml
path: /
pathType: Prefix
```

Mọi path bắt đầu từ `/` đều đi vào backend này, trừ khi có rule khác cụ thể hơn.

```yaml
service:
  name: lesson-06-web-svc
  port:
    number: 80
```

Sau khi terminate HTTPS, Ingress chuyển request vào Service `lesson-06-web-svc` port 80.

### F. HTTP redirect sang HTTPS

Với Ingress NGINX, khi Ingress có block `tls`, controller thường redirect HTTP sang HTTPS.

Test:

```bash
curl -I --resolve web.lab.local:80:10.10.10.240 http://web.lab.local/
```

Kết quả thường gặp:

```text
HTTP/1.1 308 Permanent Redirect
Location: https://web.lab.local/
```

Test HTTPS:

```bash
curl -k -I --resolve web.lab.local:443:10.10.10.240 https://web.lab.local/
```

Kết quả kỳ vọng:

```text
HTTP/2 200
```

Hoặc:

```text
HTTP/1.1 200 OK
```

Tùy phiên bản controller, cấu hình HTTP/2 và client.

Nếu muốn tắt redirect cho một Ingress cụ thể:

```yaml
metadata:
  annotations:
    nginx.ingress.kubernetes.io/ssl-redirect: "false"
```

Ví dụ đầy đủ:

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: lesson-06-web-https
  namespace: lesson-06
  annotations:
    nginx.ingress.kubernetes.io/ssl-redirect: "false"
spec:
  ingressClassName: nginx
  tls:
    - hosts:
        - web.lab.local
      secretName: web-lab-local-tls
  rules:
    - host: web.lab.local
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: lesson-06-web-svc
                port:
                  number: 80
```

Trong production, thường nên bật redirect HTTP sang HTTPS để ép người dùng đi qua kênh mã hóa.

### G. Nhiều domain dùng nhiều certificate

Một Ingress có thể khai báo nhiều host và nhiều TLS Secret.

Ví dụ:

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: multi-tls-ingress
  namespace: lesson-06
spec:
  ingressClassName: nginx
  tls:
    - hosts:
        - app1.lab.local
      secretName: app1-lab-local-tls
    - hosts:
        - app2.lab.local
      secretName: app2-lab-local-tls
  rules:
    - host: app1.lab.local
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: app1-svc
                port:
                  number: 80
    - host: app2.lab.local
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: app2-svc
                port:
                  number: 80
```

Khi client truy cập HTTPS, TLS handshake dùng SNI để báo cho server biết domain client muốn truy cập. Ingress Controller dựa vào domain đó để chọn certificate phù hợp.

Mô hình:

```text
https://app1.lab.local
  -> dùng Secret app1-lab-local-tls
  -> route app1-svc

https://app2.lab.local
  -> dùng Secret app2-lab-local-tls
  -> route app2-svc
```

### H. Một certificate dùng cho nhiều domain

Có thể dùng một certificate chứa nhiều SAN:

```text
DNS:app1.lab.local
DNS:app2.lab.local
DNS:web.lab.local
```

Hoặc wildcard certificate:

```text
DNS:*.lab.local
```

Khi đó nhiều host có thể dùng chung một TLS Secret.

Ví dụ:

```yaml
tls:
  - hosts:
      - app1.lab.local
      - app2.lab.local
      - web.lab.local
    secretName: wildcard-lab-local-tls
```

Lưu ý:

- Wildcard `*.lab.local` chỉ match một cấp như `app1.lab.local`.
- Wildcard này không match `api.dev.lab.local` vì đó là nhiều hơn một DNS label phía trước `lab.local`.

### I. Path routing trong Ingress

Ingress không chỉ route theo domain, mà còn route theo URL path.

Ví dụ một domain duy nhất:

```text
https://portal.lab.local/
https://portal.lab.local/api
https://portal.lab.local/admin
```

Có thể route đến ba Service khác nhau:

```text
/       -> frontend-svc
/api    -> api-svc
/admin  -> admin-svc
```

Luồng:

```text
Client
  |
  | GET /api/v1/users
  | Host: portal.lab.local
  v
Ingress NGINX Controller
  |
  | rule host = portal.lab.local
  | path = /api
  v
api-svc
  |
  v
Pod API
```

Điểm cần nhớ:

- Ingress route theo HTTP Host header và URL path.
- Backend của Ingress vẫn là Service.
- Ingress không route trực tiếp vào Pod.
- Các path cụ thể hơn thường được ưu tiên hơn path tổng quát `/`.

### J. Ba loại pathType trong Kubernetes Ingress

Từ Kubernetes `networking.k8s.io/v1`, mỗi path bắt buộc phải có `pathType`.

Có ba loại chính:

```text
Exact
Prefix
ImplementationSpecific
```

#### J.1. pathType Exact

`Exact` match chính xác toàn bộ path, có phân biệt chữ hoa/chữ thường.

Ví dụ:

```yaml
path: /healthz
pathType: Exact
```

Match:

```text
/healthz
```

Không match:

```text
/healthz/
/healthz/live
/Healthz
```

Dùng khi:

- Health endpoint cụ thể.
- Callback endpoint cần đúng path.
- Route đặc biệt không muốn match các subpath phía sau.

#### J.2. pathType Prefix

`Prefix` match theo từng phần tử path, phân tách bởi dấu `/`.

Ví dụ:

```yaml
path: /api
pathType: Prefix
```

Match:

```text
/api
/api/
/api/v1
/api/v1/users
```

Không nên hiểu nhầm là string prefix thuần túy.

Theo ý nghĩa Kubernetes Ingress, `/api` không nên match:

```text
/apix
/api-v2
```

Vì `/api` là một path element riêng, còn `/apix` là element khác.

Dùng khi:

- Muốn route một nhóm URL vào cùng backend.
- Ví dụ `/api`, `/admin`, `/static`, `/media`.
- Ứng dụng backend tự hiểu subpath phía sau.

#### J.3. pathType ImplementationSpecific

`ImplementationSpecific` nghĩa là cách match phụ thuộc vào Ingress Controller.

Với Ingress NGINX, loại này thường gặp khi dùng regex path hoặc một số annotation nâng cao.

Ví dụ regex:

```yaml
metadata:
  annotations:
    nginx.ingress.kubernetes.io/use-regex: "true"
spec:
  rules:
    - host: rewrite.lab.local
      http:
        paths:
          - path: /backend(/|$)(.*)
            pathType: ImplementationSpecific
            backend:
              service:
                name: path-echo-svc
                port:
                  number: 80
```

Dùng khi:

- Cần regex.
- Cần rewrite path nâng cao.
- Chấp nhận cấu hình phụ thuộc vào Ingress NGINX.

Không nên dùng `ImplementationSpecific` cho bài lab cơ bản nếu `Exact` hoặc `Prefix` đã đủ.

### K. Thứ tự ưu tiên khi nhiều path cùng match

Khi nhiều path cùng match một request, Kubernetes ưu tiên:

1. Path dài hơn, cụ thể hơn.
2. Nếu độ dài tương đương, `Exact` được ưu tiên hơn `Prefix`.

Ví dụ:

```yaml
paths:
  - path: /api/v1
    pathType: Prefix
    backend: api-v1-svc

  - path: /api
    pathType: Prefix
    backend: api-svc

  - path: /
    pathType: Prefix
    backend: frontend-svc
```

Request:

```text
/api/v1/users
```

Sẽ đi vào:

```text
api-v1-svc
```

Không đi vào:

```text
api-svc
frontend-svc
```

Vì `/api/v1` cụ thể hơn `/api`, và `/api` cụ thể hơn `/`.

Ví dụ `Exact` và `Prefix` cùng tồn tại:

```yaml
paths:
  - path: /healthz
    pathType: Exact
    backend: health-svc

  - path: /healthz
    pathType: Prefix
    backend: api-svc
```

Request:

```text
/healthz
```

Đi vào:

```text
health-svc
```

Request:

```text
/healthz/live
```

Đi vào:

```text
api-svc
```

### L. Demo bổ sung 01 - Path routing bằng Prefix

#### L.1. Mục tiêu

Triển khai ba backend:

```text
frontend
api
admin
```

Dùng một domain:

```text
path.lab.local
```

Dùng một IP Ingress:

```text
10.10.10.240
```

Route theo path:

```text
http://path.lab.local/              -> frontend-svc
http://path.lab.local/api           -> api-svc
http://path.lab.local/api/v1/users  -> api-svc
http://path.lab.local/admin         -> admin-svc
http://path.lab.local/admin/users   -> admin-svc
```

#### L.2. Tạo namespace

```bash
kubectl create namespace ingress-path-demo
```

#### L.3. Tạo ba ứng dụng demo

Dùng image `hashicorp/http-echo` để backend trả về nội dung text đơn giản.

Tạo file:

```bash
cat <<'EOF' > path-demo-apps.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: frontend
  namespace: ingress-path-demo
spec:
  replicas: 2
  selector:
    matchLabels:
      app: frontend
  template:
    metadata:
      labels:
        app: frontend
    spec:
      containers:
        - name: http-echo
          image: hashicorp/http-echo:1.0
          args:
            - "-listen=:5678"
            - "-text=frontend service - root path"
          ports:
            - containerPort: 5678
---
apiVersion: v1
kind: Service
metadata:
  name: frontend-svc
  namespace: ingress-path-demo
spec:
  type: ClusterIP
  selector:
    app: frontend
  ports:
    - name: http
      port: 80
      targetPort: 5678
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: api
  namespace: ingress-path-demo
spec:
  replicas: 2
  selector:
    matchLabels:
      app: api
  template:
    metadata:
      labels:
        app: api
    spec:
      containers:
        - name: http-echo
          image: hashicorp/http-echo:1.0
          args:
            - "-listen=:5678"
            - "-text=api service - /api prefix"
          ports:
            - containerPort: 5678
---
apiVersion: v1
kind: Service
metadata:
  name: api-svc
  namespace: ingress-path-demo
spec:
  type: ClusterIP
  selector:
    app: api
  ports:
    - name: http
      port: 80
      targetPort: 5678
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: admin
  namespace: ingress-path-demo
spec:
  replicas: 2
  selector:
    matchLabels:
      app: admin
  template:
    metadata:
      labels:
        app: admin
    spec:
      containers:
        - name: http-echo
          image: hashicorp/http-echo:1.0
          args:
            - "-listen=:5678"
            - "-text=admin service - /admin prefix"
          ports:
            - containerPort: 5678
---
apiVersion: v1
kind: Service
metadata:
  name: admin-svc
  namespace: ingress-path-demo
spec:
  type: ClusterIP
  selector:
    app: admin
  ports:
    - name: http
      port: 80
      targetPort: 5678
EOF
```

Apply:

```bash
kubectl apply -f path-demo-apps.yaml
```

Kiểm tra:

```bash
kubectl get pods -n ingress-path-demo -o wide
kubectl get svc -n ingress-path-demo
kubectl get endpointslice -n ingress-path-demo
```

#### L.4. Tạo Ingress path Prefix

Tạo file:

```bash
cat <<'EOF' > path-prefix-ingress.yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: path-prefix-ingress
  namespace: ingress-path-demo
spec:
  ingressClassName: nginx
  rules:
    - host: path.lab.local
      http:
        paths:
          - path: /api
            pathType: Prefix
            backend:
              service:
                name: api-svc
                port:
                  number: 80
          - path: /admin
            pathType: Prefix
            backend:
              service:
                name: admin-svc
                port:
                  number: 80
          - path: /
            pathType: Prefix
            backend:
              service:
                name: frontend-svc
                port:
                  number: 80
EOF
```

Apply:

```bash
kubectl apply -f path-prefix-ingress.yaml
```

Kiểm tra:

```bash
kubectl get ingress -n ingress-path-demo
kubectl describe ingress path-prefix-ingress -n ingress-path-demo
```

#### L.5. Test bằng curl --resolve

Lấy IP Ingress:

```bash
export INGRESS_IP=$(kubectl get svc ingress-nginx-controller \
  -n ingress-nginx \
  -o jsonpath='{.status.loadBalancer.ingress[0].ip}')

echo $INGRESS_IP
```

Test root path:

```bash
curl --resolve path.lab.local:80:$INGRESS_IP http://path.lab.local/
```

Kết quả kỳ vọng:

```text
frontend service - root path
```

Test `/api`:

```bash
curl --resolve path.lab.local:80:$INGRESS_IP http://path.lab.local/api
curl --resolve path.lab.local:80:$INGRESS_IP http://path.lab.local/api/v1/users
```

Kết quả kỳ vọng:

```text
api service - /api prefix
```

Test `/admin`:

```bash
curl --resolve path.lab.local:80:$INGRESS_IP http://path.lab.local/admin
curl --resolve path.lab.local:80:$INGRESS_IP http://path.lab.local/admin/users
```

Kết quả kỳ vọng:

```text
admin service - /admin prefix
```

Test path không match `/api` theo path element:

```bash
curl -i --resolve path.lab.local:80:$INGRESS_IP http://path.lab.local/apix
```

Trong cách hiểu chuẩn của Kubernetes `Prefix`, `/apix` không phải là subpath của `/api`. Nếu không có rule nào cụ thể hơn, request sẽ rơi về rule `/` và đi vào frontend.

Kết quả kỳ vọng:

```text
frontend service - root path
```

#### L.6. Vì sao path `/` nên để cuối?

Trong YAML trên, ta đặt:

```yaml
- path: /api
- path: /admin
- path: /
```

Mục đích là để người học dễ đọc từ rule cụ thể đến rule tổng quát.

Về nguyên tắc matching, path cụ thể hơn được ưu tiên. Tuy nhiên khi dạy học, nên luôn viết rule tổng quát `/` ở cuối để tránh học viên hiểu nhầm rằng `/` sẽ “ăn hết” mọi request trước.

### M. Demo bổ sung 02 - Kết hợp HTTPS + path Prefix

#### M.1. Mục tiêu

Dùng lại ba backend ở Demo bổ sung 01, nhưng publish bằng HTTPS:

```text
https://path.lab.local/
https://path.lab.local/api
https://path.lab.local/admin
```

TLS terminate tại Ingress NGINX Controller.

#### M.2. Tạo certificate cho path.lab.local

```bash
openssl req -x509 -nodes -days 365 \
  -newkey rsa:2048 \
  -keyout path.lab.local.key \
  -out path.lab.local.crt \
  -subj "/CN=path.lab.local/O=Kubernetes Lab" \
  -addext "subjectAltName=DNS:path.lab.local"
```

Tạo TLS Secret:

```bash
kubectl create secret tls path-lab-local-tls \
  --cert=path.lab.local.crt \
  --key=path.lab.local.key \
  -n ingress-path-demo
```

Kiểm tra:

```bash
kubectl get secret path-lab-local-tls -n ingress-path-demo
kubectl get secret path-lab-local-tls -n ingress-path-demo -o jsonpath='{.type}'; echo
```

Kết quả:

```text
kubernetes.io/tls
```

#### M.3. Cập nhật Ingress có TLS

Tạo file:

```bash
cat <<'EOF' > path-prefix-https-ingress.yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: path-prefix-ingress
  namespace: ingress-path-demo
spec:
  ingressClassName: nginx
  tls:
    - hosts:
        - path.lab.local
      secretName: path-lab-local-tls
  rules:
    - host: path.lab.local
      http:
        paths:
          - path: /api
            pathType: Prefix
            backend:
              service:
                name: api-svc
                port:
                  number: 80
          - path: /admin
            pathType: Prefix
            backend:
              service:
                name: admin-svc
                port:
                  number: 80
          - path: /
            pathType: Prefix
            backend:
              service:
                name: frontend-svc
                port:
                  number: 80
EOF
```

Apply:

```bash
kubectl apply -f path-prefix-https-ingress.yaml
```

Kiểm tra:

```bash
kubectl get ingress -n ingress-path-demo
kubectl describe ingress path-prefix-ingress -n ingress-path-demo
```

#### M.4. Test HTTPS

Test root path:

```bash
curl -k --resolve path.lab.local:443:$INGRESS_IP https://path.lab.local/
```

Test API path:

```bash
curl -k --resolve path.lab.local:443:$INGRESS_IP https://path.lab.local/api
curl -k --resolve path.lab.local:443:$INGRESS_IP https://path.lab.local/api/v1/users
```

Test admin path:

```bash
curl -k --resolve path.lab.local:443:$INGRESS_IP https://path.lab.local/admin
curl -k --resolve path.lab.local:443:$INGRESS_IP https://path.lab.local/admin/users
```

Kiểm tra redirect HTTP sang HTTPS:

```bash
curl -I --resolve path.lab.local:80:$INGRESS_IP http://path.lab.local/api
```

Kết quả thường gặp:

```text
HTTP/1.1 308 Permanent Redirect
Location: https://path.lab.local/api
```

Kiểm tra certificate đang được trả ra:

```bash
openssl s_client -connect $INGRESS_IP:443 -servername path.lab.local </dev/null 2>/dev/null \
  | openssl x509 -noout -subject -issuer -dates
```

Kết quả cần thấy certificate có subject tương ứng với `path.lab.local`.

### N. Demo bổ sung 03 - Exact so với Prefix

#### N.1. Mục tiêu

Chứng minh:

- `/healthz` với `Exact` chỉ match đúng `/healthz`.
- `/healthz/live` không match `Exact`.
- Nếu có thêm `/healthz` với `Prefix`, thì `/healthz/live` có thể đi vào backend Prefix.
- Khi request đúng `/healthz`, `Exact` được ưu tiên hơn `Prefix`.

#### N.2. Tạo hai backend

Tạo file:

```bash
cat <<'EOF' > exact-prefix-apps.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: health-exact
  namespace: ingress-path-demo
spec:
  replicas: 1
  selector:
    matchLabels:
      app: health-exact
  template:
    metadata:
      labels:
        app: health-exact
    spec:
      containers:
        - name: http-echo
          image: hashicorp/http-echo:1.0
          args:
            - "-listen=:5678"
            - "-text=EXACT backend: /healthz only"
          ports:
            - containerPort: 5678
---
apiVersion: v1
kind: Service
metadata:
  name: health-exact-svc
  namespace: ingress-path-demo
spec:
  type: ClusterIP
  selector:
    app: health-exact
  ports:
    - name: http
      port: 80
      targetPort: 5678
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: health-prefix
  namespace: ingress-path-demo
spec:
  replicas: 1
  selector:
    matchLabels:
      app: health-prefix
  template:
    metadata:
      labels:
        app: health-prefix
    spec:
      containers:
        - name: http-echo
          image: hashicorp/http-echo:1.0
          args:
            - "-listen=:5678"
            - "-text=PREFIX backend: /healthz and subpaths"
          ports:
            - containerPort: 5678
---
apiVersion: v1
kind: Service
metadata:
  name: health-prefix-svc
  namespace: ingress-path-demo
spec:
  type: ClusterIP
  selector:
    app: health-prefix
  ports:
    - name: http
      port: 80
      targetPort: 5678
EOF
```

Apply:

```bash
kubectl apply -f exact-prefix-apps.yaml
```

#### N.3. Tạo Ingress Exact và Prefix

Tạo file:

```bash
cat <<'EOF' > exact-prefix-ingress.yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: exact-prefix-ingress
  namespace: ingress-path-demo
spec:
  ingressClassName: nginx
  rules:
    - host: exact.lab.local
      http:
        paths:
          - path: /healthz
            pathType: Exact
            backend:
              service:
                name: health-exact-svc
                port:
                  number: 80
          - path: /healthz
            pathType: Prefix
            backend:
              service:
                name: health-prefix-svc
                port:
                  number: 80
EOF
```

Apply:

```bash
kubectl apply -f exact-prefix-ingress.yaml
```

Kiểm tra:

```bash
kubectl describe ingress exact-prefix-ingress -n ingress-path-demo
```

#### N.4. Test Exact và Prefix

Request đúng `/healthz`:

```bash
curl --resolve exact.lab.local:80:$INGRESS_IP http://exact.lab.local/healthz
```

Kết quả kỳ vọng:

```text
EXACT backend: /healthz only
```

Request subpath `/healthz/live`:

```bash
curl --resolve exact.lab.local:80:$INGRESS_IP http://exact.lab.local/healthz/live
```

Kết quả kỳ vọng:

```text
PREFIX backend: /healthz and subpaths
```

Request sai chữ hoa/thường:

```bash
curl -i --resolve exact.lab.local:80:$INGRESS_IP http://exact.lab.local/Healthz
```

Kết quả kỳ vọng là không match rule `/healthz`, vì `Exact` và `Prefix` đều case-sensitive theo Kubernetes Ingress path matching.

### O. Demo bổ sung 04 - Rewrite path với Ingress NGINX

#### O.1. Khi nào cần rewrite path?

Không phải ứng dụng nào cũng biết mình đang được expose dưới subpath.

Ví dụ bên ngoài muốn expose:

```text
https://rewrite.lab.local/backend/api/users
```

Nhưng backend app thật ra chỉ hiểu:

```text
/api/users
```

Lúc này ta cần rewrite:

```text
/backend/api/users -> /api/users
```

Với Ingress NGINX, có thể dùng annotation:

```yaml
nginx.ingress.kubernetes.io/rewrite-target: /$2
nginx.ingress.kubernetes.io/use-regex: "true"
```

Lưu ý: rewrite là tính năng phụ thuộc Ingress NGINX, không phải hành vi portable giữa mọi Ingress Controller.

#### O.2. Tạo backend echo request URI bằng nginx

Backend này trả về URI mà nó nhận được sau khi đi qua Ingress. Nhờ vậy học viên thấy được rewrite có tác dụng hay không.

Tạo file:

```bash
cat <<'EOF' > rewrite-echo-app.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: rewrite-echo-nginx-conf
  namespace: ingress-path-demo
data:
  default.conf: |
    server {
      listen 80;

      location / {
        default_type text/plain;
        return 200 "backend received uri=$request_uri\nhost=$host\n";
      }
    }
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: rewrite-echo
  namespace: ingress-path-demo
spec:
  replicas: 1
  selector:
    matchLabels:
      app: rewrite-echo
  template:
    metadata:
      labels:
        app: rewrite-echo
    spec:
      containers:
        - name: nginx
          image: nginx:1.27
          ports:
            - containerPort: 80
          volumeMounts:
            - name: nginx-conf
              mountPath: /etc/nginx/conf.d/default.conf
              subPath: default.conf
      volumes:
        - name: nginx-conf
          configMap:
            name: rewrite-echo-nginx-conf
---
apiVersion: v1
kind: Service
metadata:
  name: rewrite-echo-svc
  namespace: ingress-path-demo
spec:
  type: ClusterIP
  selector:
    app: rewrite-echo
  ports:
    - name: http
      port: 80
      targetPort: 80
EOF
```

Apply:

```bash
kubectl apply -f rewrite-echo-app.yaml
```

Kiểm tra:

```bash
kubectl get pods -n ingress-path-demo -l app=rewrite-echo
kubectl get svc rewrite-echo-svc -n ingress-path-demo
```

#### O.3. Tạo Ingress rewrite

Tạo file:

```bash
cat <<'EOF' > rewrite-ingress.yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: rewrite-ingress
  namespace: ingress-path-demo
  annotations:
    nginx.ingress.kubernetes.io/use-regex: "true"
    nginx.ingress.kubernetes.io/rewrite-target: /$2
spec:
  ingressClassName: nginx
  rules:
    - host: rewrite.lab.local
      http:
        paths:
          - path: /backend(/|$)(.*)
            pathType: ImplementationSpecific
            backend:
              service:
                name: rewrite-echo-svc
                port:
                  number: 80
EOF
```

Apply:

```bash
kubectl apply -f rewrite-ingress.yaml
```

#### O.4. Test rewrite

Test request vào `/backend`:

```bash
curl --resolve rewrite.lab.local:80:$INGRESS_IP http://rewrite.lab.local/backend
```

Kết quả kỳ vọng backend nhận URI:

```text
backend received uri=/
```

Test request vào `/backend/api/users`:

```bash
curl --resolve rewrite.lab.local:80:$INGRESS_IP http://rewrite.lab.local/backend/api/users
```

Kết quả kỳ vọng backend nhận URI:

```text
backend received uri=/api/users
```

Test query string:

```bash
curl --resolve rewrite.lab.local:80:$INGRESS_IP "http://rewrite.lab.local/backend/api/users?id=100"
```

Kết quả kỳ vọng backend nhận URI gần như:

```text
backend received uri=/api/users?id=100
```

#### O.5. Giải thích regex `/backend(/|$)(.*)`

Path:

```text
/backend(/|$)(.*)
```

Có thể hiểu:

```text
/backend
```

Là prefix bên ngoài muốn public.

```text
(/|$)
```

Sau `/backend` có thể là dấu `/` hoặc kết thúc chuỗi.

```text
(.*)
```

Phần còn lại của path, được lưu vào capture group số 2.

Annotation:

```yaml
nginx.ingress.kubernetes.io/rewrite-target: /$2
```

Nghĩa là phần path gửi vào backend sẽ thành:

```text
/<capture group 2>
```

Ví dụ:

```text
Request ngoài: /backend/api/users
Capture $2:    api/users
Rewrite thành: /api/users
```

### P. Demo bổ sung 05 - HTTPS + rewrite path

Có thể kết hợp TLS với rewrite.

Tạo certificate:

```bash
openssl req -x509 -nodes -days 365 \
  -newkey rsa:2048 \
  -keyout rewrite.lab.local.key \
  -out rewrite.lab.local.crt \
  -subj "/CN=rewrite.lab.local/O=Kubernetes Lab" \
  -addext "subjectAltName=DNS:rewrite.lab.local"
```

Tạo Secret:

```bash
kubectl create secret tls rewrite-lab-local-tls \
  --cert=rewrite.lab.local.crt \
  --key=rewrite.lab.local.key \
  -n ingress-path-demo
```

Tạo Ingress HTTPS + rewrite:

```bash
cat <<'EOF' > rewrite-https-ingress.yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: rewrite-ingress
  namespace: ingress-path-demo
  annotations:
    nginx.ingress.kubernetes.io/use-regex: "true"
    nginx.ingress.kubernetes.io/rewrite-target: /$2
spec:
  ingressClassName: nginx
  tls:
    - hosts:
        - rewrite.lab.local
      secretName: rewrite-lab-local-tls
  rules:
    - host: rewrite.lab.local
      http:
        paths:
          - path: /backend(/|$)(.*)
            pathType: ImplementationSpecific
            backend:
              service:
                name: rewrite-echo-svc
                port:
                  number: 80
EOF
```

Apply:

```bash
kubectl apply -f rewrite-https-ingress.yaml
```

Test:

```bash
curl -k --resolve rewrite.lab.local:443:$INGRESS_IP https://rewrite.lab.local/backend/api/users
```

Kết quả kỳ vọng:

```text
backend received uri=/api/users
```

Kiểm tra redirect HTTP sang HTTPS:

```bash
curl -I --resolve rewrite.lab.local:80:$INGRESS_IP http://rewrite.lab.local/backend/api/users
```

Kết quả thường gặp:

```text
HTTP/1.1 308 Permanent Redirect
Location: https://rewrite.lab.local/backend/api/users
```

### Q. Bảng tổng hợp các trường hợp Ingress path

| Nhu cầu | path | pathType | Backend | Ghi chú |
|---|---:|---|---|---|
| Website chính | `/` | `Prefix` | `frontend-svc` | Match toàn bộ nếu không có path cụ thể hơn |
| API service | `/api` | `Prefix` | `api-svc` | Match `/api`, `/api/v1`, `/api/users` |
| Admin portal | `/admin` | `Prefix` | `admin-svc` | Match `/admin`, `/admin/users` |
| Health check chính xác | `/healthz` | `Exact` | `health-svc` | Không match `/healthz/live` |
| Static assets | `/static` | `Prefix` | `static-svc` | Dùng cho file CSS/JS/image |
| Media upload | `/media` | `Prefix` | `media-svc` | Dùng cho user-uploaded content |
| Regex rewrite | `/backend(/|$)(.*)` | `ImplementationSpecific` | `backend-svc` | Phụ thuộc Ingress NGINX |
| Catch-all | `/` | `Prefix` | `frontend-svc` | Nên đặt sau các route cụ thể khi viết manifest |

### R. Troubleshooting riêng cho HTTPS và path routing

#### R.1. HTTPS báo certificate không tin cậy

Nếu dùng self-signed certificate trong lab, browser báo không tin cậy là bình thường.

Dùng curl:

```bash
curl -k https://web.lab.local/
```

Hoặc:

```bash
curl -k --resolve web.lab.local:443:$INGRESS_IP https://web.lab.local/
```

Trong production, cần dùng certificate được cấp bởi CA tin cậy hoặc CA nội bộ đã được client trust.

#### R.2. HTTPS trả về certificate không đúng domain

Kiểm tra SNI:

```bash
openssl s_client -connect $INGRESS_IP:443 -servername web.lab.local </dev/null 2>/dev/null \
  | openssl x509 -noout -subject -issuer
```

Nếu không dùng `-servername`, server có thể trả default certificate, làm kết quả kiểm tra bị sai.

Kiểm tra Secret:

```bash
kubectl get secret web-lab-local-tls -n lesson-06 -o yaml
```

Kiểm tra Ingress:

```bash
kubectl describe ingress lesson-06-web-https -n lesson-06
```

Các lỗi thường gặp:

- Secret sai namespace.
- Secret sai type.
- Secret thiếu `tls.crt` hoặc `tls.key`.
- Certificate không có SAN đúng domain.
- Host trong `tls.hosts` khác host trong `rules`.
- Client truy cập bằng IP thay vì domain.

#### R.3. HTTP không redirect sang HTTPS

Kiểm tra Ingress có block `tls` chưa:

```bash
kubectl get ingress <ingress-name> -n <namespace> -o yaml
```

Kiểm tra annotation có tắt redirect không:

```yaml
nginx.ingress.kubernetes.io/ssl-redirect: "false"
```

Kiểm tra ConfigMap của Ingress NGINX Controller nếu hệ thống có custom global setting.

#### R.4. Path `/api` được nhưng `/api/v1/users` không được

Kiểm tra `pathType`:

```yaml
pathType: Prefix
```

Nếu dùng `Exact`, `/api/v1/users` sẽ không match `/api`.

Kiểm tra backend app có tự xử lý subpath đó không. Ingress route đúng chưa chắc app trả về 200. Có thể Ingress đã chuyển request vào đúng backend, nhưng app trả 404 vì app không có route tương ứng.

#### R.5. Request vào `/api` nhưng backend nhận path `/api`

Đây là hành vi bình thường nếu không rewrite.

Ví dụ:

```text
Client gọi: /api/users
Backend nhận: /api/users
```

Nếu backend chỉ muốn nhận:

```text
/users
```

Thì cần rewrite:

```yaml
nginx.ingress.kubernetes.io/rewrite-target: /$2
```

Và regex path phù hợp.

#### R.6. Ingress trả 404

404 thường là request không match host/path.

Kiểm tra:

```bash
kubectl describe ingress -n ingress-path-demo
```

Test đúng Host header:

```bash
curl -H "Host: path.lab.local" http://$INGRESS_IP/api
```

Hoặc dùng `--resolve`:

```bash
curl --resolve path.lab.local:80:$INGRESS_IP http://path.lab.local/api
```

Nếu gọi trực tiếp bằng IP:

```bash
curl http://$INGRESS_IP/api
```

Có thể bị 404 vì thiếu Host header đúng.

#### R.7. Ingress trả 503

503 thường là đã match Ingress rule nhưng backend không có endpoint sẵn sàng.

Kiểm tra:

```bash
kubectl get svc -n ingress-path-demo
kubectl get endpointslice -n ingress-path-demo
kubectl get pods -n ingress-path-demo --show-labels
```

Các lỗi hay gặp:

- Service selector không khớp label Pod.
- Pod chưa Running.
- Pod không Ready.
- targetPort sai.
- Container không listen port đã khai báo.

#### R.8. Regex hoặc rewrite chạy không như kỳ vọng

Kiểm tra annotation:

```yaml
nginx.ingress.kubernetes.io/use-regex: "true"
nginx.ingress.kubernetes.io/rewrite-target: /$2
```

Kiểm tra `pathType`:

```yaml
pathType: ImplementationSpecific
```

Kiểm tra log controller:

```bash
kubectl logs -n ingress-nginx deploy/ingress-nginx-controller --tail=100
```

Có thể inspect cấu hình NGINX sinh ra bên trong Pod controller:

```bash
kubectl exec -n ingress-nginx deploy/ingress-nginx-controller -- nginx -T | less
```

Trong môi trường không có `less`, dùng:

```bash
kubectl exec -n ingress-nginx deploy/ingress-nginx-controller -- nginx -T | grep -A20 "server_name rewrite.lab.local"
```

### S. Bài tập thực hành thêm cho học viên

#### S.1. Bài tập 1 - Tạo portal có ba path

Yêu cầu:

- Domain: `student.lab.local`
- `/` đi vào `home-svc`
- `/api` đi vào `api-svc`
- `/admin` đi vào `admin-svc`
- Có HTTPS bằng self-signed certificate.
- Test được bằng `curl --resolve`.

#### S.2. Bài tập 2 - Exact health check

Yêu cầu:

- Domain: `student-health.lab.local`
- `/healthz` dùng `Exact`, trả về `OK`.
- `/healthz/live` dùng `Prefix`, trả về `LIVE`.
- Chứng minh `/Healthz` không match `/healthz`.

#### S.3. Bài tập 3 - Rewrite path

Yêu cầu:

- Domain: `student-rewrite.lab.local`
- Public path: `/service/api/users`
- Backend nhận path: `/api/users`
- Dùng `rewrite-target`.
- Dùng HTTPS.
- Chứng minh bằng backend echo URI.

### T. Dọn dẹp tài nguyên phần bổ sung

Xóa toàn bộ namespace demo:

```bash
kubectl delete namespace ingress-path-demo
```

Xóa file certificate local nếu muốn:

```bash
rm -f path.lab.local.crt path.lab.local.key
rm -f rewrite.lab.local.crt rewrite.lab.local.key
```

Nếu đã thêm hosts trên client, xóa các dòng tương ứng:

```text
path.lab.local
exact.lab.local
rewrite.lab.local
```

### U. Ghi nhớ nhanh cho phần bổ sung

- HTTPS trong Ingress thường là TLS termination tại Ingress Controller.
- Kubernetes dùng trường `spec.tls`, không dùng tên trường `ssl`.
- TLS Secret phải cùng namespace với Ingress.
- Certificate phải có SAN đúng domain.
- `Prefix` không phải string prefix đơn giản, mà match theo path element.
- `Exact` match chính xác và case-sensitive.
- `ImplementationSpecific` phụ thuộc Ingress Controller, thường dùng cho regex/rewrite với Ingress NGINX.
- Path cụ thể hơn được ưu tiên hơn path tổng quát.
- Nếu cùng path, `Exact` được ưu tiên hơn `Prefix`.
- Không có rewrite thì backend thường nhận nguyên path client gọi.
- Có rewrite thì cần hiểu capture group `$1`, `$2`.
- Khi test bằng IP trực tiếp, dễ thiếu Host header và bị 404.
- `curl --resolve` là công cụ rất tốt để test Ingress trong lab mà không cần sửa DNS.

### V. Tài liệu tham khảo bổ sung

- Kubernetes Documentation - Ingress path types  
  https://kubernetes.io/docs/concepts/services-networking/ingress/#path-types

- Kubernetes Documentation - Multiple matches  
  https://kubernetes.io/docs/concepts/services-networking/ingress/#multiple-matches

- Ingress NGINX Controller - TLS/HTTPS  
  https://kubernetes.github.io/ingress-nginx/user-guide/tls/

- Ingress NGINX Controller - TLS termination example  
  https://kubernetes.github.io/ingress-nginx/examples/tls-termination/

- Ingress NGINX Controller - Ingress path matching  
  https://kubernetes.github.io/ingress-nginx/user-guide/ingress-path-matching/

- Ingress NGINX Controller - Rewrite  
  https://kubernetes.github.io/ingress-nginx/examples/rewrite/

## 14. Lab tổng hợp cuối buổi

## 14.1. Yêu cầu bài lab

 cần tự triển khai hoàn chỉnh các yêu cầu sau:

- Cài Helm trên `master-01`.
- Cài MetalLB bằng Helm.
- Cấu hình MetalLB IP pool:
  - `10.10.10.240-10.10.10.250`
- Cài Ingress NGINX Controller bằng Helm.
- Đảm bảo Service `ingress-nginx-controller` nhận được external IP từ MetalLB.
- Tạo namespace `production-web`.
- Triển khai một ứng dụng nginx gồm:
  - Deployment 3 replicas.
  - ConfigMap chứa `index.html`.
  - Service type `ClusterIP`.
- Tạo Ingress HTTP cho domain:
  - `prod-web.lab.local`
- Tạo self-signed certificate cho:
  - `prod-web.lab.local`
- Tạo TLS Secret.
- Cập nhật Ingress để hỗ trợ HTTPS.
- Test được:
  - `http://prod-web.lab.local`
  - `https://prod-web.lab.local`
- Kiểm tra log của Ingress Controller.
- Xác định Pod backend nào đang phục vụ request.

## 14.2. Gợi ý manifest tổng hợp

### Namespace

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: production-web
```

### ConfigMap

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: prod-web-content
  namespace: production-web
data:
  index.html: |
    <h1>Production Web on Kubernetes</h1>
    <p>Exposed by Ingress NGINX Controller and MetalLB.</p>
```

### Deployment

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: prod-web
  namespace: production-web
spec:
  replicas: 3
  selector:
    matchLabels:
      app: prod-web
  template:
    metadata:
      labels:
        app: prod-web
    spec:
      containers:
        - name: nginx
          image: nginx:1.27
          ports:
            - containerPort: 80
          volumeMounts:
            - name: content
              mountPath: /usr/share/nginx/html/index.html
              subPath: index.html
      volumes:
        - name: content
          configMap:
            name: prod-web-content
```

### Service

```yaml
apiVersion: v1
kind: Service
metadata:
  name: prod-web-svc
  namespace: production-web
spec:
  type: ClusterIP
  selector:
    app: prod-web
  ports:
    - name: http
      port: 80
      targetPort: 80
```

### Ingress HTTP/HTTPS

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: prod-web-ingress
  namespace: production-web
spec:
  ingressClassName: nginx
  tls:
    - hosts:
        - prod-web.lab.local
      secretName: prod-web-tls
  rules:
    - host: prod-web.lab.local
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: prod-web-svc
                port:
                  number: 80
```

## 14.3. Lệnh tạo certificate cho bài lab tổng hợp

```bash
openssl req -x509 -nodes -days 365 \
  -newkey rsa:2048 \
  -keyout prod-web.lab.local.key \
  -out prod-web.lab.local.crt \
  -subj "/CN=prod-web.lab.local/O=Kubernetes Lab" \
  -addext "subjectAltName=DNS:prod-web.lab.local"
```

Tạo Secret:

```bash
kubectl create secret tls prod-web-tls \
  --cert=prod-web.lab.local.crt \
  --key=prod-web.lab.local.key \
  -n production-web
```

## 14.4. Lệnh kiểm tra

```bash
kubectl get all -n production-web
kubectl get ingress -n production-web
kubectl describe ingress prod-web-ingress -n production-web
kubectl get svc -n ingress-nginx
kubectl logs -n ingress-nginx deploy/ingress-nginx-controller --tail=100
```

Test HTTP:

```bash
curl --resolve prod-web.lab.local:80:10.10.10.240 http://prod-web.lab.local/
```

Test HTTPS:

```bash
curl -k --resolve prod-web.lab.local:443:10.10.10.240 https://prod-web.lab.local/
```

## 15. Troubleshooting

## 15.1. Service LoadBalancer bị EXTERNAL-IP `<pending>`

Kiểm tra Service:

```bash
kubectl get svc -n ingress-nginx
```

Nếu thấy:

```text
EXTERNAL-IP   <pending>
```

Nguyên nhân thường gặp:

- MetalLB chưa cài.
- MetalLB chưa có `IPAddressPool`.
- MetalLB chưa có `L2Advertisement`.
- IP pool không hợp lệ.
- IP pool không cùng mạng Layer 2 với node.
- MetalLB controller lỗi.
- MetalLB speaker lỗi.
- Namespace `metallb-system` thiếu Pod Security label `privileged`.

Lệnh kiểm tra:

```bash
kubectl get pods -n metallb-system
kubectl get ipaddresspool -n metallb-system
kubectl get l2advertisement -n metallb-system
kubectl logs -n metallb-system deploy/metallb-controller
```

## 15.2. MetalLB cấp IP nhưng client không truy cập được

Kiểm tra:

```bash
kubectl get svc -n ingress-nginx
ping 10.10.10.240
curl -v http://10.10.10.240
```

Nguyên nhân thường gặp:

- Client không cùng mạng với IP pool.
- Firewall chặn.
- IP pool trùng với thiết bị khác.
- ARP cache bị cũ.
- Không có route đến subnet chứa IP pool.
- Ingress Controller chưa chạy.
- Service của Ingress Controller chưa có endpoint.

Kiểm tra endpoint:

```bash
kubectl get endpoints -n ingress-nginx
kubectl get endpointslice -n ingress-nginx
```

## 15.3. Truy cập domain bị lỗi DNS

Test bằng `curl --resolve` để loại trừ lỗi DNS:

```bash
curl --resolve web.lab.local:80:10.10.10.240 http://web.lab.local/
```

Nếu `curl --resolve` được nhưng browser không được, lỗi nằm ở DNS hoặc file hosts.

Kiểm tra từ client:

```bash
nslookup web.lab.local
ping web.lab.local
```

## 15.4. Ingress trả về 404

Ingress NGINX trả 404 thường do request không match rule.

Kiểm tra:

```bash
kubectl describe ingress -n lesson-06
```

Các lỗi thường gặp:

- Sai hostname.
- Client không gửi đúng Host header.
- Dùng IP trực tiếp thay vì domain.
- Sai `path`.
- Sai `ingressClassName`.
- Ingress không được controller nhận.

Test đúng Host header:

```bash
curl -H "Host: web.lab.local" http://10.10.10.240/
```

## 15.5. Ingress trả về 503

503 thường nghĩa là Ingress match rule nhưng backend không sẵn sàng.

Kiểm tra Service:

```bash
kubectl get svc -n lesson-06
kubectl describe svc lesson-06-web-svc -n lesson-06
```

Kiểm tra EndpointSlice:

```bash
kubectl get endpointslice -n lesson-06
```

Kiểm tra Pod label:

```bash
kubectl get pods -n lesson-06 --show-labels
```

Nguyên nhân thường gặp:

- Service selector không match label của Pod.
- Pod chưa Running.
- Pod không Ready.
- targetPort sai.
- Container không lắng nghe port tương ứng.

## 15.6. HTTPS báo lỗi certificate

Nếu dùng self-signed certificate, browser sẽ cảnh báo không tin cậy. Đây là bình thường trong lab.

Nếu dùng `curl`, thêm `-k`:

```bash
curl -k https://web.lab.local/
```

Nếu vẫn lỗi, kiểm tra:

```bash
kubectl get secret web-lab-local-tls -n lesson-06 -o yaml
kubectl describe ingress lesson-06-web-https -n lesson-06
openssl s_client -connect 10.10.10.240:443 -servername web.lab.local
```

Các lỗi thường gặp:

- Secret không cùng namespace với Ingress.
- Secret không đúng type `kubernetes.io/tls`.
- Certificate không có SAN đúng domain.
- Host trong `tls.hosts` không khớp host trong `rules`.
- Client truy cập bằng IP thay vì domain.

## 15.7. Helm install thất bại

Kiểm tra release:

```bash
helm list -A
helm status ingress-nginx -n ingress-nginx
helm status metallb -n metallb-system
```

Nếu release ở trạng thái failed:

```bash
helm uninstall ingress-nginx -n ingress-nginx
helm uninstall metallb -n metallb-system
```

Sau đó kiểm tra tài nguyên còn sót:

```bash
kubectl get all -n ingress-nginx
kubectl get all -n metallb-system
```

Với CRD của MetalLB, cần cẩn thận trước khi xóa trong môi trường production.

## 16. Các lệnh quan trọng cần nhớ

### Helm

```bash
helm version
helm repo add <name> <url>
helm repo update
helm search repo <keyword>
helm show values <chart>
helm upgrade --install <release> <chart> -n <namespace> --create-namespace
helm list -A
helm status <release> -n <namespace>
helm uninstall <release> -n <namespace>
```

### MetalLB

```bash
kubectl get pods -n metallb-system
kubectl get ipaddresspool -n metallb-system
kubectl get l2advertisement -n metallb-system
kubectl logs -n metallb-system deploy/metallb-controller
```

### Ingress NGINX

```bash
kubectl get pods -n ingress-nginx
kubectl get svc -n ingress-nginx
kubectl get ingressclass
kubectl logs -n ingress-nginx deploy/ingress-nginx-controller
```

### Ingress

```bash
kubectl get ingress -A
kubectl describe ingress <name> -n <namespace>
kubectl get svc -n <namespace>
kubectl get endpointslice -n <namespace>
```

### Test HTTP/HTTPS

```bash
curl -H "Host: web.lab.local" http://10.10.10.240/
curl --resolve web.lab.local:80:10.10.10.240 http://web.lab.local/
curl -k --resolve web.lab.local:443:10.10.10.240 https://web.lab.local/
openssl s_client -connect 10.10.10.240:443 -servername web.lab.local
```

## 17. Câu hỏi kiểm tra cuối buổi

### Câu 1

Helm dùng để làm gì trong Kubernetes?

Gợi ý trả lời:

Helm là package manager cho Kubernetes, giúp đóng gói, cài đặt, nâng cấp và gỡ bỏ các ứng dụng hoặc thành phần hạ tầng thông qua Helm Chart.

### Câu 2

Chart và Release khác nhau như thế nào?

Gợi ý trả lời:

Chart là gói template Kubernetes manifest. Release là một lần cài đặt cụ thể của chart vào cluster.

### Câu 3

Vì sao Service type `LoadBalancer` trên kubeadm on-premise thường bị `<pending>`?

Gợi ý trả lời:

Vì Kubernetes on-premise không tự có cloud provider hoặc cloud-controller-manager để cấp external load balancer. Cần một thành phần như MetalLB để cấp IP cho Service type `LoadBalancer`.

### Câu 4

MetalLB Controller và MetalLB Speaker khác nhau như thế nào?

Gợi ý trả lời:

Controller xử lý logic cấp phát IP cho Service type `LoadBalancer`. Speaker chạy trên node và quảng bá IP ra mạng, ví dụ trả lời ARP trong Layer 2 mode.

### Câu 5

Vì sao IP pool của MetalLB không nên trùng dải DHCP?

Gợi ý trả lời:

Nếu IP pool trùng DHCP, một IP có thể vừa được MetalLB cấp cho Service, vừa được DHCP cấp cho thiết bị khác, gây IP conflict và lỗi truy cập.

### Câu 6

Ingress là gì?

Gợi ý trả lời:

Ingress là Kubernetes API object dùng để định nghĩa rule HTTP/HTTPS routing từ bên ngoài cluster vào Service bên trong cluster.

### Câu 7

Vì sao chỉ tạo Ingress object là chưa đủ?

Gợi ý trả lời:

Ingress object chỉ là cấu hình. Cần Ingress Controller để đọc cấu hình đó và thực thi bằng reverse proxy/load balancer.

### Câu 8

`ingressClassName: nginx` có ý nghĩa gì?

Gợi ý trả lời:

Nó chỉ định Ingress object này sẽ được xử lý bởi Ingress Controller tương ứng với class `nginx`.

### Câu 9

HTTPS trong bài lab được terminate ở đâu?

Gợi ý trả lời:

HTTPS được terminate tại Ingress NGINX Controller. Traffic từ client đến Ingress Controller là HTTPS, còn traffic từ Ingress Controller đến backend Service trong lab là HTTP.

### Câu 10

Nếu Ingress trả về 503, nên kiểm tra những gì?

Gợi ý trả lời:

Cần kiểm tra Service selector, Pod label, Pod readiness, EndpointSlice, targetPort và trạng thái Pod backend.

## 18. Tổng kết buổi học

Sau buổi này,  đã biết cách đưa ứng dụng web ra ngoài cluster theo mô hình gần với thực tế hơn so với NodePort đơn thuần.

Các điểm cần nhớ:

- Helm giúp cài đặt các thành phần Kubernetes phức tạp một cách có cấu trúc.
- MetalLB giúp môi trường on-premise có khả năng cấp external IP cho Service type `LoadBalancer`.
- MetalLB Layer 2 mode phù hợp cho lab và môi trường nhỏ vì đơn giản, không cần BGP.
- Ingress là object định nghĩa rule HTTP/HTTPS routing.
- Ingress Controller là thành phần thực thi các rule đó.
- Ingress NGINX Controller có thể expose ra ngoài thông qua Service type `LoadBalancer`.
- Trong lab on-premise, IP của Service type `LoadBalancer` được cấp bởi MetalLB.
- Một IP Ingress có thể phục vụ nhiều ứng dụng web khác nhau dựa trên hostname hoặc path.
- TLS Secret cho phép Ingress Controller terminate HTTPS.
- Khi troubleshoot Ingress, cần đi theo chuỗi:
  - DNS/Host header.
  - MetalLB external IP.
  - Ingress NGINX Service.
  - Ingress rule.
  - Backend Service.
  - EndpointSlice.
  - Pod backend.

## 19. Dọn dẹp tài nguyên lab

Nếu muốn xóa ứng dụng lab:

```bash
kubectl delete namespace lesson-06
kubectl delete namespace production-web
```

Nếu muốn gỡ Ingress NGINX Controller:

```bash
helm uninstall ingress-nginx -n ingress-nginx
kubectl delete namespace ingress-nginx
```

Nếu muốn gỡ MetalLB:

```bash
helm uninstall metallb -n metallb-system
kubectl delete -f metallb-l2-pool.yaml
kubectl delete namespace metallb-system
```

Lưu ý: Trong môi trường production, không xóa MetalLB hoặc Ingress Controller nếu còn Service/Ingress đang sử dụng.

## 20. Tài liệu tham khảo chính thức

- Kubernetes v1.35 Documentation - Ingress  
  https://v1-35.docs.kubernetes.io/docs/concepts/services-networking/ingress/

- Kubernetes v1.35 Documentation - Ingress Controllers  
  https://v1-35.docs.kubernetes.io/docs/concepts/services-networking/ingress-controllers/

- Helm Documentation - Installing Helm  
  https://helm.sh/docs/intro/install/

- Helm Documentation - Quickstart Guide  
  https://helm.sh/docs/intro/quickstart/

- MetalLB Documentation - Installation  
  https://metallb.io/installation/

- MetalLB Documentation - Configuration  
  https://metallb.io/configuration/

- Ingress NGINX Controller Documentation - Installation Guide  
  https://kubernetes.github.io/ingress-nginx/deploy/

- Ingress NGINX Controller Documentation - Bare-metal considerations  
  https://kubernetes.github.io/ingress-nginx/deploy/baremetal/
