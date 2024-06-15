
START_SCRIPT="/Users/henry/infra/platform-dev/us-lab/qemu/run-vm.sh"
PLIST_FILE="$HOME/Library/LaunchAgents/com.user.start-cluster.plist"

# Create launchd plist file
echo "Creating com.user.start-cluster.plist file..."
mkdir -p "$HOME/Library/LaunchAgents"
cat <<EOL > $PLIST_FILE
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.user.start-cluster</string>
    <key>ProgramArguments</key>
    <array>
        <string>$START_SCRIPT</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
</dict>
</plist>
EOL

# Load the plist file into launchd
echo "Loading com.user.start-cluster.plist into launchd..."
launchctl load $PLIST_FILE

echo "Setup complete. The VM will now start automatically at boot."

# # Managing the Service
# # Start the Service Manually:
# launchctl start com.user.start-cluster

# # Stop the Service:
# launchctl stop com.user.start-cluster

# # Unload the Service:
# launchctl unload ~/Library/LaunchAgents/com.user.start-cluster.plist
