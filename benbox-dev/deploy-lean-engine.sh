#!/bin/bash

# Variables
PROJECT="benbox"
NAMESPACE="$PROJECT-dev"
DEPLOYMENT_NAME="lean-engine"
SERVICE_NAME="$DEPLOYMENT_NAME-service"
DOCKER_IMAGE="quantconnect/lean:foundation"
CONTAINER_PORT=8080
PROJECT_DIR="/Users/henry/${PROJECT}"
CONTAINER_PROJECT_DIR="/${PROJECT}"
LOG_FILE="$DEPLOYMENT_NAME-deploy.log"
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

# Create the deployment YAML file
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

# Clear log file
> $LOG_FILE

# Debugging Information
echo "Starting deployment script..." | tee -a $LOG_FILE
echo "Namespace: $NAMESPACE" | tee -a $LOG_FILE
echo "Deployment Name: $DEPLOYMENT_NAME" | tee -a $LOG_FILE
echo "Service Name: $SERVICE_NAME" | tee -a $LOG_FILE
echo "Docker Image: $DOCKER_IMAGE" | tee -a $LOG_FILE
echo "Container Port: $CONTAINER_PORT" | tee -a $LOG_FILE
echo "Project Directory: $PROJECT_DIR" | tee -a $LOG_FILE
echo "Container Project Directory: $CONTAINER_PROJECT_DIR" | tee -a $LOG_FILE

# Create a namespace if it doesn't exist
kubectl get namespace $NAMESPACE &>/dev/null || kubectl create namespace $NAMESPACE >> $LOG_FILE 2>&1

# Apply the deployment
echo "Creating or updating deployment..." | tee -a $LOG_FILE
kubectl apply -f $DEPLOYMENT_NAME-deployment.yaml >> $LOG_FILE 2>&1
if [ $? -ne 0 ]; then
  echo "Failed to create or update deployment. Check log for details." | tee -a $LOG_FILE
  exit 1
fi

# Delete the existing service if it exists
echo "Delete the existing service if it exists..." | tee -a $LOG_FILE
kubectl delete service $SERVICE_NAME -n $NAMESPACE --ignore-not-found | tee -a $LOG_FILE

# Expose the deployment via a service
echo "Creating or updating service..." | tee -a $LOG_FILE
kubectl expose deployment $DEPLOYMENT_NAME --type=LoadBalancer --port=$PORT --target-port=$PORT --name=$SERVICE_NAME --namespace=$NAMESPACE >> $LOG_FILE 2>&1
if [ $? -ne 0 ]; then
  echo "Failed to create or update service. Check log for details." | tee -a $LOG_FILE
  exit 1
fi

echo "LEAN Engine deployed to Kubernetes successfully." | tee -a $LOG_FILE

echo "Future Management:"
echo "Stop the Service: Use kubectl delete -f lean-engine-deployment.yml to stop the deployment and kubectl delete -f lean-engine-service.yml to stop the service."
echo "Scale the Deployment: Edit the replicas field in lean-engine-deployment.yml and reapply using kubectl apply -f lean-engine-deployment.yml."
echo "Scale up: kubectl scale deployment lean-engine-deployment --replicas=2 -n lean-dev"
echo "Scale down/delete: kubectl scale deployment lean-engine-deployment --replicas=0 -n lean-dev"
echo "Scale delete: kubectl delete deployment lean-engine-deployment -n lean-dev"