# Kubernetes Dashboard Deployment (Production Setup)

This guide describes how to deploy the **Kubernetes Dashboard** on a production-grade cluster using your **commercial SSL certificate** (not self-signed), and expose it at **https://eoh-k8s.tpcloud.vn**.

---

## 0) Prerequisites

- A running Kubernetes cluster with Ingress controller (NGINX preferred).
- A valid DNS record:
  - `eoh-k8s.tpcloud.vn → 200.64.129.200`
- A commercial SSL certificate consisting of:
  - `fullchain.pem`
  - `privkey.pem`

---

## 1) Create Namespace & Secret for TLS

```bash
kubectl create namespace kubernetes-dashboard

kubectl -n kubernetes-dashboard create secret tls kubedash-tls   --cert=fullchain.pem   --key=privkey.pem
```

---

## 2) Install Kubernetes Dashboard using Helm

Add the official Helm repository and install the chart with custom values.

```bash
helm repo add kubernetes-dashboard https://kubernetes.github.io/dashboard/
helm repo update

cat > values-dashboard.yaml <<'EOF'
app:
  ingress:
    enabled: true
    ingressClassName: nginx
    hosts:
      - eoh-k8s.tpcloud.vn
    tls:
      enabled: true
      secretName: kubedash-tls
EOF

helm upgrade --install kubernetes-dashboard   kubernetes-dashboard/kubernetes-dashboard   --namespace kubernetes-dashboard   -f values-dashboard.yaml
```

> 🛈 Dashboard v7.x and above supports Helm installation only. The Ingress terminates TLS and routes traffic to the internal Dashboard service.

---

## 3) Create User Accounts and Tokens

### Viewer (Recommended for Daily Operations)

```bash
kubectl -n kubernetes-dashboard create serviceaccount viewer
kubectl create clusterrolebinding dashboard-view   --clusterrole=view   --serviceaccount=kubernetes-dashboard:viewer
kubectl -n kubernetes-dashboard create token viewer --duration=30m
```

### Admin (Temporary Full Access)

```bash
kubectl -n kubernetes-dashboard create serviceaccount admin-user
kubectl create clusterrolebinding admin-user-binding   --clusterrole=cluster-admin   --serviceaccount=kubernetes-dashboard:admin-user
kubectl -n kubernetes-dashboard create token admin-user --duration=10m
```

---

## 4) Verify Deployment

```bash
kubectl -n kubernetes-dashboard get pods -o wide
kubectl -n kubernetes-dashboard get svc,ingress -o wide
kubectl -n ingress-nginx get svc ingress-nginx-controller -o wide
```

Access the Dashboard via:
👉 **https://eoh-k8s.tpcloud.vn**  
Sign in using the token generated above.

---

## 5) Security & Hardening Recommendations

- **Use RBAC minimum privilege:** Viewer for normal users, admin only when needed.
- **Short-lived tokens:** Always set `--duration` for token expiration.
- **Certificate chain:** Ensure your `fullchain.pem` includes intermediate CAs.
- **Ingress security:** Add security headers (HSTS, X-Frame-Options, etc.) at the Ingress Controller.

---

## 6) Troubleshooting

| Issue | Cause | Solution |
|-------|--------|-----------|
| 404 / “No resources found” | Wrong ingress class or namespace | Verify `ingressClassName: nginx` and namespace `kubernetes-dashboard` |
| 502 / 504 Gateway Timeout | Pod not Ready | Check pod status with `kubectl get pods` |
| TLS Error | Missing intermediate cert | Use `fullchain.pem` with full chain |
| Invalid Token | Token expired | Recreate token with `kubectl create token ... --duration=...` |

---

## 7) Optional – Install NGINX Ingress (If Missing)

```bash
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo update
helm upgrade --install ingress-nginx ingress-nginx/ingress-nginx   --namespace ingress-nginx --create-namespace
```

For bare-metal environments, expose via **MetalLB** or **NodePort**.

---

✅ **You now have a fully functional, SSL-secured Kubernetes Dashboard accessible at:**
**https://eoh-k8s.tpcloud.vn**
