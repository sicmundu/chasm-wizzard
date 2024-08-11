#!/bin/bash

# 🛠️ Welcome, intrepid explorer! Ready to bring your very own Chasm Network Testnet Node to life? Let’s make some magic happen.

# Step 1: The Setup Crew – Installing Dependencies (because nobody likes surprises halfway through)
echo -e "\e[34m🔧 Gearing up with some necessary tools...\e[0m"
sudo apt-get update && sudo apt-get upgrade -y
sudo apt-get install -y ca-certificates curl ufw

# Step 2: Docker, Your New Best Friend (Because this ship needs a sturdy captain)
echo -e "\e[34m🐳 All aboard the Docker ship...\e[0m"
sudo apt-get remove -y docker docker-engine docker.io containerd runc
sudo apt-get update
sudo apt-get install -y ca-certificates curl gnupg
sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo tee /etc/apt/keyrings/docker.gpg > /dev/null
if [ $? -ne 0 ]; then
    echo -e "\e[31m❌ Failed to download Docker GPG key. Exiting.\e[0m"
    exit 1
fi
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo \"$VERSION_CODENAME\") stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
sudo apt-get update
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin screen

# Step 3: ngrok, The Tunnel Master (Because every hero needs a secret passage)
echo -e "\e[34m🌐 Opening up the tunnels with ngrok...\e[0m"
if ! command -v ngrok &> /dev/null; then
    curl -s https://ngrok-agent.s3.amazonaws.com/ngrok.asc | sudo tee /etc/apt/trusted.gpg.d/ngrok.asc >/dev/null
    if [ $? -ne 0 ]; then
        echo -e "\e[31m❌ Failed to download ngrok GPG key. Exiting.\e[0m"
        exit 1
    fi
    echo "deb https://ngrok-agent.s3.amazonaws.com buster main" | sudo tee /etc/apt/sources.list.d/ngrok.list
    sudo apt-get update
    sudo apt-get install -y ngrok
fi

# Step 4: Sharing Secrets – Let’s Get Your Details (No cloak and dagger, just some quick inputs)
echo -e "\e[34m📝 We need a few details before we can proceed...\e[0m"
read -p $'\e[33mEnter your SCOUT_NAME (make it memorable!): \e[0m' SCOUT_NAME
read -p $'\e[33mEnter your SCOUT_UID: \e[0m' SCOUT_UID
read -p $'\e[33mEnter your WEBHOOK_API_KEY: \e[0m' WEBHOOK_API_KEY
read -p $'\e[33mEnter your GROQ_API_KEY: \e[0m' GROQ_API_KEY
read -p $'\e[33mEnter your ngrok Authtoken: \e[0m' NGROK_AUTHTOKEN

# Step 5: ngrok Setup – Preparing Your Secret Passage
ngrok config add-authtoken $NGROK_AUTHTOKEN
if [ $? -ne 0 ]; then
    echo -e "\e[31m❌ Failed to configure ngrok with the provided Authtoken. Exiting.\e[0m"
    exit 1
fi

# Time to freshen up – Close any old ngrok sessions
screen -ls | grep "ngrok_session" | cut -d. -f1 | awk '{print $1}' | xargs -I {} screen -S {} -X quit
if screen -ls | grep -q "ngrok_session"; then
    echo -e "\e[31m❌ Failed to terminate existing ngrok session. Exiting.\e[0m"
    exit 1
fi
screen -dmS ngrok_session
screen -S ngrok_session -p 0 -X stuff "ngrok http 3032\n"

# Step 6: Creating the Environment – Time to Set the Scene
echo -e "\e[34m📂 Preparing the environment...\e[0m"
EXTERNAL_IP=$(curl -s https://api.ipify.org)
WEBHOOK_URL="http://${EXTERNAL_IP}:3032"

cd $HOME
mkdir -p chasm
cd chasm

if [ -f ".env" ]; then
    echo -e "\e[33m⚠️ The .env file already exists in the chasm directory. Do you want to overwrite it? (y/n)\e[0m"
    read -p "Enter your choice: " choice
    if [ "$choice" != "y" ]; then
        echo -e "\e[31m🚫 Exiting without overwriting the .env file.\e[0m"
        exit 1
    fi
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

# Step 7: Fortify the Castle – Setting Up the Firewall (No invaders allowed)
echo -e "\e[34m🔥 Putting up the firewall defenses...\e[0m"
sudo ufw allow 3032

# Step 8: Liftoff! – Launching Your Node (Prepare for greatness)
echo -e "\e[34m🚀 Launching your Chasm Node into the wild...\e[0m"
docker pull chasmtech/chasm-scout
if [ $? -ne 0 ]; then
    echo -e “\e[31m❌ Failed to pull the Docker image. Exiting.\e[0m”
    exit 1
fi

docker run -d –restart=always –env-file ./.env -p 3032:3032 –name scout chasmtech/chasm-scout
if [ $? -ne 0 ]; then
    echo -e “\e[31m❌ Failed to launch the Docker container. Exiting.\e[0m”
    exit 1
fi

# And that’s a wrap!
echo -e "\e[32m✅ Congratulations! Your Chasm Network Testnet Node is now live. Take a moment to bask in your awesomeness.\e[0m"