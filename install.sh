#!/bin/bash

# Mettre à jour les paquets
sudo apt update && sudo apt upgrade -y

# Installer les dépendances
sudo apt install -y wget unzip curl

# Installer Prometheus
wget https://github.com/prometheus/prometheus/releases/download/v3.2.0-rc.1/prometheus-3.2.0-rc.1.linux-amd64.tar.gz
tar xvf prometheus-3.2.0-rc.1.linux-amd64.tar.gz
sudo mv prometheus-3.2.0-rc.1.linux-amd64.tar.gz /usr/local/prometheus

# Configurer Prometheus
cat <<EOF | sudo tee /usr/local/prometheus/prometheus.yml
global:
  scrape_interval: 15s

scrape_configs:
  - job_name: 'java-app'
    static_configs:
      - targets: ['localhost:8080']
EOF

# Démarrer Prometheus
nohup /usr/local/prometheus/prometheus --config.file=/usr/local/prometheus/prometheus.yml &

# Installer Grafana
sudo apt-get install -y apt-transport-https software-properties-common wget
sudo mkdir -p /etc/apt/keyrings/
wget -q -O - https://apt.grafana.com/gpg.key | gpg --dearmor | sudo tee /etc/apt/keyrings/grafana.gpg > /dev/null
echo "deb [signed-by=/etc/apt/keyrings/grafana.gpg] https://apt.grafana.com stable main" | sudo tee -a /etc/apt/sources.list.d/grafana.list
echo "deb [signed-by=/etc/apt/keyrings/grafana.gpg] https://apt.grafana.com beta main" | sudo tee -a /etc/apt/sources.list.d/grafana.list
sudo apt-get update
sudo apt-get install grafana -y
sudo systemctl start grafana-server
sudo systemctl enable grafana-server

# Installer Loki
wget https://github.com/grafana/loki/releases/latest/download/loki-linux-amd64.zip
unzip loki-linux-amd64.zip
sudo mv loki-linux-amd64 /usr/local/bin/loki

cat <<EOF | sudo tee /usr/local/bin/loki-config.yml
auth_enabled: false
server:
  http_listen_port: 3100
ingester:
  lifecycler:
    address: 127.0.0.1
    ring:
      kvstore:
        store: inmemory
      replication_factor: 1
    final_sleep: 0s
  chunk_idle_period: 5m
  chunk_retain_period: 30s
schema_config:
  configs:
    - from: 2022-06-01
      store: boltdb-shipper
      object_store: filesystem
      schema: v11
      index:
        prefix: index_
        period: 24h
EOF

# Démarrer Loki
nohup /usr/local/bin/loki -config.file=/usr/local/bin/loki-config.yml &

# Installer Promtail
wget https://github.com/grafana/loki/releases/latest/download/promtail-linux-amd64.zip
unzip promtail-linux-amd64.zip
sudo mv promtail-linux-amd64 /usr/local/bin/promtail

cat <<EOF | sudo tee /usr/local/bin/promtail-config.yml
server:
  http_listen_port: 9080
positions:
  filename: /tmp/positions.yaml
clients:
  - url: http://localhost:3100/loki/api/v1/push
scrape_configs:
  - job_name: 'java-logs'
    static_configs:
      - targets:
          - localhost
        labels:
          job: "java"
          host: "EC2"
          __path__: "/var/log/java/*.log"
EOF

# Démarrer Promtail
nohup /usr/local/bin/promtail -config.file=/usr/local/bin/promtail-config.yml &