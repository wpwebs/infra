#!/bin/bash

# Variables
PROJECT="benbox"
NAMESPACE="$PROJECT-dev"
DEPLOYMENT_NAME="lean-cli"
SERVICE_NAME="$DEPLOYMENT_NAME-service"
DOCKER_IMAGE="quantconnect/lean:foundation"
PROJECT_DIR="/Users/henry/${PROJECT}"
CONTAINER_PROJECT_DIR="${PROJECT}"
PORT=5678
CPU_LIMIT="1"
RAM_LIMIT="1Gi"
STORAGE_LIMIT="10Gi"


# Check if the PVC already exists
if kubectl get pvc $PROJECT-pvc -n $NAMESPACE &>/dev/null; then
  echo "PersistentVolumeClaim '$PROJECT-pvc' already exists. Using the existing PVC."
else
  # Create a Persistent Volume Claim (PVC) if it does not exist
  cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: $PROJECT-pvc
  namespace: $NAMESPACE
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: $STORAGE_LIMIT
EOF
fi

# Create a deployment YAML file
cat <<EOF > $DEPLOYMENT_NAME-deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: $DEPLOYMENT_NAME
  namespace: $NAMESPACE
spec:
  replicas: 1
  selector:
    matchLabels:
      app: $DEPLOYMENT_NAME
  template:
    metadata:
      labels:
        app: $DEPLOYMENT_NAME
    spec:
      containers:
      - name: $DEPLOYMENT_NAME
        image: $DOCKER_IMAGE
        ports:
        - containerPort: $PORT
        resources:
          limits:
            cpu: $CPU_LIMIT
            memory: $RAM_LIMIT
        volumeMounts:
        - name: $PROJECT-volume
          mountPath: /$CONTAINER_PROJECT_DIR
      volumes:
      - name: $PROJECT-volume
        persistentVolumeClaim:
          claimName: $PROJECT-pvc
EOF

# Create a namespace if it doesn't exist
kubectl get namespace $NAMESPACE &>/dev/null || kubectl create namespace $NAMESPACE

# Apply the deployment
kubectl apply -f $DEPLOYMENT_NAME-deployment.yaml

# Delete the existing service if it exists
kubectl delete service $SERVICE_NAME -n $NAMESPACE --ignore-not-found

# Expose the deployment via a service
kubectl expose deployment $DEPLOYMENT_NAME --type=LoadBalancer --port=$PORT --target-port=$PORT --name=$SERVICE_NAME --namespace=$NAMESPACE 

echo "LEAN CLI deployed to Kubernetes successfully."
echo "Management:"
echo "Stop the deployment and service: kubectl delete deployment $DEPLOYMENT_NAME -n $NAMESPACE && kubectl delete service $SERVICE_NAME -n $NAMESPACE"
echo "Scale the deployment: Edit the replicas field in $DEPLOYMENT_NAME-deployment.yaml and reapply using kubectl apply -f $DEPLOYMENT_NAME-deployment.yaml."
echo "Scale up without editing deployment file: kubectl scale deployment $DEPLOYMENT_NAME --replicas=2 -n $NAMESPACE"
echo "Scale down/delete: kubectl scale deployment $DEPLOYMENT_NAME --replicas=0 -n $NAMESPACE"
