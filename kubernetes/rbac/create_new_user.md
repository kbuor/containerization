# Hướng dẫn tạo User mới và file kubeconfig riêng trong Kubernetes

## Mục tiêu
Tạo một user mới trong cụm Kubernetes sử dụng **x509 client certificate** để xác thực, đồng thời tạo file **kubeconfig** riêng cho user đó nhằm truy cập cụm với quyền hạn được phân định rõ.

---

## Chuẩn bị
- Có quyền `admin` hoặc `cluster-admin` trên cụm Kubernetes.
- Đã cài công cụ `kubectl` và `openssl`.

---

## Bước 1: Tạo private key cho user

Ví dụ tạo user tên `devuser`:

```bash
mkdir -p ~/certs/devuser
cd ~/certs/devuser

openssl genrsa -out devuser.key 2048
```

---

## Bước 2: Tạo Certificate Signing Request (CSR)

```bash
openssl req -new -key devuser.key -out devuser.csr -subj "/CN=devuser/O=developer"
```

- `CN`: Common Name (tên user)
- `O`: Group (tên nhóm người dùng trong RBAC)

---

## Bước 3: Ký chứng chỉ cho user bằng CA của cụm Kubernetes

> CA file thường nằm ở `/etc/kubernetes/pki/ca.crt` và key tương ứng là `/etc/kubernetes/pki/ca.key`

```bash
sudo openssl x509 -req -in devuser.csr   -CA /etc/kubernetes/pki/ca.crt   -CAkey /etc/kubernetes/pki/ca.key   -CAcreateserial   -out devuser.crt -days 365
```

---

## Bước 4: Kiểm tra chứng chỉ

```bash
openssl x509 -in devuser.crt -text -noout
```

---

## Bước 5: Tạo kubeconfig cho user

```bash
kubectl config set-cluster k8s-cluster   --certificate-authority=/etc/kubernetes/pki/ca.crt   --embed-certs=true   --server=https://<API-SERVER-IP>:6443   --kubeconfig=devuser.kubeconfig

kubectl config set-credentials devuser   --client-certificate=devuser.crt   --client-key=devuser.key   --embed-certs=true   --kubeconfig=devuser.kubeconfig

kubectl config set-context devuser@k8s-cluster   --cluster=k8s-cluster   --user=devuser   --kubeconfig=devuser.kubeconfig

kubectl config use-context devuser@k8s-cluster --kubeconfig=devuser.kubeconfig
```

> File `devuser.kubeconfig` là file cấu hình để user sử dụng với `kubectl`.

---

## Bước 6: Tạo Role hoặc ClusterRole và RoleBinding/ClusterRoleBinding

Ví dụ cấp quyền xem tài nguyên trong namespace `dev`:

```bash
kubectl create namespace dev

kubectl create role dev-viewer   --verb=get,list,watch   --resource=pods,deployments,services   -n dev

kubectl create rolebinding devuser-viewer-binding   --role=dev-viewer   --user=devuser   -n dev
```

---

## Bước 7: Kiểm tra quyền truy cập của user

```bash
kubectl --kubeconfig=devuser.kubeconfig get pods -n dev
```

Nếu hiển thị được danh sách `pods` thì user đã được cấp quyền chính xác.

---

## Ghi chú

- Nếu muốn user có quyền toàn cụm, sử dụng `ClusterRole` và `ClusterRoleBinding`.
- Có thể thêm nhiều group trong CSR để quản lý RBAC theo nhóm.
- File `devuser.kubeconfig` có thể gửi cho user để dùng trực tiếp với `kubectl` hoặc các client như Lens, Rancher Desktop,...

---

## Cleanup (Xóa user)

```bash
rm -rf ~/certs/devuser
kubectl delete rolebinding devuser-viewer-binding -n dev
kubectl delete role dev-viewer -n dev
```

---

## Tham khảo

- [Kubernetes RBAC Authorization](https://kubernetes.io/docs/reference/access-authn-authz/rbac/)
- [Managing kubeconfig Files](https://kubernetes.io/docs/concepts/configuration/organize-cluster-access-kubeconfig/)
