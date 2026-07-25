Bước 1: Tạo Private Key và Certificate Signing Request (CSR)
Đầu tiên, bạn tạo một private key cho user mới (ví dụ user tên là devops-user) và một file yêu cầu ký chứng chỉ (csr).

Bash
# 1. Tạo private key cho user
openssl genrsa -out devops-user.key 2048

# 2. Tạo CSR (Lưu ý: Thay đổi CN=tên_user và O=tên_group theo ý muốn)
openssl req -new -key devops-user.key -out devops-user.csr -subj "/CN=devops-user/O=my-company:developers"
Bước 2: Ký CSR bằng Kubernetes CA (Cluster Certificate Authority)
Bạn cần gửi file CSR này lên cụm Kubernetes để CA của cluster ký và cấp phát chứng chỉ.

Tạo một đối tượng CertificateSigningRequest trong Kubernetes (YAML):

YAML
apiVersion: certificates.k8s.io/v1
kind: CertificateSigningRequest
metadata:
  name: devops-user-csr
spec:
  request: $(cat devops-user.csr | base64 | tr -d "\n")
  signerName: kubernetes.io/kube-apiserver-client
  expirationSeconds: 31536000 # Thời hạn 1 năm
  usages:
  - client auth
Hoặc chạy trực tiếp lệnh tạo nhanh:

Bash
cat <<EOF | kubectl apply -f -
apiVersion: certificates.k8s.io/v1
kind: CertificateSigningRequest
metadata:
name: devops-user-csr

spec:
request: $(base64 < devops-user.csr | tr -d "\n")
signerName: kubernetes.io/kube-apiserver-client
usages:

client auth
EOF

Phê duyệt (Approve) CSR từ phía cluster admin:

Bash
kubectl certificate approve devops-user-csr
Trích xuất chứng chỉ (crt) đã được ký trả về từ cluster:

Bash
kubectl get csr devops-user-csr -o jsonpath='{.status.certificate}' | base64 --decode > devops-user.crt
Bước 3: Phân quyền cho User (RBAC)
Mặc định user mới tạo chưa có quyền làm gì trên cluster cả. Bạn cần gán quyền thông qua Role (hoặc ClusterRole) và RoleBinding (hoặc ClusterBinding).

Ví dụ tạo quyền read-only trên namespace default:

YAML
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  namespace: default
  name: pod-reader
rules:
- apiGroups: [""]
  resources: ["pods"]
  verbs: ["get", "watch", "list"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: read-pods-global
  namespace: default
subjects:
- kind: User
  name: devops-user # Phải trùng với Common Name (CN) ở Bước 1
  apiGroup: rbac.authorization.k8s.io
roleRef:
  kind: Role
  name: pod-reader
  apiGroup: rbac.authorization.k8s.io
Lưu file trên thành rbac.yaml rồi chạy lệnh: kubectl apply -f rbac.yaml

Bước 4: Tạo file Kubeconfig cho User
Bây giờ, bạn gom thông tin Cluster CA, Client Key, Client Certificate và thông tin Cluster Endpoint lại để tạo file cấu hình kubeconfig riêng cho user đó.

Lấy thông tin cluster hiện tại (địa chỉ API Server và CA Data):

Bash
# Lấy API server endpoint
CLUSTER_SERVER=$(kubectl config view --minify -o jsonpath='{.clusters[0].cluster.server}')

# Lấy Cluster CA (base64)
CLUSTER_CA=$(kubectl config view --raw --minify -o jsonpath='{.clusters[0].cluster.certificate-authority-data}')
Tạo file kubeconfig-devops-user.yaml hoàn chỉnh:

YAML
apiVersion: v1
kind: Config
clusters:
- cluster:
    certificate-authority-data: ${CLUSTER_CA}
    server: ${CLUSTER_SERVER}
  name: my-cluster
contexts:
- context:
    cluster: my-cluster
    user: devops-user
  name: devops-user-context
current-context: devops-user-context
users:
- name: devops-user
  user:
    client-certificate-data: $(base64 < devops-user.crt | tr -d '\n')
    client-key-data: $(base64 < devops-user.key | tr -d '\n')
Bạn có thể thay thế các biến ${...} bằng chuỗi base64 thực tế hoặc viết script nhỏ để sinh file tự động cho nhanh nhé!
