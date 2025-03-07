# Demo Creating and Scaling a Deployment.

> Let's start off imperatively creating a deployment and scaling it...

```shell
kubectl run hello-world --image=gcr.io/google-samples/hello-app:1.0
```

> Check out the status of our deployment, we get 1 Replica

```shell
kubectl get deployments hello-world
```

> Let's scale our deployment from 1 to 10 replicas

```shell
kubectl scale deployments hello-world --replicas=10
```

> Check out the status of our deployment, we get 10 Replicas

```shell
kubectl get deployments hello-world
```

> But we're going to want to use Declarative deployments in yaml, so let's delete this.

```shell
kubectl delete deployment hello-world
```

> Deploy our Deployment via yaml, look inside deployment.yaml first.

```shell
kubectl apply -f deployment.yaml 
```

> Check the status of our deployment

```shell
kubectl get deployments hello-world
```

> Apply a modified yaml file scaling from 10 to 20 replicas.

```shell
kubectl apply -f deployment.20replicas.yaml
kubectl get deployments hello-world
```

> Clean up from our demos

```shell
kubectl delete deployment hello-world
kubectl delete service hello-world
```

--------------

# Updating a Deployment and checking our rollout status

> Let's start off with rolling out v1

```shell
kubectl apply -f deployment.yaml
```

> Check the status of the deployment

```shell
kubectl get deployment hello-world
```

> Now let's apply that deployment, run both this and line 18 at the same time.

```shell
kubectl apply -f deployment.v2.yaml
```

> Let's check the status of that rollout, while the command blocking your deployment is in the Progressing status.

```shell
kubectl rollout status deployment hello-world
```

> Expect a return code of 0 from kubectl rollout status...that's how we know we're in the Complete status.

```shell
echo $?
```

> Let's walk through the description of the deployment...

> Check out Replicas, Conditions and Events OldReplicaSet (will only be populated during a rollout) and NewReplicaSet

> Conditions (more information about our objects state):

* Available      True    MinimumReplicasAvailable
* Progressing    True    NewReplicaSetAvailable (when true, deployment is still progressing or complete)

```shell
kubectl describe deployments hello-world
```

> Both replicasets remain, and that will become very useful shortly when we use a rollback :)

```shell
kubectl get replicaset
```

> The NewReplicaSet, check out labels, replicas, status and pod-template-hash

```shell
kubectl describe replicaset <new-rs-id>
```

> The OldReplicaSet, check out labels, replicas, status and pod-template-hash

```shell
kubectl describe replicaset <old-rs-id>
```
-----------
# Updating to a non-existent image. 

> Delete any current deployments, because we're interested in the deploy state changes.

```shell
kubectl delete deployment hello-world
kubectl delete service hello-world
```


> Create our v1 deployment, then update it to v2

```shell
kubectl apply -f deployment.yaml
kubectl apply -f deployment.v2.yaml
```

> Observe behavior since new image wasn’t available, the ReplicaSet doesn't go below maxUnavailable

```shell
kubectl apply -f deployment.broken.yaml
```


> Why isn't this finishing...? after progressDeadlineSeconds which we set to 10 seconds (defaults to 10 minutes)

```shell
kubectl rollout status deployment hello-world
```

> Expect a return code of 1 from kubectl rollout status...that's how we know we're in the failed status.

```shell
echo $?
```

> Let's check out Pods, ImagePullBackoff/ErrImagePull...ah an error in our image definition.

> Also, it stopped the rollout at 5, that's kind of nice isn't it?

> And 8 are online, let's look at why.

```shell
kubectl get pods
```

> What is maxUnavailable? 25%...So only two Pods in the ORIGINAL ReplicaSet are offline and 8 are online.

> What is maxSurge? 25%? So we have 13 total Pods, or 25% in addition to Desired number.

> Look at Replicas and OldReplicaSet 8/8 and NewReplicaSet 5/5.

* Available      True    MinimumReplicasAvailable
* Progressing    False   ProgressDeadlineExceeded

```shell
kubectl describe deployments hello-world 
```

> Let's sort this out now...check the rollout history, but which revision should we rollback to?

```shell
kubectl rollout history deployment hello-world
```

> It's easy in this example, but could be harder for complex systems.
Let's look at our revision Annotation, should be 3

```shell
kubectl describe deployments hello-world | head
```

> We can also look at the changes applied in each revision to see the new pod templates.

```shell
kubectl rollout history deployment hello-world --revision=2
kubectl rollout history deployment hello-world --revision=3
```

> Let's undo our rollout to revision 2, which is our v2 container.

```shell
kubectl rollout undo deployment hello-world --to-revision=2
kubectl rollout status deployment hello-world
echo $?
```

> We're back to Desired of 10 and 2 new Pods where deployed using the previous Deployment Replicas/Container Image.

```shell
kubectl get pods
```

> Let's delete this Deployment and start over with a new Deployment.

```shell
kubectl delete deployment hello-world
kubectl delete service hello-world
```

# Controlling the rate and update strategy of a Deployment update.

> Let's deploy a Deployment with Readiness Probes

```shell
kubectl apply -f deployment.probes-1.yaml --record
```

> Available is still 0 because of our Readiness Probe's initialDelaySeconds is 10 seconds.
Also, look there's a new annotaion for our change-cause.
And check the Conditions, 

*   Progressing   True    NewReplicaSetCreated or ReplicaSetUpdated - depending on the state.
*   Available     False   MinimumReplicasUnavailable

```shell
kubectl describe deployment hello-world
```

> Check again, Replicas and Conditions, all Pods should be online and ready.
*   Available      True    MinimumReplicasAvailable
*   Progressing    True    NewReplicaSetAvailable

```shell
kubectl describe deployment hello-world
```

> Let's update from v1 to v2 with Readiness Probes Controlling the rollout, and record our rollout

```shell
diff deployment.probes-1.yaml deployment.probes-2.yaml
kubectl apply -f deployment.probes-2.yaml --record
```

> Lots of pods, most are not ready yet, but progressing...how do we know it's progressing?

```shell
kubectl get replicaset
```

> Check again, Replicas and Conditions. 

> Progressing is now ReplicaSetUpdated, will change to NewReplicaSetAvailable when it's Ready
NewReplicaSet is THIS current RS, OldReplicaSet is populated during a Rollout, otherwise it's <None>
We used the update strategy settings of max unavailable and max surge to slow this rollout down.
This update takes about a minute to rollout

```shell
kubectl describe deployment hello-world
```

> Let's update again, but I'm not going to tell you what I changed, we're going to troubleshoot it together

```shell
kubectl apply -f deployment.probes-3.yaml --record
```

> We stall at 4 out of 20 replicas updated...let's look

```shell
kubectl rollout status deployment hello-world
```

> Let's check the status of the Deployment, Replicas and Conditions, 
* 22 total (20 original + 2 max surge)
* 18 available (20 original - 2 (10%) in the old RS)
* 4 Unavailable, (only 2 pods in the old RS are offline, 4 in the new RS are not READY)


*  Available      True    MinimumReplicasAvailable
*  Progressing    True    ReplicaSetUpdated 

```shell
kubectl describe deployment hello-world
```

> Let's look at our ReplicaSets, no Pods in the new RS are READY, but 4 our deployed.
That RS with Desired 0 is from our V1 deployment, 18 is from our V2 deployment.

```shell
kubectl get replicaset
```

> Ready...that sounds familiar, let's check the deployment again

> What keeps a pod from reporting ready? A Readiness Probe...see that Readiness Probe, wrong port ;)

```shell
kubectl describe deployment hello-world
``` 

> We can read the Deployment's rollout history, and see our CHANGE-CAUSE annotations

```shell
kubectl rollout history deployment hello-world
```


> Let's rollback to revision 2 to undo that change...

```shell
kubectl rollout history deployment hello-world --revision=3
kubectl rollout history deployment hello-world --revision=2
kubectl rollout undo deployment hello-world --to-revision=2
```

> And check out our deployment to see if we get 20 Ready replicas

```shell
kubectl describe deployment | head
kubectl get deployment
```

> Let's clean up

```shell
kubectl delete deployment hello-world
kubectl delete service hello-world
```
