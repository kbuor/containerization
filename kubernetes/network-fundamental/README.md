# Investigating k8s networking

> Get all Nodes and their IP information, INTERNAL-IP is the real IP of the Node

```shell
kubectl get nodes -o wide

NAME          STATUS   ROLES           AGE   VERSION   INTERNAL-IP   EXTERNAL-IP   OS-IMAGE             KERNEL-VERSION      CONTAINER-RUNTIME
k8s-master    Ready    control-plane   8d    v1.27.3   10.236.0.10   <none>        Ubuntu 20.04.6 LTS   5.4.0-153-generic   containerd://1.6.12
k8s-node-01   Ready    <none>          8d    v1.27.3   10.236.0.11   <none>        Ubuntu 20.04.6 LTS   5.4.0-153-generic   containerd://1.6.12
k8s-node-02   Ready    <none>          8d    v1.27.3   10.236.0.12   <none>        Ubuntu 20.04.6 LTS   5.4.0-153-generic   containerd://1.6.12
```

> Deploy a basic workload, hello-world with 3 replicas.

```shell
kubectl apply -f Deployment.yaml
```


> Verify if a pod has its unique IP address

```shell
kubectl get pods -o wide

NAME                           READY   STATUS    RESTARTS   AGE   IP                NODE          NOMINATED NODE   READINESS GATES
hello-world-75d6d8cfd7-bxqj7   1/1     Running   0          44m   192.168.154.243   k8s-node-01   <none>           <none>
hello-world-75d6d8cfd7-p2559   1/1     Running   0          44m   192.168.44.215    k8s-node-02   <none>           <none>
hello-world-75d6d8cfd7-qlzjw   1/1     Running   0          44m   192.168.154.244   k8s-node-01   <none>           <none>
```

> Access to pod shell and check its networking configuration

```shell

1: lo: <LOOPBACK,UP,LOWER_UP> mtu 65536 qdisc noqueue state UNKNOWN qlen 1000
    link/loopback 00:00:00:00:00:00 brd 00:00:00:00:00:00
    inet 127.0.0.1/8 scope host lo
       valid_lft forever preferred_lft forever
    inet6 ::1/128 scope host 
       valid_lft forever preferred_lft forever
3: eth0@if57: <BROADCAST,MULTICAST,UP,LOWER_UP,M-DOWN> mtu 1450 qdisc noqueue state UP 
    link/ether 5e:77:32:7e:a2:cb brd ff:ff:ff:ff:ff:ff
    inet 192.168.154.243/32 scope global eth0
       valid_lft forever preferred_lft forever
    inet6 fe80::5c77:32ff:fe7e:a2cb/64 scope link 
       valid_lft forever preferred_lft forever

```

> SSH to the worker node and check the network information

```shell
ip a

1: lo: <LOOPBACK,UP,LOWER_UP> mtu 65536 qdisc noqueue state UNKNOWN group default qlen 1000
    link/loopback 00:00:00:00:00:00 brd 00:00:00:00:00:00
    inet 127.0.0.1/8 scope host lo
       valid_lft forever preferred_lft forever
    inet6 ::1/128 scope host 
       valid_lft forever preferred_lft forever
2: ens160: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc fq_codel state UP group default qlen 1000
    link/ether 00:50:56:01:05:84 brd ff:ff:ff:ff:ff:ff
    inet 10.236.0.11/24 brd 10.236.0.255 scope global ens160
       valid_lft forever preferred_lft forever
    inet6 fe80::250:56ff:fe01:584/64 scope link 
       valid_lft forever preferred_lft forever
3: docker0: <NO-CARRIER,BROADCAST,MULTICAST,UP> mtu 1500 qdisc noqueue state DOWN group default 
    link/ether 02:42:f4:6c:26:17 brd ff:ff:ff:ff:ff:ff
    inet 172.17.0.1/16 brd 172.17.255.255 scope global docker0
       valid_lft forever preferred_lft forever
6: vxlan.calico: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1450 qdisc noqueue state UNKNOWN group default 
    link/ether 66:0f:78:83:d5:e1 brd ff:ff:ff:ff:ff:ff
    inet 192.168.154.192/32 scope global vxlan.calico
       valid_lft forever preferred_lft forever
    inet6 fe80::640f:78ff:fe83:d5e1/64 scope link 
       valid_lft forever preferred_lft forever
7: cali6d8e864b353@if3: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1450 qdisc noqueue state UP group default 
    link/ether ee:ee:ee:ee:ee:ee brd ff:ff:ff:ff:ff:ff link-netns cni-05941676-472a-9671-6382-121b242e1527
    inet6 fe80::ecee:eeff:feee:eeee/64 scope link 
       valid_lft forever preferred_lft forever
57: cali6833ab5953b@if3: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1450 qdisc noqueue state UP group default 
    link/ether ee:ee:ee:ee:ee:ee brd ff:ff:ff:ff:ff:ff link-netns cni-c32a9b0f-b509-25d1-b093-5734b8dac4f0
    inet6 fe80::ecee:eeff:feee:eeee/64 scope link 
       valid_lft forever preferred_lft forever
58: cali72039afe81f@if3: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1450 qdisc noqueue state UP group default 
    link/ether ee:ee:ee:ee:ee:ee brd ff:ff:ff:ff:ff:ff link-netns cni-0cd99757-f7fe-f06e-957b-087852beee2f
    inet6 fe80::ecee:eeff:feee:eeee/64 scope link 
       valid_lft forever preferred_lft forever
```

> Check Route

```shell
route

Kernel IP routing table
Destination     Gateway         Genmask         Flags Metric Ref    Use Iface
default         _gateway        0.0.0.0         UG    0      0        0 ens160
10.236.0.0      0.0.0.0         255.255.255.0   U     0      0        0 ens160
172.17.0.0      0.0.0.0         255.255.0.0     U     0      0        0 docker0
192.168.44.192  k8s-node-02     255.255.255.192 UG    0      0        0 ens160
192.168.154.192 0.0.0.0         255.255.255.192 U     0      0        0 *
192.168.154.195 0.0.0.0         255.255.255.255 UH    0      0        0 cali6d8e864b353
192.168.154.243 0.0.0.0         255.255.255.255 UH    0      0        0 cali6833ab5953b
192.168.154.244 0.0.0.0         255.255.255.255 UH    0      0        0 cali72039afe81f
192.168.235.192 k8s-master      255.255.255.192 UG    0      0        0 ens160   
```

> Exploring cluster DNS
> Get k8s service in kube-system

```shell
kubectl get service --namespace kube-system

NAME       TYPE        CLUSTER-IP   EXTERNAL-IP   PORT(S)                  AGE
kube-dns   ClusterIP   10.96.0.10   <none>        53/UDP,53/TCP,9153/TCP   8d      
```

> Get detail info about CoreDNS deployment

```shell
kubectl describe deployment coredns --namespace kube-system
```

> Discover the CoreDNS configuration and default forwarder

```shell
kubectl get configmaps --namespace kube-system coredns -o yaml
```

> Configure Pod DNS client Configuration

```shell
kubectl apply -f DeploymentCustomDns.yaml
```


> Check the DNS configuration of the normal pod and custom pod

```shell

kubectl exec -it 'CUSTOM_PODNAME' -- cat /etc/resolv.conf
nameserver 9.9.9.9

kubectl exec -it 'PODNAME' -- cat /etc/resolv.conf
nameserver 10.0.0.10
search default.svc.cluster.local svc.cluster.local cluster.local
options ndots:
```

> DNS discovering

> Run a busybox pod in the same namespace and test DNS resolving

```shell
kubectl run -it --rm bb --image busybox -- bin/sh
/ # nslookup hello-world
Server:         10.96.0.10
Address:        10.96.0.10:53

** server can't find hello-world.cluster.local: NXDOMAIN

** server can't find hello-world.cluster.local: NXDOMAIN

Name:   hello-world.default.svc.cluster.local
Address: 10.102.161.178
```

> Run another busybox pod in a different namespace

```shell
kubectl create ns myns
```

```shell
kubectl run -n myns -it --rm bb1 --image busybox -- bin/sh
/ # nslookup hello-world
/ # nslookup hello-world
Server:         10.96.0.10
Address:        10.96.0.10:53

** server can't find hello-world.cluster.local: NXDOMAIN

** server can't find hello-world.myns.svc.cluster.local: NXDOMAIN

** server can't find hello-world.svc.cluster.local: NXDOMAIN

** server can't find hello-world.svc.cluster.local: NXDOMAIN

** server can't find hello-world.myns.svc.cluster.local: NXDOMAIN

** server can't find hello-world.cluster.local: NXDOMAIN

** server can't find hello-world.myns.svc.cluster.local: NXDOMAIN
```
```shell
/ # nslookup hello-world.default.svc.cluster.local
Server:         10.96.0.10
Address:        10.96.0.10:53


Name:   hello-world.default.svc.cluster.local
Address: 10.102.161.178
```
