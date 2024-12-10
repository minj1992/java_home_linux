#!/bin/bash

set -e  # Exit immediately if a command exits with a non-zero status.

# Usage: ./upgrade_jira.sh <new_version> <old_version>
# Example: ./upgrade_jira.sh 9.12.12 9.12.8

if [ $# -lt 2 ]; then
  echo "Please provide the new Jira version and the old Jira version."
  echo "Usage: $0 <new_version> <old_version>"
  exit 1
fi

NEW_VERSION="$1"
OLD_VERSION="$2"
JIRA_INSTALL_DIR="/App/JIRA"
JIRA_DATA_DIR="/App/JIRA_DATA"
JIRA_SHARED_DIR="/efs/JIRA_SHARED"
BACKUP_DIR="/jira_backup/jira_backup_$OLD_VERSION"
JIRA_BIN="$JIRA_INSTALL_DIR/bin/version.sh"
JIRA_DOWNLOAD_URL="https://product-downloads.atlassian.com/software/jira/downloads/atlassian-jira-software-$NEW_VERSION.zip"
TEMP_DOWNLOAD="/tmp/atlassian-jira-software-$NEW_VERSION.zip"
EXTRACT_DIR="/tmp/jira_$NEW_VERSION"
sudo yum install zip -y

# Backup flags
BACKUP_INSTALLATION=true   # Set to true if you want to backup Jira installation
BACKUP_DATA=true           # Set to true if you want to backup Jira data
BACKUP_SHARED=false         # Set to true if you want to backup Jira shared directory

# Function to print status and track the step
print_status() {
    echo "========> $1"
}

# Function to handle errors and print the step where the failure occurred
trap 'print_status "Error occurred at step: $CURRENT_STEP"; exit 1' ERR

# Step 1: Gather the current Jira version
CURRENT_STEP="Gathering the current Jira version"
print_status "$CURRENT_STEP"
CURRENT_VERSION=$(sh "$JIRA_BIN" 2>/dev/null | awk '/Version :/ {print $NF}')
echo "Current Jira version: $CURRENT_VERSION"

# Step 2: Stop the Jira service
CURRENT_STEP="Stopping Jira service"
print_status "$CURRENT_STEP"
sudo systemctl stop jira

# Step 3: Create backup directory if it doesn't exist
CURRENT_STEP="Creating backup directory for Jira version $OLD_VERSION"
print_status "$CURRENT_STEP"
if [ ! -d "$BACKUP_DIR" ]; then
    mkdir -p "$BACKUP_DIR"
    print_status "Backup directory created at $BACKUP_DIR"
else
    print_status "Backup directory already exists at $BACKUP_DIR"
fi

# Step 4: Backup Jira installation if BACKUP_INSTALLATION is true
if [ "$BACKUP_INSTALLATION" = true ]; then
    CURRENT_STEP="Backing up the Jira installation directory"
    print_status "$CURRENT_STEP"
    if [ -d "$JIRA_INSTALL_DIR" ]; then
        sudo zip -r "$BACKUP_DIR/jira_installation_backup_$OLD_VERSION.zip" "$JIRA_INSTALL_DIR" | sudo tee "$BACKUP_DIR/backup_log.txt" >/dev/null
        print_status "Jira installation backup created successfully."
    else
        print_status "Jira installation directory not found. Skipping backup."
    fi
else
    print_status "Skipping Jira installation backup as per configuration."
fi

# Step 5: Backup Jira data if BACKUP_DATA is true
if [ "$BACKUP_DATA" = true ]; then
    CURRENT_STEP="Backing up the Jira data directory"
    print_status "$CURRENT_STEP"
    if [ -d "$JIRA_DATA_DIR" ]; then
        sudo zip -r "$BACKUP_DIR/jira_data_backup_$OLD_VERSION.zip" "$JIRA_DATA_DIR" | sudo tee -a "$BACKUP_DIR/backup_log.txt" >/dev/null
        print_status "Jira data backup created successfully."
    else
        print_status "Jira data directory not found. Skipping backup."
    fi
else
    print_status "Skipping Jira data backup as per configuration."
fi

# Step 6: Backup Jira shared directory if BACKUP_SHARED is true
if [ "$BACKUP_SHARED" = true ]; then
    CURRENT_STEP="Backing up the Jira shared directory"
    print_status "$CURRENT_STEP"
    if [ -d "$JIRA_SHARED_DIR" ]; then
        sudo zip -r "$BACKUP_DIR/jira_shared_backup_$OLD_VERSION.zip" "$JIRA_SHARED_DIR" | sudo tee -a "$BACKUP_DIR/backup_log.txt" >/dev/null
        print_status "Jira shared directory backup created successfully."
    else
        print_status "Jira shared directory not found. Skipping backup."
    fi
else
    print_status "Skipping Jira shared directory backup as per configuration."
fi

# Step 7: Remove any existing Jira zip or extracted directory from /tmp
CURRENT_STEP="Checking for existing Jira files in /tmp"
print_status "$CURRENT_STEP"
if [ -f "$TEMP_DOWNLOAD" ]; then
    print_status "Removing existing Jira zip file in /tmp"
    rm -f "$TEMP_DOWNLOAD"
fi

if [ -d "$EXTRACT_DIR" ]; then
    print_status "Removing existing Jira extracted directory in /tmp"
    rm -rf "$EXTRACT_DIR"
fi

# Step 8: Download the new version of Jira
CURRENT_STEP="Downloading Jira version $NEW_VERSION"
print_status "$CURRENT_STEP"
wget "$JIRA_DOWNLOAD_URL" -O "$TEMP_DOWNLOAD"

# Step 9: Prepare the Installation Directory
CURRENT_STEP="Renaming current Jira installation"
print_status "$CURRENT_STEP"
mv "$JIRA_INSTALL_DIR" "${JIRA_INSTALL_DIR}_backup_$OLD_VERSION"

CURRENT_STEP="Extracting the new Jira version"
print_status "$CURRENT_STEP"
unzip "$TEMP_DOWNLOAD" -d "$EXTRACT_DIR"

CURRENT_STEP="Copying new Jira version to installation directory"
print_status "$CURRENT_STEP"
cp -R "$EXTRACT_DIR/atlassian-jira-software-$NEW_VERSION-standalone" "$JIRA_INSTALL_DIR"

# Step 10: Configure Jira home directory
CURRENT_STEP="Configuring Jira home directory"
print_status "$CURRENT_STEP"
sudo bash -c "echo 'jira.home = $JIRA_DATA_DIR' > /App/JIRA/atlassian-jira/WEB-INF/classes/jira-application.properties"


# Step 11: Copy Over Custom Configurations from Backup
CURRENT_STEP="Copying custom configurations (server.xml and setenv.sh) from the backup"
print_status "$CURRENT_STEP"
cp -rf "${JIRA_INSTALL_DIR}_backup_$OLD_VERSION/conf/server.xml" "$JIRA_INSTALL_DIR/conf/server.xml"
cp -rf "${JIRA_INSTALL_DIR}_backup_$OLD_VERSION/bin/setenv.sh" "$JIRA_INSTALL_DIR/bin/setenv.sh"
#cp -rf "${JIRA_INSTALL_DIR}_backup_$OLD_VERSION/jre" "$JIRA_INSTALL_DIR/"
cp -rf "${JIRA_INSTALL_DIR}_backup_$OLD_VERSION/atlassian-jira/WEB-INF/web.xml" "$JIRA_INSTALL_DIR/atlassian-jira/WEB-INF/web.xml"
cp -rf "${JIRA_INSTALL_DIR}_backup_$OLD_VERSION/atlassian-jira/WEB-INF/classes/seraph-config.xml" "$JIRA_INSTALL_DIR/atlassian-jira/WEB-INF/classes/seraph-config.xml"


# Step 12: Verify Permissions
CURRENT_STEP="Setting Jira directory permissions"
print_status "$CURRENT_STEP"
sudo chown -R jira:jira "$JIRA_INSTALL_DIR"
sudo chown -R jira:jira "$JIRA_DATA_DIR"
sudo chown -R jira:jira /App
sudo chmod -R 775 "/App"


# Step 13: Start Jira Service
#CURRENT_STEP="Starting Jira service"
#print_status "$CURRENT_STEP"
#sudo systemctl start jira

# Step 14: Clean Up
CURRENT_STEP="Cleaning up temporary files"
print_status "$CURRENT_STEP"
rm -rf "$TEMP_DOWNLOAD" "$EXTRACT_DIR"

# Final Step: Completion
CURRENT_STEP="Upgrade completed"
print_status "Jira upgrade to version $NEW_VERSION completed. Verify in your browser."
exit 0
