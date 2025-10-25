## DEPLOY METALLB
---
> Deploy MetalLB
```shell
kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/refs/heads/main/config/manifests/metallb-native.yaml
```

```shell
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: metallb-pool
  namespace: metallb-system
spec:
  addresses:
  - 10.20.30.200-10.20.30.210  # Dải IP được chọn
---
apiVersion: metallb.io/v1beta1
kind: L2Advertisement
metadata:
  name: l2-advertisement
  namespace: metallb-system
spec: {}
```
```shell
kubectl apply -f metallb-config.yaml
```

> Setup NGINX ingress by Helm
```shell
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo update
helm install ingress-nginx ingress-nginx/ingress-nginx --namespace ingress-nginx --create-namespace
```

> Check Ingress Controller running
```shell
kubectl get pods -n ingress-nginx
```

> Create Deployment (`app.yaml`)
```shell
apiVersion: apps/v1
kind: Deployment
metadata:
  name: demo-app
spec:
  replicas: 2
  selector:
    matchLabels:
      app: demo
  template:
    metadata:
      labels:
        app: demo
    spec:
      containers:
      - name: demo
        image: hashicorp/http-echo:0.2.3
        args:
        - "-text=Hello from Demo App"
        ports:
        - containerPort: 5678
---
apiVersion: v1
kind: Service
metadata:
  name: demo-service
spec:
  selector:
    app: demo
  ports:
  - protocol: TCP
    port: 80
    targetPort: 5678
  type: ClusterIP
```
```shell
kubectl apply -f app.yaml
```

> Create Ingress Resource (`ingress.yaml`):
```shell
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: demo-ingress
  annotations:
    nginx.ingress.kubernetes.io/rewrite-target: /
spec:
  ingressClassName: nginx
  rules:
  - host: demo.local
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: demo-service
            port:
              number: 80
```
