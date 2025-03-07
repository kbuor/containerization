# Pod

> Start up kubectl get events --watch to monitor the cluster events in a separate terminal

```shell
kubectl get events --watch
```

> Create a pod...we can see the scheduling, container pulling and container starting.

```shell
kubectl apply -f hello-world-pod.yaml
```

> Start a Deployment with 1 replica. We see the deployment created, scaling the replica set and the replica set starting the first pod

```shell
kubectl apply -f deployment.yaml
```

> Scale a Deployment to 2 replicas. We see the scaling the replica set and the replica set starting the second pod

```shell
kubectl scale deployment hello-world --replicas=2
```

> We start off with the replica set scaling to 1, then  Pod deletion, then the Pod killing the container 

```shell
kubectl scale deployment hello-world --replicas=1
```

> Now, let's access our Pod's application directly, without a service and also off the Pod network.

```shell
kubectl port-forward PASTE_POD_NAME_HERE 80:8080
```

> Let's do it again, but this time with a non-priviledged port

```shell
kubectl port-forward PASTE_POD_NAME_HERE 8080:8080 &
```

> We can point curl to localhost, and kubectl port-forward will send the traffic through the API server to the Pod

```shell
curl http://localhost:8080
```

> Kill our port forward session.

```shell
fg
ctrl+c
```
---------------
# Multi-containers pod

> Review multi-containers pod manifest

```shell
more multicontainer-pod.yaml
```

> Create our multi-container Pod

```shell
kubectl apply -f multicontainer-pod.yaml
```

> Connect to our Pod...not specifying a name defaults to the first container in the configuration

```shell
kubectl exec -it multicontainer-pod -- /bin/sh
ls -la /var/log
tail /var/log/index.html
exit
```

> Specify a container name and access the consumer container in our Pod

```shell
kubectl exec -it multicontainer-pod --container consumer -- /bin/sh
ls -la /usr/share/nginx/html
tail /usr/share/nginx/html/index.html
exit
```

> This application listens on port 80, we'll forward from 8080->80 or any port that available on your kubectl client

```shell
kubectl port-forward multicontainer-pod 8080:80 &
curl http://localhost:8080
```

> Kill our port-forward.

```shell
fg
ctrl+c
```

> Cleanup

```shell
kubectl delete pod multicontainer-pod
```
----------------
# Pod Lifecycel

> Start up kubectl get events --watch and background it

```shell
kubectl get events --watch &
clear
```

> Create a pod from manifest

```shell
kubectl apply -f pod.yaml
```

> Access to pod and check the container process

```shell
kubectl exec -it hello-world-pod -- ps
ps
exit
```

> Kill the main process in container

```shell
kubectl exec -it hello-world-pod -- /usr/bin/killall hello-app
```


> Restart count increased by 1 after the container needed to be restarted.

```shell
kubectl get pods hello-world-pod
```

> Look at Containers->State, Last State, Reason, Exit Code, Restart Count and Events

```shell
kubectl describe pod hello-world-pod
```

> Cleanup time

```shell
kubectl delete pod hello-world-pod
```

> Create 2 pods with restartPolicy set as OnFailure/Never

```shell
kubectl apply -f pod-restart-policy.yaml
```

> Check to ensure both pods are up and running, we can see the restarts is 0

```shell
kubectl get pods 
```

> Kill main apps in pod with restartPolicy was set as Never and see how the container restart policy reacts

```shell
kubectl exec -it hello-world-never-pod -- /usr/bin/killall hello-app
kubectl get pods hello-world-never-pod
```

> Review container state, reason, exit code, ready and contitions Ready, ContainerReady

```shell
kubectl describe pod hello-world-never-pod
```

> Kill main apps in pod with restartPolicy was set as OnFailure and see how the container restart policy reacts

```shell
kubectl exec -it hello-world-onfailure-pod -- /usr/bin/killall hello-app
```

> We'll see 1 restart on the pod with the OnFailure restart policy.

```shell
kubectl get pods hello-world-onfailure-pod
```
----------
# Container Probes

> Create pod with its liveness and readiness defined

```shell
kubectl apply -f container-probes.yaml
```

> The pod keeps restarting...
kubectl get pods --selector app=hello-world

> Let's figure out what's wrong

* We can see in the events. The Liveness and Readiness probe failures.
* Under Containers, Liveness and Readiness, we can see the current configuration. And the current probe configuration. Both are pointing to 8081.
* Under Containers, Ready and Container Contidtions, we can see that the container isn't ready.
* Our Container Port is 8080, that's what we want our probes, probings. 

```shell
kubectl describe pods
```

> Go ahead and change the probes to 8080

```shell
vi container-probes.yaml
```

> Apply change to the current deployment

```shell
kubectl apply -f container-probes.yaml
```

> Confirm our probes are pointing to the correct container port now, which is 8080.
 
> Let's check our status, a couple of things happened there.

* Our Deployment ReplicaSet created a NEW Pod, when we pushed in the new deployment configuration.

* It's not immediately ready because of our initialDelaySeconds which is 10 seconds.

* If we wait long enough, the livenessProbe will kill the original Pod and it will go away.

* Leaving us with the one pod in our Deployment's ReplicaSet

```shell
kubectl get pods 
```

```shell
kubectl delete deployment hello-world
```
