#!/bin/bash
set -euo pipefail

LOG_DIR="/var/log/hongbao"
LOG_FILE="$LOG_DIR/deploy_hongbao.log"

sudo mkdir -p "$LOG_DIR"

echo "🔄 Update time: $(date '+%Y-%m-%d %H:%M:%S')" | tee -a "$LOG_FILE"
echo "🚀 Starting deployment of HongBao system..." | tee -a "$LOG_FILE"

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

sudo mkdir -p /opt/hongbao
sudo mkdir -p /opt/hongbao/backend

if [ ! -f "/opt/hongbao/backend/Dockerfile" ]; then
    echo "⚠️ /opt/hongbao/backend/Dockerfile does not exist, creating default Dockerfile..." | tee -a "$LOG_FILE"
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
    echo "⚠️ /opt/hongbao/backend/package.json does not exist, creating default package.json..." | tee -a "$LOG_FILE"
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
    echo "⚠️ /opt/hongbao/backend/index.js does not exist, creating default index.js..." | tee -a "$LOG_FILE"
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

echo "🔧 Creating Docker Compose configuration..." | tee -a "$LOG_FILE"
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

echo "🚀 Starting all containers..." | tee -a "$LOG_FILE"
cd /opt/hongbao
sudo docker-compose up -d || { echo "❌ Failed to start containers, please check logs" | tee -a "$LOG_FILE"; exit 1; }

echo "🔍 Verifying services status..." | tee -a "$LOG_FILE"
sudo docker ps | tee -a "$LOG_FILE"

echo "🔧 Creating periodic service status check script..." | tee -a "$LOG_FILE"
sudo tee /opt/hongbao/check_services.sh > /dev/null <<'EOF'
#!/bin/bash
containers=("hongbao-api" "hongbao-hardhat" "hongbao-zokrates" "hongbao-mongodb" "hongbao-redis")
for container in "${containers[@]}"
do
  status=$(docker inspect -f '{{.State.Status}}' "$container" 2>/dev/null)
  if [ "$status" != "running" ]; then
    echo "$(date): Container $container is not running, restarting..."
    docker restart "$container"
  else
    health=$(docker inspect -f '{{.State.Health.Status}}' "$container" 2>/dev/null || echo "no-health")
    if [ "$health" != "healthy" ] && [ "$health" != "no-health" ]; then
      echo "$(date): Container $container is running but unhealthy (status: $health), restarting..."
      docker restart "$container"
    fi
  fi
done
EOF
sudo chmod +x /opt/hongbao/check_services.sh

echo "🔧 Creating Cron Job for periodic service status check..." | tee -a "$LOG_FILE"
sudo tee /etc/cron.d/hongbao_check > /dev/null <<'EOF'
*/5 * * * * root /opt/hongbao/check_services.sh >> /var/log/hongbao/service_check.log 2>&1
EOF

echo "✅ HongBao system deployment completed!" | tee -a "$LOG_FILE"
