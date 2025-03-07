# Finding scheduling information

> Let's create a deployment with three replicas

```shell
kubectl apply -f deployment.yaml
```

> Pods spread out evenly across the Nodes due to our scoring functions for selector spread during Scoring.

```shell
kubectl get pods -o wide
```

> We can look at the Pods events to see the scheduler making its choice

```shell
kubectl describe pods 
```

> If we scale our deployment to 6...

```shell
kubectl scale deployment hello-world --replicas=6
```

> We can see that the scheduler works to keep load even across the nodes.

```shell
kubectl get pods -o wide
```

> We can see the nodeName populated for this node

```shell
kubectl get pods hello-world-[tab][tab] -o yaml
```

> Clean up this demo...and delete its resources

```shell
kubectl delete deployment hello-world
```



# Scheduling Pods with resource requests

> Get resources allocable

```shell
kubectl top nodes
```

> Scheduling Pods with resource requests

```shell
kubectl apply -f requests.yaml
```

> We created three pods, one on each node

```shell
kubectl get pods -o wide
```

> Let's scale our deployment to 6 replica

```shell
kubectl scale deployment hello-world-requests --replicas=6
```

> We see that three Pods are pending...why?

```shell
kubectl get pods -o wide
kubectl get pods -o wide | grep Pending
```

> Let's look at why the Pod is Pending...check out the Pod's events...

```shell
kubectl describe pods
```

> Now let's look at the node's Allocations...we've allocated 62% of our CPU...
1 User pod using 1 whole CPU, one system Pod ising 250 millicores of a CPU and 
looking at allocatable resources, we have only 2 whole Cores available for use.
The next pod coming along wants 1 whole core, and tha'ts not available.
The scheduler can't find a place in this cluster to place our workload...is this good or bad?

```shell
kubectl get nodes
kubectl describe nodes
kubectl describe node <node-id>
```

> Clean up after this demo

```shell
kubectl delete deployment hello-world-requests
```
-----------------
# Using Affinity and Anti-Affinity to schedule Pods to Nodes

> Let's start off with a deployment of web and cache pods.
Affinity: we want to have always have a cache pod co-located on a Node where we a Web Pod

```shell
kubectl apply -f deployment-affinity.yaml
```

> Let's check out the labels on the nodes, look for kubernetes.io/hostname which
we're using for our topologykey

```shell
kubectl describe nodes gke-cluster-1-default-pool-990b49f7-bzft | head
kubectl get nodes --show-labels
```

> We can see that web and cache are both on the name node

```shell
kubectl get pods -o wide 
```

> If we scale the web deployment
We'll still get spread across nodes in the ReplicaSet, so we don't need to enforce that with affinity

```shell
kubectl scale deployment hello-world-web --replicas=6
kubectl get pods -o wide 
```

> Then when we scale the cache deployment, it will get scheduled to the same node as the other web server

```shell
kubectl scale deployment hello-world-cache --replicas=2
kubectl get pods -o wide 
```

> Clean up the resources from these deployments

```shell
kubectl delete -f deployment-affinity.yaml
```



# Using anti-affinity 

> Now, let's test out anti-affinity, deploy web and cache again. 
But this time we're going to make sure that no more than 1 web pod is on each node with anti-affinity

```shell
kubectl apply -f deployment-antiaffinity.yaml
kubectl get pods -o wide
```

> Now let's scale the replicas in the web and cache deployments

```shell
kubectl scale deployment hello-world-web --replicas=4
```

> One Pod will go Pending because we can have only 1 Web Pod per node.
when using requiredDuringSchedulingIgnoredDuringExecution in our antiaffinity rule

```shell
kubectl get pods -o wide --selector app=hello-world-web
```

> To 'fix' this we can change the scheduling rule to preferredDuringSchedulingIgnoredDuringExecution
Also going to set the number of replicas to 4

```shell
kubectl apply -f deployment-antiaffinity-corrected.yaml
kubectl scale deployment hello-world-web --replicas=4
```

> Now we'll have 4 pods up an running, but doesn't the scheduler already ensure replicaset spread? Yes!

```shell
kubectl get pods -o wide --selector app=hello-world-web
```

> Let's clean up the resources from this demos

```shell
kubectl delete -f deployment-antiaffinity-corrected.yaml
```



# Controlling Pods placement with Taints and Tolerations

> Let's add a Taint to c1-node1

```shell
kubectl taint nodes c1-node1 key=MyTaint:NoSchedule
```

> We can see the taint at the node level, look at the Taints section

```shell
kubectl describe node c1-node1
```

> Let's create a deployment with three replicas

```shell
kubectl apply -f deployment.yaml
```

> We can see Pods get placed on the non tainted nodes

```shell
kubectl get pods -o wide
```

> But we we add a deployment with a Toleration...

```shell
kubectl apply -f deployment-tolerations.yaml
```

> We can see Pods get placed on the non tainted nodes

```shell
kubectl get pods -o wide
```

> Remove our Taint

```shell
kubectl taint nodes c1-node1 key:NoSchedule-
```

> Clean up after our demo

```shell
kubectl delete -f deployment-tolerations.yaml
kubectl delete -f deployment.yaml
```



# Demo - Using Labels to Schedule Pods to Nodes


> Scheduling a pod to a node

```shell
kubectl get nodes --show-labels 
```

> Label our nodes with something descriptive

```shell
kubectl label node c1-node2 disk=local_ssd
kubectl label node c1-node3 hardware=local_gpu
```

> Query our labels to confirm.

```shell
kubectl get node -L disk,hardware
```

> Create three Pods, two using nodeSelector, one without.

```shell
kubectl apply -f DeploymentsToNodes.yaml
```

> View the scheduling of the pods in the cluster.

```shell
kubectl get node -L disk,hardware
kubectl get pods -o wide
```

> If we scale this Deployment, all new Pods will go onto the node with the GPU label

```shell
kubectl scale deployment hello-world-gpu --replicas=3 
kubectl get pods -o wide 
```

> If we scale this Deployment, all new Pods will go onto the node with the SSD label

```shell
kubectl scale deployment hello-world-ssd --replicas=3 
kubectl get pods -o wide 
```

> If we scale this Deployment, all new Pods will go onto the node without the labels to keep the load balanced

```shell
kubectl scale deployment hello-world --replicas=3
kubectl get pods -o wide 
```

> If we go beyond that...it will use all node to keep load even globally

```shell
kubectl scale deployment hello-world --replicas=10
kubectl get pods -o wide 
```

> Clean up when we're finished, delete our labels and Pods

```shell
kubectl label node c1-node2 disk-
kubectl label node c1-node3 hardware-
kubectl delete deployments.apps hello-world
kubectl delete deployments.apps hello-world-gpu
kubectl delete deployments.apps hello-world-ssd
```
-------------
# Node Cordoning

> Drain node in preparation for maintenance.
The given node will be marked unschedulable to prevent new pods from arriving. and evict pods
When you are ready to put the node back into service, use kubectl uncordon, which will make the node schedulable again.
Let's create a deployment with three replicas

```shell
kubectl apply -f deployment.yaml
```

> Pods spread out evenly across the nodes

```shell
kubectl get pods -o wide
```

> Let's cordon c1-node3

```shell
kubectl cordon c1-node3
```

> That won't evict any pods...

```shell
kubectl get pods -o wide
```

> Let's drain (remove) the Pods from node3..

```shell
kubectl drain gke-cluster-1-default-pool-990b49f7-bzft
```

> Let's try that again since daemonsets aren't scheduled we need to work around them.

```shell
kubectl drain gke-cluster-1-default-pool-990b49f7-bzft --ignore-daemonsets
```

> Now all the workload is on node 1 and 2

```shell
kubectl get pods -o wide
```

> We can uncordon c1-node3, but nothing will get scheduled there until there's an event like a scaling operation or an eviction.

```shell
kubectl uncordon gke-cluster-1-default-pool-990b49f7-bzft
kubectl get pods -o wide
```

> So let's scale that Deployment and see where they get scheduled...

```shell
kubectl scale deployment hello-world --replicas=4
```

> All three get scheduled to the cordoned node

```shell
kubectl get pods -o wide
```

> Clean up this demo...

```shell
kubectl delete deployment hello-world
```
