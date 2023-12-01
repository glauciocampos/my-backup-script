#!/bin/bash

# Parameters
REMOTE_HOST="$3"
REMOTE_USER="$4"
REMOTE_PATH="$5"
TELEGRAM_BOT_TOKEN="$6"
TELEGRAM_CHAT_ID="$7"
RESTART_SERVICE="$8"
SERVICE_NAME="$9"

# Check if enough parameters were provided
if [ "$#" -lt 5 ]; then
    echo "Usage: $0 <path1,path2,...> <name1,name2,...> <remote-host> <remote-user> <remote-path> <bot-token> <chat-id> <restart-service(boolean)> <service-name>"
    exit 1
fi

# Check if mandatory parameters are not empty or null
if [[ -z "$1" || -z "$2" || -z "$3" || -z "$4" || -z "$5" || -z "$6" || -z "$7" ]]; then
    echo "All parameters must be provided and cannot be empty."
    exit 1
fi

# Convert arguments to arrays
SOURCE_PATHS=($(echo "$1" | tr ',' '\n'))
BACKUP_FILE_NAMES=($(echo "$2" | tr ',' '\n'))

# Function to check the availability of the remote host
check_remote_host() {
    echo "Checking the availability of the remote host..."
    while ! ping -c 1 -W 1 $REMOTE_HOST > /dev/null; do
        echo "The remote host is not online. Waiting 15 minutes before trying again..."
        sleep 900  # Wait for 15 minutes (900 seconds)
    done
    echo "Remote host online. Continuing with the backup."
}

# Function to send message to Telegram
send_telegram_message() {
    MESSAGE="Backup $backup_status at $(date +'%Y-%m-%d %H:%M:%S')"
    curl -s -X POST "https://api.telegram.org/bot$TELEGRAM_BOT_TOKEN/sendMessage" -d "chat_id=$TELEGRAM_CHAT_ID" -d "text=$MESSAGE"
}

if [[ $RESTART_SERVICE -eq 1 ]] || [[ $RESTART_SERVICE == "true" ]]; then
    # Stop the k3s service
    echo "Stopping the k3s service..."
    sudo systemctl enable --now $SERVICE_NAME
fi

# Check the availability of the remote host
check_remote_host

# Local temporary directory for compression
TEMP_DIR="/tmp/backup_temp"
mkdir -p "$TEMP_DIR"

# Compress files locally using bzip2 with the -k option
echo "Compressing files locally..."
tar -cvf - "${SOURCE_PATHS[@]}" | bzip2 -k -c > "$TEMP_DIR/backup-$(IFS=-; echo "${BACKUP_FILE_NAMES[*]}")-$(date +'%Y%m%d').tar.bz2"

# Test the integrity of the compressed file
echo "Testing the integrity of the compressed file..."
bzip2 -t "$TEMP_DIR/backup-$(IFS=-; echo "${BACKUP_FILE_NAMES[*]}")-$(date +'%Y%m%d').tar.bz2"

# Transfer compressed file to the remote host using rsync
echo "Transferring compressed file to the remote host using rsync..."
rsync -a --partial --progress "$TEMP_DIR/backup-$(IFS=-; echo "${BACKUP_FILE_NAMES[*]}")-$(date +'%Y%m%d').tar.bz2" "$REMOTE_USER@$REMOTE_HOST:$REMOTE_PATH"

if [ $? -eq 0 ]; then
    echo "Transfer successful. Removing local temporary file..."
    # Clean local temporary directory
    rm -rf "$TEMP_DIR"

    backup_status="completed successfully"

    # Send message to Telegram after the backup
    send_telegram_message

    echo "Backup completed!"
else
    echo "Error during transfer. Check and try again."
    rm -rf "$TEMP_DIR"

    backup_status="completed with failure"

    # Send message to Telegram after the backup
    send_telegram_message
fi

if [[ $RESTART_SERVICE -eq 1 ]] || [[ $RESTART_SERVICE == "true" ]]; then
    # Restart the k3s service
    echo "Starting the k3s service..."
    sudo systemctl enable --now $SERVICE_NAME
fi

echo "Backup $backup_status!"