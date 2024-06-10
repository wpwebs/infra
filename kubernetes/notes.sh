
```sh
#  Get Pod Name:
kubectl get pods -n lean-dev

kubectl get svc -n lean-dev

pod_name=lean-engine-deployment-5d8b46578d-h9kbl
# View Logs:
kubectl logs $pod_name -n lean-dev
# Execute Command:
kubectl exec -it $pod_name -n lean-dev -- /bin/bash
# Port Forwarding:
kubectl port-forward $pod_name 8080:8080 -n lean-dev

```

kubectl get pods -n lean-dev

pod_name=lean-cli-deployment-5ccdcb9466-f2tfg 
kubectl exec -it $pod_name -n lean-dev -- /bin/bash

kubectl port-forward $pod_name 2222:22 -n lean-dev


code --remote ssh-remote+benbox /home/trader/LEAN/LEAN.code-workspace


# Identify the Deployment
kubectl get deployments -n lean-dev
# Delete the Deployment
kubectl delete deployment lean-engine-deployment -n lean-dev
# Optional: Scaling Down a Deployment
kubectl scale deployment lean-engine-deployment --replicas=0 -n lean-dev
# Scaling Up a Deployment
kubectl scale deployment lean-engine-deployment --replicas=2 -n lean-dev




# Check Kubernetes Cluster:
kubectl get nodes
kubectl get pods -A

# Check Docker Setup:
docker info

# Kubernetes Context:
kubectl config current-context
# --> docker-desktop
# Switch kubectl context
kubectl config use-context default

# Switch Docker client context 
docker context use docker-desktop
