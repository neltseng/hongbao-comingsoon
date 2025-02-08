#!/bin/bash
set -euo pipefail

# Create log directory and set log file
sudo mkdir -p "/var/log/hongbao"
LOG_DIR="/var/log/hongbao"
LOG_FILE="$LOG_DIR/deploy_hongbao.log"

echo "🔄 Update time: $(date '+%Y-%m-%d %H:%M:%S')" | tee -a "$LOG_FILE"
echo "🚀 Starting deployment of the HongBao system..." | tee -a "$LOG_FILE"

# 1. Install required components (Docker, Docker Compose, npm)
if ! command -v docker &>/dev/null; then
    echo "🔧 Installing Docker..." | tee -a "$LOG_FILE"
    sudo apt update && sudo apt install -y docker.io
fi
if ! command -v docker-compose &>/dev/null; then
    echo "🔧 Installing Docker Compose..." | tee -a "$LOG_FILE"
    sudo apt install -y docker-compose
fi
if ! command -v npm &>/dev/null; then
    echo "🔧 Installing Node.js and npm..." | tee -a "$LOG_FILE"
    sudo apt install -y nodejs npm
fi

# 2. Create deployment and backend directories if they don't exist
sudo mkdir -p /opt/hongbao
sudo mkdir -p /opt/hongbao/backend

# 3. Check and create default backend files if they don't exist
if [ ! -f "/opt/hongbao/backend/Dockerfile" ]; then
    echo "⚠️ /opt/hongbao/backend/Dockerfile not found. Creating a default Dockerfile..." | tee -a "$LOG_FILE"
    sudo tee /opt/hongbao/backend/Dockerfile > /dev/null <<'EOF'
FROM node:14
WORKDIR /app
COPY package.json .
RUN npm install
COPY index.js .
EXPOSE 5000
CMD ["node", "index.js"]
EOF
fi

if [ ! -f "/opt/hongbao/backend/package.json" ]; then
    echo "⚠️ /opt/hongbao/backend/package.json not found. Creating a default package.json..." | tee -a "$LOG_FILE"
    sudo tee /opt/hongbao/backend/package.json > /dev/null <<'EOF'
{
  "name": "dummy-api",
  "version": "1.0.0",
  "main": "index.js",
  "scripts": {
    "start": "node index.js"
  },
  "dependencies": {
    "express": "^4.18.2"
  }
}
EOF
fi

if [ ! -f "/opt/hongbao/backend/index.js" ]; then
    echo "⚠️ /opt/hongbao/backend/index.js not found. Creating a default index.js..." | tee -a "$LOG_FILE"
    sudo tee /opt/hongbao/backend/index.js > /dev/null <<'EOF'
const express = require('express');
const app = express();

app.get('/', (req, res) => {
  res.send('Hello World from Dummy API');
});

const port = 5000;
app.listen(port, () => {
  console.log(`API listening on port ${port}`);
});
EOF
fi

# Docker Compose configuration
echo "🔧 Setting up Docker Compose configuration..." | tee -a "$LOG_FILE"
sudo tee /opt/hongbao/docker-compose.yml > /dev/null <<'EOF'
version: '3.8'
services:
  mongo:
    image: mongo:${MONGO_VERSION:-8.0}
    container_name: hongbao-mongodb
    restart: always
    networks:
      - hongbao_network
    volumes:
      - mongodb_data:/data/db
  
  redis:
    image: redis:${REDIS_VERSION:-6.2}
    container_name: hongbao-redis
    restart: always
    networks:
      - hongbao_network
    volumes:
      - redis_data:/data
  
  zokrates:
    image: zokrates/zokrates:${ZOKRATES_VERSION:-latest}
    container_name: hongbao-zokrates
    restart: always
    command: tail -f /dev/null
    networks:
      - hongbao_network
  
  hardhat:
    image: ethereumoptimism/hardhat:${HARDHAT_VERSION:-latest}
    container_name: hongbao-hardhat
    restart: always
    networks:
      - hongbao_network
  
  api:
    build:
      context: ./backend
      dockerfile: Dockerfile
    container_name: hongbao-api
    restart: always
    ports:
      - "5000:5000"
    networks:
      - hongbao_network
    depends_on:
      - mongo
      - redis
    healthcheck:
      test: ["CMD-SHELL", "curl -s -o /dev/null -w '%{http_code}' http://localhost:5000 | grep -q '200' || exit 1"]
      interval: 10s
      timeout: 5s
      retries: 5
      start_period: 10s

volumes:
  mongodb_data:
  redis_data:
  api_data:
    driver: local

networks:
  hongbao_network:
    driver: bridge
EOF

# Start containers
echo "🚀 Starting all containers..." | tee -a "$LOG_FILE"
cd /opt/hongbao
sudo docker-compose up -d || { echo "❌ Failed to start containers. Please check the log." | tee -a "$LOG_FILE"; exit 1; }

echo "🔍 Verifying service status..." | tee -a "$LOG_FILE"
sudo docker ps | tee -a "$LOG_FILE"

# Create monitoring script
echo "🔧 Creating monitoring script monitor_hongbao.sh ..." | tee -a "$LOG_FILE"
sudo tee /opt/hongbao/monitor_hongbao.sh > /dev/null <<'EOF'
#!/bin/bash
set -euo pipefail
LOG_FILE="/var/log/hongbao/monitor_hongbao.log"
while true; do
    desired_services=("hongbao-mongodb" "hongbao-redis" "hongbao-zokrates" "hongbao-hardhat" "hongbao-api")
    for service in "${desired_services[@]}"; do
        if ! docker ps --format '{{.Names}}' | grep -q "^${service}\$"; then
            echo "$(date '+%Y-%m-%d %H:%M:%S'): ${service} is not running, attempting to restart..." >> "$LOG_FILE"
            cd /opt/hongbao
            docker-compose restart "${service}"
        fi
    done
    sleep 60
done
EOF

sudo chmod +x /opt/hongbao/monitor_hongbao.sh

# Create systemd service for monitoring script
echo "🔧 Creating systemd service hongbao-monitor.service ..." | tee -a "$LOG_FILE"
sudo tee /etc/systemd/system/hongbao-monitor.service > /dev/null <<'EOF'
[Unit]
Description=HongBao Monitor Service
After=docker.service
Requires=docker.service

[Service]
Type=simple
ExecStart=/opt/hongbao/monitor_hongbao.sh
Restart=always
RestartSec=30

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable hongbao-monitor.service
sudo systemctl start hongbao-monitor.service

echo "✅ HongBao system deployed successfully and monitoring service is running!" | tee -a "$LOG_FILE"
