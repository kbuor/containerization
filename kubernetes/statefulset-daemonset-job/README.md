# DaemonSet

## Creating a DaemonSet on All Nodes

> We get one Pod per Node to run network services on that Node

```shell
kubectl get nodes
kubectl get daemonsets --namespace kube-system
```

> Let's create a DaemonSet with Pods on each node in our cluster...that's NOT the master

```shell
kubectl apply -f DaemonSet.yaml
```

> So we'll get three since we have 3 workers and 1 master in our cluster and the master is set to run only system pods

```shell
kubectl get daemonsets
kubectl get daemonsets -o wide
kubectl get pods -o wide
```

> Callout, labels, Desired/Current Nodes Scheduled. Pod Status and Template and Events.

```shell
kubectl describe daemonsets hello-world | more 
```

> Each Pods is created with our label, app=hello-world, controller-revision-hash and a pod-template-generation

```shell
kubectl get pods --show-labels
```

> If we change the label to one of our Pods...

```shell
MYPOD=$(kubectl get pods -l app=hello-world-app | grep hello-world | head -n 1 | awk {'print $1'})
echo $MYPOD
kubectl label pods $MYPOD app=not-hello-world --overwrite
```

> We'll get a new Pod from the DaemonSet Controller

```shell
kubectl get pods --show-labels
```

> Let's clean up this DaemonSet

```shell
kubectl delete daemonsets hello-world-ds
kubectl delete pods $MYPOD
```


## Creating a DaemonSet on a Subset of Nodes

> Let's create a DaemonSet with a defined nodeSelector

```shell
kubectl apply -f DaemonSetWithNodeSelector.yaml
```

> No pods created because we don't have any nodes with the appropriate label

```shell
kubectl get daemonsets
```

> We need a Node that satisfies the Node Selector

```shell
kubectl label node gke-cluster-1-default-pool-c9e0f08b-9hh7 node=hello-world-ns
```

> Let's see if a Pod gets created...

```shell
kubectl get daemonsets -o wide
```

> What's going to happen if we remove the label

```shell
kubectl label node gke-cluster-1-default-pool-c9e0f08b-9hh7 node-
```

> It's going to terminate the Pod, examine events, Desired Number of Nodes Scheduled...

```shell
kubectl describe daemonsets hello-world-ds
```

> Clean up our demo

```shell
kubectl delete daemonsets hello-world-ds
```


## Updating a DaemonSet

```shell
kubectl apply -f DaemonSet.yaml
```


> Examine what our update stategy is...defaults to rollingUpdate and maxUnavailable 1

```shell
kubectl get DaemonSet hello-world-ds -o yaml | more
```

> Update our container image from 1.0 to 2.0 and apply the config

```shell
diff DaemonSet.yaml DaemonSet-v2.yaml
kubectl apply -f DaemonSet-v2.yaml
```

> Check on the status of our rollout, a touch slower than a deployment due to maxUnavailable.

```shell
kubectl rollout status daemonsets hello-world-ds
```

> We can see our DaemonSet Container Image is now 2.0 and in the Events that it rolled out.

```shell
kubectl describe daemonsets
```

> we can see the new controller-revision-hash and also an updated pod-template-generation

```shell
kubectl get pods --show-labels
```

> Time to clean up our demos

```shell
kubectl delete daemonsets hello-world-ds
```
-----------
# JobsCronJobs

## Executing tasks with Jobs, check out the file job.yaml

> Ensure you define a restartPolicy, the default of a Pod is Always, which is not compatible with a Job. We'll need OnFailure or Never, let's look at OnFailure

```shell
kubectl apply -f job.yaml
```

> Follow job status with a watch

```shell
kubectl get job --watch
```

> Get the list of Pods, status is Completed and Ready is 0/1

```shell
kubectl get pods
```

> Let's get some more details about the job...labels and selectors, Start Time, Duration and Pod Statuses

```shell
kubectl describe job hello-world-job
```

> Get the logs from stdout from the Job Pod

```shell
kubectl get pods -l job-name=hello-world-job 
kubectl logs hello-world-job-cmn2f
```

> Our Job is completed, but it's up to use to delete the Pod or the Job.

```shell
kubectl delete job hello-world-job
```

> Which will also delete it's Pods

```shell
kubectl get pods
```



## Show restartPolicy in action..., check out backoffLimit: 2 and restartPolicy: Never

> We'll want to use Never so our pods aren't deleted after backoffLimit is reached.

```shell
kubectl apply -f job-failure-OnFailure.yaml
```


> Let's look at the pods, enters a backoffloop after 2 crashes

```shell
kubectl get pods --watch
```

> The pods aren't deleted so we can troubleshoot here if needed.

```shell
kubectl get pods 
```

> And the job won't have any completions and it doesn't get deleted

```shell
kubectl get jobs 
```

> So let's review what the job did...Events, created...then deleted. Pods status, 3 Failed.

```shell
kubectl describe jobs | more
```

> Clean up this job

```shell
kubectl delete jobs hello-world-job-fail
kubectl get pods
```


## Defining a Parallel Job

```shell
kubectl apply -f ParallelJob.yaml
```

> 10 Pods will run in parallel up until 50 completions

```shell
kubectl get pods
```



> We can 'watch' the Statuses with watch

```shell
watch 'kubectl describe job | head -n 11'
```

> We'll get to 50 completions very quickly

```shell
kubectl get jobs
```

> Let's clean up...

```shell
kubectl delete job hello-world-job-parallel
```



## Scheduling tasks with CronJobs

```shell
kubectl apply -f CronJob.yaml
```

> Quick overview of the job and it's schedule

```shell
kubectl get cronjobs
```

> But let's look closer...schedule, Concurrency, Suspend,Starting Deadline Seconds, events...there's execution history

```shell
kubectl describe cronjobs | more 
```

> Get a overview again...

```shell
kubectl get cronjobs
```

> The pods will stick around, in the event we need their logs or other inforamtion. How long?

```shell
kubectl get pods --watch
```

> They will stick around for successfulJobsHistoryLimit, which defaults to three

```shell
kubectl get cronjobs -o yaml
```

> Clean up the job...

```shell
kubectl delete cronjob hello-world-cron
```

> Deletes all the Pods too...

```shell
kubectl get pods 
```
-----------
# StatefullSet

## Create StatefulSet Basic

> Check StorageClass default

```shell
kubectl get storageclass
```

> Create a basic statefulset

```shell
kubectl apply -f Nginx_StatefulSet.yaml
```

> Check pods

```shell
kubectl get pods -l app=nginx
```

> Get Service

```shell
kubectl get service nginx
```

> Get Statefulset

```shell
kubectl get statefulset web
```

> Check using Stable Network Identities

```shell
for i in 0 1; do kubectl exec "web-$i" -- sh -c 'hostname'; done
```

> Using nslookup on the Pods' hostnames, you can examine their in-cluster DNS addresses:

```shell
kubectl run -i --tty --image busybox:1.28 dns-test --restart=Never --rm
nslookup web-0.nginx
```

> Delete pod and Wait for the StatefulSet to restart them. In one terminal, watch the StatefulSet's Pods, In a second terminal, use kubectl delete to delete all the Pods in the StatefulSet

```shell
kubectl get pod -w -l app=nginx
kubectl delete pod -l app=nginx
```

> Recheck hostname

```shell
for i in 0 1; do kubectl exec web-$i -- sh -c 'hostname'; done
```

> Rerun nslookup

```shell
kubectl run -i --tty --image busybox:1.28 dns-test --restart=Never --rm -- nslookup web-0.nginx
```

## Writing to Stable Storage

> Check PVC

```shell
kubectl get pvc -l app=nginx
```

> Write the Pods' hostnames to their index.html files and verify that the NGINX webservers serve the hostnames

```shell
kubectl exec "web-0" -- sh -c 'echo "Hello, $(hostname)" > /usr/share/nginx/html/index.html'
kubectl exec "web-1" -- sh -c 'echo "Hello, $(hostname)" > /usr/share/nginx/html/index.html'
```

```shell
kubectl exec -i -t "web-0" -- curl http://localhost/
```

> Delete pods and recheck value of file content

```shell
kubectl delete pod -l app=nginx
```

```shell
kubectl get pods -l app=nginx
```

```shell
kubectl exec -i -t "web-0" -- curl http://localhost/
```

## Scaling Up

> Increase replicas

```shell
kubectl scale sts web --replicas=5
```

> Get pods

```shell
kubectl get pods -w -l app=nginx
```

> Scale Down

```shell
kubectl scale sts web --replicas=3
```

> Get pods

```shell
kubectl get pods -w -l app=nginx
```

> Ordered Pod Termination. The controller deleted one Pod at a time, in reverse order with respect to its ordinal index, and it waited for each to be completely shutdown before deleting the next.

> Check PVC

```shell
kubectl get pvc -l app=nginx
```

> Clean up

```shell
kubectl delete -f Nginx_StatefulSet.yaml
kubectl delete pvc -l app=nginx
```