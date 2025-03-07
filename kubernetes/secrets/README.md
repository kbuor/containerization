# Demo Creating and accessing Secrets

> Generic - Create a secret from a local file, directory or literal value.
> They keys and values are case sensitive

```shell
kubectl create secret generic app1 --from-literal=USERNAME=app1login --from-literal=PASSWORD='S0methingS@Str0ng!'
```


> Opaque means it's an arbitrary user defined key/value pair. Data 2 means two key/value pairs in the secret.
Other types include service accounts and container registry authentication info

```shell
kubectl get secrets
```

> app1 said it had 2 Data elements, let's look

```shell
kubectl describe secret app1
```

> If we need to access those at the command line...
These are wrapped in bash expansion to add a newline to output for readability

```shell
echo $(kubectl get secret app1 --template={{.data.USERNAME}} )
echo $(kubectl get secret app1 --template={{.data.USERNAME}} | base64 --decode )

echo $(kubectl get secret app1 --template={{.data.PASSWORD}} )
echo $(kubectl get secret app1 --template={{.data.PASSWORD}} | base64 --decode )
```



# Demo Accessing Secrets inside a Pod

> As environment variables

```shell
kubectl apply -f deployment-secrets-env.yaml
```

```shell
PODNAME=$(kubectl get pods | grep hello-world-secrets-env | awk '{print $1}' | head -n 1)
echo $PODNAME
```

> Now let's get our enviroment variables from our container.
Our Enviroment variables from our Pod Spec are defined

```shell
kubectl exec -it $PODNAME -- /bin/sh
printenv | grep ^app1
exit
```

> Accessing Secrets as files

```shell
kubectl apply -f deployment-secrets-files.yaml
```

> Grab our pod name into a variable

```shell
PODNAME=$(kubectl get pods | grep hello-world-secrets-files | awk '{print $1}' | head -n 1)
echo $PODNAME
```

> Looking more closely at the Pod we see volumes, appconfig and in Mounts...

```shell
kubectl describe pod $PODNAME
```

> Let's access a shell on the Pod

```shell
kubectl exec -it $PODNAME -- /bin/sh
```

> Now we see the path we defined in the Volumes part of the Pod Spec.
A directory for each KEY and it's contents are the value

```shell
ls /etc/appconfig
cat /etc/appconfig/USERNAME
cat /etc/appconfig/PASSWORD
exit
```

> If you need to put only a subset of the keys in a secret check out this line here and look at items
https://kubernetes.io/docs/concepts/storage/volumes#secret


> let's clean up after our demos...

```shell
kubectl delete secret app1
kubectl delete deployment hello-world-secrets-env
kubectl delete deployment hello-world-secrets-files
```


# Additional examples of using secrets in your Pods

> Create a secret using clear text and the stringData field

```shell
kubectl apply -f secret.string.yaml
```

> Create a secret with encoded values, preferred over clear text.

```shell
echo -n 'app2login' | base64
echo -n 'S0methingS@Str0ng!' | base64
kubectl apply -f secret.encoded.yaml
```

> Check out the list of secrets now available 

```shell
kubectl get secrets
```

> There's also an envFrom example in here for you too...

```shell
kubectl create secret generic app1 --from-literal=USERNAME=app1login --from-literal=PASSWORD='S0methingS@Str0ng!'
```

> Create the deployment, envFrom will create  enviroment variables for each key in the named secret app1 with and set it's value set to the secrets value

```shell
kubectl apply -f deployment-secrets-env-from.yaml
PODNAME=$(kubectl get pods | grep hello-world-secrets-env-from | awk '{print $1}' | head -n 1)
kubectl exec -it $PODNAME -- printenv | sort
```

> Clean up

```shell
kubectl delete secret app1
kubectl delete secret app2
kubectl delete secret app3
kubectl delete deployment hello-world-secrets-env-from
```
