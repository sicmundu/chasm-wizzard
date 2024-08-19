#!/bin/bash

LOG_FILE="install_log_$(date +%F).log"
SPINNER="/-\|"

# Spinner function for progress indication
spin() {
    i=0
    while kill -0 $1 2>/dev/null; do
        i=$(( (i+1) %4 ))
        printf "\r\e[36m%s\e[0m" "${SPINNER:$i:1}"
        sleep 0.1
    done
    echo -ne "\r"
}

# Enhanced logging
log() {
    echo -e "$1" | tee -a $LOG_FILE
}

check_system_health() {
    log "\e[36m🔍 Running system health check...\e[0m"
    FREE_SPACE=$(df -h / | grep -vE '^Filesystem' | awk '{print $4}')
    CPU_LOAD=$(uptime | awk '{print $10}')
    log "\e[36mDisk space available: $FREE_SPACE\e[0m"
    log "\e[36mCurrent CPU load: $CPU_LOAD\e[0m"
    if [ "$(echo $FREE_SPACE | sed 's/G//' | cut -d. -f1)" -lt 5 ]; then
        log "\e[31m⚠️ Warning: Low disk space! Proceed with caution.\e[0m"
    fi
}

check_docker_installed() {
    if command -v docker &> /dev/null; then
        log "\e[32m🐳 Docker's already on board! Skipping installation...\e[0m"
        DOCKER_INSTALLED=true
    else
        log "\e[36m🐳 Docker's not here yet. Let’s get it installed...\e[0m"
        DOCKER_INSTALLED=false
    fi
}

check_dependencies_installed() {
    log "\e[36m🔍 Checking for required dependencies...\e[0m"
    PACKAGES="ca-certificates curl ufw"
    for package in $PACKAGES; do
        if dpkg -l | grep -qw $package; then
            log "\e[32m✅ $package is already installed!\e[0m"
        else
            log "\e[36m🔧 $package is missing. We’ll install it now...\e[0m"
            sudo apt-get install -y $package
        fi
    done
}

install_dependencies() {
    log "\e[36m🔧 Step 1: Updating system and locking down dependencies...\e[0m"
    sudo apt-get update && sudo apt-get upgrade -y &
    spin $!
    check_dependencies_installed
}

install_docker() {
    if [ "$DOCKER_INSTALLED" = false ]; then
        sudo install -m 0755 -d /etc/apt/keyrings
        for pkg in docker.io docker-doc docker-compose docker-compose-v2 podman-docker containerd runc; do sudo apt-get remove $pkg; done
        sudo apt-get update
        sudo apt-get install ca-certificates curl
        sudo install -m 0755 -d /etc/apt/keyrings
        sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
        sudo chmod a+r /etc/apt/keyrings/docker.asc

        echo \
        "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
        $(. /etc/os-release && echo \"$VERSION_CODENAME\") stable" | \
        sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

        sudo apt-get update
        sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin screen &
        spin $!
    fi
    sudo systemctl restart docker
}

prompt_user_input() {
    echo -e "\e[36m📝 Step 3: Let’s get your details...\e[0m"
    echo -e "\e[33m👉 Drop in the following deets:\e[0m"
    read -p $'\e[33m💻 SCOUT_NAME (Node Name): \e[0m' SCOUT_NAME
    read -p $'\e[33m🔐 SCOUT_UID: \e[0m' SCOUT_UID
    read -p $'\e[33m🔑 WEBHOOK_API_KEY: \e[0m' WEBHOOK_API_KEY
    read -p $'\e[33m🛠️ GROQ_API_KEY: \e[0m' GROQ_API_KEY
}

get_external_ip() {
    EXTERNAL_IP=$(curl -s https://api.ipify.org)
    if [ -z "$EXTERNAL_IP" ]; then
        log "\e[31m💥 Couldn't fetch your external IP. Halting...\e[0m"
        exit 1
    fi
    WEBHOOK_URL="http://${EXTERNAL_IP}:3032"
}

create_env_file() {
    get_external_ip
    log "\e[36m📂 Step 4: Crafting your environment file...\e[0m"
    cd $HOME
    if [ ! -d "chasm" ]; then
        mkdir chasm
    else
        log "\e[33m⚠️ Heads up! The 'chasm' directory is already there. We’ll roll with it.\e[0m"
    fi
    cd chasm
    if [ -f ".env" ]; then
        log "\e[33m⚠️ Found an existing '.env' file. We’re overwriting it.\e[0m"
    fi
    cat <<EOF > .env
PORT=3032
LOGGER_LEVEL=debug

# Chasm
ORCHESTRATOR_URL=https://orchestrator.chasm.net
SCOUT_NAME=$SCOUT_NAME
SCOUT_UID=$SCOUT_UID
WEBHOOK_API_KEY=$WEBHOOK_API_KEY
WEBHOOK_URL=$WEBHOOK_URL

# Chosen Provider (groq, openai)
PROVIDERS=groq
MODEL=gemma2-9b-it
GROQ_API_KEY=$GROQ_API_KEY

NODE_ENV=production
EOF
}

configure_firewall() {
    log "\e[36m🔥 Step 5: Let’s fire up that firewall...\e[0m"
    sudo ufw allow 3032
}

run_docker_container() {
    log "\e[36m🚀 Step 6: Launching the Docker container... Hold on tight!\e[0m"
    docker pull chasmtech/chasm-scout
    docker run -d --restart=always --env-file ./.env -p 3032:3032 --name scout chasmtech/chasm-scout
}

restart_node() {
    log "\e[36m🔄 Step 7: Restarting your node for good measure...\e[0m"
    docker stop scout
    docker rm scout
    docker run -d --restart=always --env-file ./.env -p 3032:3032 --name scout chasmtech/chasm-scout
}

main() {
    check_system_health
    check_docker_installed
    install_dependencies
    install_docker
    prompt_user_input
    create_env_file
    configure_firewall
    run_docker_container
    log "\e[32m✅ All set and done! Your node is up and running!\e[0m"
    log "\e[31m⚠️ Make sure your SSH port is open if UFW is enabled.\e[0m"
}

main