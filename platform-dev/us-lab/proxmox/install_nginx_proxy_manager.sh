#!/bin/bash

# Define the setup script to Install Nginx Proxy Manager and Remove Existing Nginx
DEPLOY_NPM=$(cat <<'EOM'
#!/bin/bash

# Function to handle errors
handle_error() {
  echo "Error on line $1"
  exit 1
}
trap 'handle_error $LINENO' ERR

# Function to check if a package is installed
is_installed() {
  dpkg -l | grep -q "$1"
}

# Function to remove existing Nginx installation
remove_existing_nginx() {
  if is_installed nginx; then
      echo "Removing existing Nginx installation..."
      sudo systemctl stop nginx
      sudo apt-get remove -y nginx nginx-common nginx-full
      sudo apt-get purge -y nginx nginx-common nginx-full
      sudo rm -rf /etc/nginx /usr/share/nginx /var/log/nginx
  else
      echo "No existing Nginx installation found."
  fi
}

# Function to install Docker if not installed
install_docker() {
    if ! [ -x "$(command -v docker)" ]; then
        echo "Docker is not installed. Installing Docker then continue."
    fi
}

# Function to install Docker Compose if not installed
install_docker_compose() {
    if ! [ -x "$(command -v docker-compose)" ]; then
        echo "Docker Compose is not installed. Install Docker Compose then continue."
    fi
}

# Function to set up Nginx Proxy Manager
setup_nginx_proxy_manager() {
  echo "Setting up Nginx Proxy Manager..."

  # Variables
  DATA_DIR=$DATA_DIR
  CONTAINER_NAME=$(echo "$CONTAINER_NAME" | tr '[:upper:]' '[:lower:]')

  # Stop and remove the NPM container
  echo "Stop and remove existing NPM container ..."
  docker stop $CONTAINER_NAME || true
  docker rm $CONTAINER_NAME || true

  # Remove Docker volumes related to NPM
  # echo "Docker volumes related to NPM ..."
  # VOLUME_IDS=$(docker volume ls -q | grep $CONTAINER_NAME)
  # if [ ! -z "$VOLUME_IDS" ]; then
  #     docker volume rm $VOLUME_IDS || true
  # fi

  # # Remove any remaining configuration files
  # echo "Remove any remaining configuration files ..."
  # sudo rm -rf $DATA_DIR || true

  # Create Docker Compose directory and file for NPM
  echo "Create Docker Compose directory and file for NPM at: $DATA_DIR ..."
  mkdir -p $DATA_DIR
  cd $DATA_DIR
  mkdir -p ./data ./letsencrypt
  sudo chown -R 472:472 $DATA_DIR

  # Create a docker-compose.yml file
  sudo tee docker-compose.yml > /dev/null <<EOF
services:
  npm:
    container_name: $(echo "$CONTAINER_NAME" | tr '[:upper:]' '[:lower:]')
    image: 'yobasystems/alpine-mariadb:latest'
    restart: unless-stopped
    networks:
      - benbox_network
    ports:
      - '80:80'
      - '81:81'
      - '443:443'
    environment:
      DB_SQLITE_FILE: "/data/database.sqlite"
    volumes:
      - $DATA_DIR/data:/data
      - $DATA_DIR/letsencrypt:/etc/letsencrypt
networks:
  benbox_network:
    external: true
EOF

  # Start Nginx Proxy Manager using Docker Compose
  sudo docker-compose up -d

  # Check if Nginx Proxy Manager started successfully
  if [ $? -ne 0 ]; then
    echo "Nginx Proxy Manager failed to start. Exiting."
    exit 1
  fi

  echo "Nginx Proxy Manager has been set up successfully."

  # Wait for Nginx Proxy Manager to start up
  sleep 10

  # Obtain SSL certificates for the domains and configure redirects to HTTPS
  echo "Please log into Nginx Proxy Manager and configure your domains to force HTTPS."
}

# Remove existing Nginx installation
remove_existing_nginx

# Install Docker if not installed
install_docker

# Install Docker Compose if not installed
install_docker_compose

# Set up Nginx Proxy Manager
setup_nginx_proxy_manager

echo "Nginx Proxy Manager installation and setup completed. Please configure your domains to force HTTPS in the NPM web UI."
EOM
)

# Define your remote server details
NEW_USER="trader"
IP_ADDRESS="172.104.25.70"

# Define the variables
CONTAINER_NAME="nginx-proxy-manager"
DATA_DIR="/home/$NEW_USER/npm_data"

# Execute the setup script on the remote server
ssh -o StrictHostKeyChecking=no -t $NEW_USER@$IP_ADDRESS "CONTAINER_NAME=$CONTAINER_NAME DATA_DIR='$DATA_DIR' bash -s" <<EOM
$DEPLOY_NPM
EOM
