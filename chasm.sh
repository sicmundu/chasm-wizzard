#!/bin/bash


CONFIG_FILE="$HOME/chasm/scouts.ini"
LOG_FILE="install_log_$(date +%F).log"
SPINNER="/-\|"

# Function to restart a selected scout
restart_selected_scout() {
    echo -e "\e[36mAvailable scouts:\e[0m"
    scouts=($(grep -oP '(?<=\[)[^]]+' "$CONFIG_FILE"))
    
    for i in "${!scouts[@]}"; do
        echo "$((i + 1))) ${scouts[$i]}"
    done

    read -p $'\e[33mSelect a scout to restart (enter the number): \e[0m' SCOUT_CHOICE

    if [[ "$SCOUT_CHOICE" -ge 1 && "$SCOUT_CHOICE" -le "${#scouts[@]}" ]]; then
        selected_scout="${scouts[$((SCOUT_CHOICE - 1))]}"
        config=$(get_scout_config "$selected_scout")
        SCOUT_PORT=$(echo "$config" | grep "port" | cut -d'=' -f2 | xargs)

        log "\e[36mRestarting selected scout '$selected_scout'...\e[0m"
        restart_scout "$selected_scout" "$SCOUT_PORT"
    else
        echo -e "\e[31mInvalid choice. Exiting...\e[0m"
        exit 1
    fi
}

# Функция для генерации имени нового скаута
generate_scout_name() {
    base_name="shadow_scout"
    count=$(grep -oP '\[shadow_scout_\d+\]' "$CONFIG_FILE" | wc -l)
    SCOUT_NAME="${base_name}_$((count + 1))"
    echo "$SCOUT_NAME"
}

update_env_file_with_port() {
    scout_name=$1
    current_port=$2
    env_file="$HOME/chasm/.env_$scout_name"

    # Убедитесь, что порт в .env совпадает с портом в конфиге
    if grep -q "PORT=" "$env_file"; then
        sed -i "s/^PORT=.*/PORT=$current_port/" "$env_file"
    else
        echo "PORT=$current_port" >> "$env_file"
    fi

    # Обновляем WEBHOOK_URL с новым портом
    if grep -q "WEBHOOK_URL=" "$env_file"; then
        sed -i "s|^WEBHOOK_URL=.*|WEBHOOK_URL=http://${EXTERNAL_IP}:${current_port}|" "$env_file"
    else
        echo "WEBHOOK_URL=http://${EXTERNAL_IP}:${current_port}" >> "$env_file"
    fi
}

restart_all_scouts() {
    get_external_ip  # Получаем внешний IP перед использованием

    if [ -f "$CONFIG_FILE" ]; then
        while IFS= read -r scout_name; do
            config=$(get_scout_config "$scout_name")
            SCOUT_PORT=$(echo "$config" | grep "port" | cut -d'=' -f2 | xargs)
            SCOUT_STATUS=$(echo "$config" | grep "status" | cut -d'=' -f2 | xargs)

            if [ "$SCOUT_STATUS" == "active" ]; then
                # Удаляем существующий контейнер перед созданием нового
                if [ "$(docker ps -a --filter "name=scout_$scout_name" --format '{{.Names}}')" ]; then
                    log "\e[33m⚠️ Container 'scout_$scout_name' already exists. Removing it...\e[0m"
                    docker rm -f scout_$scout_name
                fi

                # Проверяем и обновляем порт в .env файле и конфигурации, если нужно
                update_env_file_with_port "$scout_name" "$SCOUT_PORT"

                # Пересоздаем контейнер
                log "\e[36m🔄 Recreating scout '$scout_name'...\e[0m"
                docker run -d --restart=always --env-file $HOME/chasm/.env_$scout_name -p $SCOUT_PORT:$SCOUT_PORT --name scout_$scout_name chasmtech/chasm-scout
                if [ $? -eq 0 ]; then
                    echo -e "\e[32m✅ Successfullаy recreated scout '$scout_name' on port $SCOUT_PORT\e[0m"
                    update_scout_status "$scout_name" "active"
                else
                    echo -e "\e[31m❌ Failed to recreate scout '$scout_name'. Please check the Docker logs for details.\e[0m"
                fi
            else
                echo -e "\e[33mScout '$scout_name' is configured but marked as inactive.\e[0m"
            fi
        done < <(grep -oP '(?<=\[)[^]]+' "$CONFIG_FILE")
    else
        log "\e[33m⚠️ Configuration file $CONFIG_FILE does not exist. Skipping scout restart.\e[0m"
    fi
}

add_scout_to_config() {
    cat <<EOF >> "$CONFIG_FILE"

[$SCOUT_NAME]
name = $SCOUT_NAME
port = $SCOUT_PORT
status = active
EOF
}

restart_scout() {
    scout_name=$1
    config=$(awk -v scout="$scout_name" 'BEGIN{FS=" = "} $0 ~ "\\["scout"\\]" {in_scout=1} in_scout && $1 == "port" {print $2; exit}' "$CONFIG_FILE")
    scout_port=$(echo "$config" | xargs)  # Убираем лишние пробелы
    env_file="$HOME/chasm/.env_$scout_name"

    # Логируем значения перед перезапуском контейнера
    log "\e[36mDEBUG: Scout Name: $scout_name\e[0m"
    log "\e[36mDEBUG: Scout Port: $scout_port\e[0m"
    log "\e[36mDEBUG: Env File: $env_file\e[0m"

    # Удаляем существующий контейнер перед созданием нового
    if [ "$(docker ps -a --filter "name=scout_$scout_name" --format '{{.Names}}')" ]; then
        log "\e[33m⚠️ Container 'scout_$scout_name' already exists. Attempting to remove it...\e[0m"
        docker rm -f scout_$scout_name
    fi

    log "\e[36m🔄 Attempting to restart scout '$scout_name'...\e[0m"

    # Запускаем Docker контейнер с правильным указанием порта
    docker run -d --restart=always --env-file "$env_file" -p "$scout_port:$scout_port" --name "scout_$scout_name" chasmtech/chasm-scout

    if [ $? -eq 0 ]; then
        echo -e "\e[32m✅ Successfully restarted scout '$scout_name' on port $scout_port\e[0m"
        update_scout_status "$scout_name" "active"
    else
        echo -e "\e[31m❌ Failed to restart scout '$scout_name'. Please check the Docker logs for details.\e[0m"
    fi
}

# Function to parse INI file and get specific scout details
get_scout_config() {
    scout_name=$1
    section=$(awk -F' = ' -v scout="$scout_name" '
    $0 ~ "\\["scout"\\]" {found=1; next}
    found && $1 == "port" {port=$2}
    found && $1 == "status" {status=$2}
    found && $0 ~ /^\[/ {found=0}
    END {print "port = " port "\nstatus = " status}
    ' "$CONFIG_FILE")
    echo "$section"
}

# Function to update the status of a scout in the INI file
update_scout_status() {
    scout_name=$1
    new_status=$2
    sed -i "/^\[$scout_name\]$/,/^status =/ s/^status =.*/status = $new_status/" "$CONFIG_FILE"
}

setup_chasm_directory() {
    if [ ! -d "$HOME/chasm" ]; then
        log "\e[36m📂 Creating chasm directory at $HOME/chasm...\e[0m"
        mkdir -p $HOME/chasm
    fi
}

get_used_ports() {
    docker ps --format '{{.Names}} {{.Ports}}' | grep scout_ | awk '{print $2}' | cut -d':' -f2 | cut -d'-' -f1
}

migrate_old_scout() {
    OLD_SCOUT_NAME="scout"
    OLD_SCOUT_PORT="3032"

    if [ "$(docker inspect -f '{{.State.Running}}' $OLD_SCOUT_NAME 2>/dev/null)" == "true" ]; then
        log "\e[33m⚠️ Detected legacy scout running on port $OLD_SCOUT_PORT with name $OLD_SCOUT_NAME.\e[0m"
        read -p $'\e[33m🛠️ Would you like to migrate this scout to the new system? (y/n): \e[0m' MIGRATE_CHOICE
        if [ "$MIGRATE_CHOICE" == "y" ]; then
            NEW_SCOUT_NAME="scout_legacy"
            docker stop $OLD_SCOUT_NAME
            docker rm $OLD_SCOUT_NAME

            log "\e[36m🔄 Migrating old scout to new configuration...\e[0m"

            SCOUT_PORT=$(get_next_available_port)
            ENV_FILE="$HOME/chasm/.env_$NEW_SCOUT_NAME"

            cat <<EOF > $ENV_FILE
PORT=$SCOUT_PORT
LOGGER_LEVEL=debug

# Chasm
ORCHESTRATOR_URL=https://orchestrator.chasm.net
SCOUT_NAME=$NEW_SCOUT_NAME
SCOUT_UID=$(grep "SCOUT_UID=" "$HOME/chasm/.env" | cut -d'=' -f2)
WEBHOOK_API_KEY=$(grep "WEBHOOK_API_KEY=" "$HOME/chasm/.env" | cut -d'=' -f2)
WEBHOOK_URL=http://${EXTERNAL_IP}:${SCOUT_PORT}

# Chosen Provider (groq, openai)
PROVIDERS=groq
MODEL=gemma2-9b-it
GROQ_API_KEY=$(grep "GROQ_API_KEY=" "$HOME/chasm/.env" | cut -d'=' -f2)

NODE_ENV=production
EOF

            log "\e[36m🚀 Relaunching the migrated scout with the new configuration...\e[0m"
            docker run -d --restart=always --env-file $ENV_FILE -p $SCOUT_PORT:$SCOUT_PORT --name $NEW_SCOUT_NAME chasmtech/chasm-scout
            update_scout_status "$NEW_SCOUT_NAME" "active"
            log "\e[32m✅ Migration completed! Scout is now running with name $NEW_SCOUT_NAME on port $SCOUT_PORT.\e[0m"
        fi
    else
        log "\e[32m💡 No legacy scout detected. Proceeding with the standard setup.\e[0m"
    fi
}

get_next_available_port() {
    USED_PORTS=$(get_used_ports)
    CONFIG_PORTS=$(grep -oP 'port = \K\d+' "$CONFIG_FILE")
    ALL_PORTS=$(echo -e "$USED_PORTS\n$CONFIG_PORTS" | sort -n | uniq)

    PORT=3032
    while echo "$ALL_PORTS" | grep -q "^$PORT$"; do
        PORT=$((PORT+1))
    done
    echo $PORT
}

check_existing_scouts() {
    if [ -f "$CONFIG_FILE" ]; then
        while IFS= read -r scout_name; do
            config=$(get_scout_config "$scout_name")
            SCOUT_PORT=$(echo "$config" | grep "port" | cut -d'=' -f2 | xargs)
            SCOUT_STATUS=$(echo "$config" | grep "status" | cut -d'=' -f2 | xargs)

            if [ "$SCOUT_STATUS" == "active" ]; then
                if [ "$(docker ps --filter "name=scout_$scout_name" --format '{{.Names}}')" ]; then
                    echo -e "\e[32m💡 Scout '$scout_name' is running on port $SCOUT_PORT\e[0m"
                else
                    restart_scout "$scout_name" "$SCOUT_PORT"
                fi
            else
                echo -e "\e[33mScout '$scout_name' is configured but marked as inactive.\e[0m"
            fi
        done < <(grep -oP '(?<=\[)[^]]+' "$CONFIG_FILE")
    else
        log "\e[33m⚠️ Configuration file $CONFIG_FILE does not exist. Skipping scout check.\e[0m"
    fi
}

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

    # Проверка наличия GROQ_API_KEY в существующем файле .env
    if [ -f "$HOME/chasm/.env" ] && grep -q "GROQ_API_KEY=" "$HOME/chasm/.env"; then
        GROQ_API_KEY=$(grep "GROQ_API_KEY=" "$HOME/chasm/.env" | cut -d'=' -f2)
        echo -e "\e[32m🔑 Found existing GROQ_API_KEY in .env: $GROQ_API_KEY\e[0m"
    elif [ -f "$HOME/chasm/GROQ_API_KEY.env" ]; then
        source "$HOME/chasm/GROQ_API_KEY.env"
        echo -e "\e[32m🔑 Found existing GROQ_API_KEY in GROQ_API_KEY.env: $GROQ_API_KEY\e[0m"
    else
        read -p $'\e[33m🛠️ GROQ_API_KEY: \e[0m' GROQ_API_KEY
        mkdir -p $HOME/chasm
        echo "GROQ_API_KEY=$GROQ_API_KEY" > $HOME/chasm/GROQ_API_KEY.env
    fi

    SCOUT_NAME=$(generate_scout_name)  # Автоматически генерируем имя скаута
    read -p $'\e[33m🔐 SCOUT_UID: \e[0m' SCOUT_UID
    read -p $'\e[33m🔑 WEBHOOK_API_KEY: \e[0m' WEBHOOK_API_KEY
}

get_external_ip() {
    EXTERNAL_IP=$(curl -s https://api.ipify.org)
    if [ -z "$EXTERNAL_IP" ]; then
        log "\e[31m💥 Couldn't fetch your external IP. Halting...\e[0m"
        exit 1
    fi
}

create_env_file() {
    get_external_ip
    log "\e[36m📂 Step 4: Crafting your environment file for $SCOUT_NAME...\e[0m"

    cd $HOME/chasm

    SCOUT_PORT=$(get_next_available_port)
    ENV_FILE=".env_$SCOUT_NAME"

    # Генерация уникального порта для WEBHOOK_URL на основе SCOUT_PORT
    WEBHOOK_URL="http://${EXTERNAL_IP}:${SCOUT_PORT}"

    cat <<EOF > $ENV_FILE
PORT=$SCOUT_PORT
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

    # Обновление конфигурационного файла
    cat <<EOF >> $CONFIG_FILE
[$SCOUT_NAME]
name = $SCOUT_NAME
port = $SCOUT_PORT
status = active
EOF
}

configure_firewall() {
    log "\e[36m🔥 Step 5: Let’s fire up that firewall...\e[0m"
    sudo ufw allow $SCOUT_PORT
}

run_docker_container() {
    log "\e[36m🚀 Launching the Docker container for $SCOUT_NAME... Hold on tight!\e[0m"
    sleep 5 

    docker pull chasmtech/chasm-scout
    docker run -d --restart=always --env-file $HOME/chasm/.env_$SCOUT_NAME -p $SCOUT_PORT:$SCOUT_PORT --name scout_$SCOUT_NAME chasmtech/chasm-scout
    if [ $? -eq 0 ]; then
        echo -e "\e[32m✅ Successfully launched scout '$SCOUT_NAME' on port $SCOUT_PORT\e[0m"
    else
        echo -e "\e[31m❌ Failed to launch scout '$SCOUT_NAME'. Please check the Docker logs for details.\e[0m"
    fi
}

restart_node() {
    log "\e[36m🔄 Step 7: Restarting your node for good measure...\e[0m"
    docker stop scout
    docker rm scout
    docker run -d --restart=always --env-file ./.env -p 3032:3032 --name scout chasmtech/chasm-scout
}


main() {
    echo -e "\n\e[1;34m╔═════════════════════════════════════════════╗\e[0m"
    echo -e "\e[1;34m║            \e[36mChasm Scout Manager\e[1;34m              ║\e[0m"
    echo -e "\e[1;34m╚═════════════════════════════════════════════╝\e[0m\n"

    echo -e "\e[36mPlease select an action:\e[0m"
    echo -e "\e[1;33m1)\e[0m \e[32mAdd a new scout\e[0m"
    echo -e "\e[1;33m2)\e[0m \e[32mStart or restart all existing scouts\e[0m"
    echo -e "\e[1;33m3)\e[0m \e[32mRestart a specific scout\e[0m"
    echo -e "\e[1;33m4)\e[0m \e[32mList all running scouts and check statuses\e[0m"
    echo -e "\e[1;34m─────────────────────────────────────────────\e[0m"
    read -p $'\e[33mChoose an option (1, 2, 3, or 4): \e[0m' ACTION_CHOICE

    if [ "$ACTION_CHOICE" == "1" ]; then
        # Добавление нового скаута
        check_system_health
        check_docker_installed
        install_dependencies
        install_docker
        setup_chasm_directory  
        migrate_old_scout  
        check_existing_scouts
        prompt_user_input
        create_env_file
        configure_firewall
        run_docker_container
        log "\e[32m✅ All set and done! Your new node is up and running!\e[0m"
        log "\e[31m⚠️ Make sure your SSH port is open if UFW is enabled.\e[0m"
        exit 0
    elif [ "$ACTION_CHOICE" == "2" ]; then
        # Полный рестарт всех скаутов (удаление и создание заново)
        setup_chasm_directory
        restart_all_scouts
        log "\e[32m✅ All existing scouts have been fully restarted!\e[0m"
        exit 0
    elif [ "$ACTION_CHOICE" == "3" ]; then
        # Перезапуск выбранного скаута
        setup_chasm_directory
        restart_selected_scout
        log "\e[32m✅ The selected scout has been restarted!\e[0m"
        exit 0
    elif [ "$ACTION_CHOICE" == "4" ]; then
        # Вывод списка всех работающих скаутов и проверка статусов
        list_running_scouts
        exit 0
    else
        echo -e "\e[31mInvalid choice. Exiting...\e[0m"
        exit 1
    fi
}

list_running_scouts() {
    echo -e "\n\e[1;34m╔═════════════════════════════════════════════╗\e[0m"
    echo -e "\e[1;34m║          \e[36mList of Running Scouts\e[1;34m             ║\e[0m"
    echo -e "\e[1;34m╚═════════════════════════════════════════════╝\e[0m\n"

    if [ -f "$CONFIG_FILE" ]; then
        while IFS= read -r scout_name; do
            config=$(get_scout_config "$scout_name")
            SCOUT_PORT=$(echo "$config" | grep -oP '(?<=port = ).*')
            SCOUT_STATUS=$(echo "$config" | grep -oP '(?<=status = ).*')



            if [ "$(docker ps --filter "name=scout_$scout_name" --format '{{.Names}}')" ]; then
                echo -e "\e[32m💡 Scout '$scout_name' is running on port $SCOUT_PORT\e[0m"

                if [ "$SCOUT_STATUS" != "active" ]; then
                    echo -e "\e[33m⚠️  Warning: Scout '$scout_name' is not marked as active in the configuration!\e[0m"
                fi
            else
                echo -e "\e[31m❌ Scout '$scout_name' is not running but is configured on port $SCOUT_PORT\e[0m"
            fi
        done < <(grep -oP '(?<=\[)[^]]+' "$CONFIG_FILE")
    else
        log "\e[33m⚠️ Configuration file $CONFIG_FILE does not exist. Unable to list scouts.\e[0m"
    fi
}

main