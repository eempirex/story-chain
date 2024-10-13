#!/bin/bash

# Define text colors for logs
green="\e[32m"
red="\e[31m"
yellow="\e[33m"
blue="\e[34m"
purple="\e[35m"
cyan="\e[36m"
reset="\e[0m"

# Function: Display success message
log_success() {
    echo -e "${green}[✔ SUCCESS] $1${reset}"
}

# Function: Display error message
log_error() {
    echo -e "${red}[✘ ERROR] $1${reset}"
}

# Function: Display warning message
log_warning() {
    echo -e "${yellow}[⚠ WARNING] $1${reset}"
}

# Function: Display info message
log_info() {
    echo -e "${blue}[ℹ INFO] $1${reset}"
}

# Function: Display process message
log_process() {
    echo -e "${cyan}[... PROCESSING] $1${reset}"
}

# Function: Display important message
log_important() {
    echo -e "${purple}[★ IMPORTANT] $1${reset}"
}

# Function: Ensure the script is run as root
ensure_root() {
    log_info "Checking if the script is running as root..."
    if [ "$EUID" -ne 0 ]; then
        log_error "This script must be run as root. Exiting..."
        exit 1
    fi
    log_success "User has root privileges."
}

# Function: Update and upgrade the system
update_system() {
    log_important "Preparing to update and upgrade the system..."
    apt-get update -y
    DEBIAN_FRONTEND=noninteractive apt-get upgrade -y
    log_success "System successfully updated and upgraded."
}

# Function: Install necessary dependencies
install_dependencies() {
    log_important "Installing required dependencies for the setup..."
    apt-get install -y curl tar wget original-awk gawk netcat jq
    log_success "Dependencies installed successfully."
}

# Display banner using figlet
display_banner() {
    sleep 1
    echo -e '\e[40m\e[92m'
    figlet Empirex
    echo -e '\e[0m'
    sleep 2
}

# Function: Get node status and configuration
get_node_status() {
    log_info "Fetching the node status and network configuration..."
    
    # Extract the port number from the [rpc] section in the config.toml file
    port=$(awk '/\[rpc\]/ {f=1} f && /laddr/ {match($0, /127.0.0.1:([0-9]+)/, arr); print arr[1]; f=0}' $HOME/.story/story/config/config.toml)
    
    # Use the extracted port in your curl request
    json_data=$(curl -s http://localhost:$port/status)
    
    story_address=$(echo "$json_data" | jq -r '.result.validator_info.address')
    network=$(echo "$json_data" | jq -r '.result.node_info.network')

    touch .bash_profile
    source .bash_profile
    log_success "Node status successfully retrieved."
}

# Function: Check the status of a service
check_service_status() {
    local service_name="$1"
    log_process "Checking the status of the service: $service_name"
    if systemctl is-active --quiet "$service_name"; then
        log_success "$service_name is running."
    else
        log_warning "$service_name is not running."
    fi
}

# Function: Create necessary directories
create_directories() {
    log_info "Creating essential directories for Prometheus setup..."
    local directories=("/var/lib/prometheus" "/etc/prometheus/rules" "/etc/prometheus/rules.d" "/etc/prometheus/files_sd")

    for dir in "${directories[@]}"; do
        if [ -d "$dir" ] && [ "$(ls -A $dir)" ]; then
            log_warning "Directory $dir already exists and is not empty. Skipping..."
        else
            mkdir -p "$dir"
            log_success "Created directory: $dir"
        fi
    done
}

# Function: Download and install Prometheus
install_prometheus() {
    log_important "Downloading and installing Prometheus..."
    cd $HOME
    rm -rf prometheus*
    wget https://github.com/prometheus/prometheus/releases/download/v2.45.0/prometheus-2.45.0.linux-amd64.tar.gz
    sleep 1
    tar xvf prometheus-2.45.0.linux-amd64.tar.gz
    rm prometheus-2.45.0.linux-amd64.tar.gz
    cd prometheus*/

    [ -d "/etc/prometheus/consoles" ] && [ "$(ls -A /etc/prometheus/consoles)" ] || mv consoles /etc/prometheus/
    [ -d "/etc/prometheus/console_libraries" ] && [ "$(ls -A /etc/prometheus/console_libraries)" ] || mv console_libraries /etc/prometheus/

    mv prometheus promtool /usr/local/bin/
    log_success "Prometheus installed successfully."
}

# Function: Configure Prometheus
configure_prometheus() {
    log_info "Setting up Prometheus configuration..."
    [ -f "/etc/prometheus/prometheus.yml" ] && rm "/etc/prometheus/prometheus.yml"

    sudo tee /etc/prometheus/prometheus.yml <<EOF
global:
  scrape_interval: 15s
  evaluation_interval: 15s
alerting:
  alertmanagers:
    - static_configs:
        - targets: []
rule_files: []
scrape_configs:
  - job_name: "prometheus"
    metrics_path: /metrics
    static_configs:
      - targets: ["localhost:9345"]
  - job_name: "story"
    scrape_interval: 5s
    metrics_path: /
    static_configs:
      - targets: ['localhost:26660']
EOF
    log_success "Prometheus configuration completed."
}

# Function: Create Prometheus systemd service
create_prometheus_service() {
    log_info "Creating systemd service for Prometheus..."
    sudo tee /etc/systemd/system/prometheus.service <<EOF
[Unit]
Description=Prometheus
Wants=network-online.target
After=network-online.target
[Service]
Type=simple
User=root
ExecReload=/bin/kill -HUP \$MAINPID
ExecStart=/usr/local/bin/prometheus \
  --config.file=/etc/prometheus/prometheus.yml \
  --storage.tsdb.path=/var/lib/prometheus \
  --web.console.templates=/etc/prometheus/consoles \
  --web.console.libraries=/etc/prometheus/console_libraries \
  --web.listen-address=0.0.0.0:9344
Restart=always
[Install]
WantedBy=multi-user.target
EOF
    log_success "Prometheus service created successfully."
}

# Function: Reload systemd and start Prometheus
start_prometheus() {
    log_process "Reloading systemd and starting Prometheus service..."
    systemctl daemon-reload
    systemctl enable prometheus
    systemctl start prometheus
    check_service_status "prometheus"
}

# Function: Install Grafana
install_grafana() {
    log_important "Installing Grafana monitoring platform..."
    apt-get install -y apt-transport-https software-properties-common wget
    wget -q -O - https://packages.grafana.com/gpg.key | apt-key add -
    echo "deb https://packages.grafana.com/enterprise/deb stable main" | tee -a /etc/apt/sources.list.d/grafana.list
    apt-get update -y
    apt-get install grafana-enterprise -y
    systemctl daemon-reload
    systemctl enable grafana-server
    systemctl start grafana-server
    check_service_status "grafana-server"
    log_success "Grafana installed successfully."
}

# Function: Download and modify grafana-dashboard.json with dynamic validator address
modify_story_json() {
    prometheus_url="http://localhost:9344"
    dashboard_url="https://raw.githubusercontent.com/eempirex/story-chain/refs/heads/main/grafana-dashboard.json"
    
    log_info "Downloading and modifying the grafana-dashboard.json..."
    curl -s "$dashboard_url" -o $HOME/grafana-dashboard.json

    log_info "Replacing validator address in the grafana-dashboard.json..."
    sed -i "s/3EFC18878454304004F18E8B3BFF7BC8ED166D10/$story_address/g" $HOME/grafana-dashboard.json
    log_success "grafana-dashboard.json modified successfully."
}

# Function: Configure Prometheus data source in Grafana
configure_grafana_datasource() {
    log_info "Configuring Prometheus data source in Grafana..."
    grafana_host="http://localhost:9346"
    admin_user="admin"
    admin_password="admin"

    curl -X POST "$grafana_host/api/datasources" \
        -H "Content-Type: application/json" \
        -u "$admin_user:$admin_password" \
        -d '{
              "name": "Prometheus",
              "type": "prometheus",
              "access": "proxy",
              "url": "'"$prometheus_url"'",
              "basicAuth": false,
              "isDefault": true,
              "jsonData": {}
            }'
    log_success "Prometheus data source configured successfully in Grafana."
}

# Function: Import dashboard into Grafana
import_grafana_dashboard() {
    log_info "Importing the modified dashboard into Grafana..."
    grafana_host="http://localhost:9346"
    admin_user="admin"
    admin_password="admin"

    curl -X POST "$grafana_host/api/dashboards/db" \
        -H "Content-Type: application/json" \
        -u "$admin_user:$admin_password" \
        -d '{
              "dashboard": '"$(cat "$HOME/grafana-dashboard.json")"',
              "overwrite": true,
              "folderId": 0
            }'
    log_success "Dashboard successfully imported into Grafana."

    # Log the access URL
    real_ip=$(hostname -I | awk '{print $1}')
    log_info "Access your Grafana dashboard at: http://$real_ip:9346/d/Empirex/"
}

# Function: Main execution block
main() {
    ensure_root
    update_system
    install_dependencies
    display_banner
    get_node_status
    create_directories
    install_prometheus
    configure_prometheus
    create_prometheus_service
    start_prometheus
    install_grafana
    modify_story_json
    configure_grafana_datasource
    import_grafana_dashboard
}

# Run the main function
main
