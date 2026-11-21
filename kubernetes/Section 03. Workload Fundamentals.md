# Buổi 03 - Kubernetes Workloads: Pod, Deployment, DaemonSet, StatefulSet, Job và CronJob

## 1. Mục tiêu buổi học

Sau khi đã dựng cluster ở buổi 02, câu hỏi tiếp theo là: **chạy một ứng dụng hoặc tác vụ trên Kubernetes bằng cách nào?**

Sau buổi này, học viên có thể:

- Giải thích Pod và phân biệt Pod đơn lẻ với Pod có nhiều container.
- Hiểu cách Deployment duy trì số lượng Pod thông qua ReplicaSet.
- Nhận biết khi nào dùng DaemonSet, StatefulSet, Job và CronJob.
- Đọc, viết manifest cơ bản và kiểm tra workload bằng `kubectl`.
- Quan sát điều gì xảy ra khi xóa Pod do một controller quản lý.

Bài học tập trung vào **tạo và quan sát workload**. Mỗi manifest chỉ giữ những trường cần cho ví dụ chạy và thể hiện đặc trưng của workload. Những phần về kết nối ứng dụng, lưu trữ và cấu hình vận hành sẽ học ở các buổi sau.

## 2. Môi trường lab

Giả định đã có cluster Kubernetes dựng bằng `kubeadm` với một control plane, hai worker node, `containerd` và Calico. Tên node và phiên bản hiển thị trên máy của học viên có thể khác ví dụ.

Kiểm tra cluster:

```bash
kubectl get nodes -o wide
```

Các node dùng cho lab cần ở trạng thái `Ready`. Tạo thư mục làm việc:

```bash
mkdir -p ~/k8s-course/buoi-03-workloads
cd ~/k8s-course/buoi-03-workloads
```

Tạo namespace riêng cho bài lab:

```bash
cat <<'EOF_NAMESPACE' > 00-namespace.yaml
apiVersion: v1
kind: Namespace
metadata:
  name: lab-workloads
EOF_NAMESPACE
kubectl apply -f 00-namespace.yaml
kubectl get namespace lab-workloads
```

Tất cả workload trong bài dùng namespace `lab-workloads`. Các manifest được tạo lần lượt ở từng phần bên dưới.

## 3. Workload, Pod và trạng thái mong muốn

**Workload** là ứng dụng hoặc tác vụ chạy trên cluster. Ví dụ: web chạy liên tục, agent chạy trên các node, chương trình xử lý chạy một lần, hoặc công việc chạy theo lịch.

**Pod** là đơn vị chạy nhỏ nhất trong Kubernetes. Một Pod chứa một hoặc nhiều container. Các container trong cùng Pod chạy trên cùng node và chia sẻ môi trường mạng của Pod.

Khi tạo Pod trực tiếp, ta có một Pod cụ thể. Khi tạo Deployment với ba bản sao, ta khai báo **trạng thái mong muốn** là ba Pod. Controller quan sát số Pod hiện có và tạo thêm nếu thiếu. Nếu một Pod do Deployment quản lý bị xóa, một Pod khác sẽ thay thế nó.

> Pod có thể bị thay thế. Với ứng dụng cần duy trì liên tục, hãy dùng controller phù hợp thay vì chỉ tạo một Pod trực tiếp.

## 4. Label, selector và Pod template

**Label** là cặp khóa và giá trị gắn với object. Ví dụ:

```yaml
metadata:
  labels:
    app: deploy-web
```

**Selector** chọn các Pod theo label:

```yaml
selector:
  matchLabels:
    app: deploy-web
```

Trong Deployment, DaemonSet và StatefulSet, selector phải khớp với label của **Pod template**:

```yaml
selector:
  matchLabels:
    app: deploy-web
template:
  metadata:
    labels:
      app: deploy-web
```

Pod template là khuôn mẫu để controller tạo Pod. Mỗi ví dụ trong bài dùng một giá trị `app` khác nhau để dễ quan sát và tránh các controller chọn trùng Pod.

## 5. Pod đơn lẻ

### 5.1. Tạo Pod

Pod đơn lẻ giúp thấy cách Kubernetes chạy một container. Manifest sau chỉ cần tên Pod, namespace, tên container và image:

```bash
cat <<'EOF_POD' > 01-pod-single-container.yaml
apiVersion: v1
kind: Pod
metadata:
  name: single-nginx
  namespace: lab-workloads
spec:
  containers:
    - name: nginx
      image: nginx:1.27-alpine
EOF_POD
kubectl apply -f 01-pod-single-container.yaml
```

Kiểm tra:

```bash
kubectl get pod single-nginx -n lab-workloads
kubectl describe pod single-nginx -n lab-workloads
kubectl logs single-nginx -n lab-workloads
```

`apiVersion` và `kind` xác định loại object. `metadata` đặt tên và namespace. `spec.containers` mô tả container sẽ chạy; `image` chỉ image cần kéo về.

### 5.2. Xóa Pod

```bash
kubectl delete pod single-nginx -n lab-workloads
kubectl get pod single-nginx -n lab-workloads
```

Lệnh kiểm tra sẽ báo không còn Pod tên `single-nginx`. Pod tạo trực tiếp không có controller để tạo lại sau khi bị xóa. Không cần tạo lại Pod này để làm các phần tiếp theo.

## 6. Pod có nhiều container

Một Pod có thể chứa nhiều container khi chúng cần chạy cùng nhau trong một đơn vị ứng dụng. Ở ví dụ này, `web` chạy nginx, còn `helper` ghi một dòng trạng thái vào log theo chu kỳ. Hai container có cùng vòng đời Pod. Ví dụ chỉ minh họa cấu trúc Pod nhiều container, chưa cấu hình để chúng trao đổi dữ liệu.

```bash
cat <<'EOF_MULTI' > 02-pod-multi-container.yaml
apiVersion: v1
kind: Pod
metadata:
  name: multi-container-web
  namespace: lab-workloads
spec:
  containers:
    - name: web
      image: nginx:1.27-alpine
    - name: helper
      image: busybox:1.36
      command: ["/bin/sh", "-c", "while true; do echo helper-is-running; sleep 10; done"]
EOF_MULTI
kubectl apply -f 02-pod-multi-container.yaml
```

Kiểm tra hai container trong cùng Pod:

```bash
kubectl get pod multi-container-web -n lab-workloads
kubectl describe pod multi-container-web -n lab-workloads
kubectl logs multi-container-web -n lab-workloads -c helper
```

Với Pod có nhiều container, tham số `-c` chỉ định container cần xem log. Trường `command` cho container `helper` chạy vòng lặp để nó không kết thúc ngay sau khi in log.

> Không gom các ứng dụng độc lập vào cùng Pod chỉ để giảm số manifest. Một web frontend và một database thường cần vòng đời riêng.

## 7. Deployment và ReplicaSet

### 7.1. Deployment làm gì?

Deployment phù hợp với ứng dụng chạy liên tục có thể tạo nhiều bản sao, chẳng hạn web hoặc API không phụ thuộc vào danh tính của từng Pod.

Khi tạo Deployment, Kubernetes tạo một **ReplicaSet** bên dưới; ReplicaSet duy trì số Pod theo số lượng Deployment yêu cầu. Ta tạo và chỉnh **Deployment**, không cần viết manifest ReplicaSet riêng trong bài này.

```text
Deployment → ReplicaSet → các Pod
```

Một Pod bị xóa không nhất thiết được khôi phục với cùng tên. Điều được duy trì là **số lượng Pod mong muốn**.

### 7.2. Tạo Deployment

```bash
cat <<'EOF_DEPLOY' > 03-deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: deploy-web
  namespace: lab-workloads
spec:
  replicas: 3
  selector:
    matchLabels:
      app: deploy-web
  template:
    metadata:
      labels:
        app: deploy-web
    spec:
      containers:
        - name: nginx
          image: nginx:1.27-alpine
EOF_DEPLOY
kubectl apply -f 03-deployment.yaml
```

`replicas: 3` đặt số Pod mong muốn. `selector` và label trong `template` cùng dùng `app: deploy-web`. `template.spec.containers` mô tả container của mỗi Pod được tạo ra.

Quan sát:

```bash
kubectl get deployment deploy-web -n lab-workloads
kubectl get rs -n lab-workloads
kubectl get pods -n lab-workloads -l app=deploy-web -o wide
```

Đầu ra cho thấy một Deployment, ReplicaSet do nó tạo và ba Pod. Đây là toàn bộ phần ReplicaSet cần nắm ở buổi này: nó là cơ chế duy trì các bản sao của Deployment.

### 7.3. Xóa một Pod và quan sát

Lấy tên một Pod của Deployment từ lệnh `kubectl get pods` ở trên, sau đó thay vào lệnh:

```bash
kubectl delete pod <ten-pod-deploy-web> -n lab-workloads
kubectl get pods -n lab-workloads -l app=deploy-web -w
```

Một Pod mới sẽ xuất hiện để số Pod quay về ba. Dừng lệnh theo dõi bằng `Ctrl + C`.

### 7.4. Thay đổi số bản sao

```bash
kubectl scale deployment deploy-web -n lab-workloads --replicas=5
kubectl get pods -n lab-workloads -l app=deploy-web -o wide
```

Có thể có nhiều Pod trên cùng một worker node; năm bản sao không có nghĩa là phải có năm node. Đưa về số lượng ban đầu:

```bash
kubectl scale deployment deploy-web -n lab-workloads --replicas=3
```

Lệnh `scale` thay đổi object đang chạy. Nếu sau đó áp dụng lại file `03-deployment.yaml`, giá trị khai báo trong file là `replicas: 3`.

## 8. DaemonSet

DaemonSet tạo một Pod trên **mỗi node phù hợp**. Ví dụ sử dụng: agent thu thập log hoặc giám sát node. Khác Deployment, DaemonSet không đặt số bản sao trong manifest; số Pod phụ thuộc vào số node phù hợp.

```bash
cat <<'EOF_DAEMON' > 04-daemonset.yaml
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: ds-node-agent
  namespace: lab-workloads
spec:
  selector:
    matchLabels:
      app: ds-node-agent
  template:
    metadata:
      labels:
        app: ds-node-agent
    spec:
      containers:
        - name: node-agent
          image: busybox:1.36
          command: ["/bin/sh", "-c", "while true; do echo agent-is-running; sleep 30; done"]
EOF_DAEMON
kubectl apply -f 04-daemonset.yaml
```

Kiểm tra Pod và node được chọn:

```bash
kubectl get daemonset ds-node-agent -n lab-workloads
kubectl get pods -n lab-workloads -l app=ds-node-agent -o wide
kubectl logs -n lab-workloads -l app=ds-node-agent --tail=10
```

Với cluster một control plane và hai worker, thường sẽ thấy Pod trên hai worker. Control plane có thể không nhận Pod lab do cấu hình mặc định của cluster. Nếu bổ sung một worker phù hợp, DaemonSet sẽ tạo Pod trên worker đó.

## 9. StatefulSet

StatefulSet phù hợp với ứng dụng cần **danh tính Pod ổn định**. Ví dụ với hai bản sao, tên Pod sẽ là `sts-web-0` và `sts-web-1`. Nếu `sts-web-0` bị xóa, StatefulSet tạo lại Pod có cùng tên.

Ví dụ này dùng nginx để quan sát tên Pod; nó **không** tạo database cluster hay lưu dữ liệu bền vững. StatefulSet cần một Service quản lý danh tính mạng. File dưới đây tạo Service tối thiểu và StatefulSet; phần truy cập ứng dụng qua Service sẽ học ở buổi sau.

```bash
cat <<'EOF_STATEFUL' > 05-statefulset.yaml
apiVersion: v1
kind: Service
metadata:
  name: sts-web-headless
  namespace: lab-workloads
spec:
  clusterIP: None
  selector:
    app: sts-web
  ports:
    - port: 80
---
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: sts-web
  namespace: lab-workloads
spec:
  serviceName: sts-web-headless
  replicas: 2
  selector:
    matchLabels:
      app: sts-web
  template:
    metadata:
      labels:
        app: sts-web
    spec:
      containers:
        - name: nginx
          image: nginx:1.27-alpine
EOF_STATEFUL
kubectl apply -f 05-statefulset.yaml
```

`serviceName` trỏ tới Service được tạo ở đầu file. `clusterIP: None` đặt Service ở dạng headless. Các trường đó có mặt để ví dụ StatefulSet có Service quản lý danh tính; chưa cần tìm hiểu cơ chế Service trong buổi này.

Kiểm tra:

```bash
kubectl get statefulset sts-web -n lab-workloads
kubectl get pods -n lab-workloads -l app=sts-web
```

Xóa Pod đầu tiên rồi quan sát:

```bash
kubectl delete pod sts-web-0 -n lab-workloads
kubectl get pods -n lab-workloads -l app=sts-web -w
```

Sau khi Pod mới chạy, tên `sts-web-0` xuất hiện lại. Dừng lệnh theo dõi bằng `Ctrl + C`.

> Tên Pod ổn định không có nghĩa dữ liệu trong container được giữ lại. Lưu trữ bền vững là nội dung của buổi khác.

## 10. Job

Job dùng cho một tác vụ **chạy đến khi hoàn tất**, chẳng hạn xử lý dữ liệu một lần. Ví dụ sau in log rồi kết thúc:

```bash
cat <<'EOF_JOB' > 06-job.yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: job-hello
  namespace: lab-workloads
spec:
  template:
    spec:
      restartPolicy: Never
      containers:
        - name: hello
          image: busybox:1.36
          command: ["/bin/sh", "-c", "echo Job completed"]
EOF_JOB
kubectl apply -f 06-job.yaml
```

Với Job, `template` mô tả Pod chạy tác vụ. `restartPolicy: Never` là giá trị hợp lệ để Pod kết thúc sau khi lệnh hoàn tất; Job không dùng giá trị mặc định `Always` như các ví dụ chạy liên tục.

Kiểm tra:

```bash
kubectl get job job-hello -n lab-workloads
kubectl get pods -n lab-workloads
kubectl logs job/job-hello -n lab-workloads
```

Sau khi hoàn tất, Job có trạng thái `Complete`; Pod của nó có thể hiển thị `Completed`. Job phù hợp với chương trình có điểm kết thúc, không phải web server chạy liên tục.

## 11. CronJob

CronJob tạo Job theo một lịch. Ví dụ này chạy mỗi phút để dễ quan sát trong lab:

```bash
cat <<'EOF_CRON' > 07-cronjob.yaml
apiVersion: batch/v1
kind: CronJob
metadata:
  name: cronjob-hello
  namespace: lab-workloads
spec:
  schedule: "* * * * *"
  jobTemplate:
    spec:
      template:
        spec:
          restartPolicy: Never
          containers:
            - name: hello
              image: busybox:1.36
              command: ["/bin/sh", "-c", "echo CronJob completed"]
EOF_CRON
kubectl apply -f 07-cronjob.yaml
```

Năm vị trí trong lịch lần lượt là **phút, giờ, ngày trong tháng, tháng, ngày trong tuần**. Dấu `*` ở mọi vị trí nghĩa là mỗi phút. `jobTemplate` là khuôn mẫu của Job mà CronJob sẽ tạo; Job lại tạo Pod.

```text
CronJob → Job → Pod
```

Quan sát sau khoảng một đến hai phút:

```bash
kubectl get cronjob cronjob-hello -n lab-workloads
kubectl get jobs -n lab-workloads
kubectl get pods -n lab-workloads
```

Lấy tên một Job do CronJob tạo trong đầu ra, rồi xem log:

```bash
kubectl logs job/<ten-job-do-cronjob-tao> -n lab-workloads
```

Các Job và Pod được tạo theo lịch sẽ tiếp tục xuất hiện cho đến khi dọn lab. Lịch một phút chỉ dùng để quan sát nhanh.

## 12. Chọn workload phù hợp

| Loại | Mục đích chính | Điều cần quan sát trong lab |
|---|---|---|
| Pod trực tiếp | Chạy thử một hoặc nhiều container | Xóa Pod thì không tự tạo lại |
| Deployment | Chạy ứng dụng liên tục với số bản sao mong muốn | ReplicaSet bên dưới tạo Pod thay thế |
| DaemonSet | Chạy agent trên các node phù hợp | Pod xuất hiện theo node |
| StatefulSet | Chạy Pod có danh tính ổn định | Pod được tạo lại với cùng tên |
| Job | Chạy tác vụ đến khi hoàn tất | Job và Pod hoàn thành |
| CronJob | Chạy Job theo lịch | Job mới xuất hiện theo lịch |

ReplicaSet được quan sát **trong phần Deployment**, không cần chọn hoặc tạo riêng cho các ví dụ của buổi này.

## 13. Bài thực hành tổng hợp

Các phần trên đã tạo đầy đủ manifest. Thực hành lại theo thứ tự và tự trả lời câu hỏi ở mỗi bước:

1. Tạo namespace và Pod đơn lẻ. Xóa Pod: nó có quay lại không?
2. Tạo Pod hai container. Dùng `kubectl logs -c helper` để xem đúng container.
3. Tạo Deployment. Tìm ReplicaSet và ba Pod. Xóa một Pod: có Pod thay thế không?
4. Tăng Deployment lên năm Pod. Chúng có bắt buộc nằm trên năm node khác nhau không?
5. Tạo DaemonSet. So sánh số Pod với số node phù hợp.
6. Tạo StatefulSet. Xóa `sts-web-0`: tên Pod tạo lại là gì?
7. Tạo Job. Quan sát `Complete` và xem log.
8. Tạo CronJob. Quan sát một Job do lịch tạo ra.

Xem nhanh các workload trong namespace:

```bash
kubectl get pods,deployments,replicasets,daemonsets,statefulsets,jobs,cronjobs -n lab-workloads
```

Nếu một Pod chưa chạy, kiểm tra tình trạng và sự kiện:

```bash
kubectl describe pod <ten-pod> -n lab-workloads
kubectl get events -n lab-workloads --sort-by=.lastTimestamp
```

Khi kết thúc, xóa namespace để dọn toàn bộ lab, gồm cả các Job do CronJob tạo:

```bash
kubectl delete namespace lab-workloads
```

Các file YAML vẫn nằm trong thư mục lab để dùng lại sau này.

## 14. Câu hỏi kiểm tra cuối buổi

**1. Pod đơn lẻ khác Pod do Deployment tạo ở điểm nào khi bị xóa?**  
Pod đơn lẻ không tự quay lại; Pod do Deployment quản lý sẽ có Pod khác thay thế để duy trì số lượng mong muốn.

**2. ReplicaSet nằm ở đâu trong ví dụ của buổi học?**  
Deployment tạo ReplicaSet; ReplicaSet tạo và duy trì các Pod. Bài học không tạo ReplicaSet riêng.

**3. Vì sao selector và label trong Pod template phải khớp?**  
Controller dựa vào selector để xác định nhóm Pod cần quản lý.

**4. Deployment có năm bản sao trên cluster hai worker được không?**  
Có thể, nếu cluster đáp ứng điều kiện chạy. Một node có thể chứa nhiều Pod.

**5. DaemonSet khác Deployment về cách quyết định số Pod như thế nào?**  
DaemonSet chạy theo số node phù hợp; Deployment dùng số bản sao mong muốn.

**6. StatefulSet minh họa điều gì khi xóa `sts-web-0`?**  
Pod được tạo lại với tên `sts-web-0`. Điều này minh họa danh tính ổn định, không chứng minh dữ liệu được lưu bền vững.

**7. Job và CronJob khác nhau ra sao?**  
Job chạy một tác vụ đến khi hoàn tất; CronJob tạo Job theo lịch.

**8. Vì sao manifest Job khai báo `restartPolicy: Never`?**  
Pod của Job cần một chính sách khởi động lại hợp lệ để có thể kết thúc sau khi lệnh chạy xong.

## 15. Tổng kết và buổi tiếp theo

Pod chứa container. Deployment duy trì số Pod thông qua ReplicaSet. DaemonSet chạy Pod theo node; StatefulSet giữ danh tính Pod; Job chạy đến khi hoàn tất; CronJob tạo Job theo lịch.

Sau khi biết cách chạy workload, buổi tiếp theo sẽ học **Service và cách các ứng dụng truy cập nhau trong Kubernetes**.

## 16. Nguồn tham khảo chính thức

- Kubernetes - Workloads: https://kubernetes.io/docs/concepts/workloads/
- Kubernetes - Pods: https://kubernetes.io/docs/concepts/workloads/pods/
- Kubernetes - Deployment và ReplicaSet: https://kubernetes.io/docs/concepts/workloads/controllers/deployment/
- Kubernetes - DaemonSet: https://kubernetes.io/docs/concepts/workloads/controllers/daemonset/
- Kubernetes - StatefulSet: https://kubernetes.io/docs/concepts/workloads/controllers/statefulset/
- Kubernetes - Job: https://kubernetes.io/docs/concepts/workloads/controllers/job/
- Kubernetes - CronJob: https://kubernetes.io/docs/concepts/workloads/controllers/cron-jobs/
