#!/usr/bin/env bash

################################################################################
##               Netcheck - Simple internet connection logging                ##
##               https://github.com/TristanBrotherton/netcheck                ##
##                                       -- Tristan Brotherton                ##
################################################################################

VAR_SCRIPTNAME=`basename "$0"`
VAR_SCRIPTLOC="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
VAR_CONNECTED=true
VAR_LOGFILE="$VAR_SCRIPTLOC/log/connection.log"
VAR_SPEEDTEST_DISABLED=false
VAR_CHECK_TIME=60
VAR_CONNECTIVIY_DETECTION=http://www.gstatic.com/generate_204
VAR_EXPECTED_HTTP_CODE="204"
VAR_HOST=${VAR_CONNECTIVIY_DETECTION}
VAR_ENABLE_WEBINTERFACE=false
VAR_ENABLE_ALWAYS_SPEEDTEST=false
VAR_WEB_PORT=9000
VAR_CUSTOM_WEB_PORT=false

COLOR_RED="\033[31m"
COLOR_GREEN="\033[32m"
COLOR_CYAN="\033[36m"
COLOR_RESET="\033[0m"

STRING_1="LINK RECONNECTED:                               "
STRING_2="LINK DOWN:                                      "
STRING_3="TOTAL DOWNTIME:                                 "
STRING_4="RECONNECTED LINK SPEED:                         "
STRING_5="CONNECTED LINK SPEED:                           "

PRINT_NL() {
  echo
}

PRINT_HR() {
  echo "-----------------------------------------------------------------------------"
}

PRINT_HELP() {
  echo "Here are your options:"
  echo
  echo "$VAR_SCRIPTNAME -h                                           Display this message"
  echo "$VAR_SCRIPTNAME -f path/my_log_file.log          Specify log file and path to use"
  echo "$VAR_SCRIPTNAME -s                                 Disable speedtest on reconnect"
  echo "$VAR_SCRIPTNAME -c                Check connection ever (n) seconds. Default is 5"
  echo "$VAR_SCRIPTNAME -u            URL/Host to check, default is http://www.google.com"
  echo "$VAR_SCRIPTNAME -w                                  Enable the remote webinteface"
  echo "$VAR_SCRIPTNAME -p                  Specify an optional port for the webinterface"  
  echo "$VAR_SCRIPTNAME -i                           Install netcheck as a system service"
  echo "$VAR_SCRIPTNAME -d path/script            Specify script to execute on disconnect"
  echo "$VAR_SCRIPTNAME -r path/script             Specify script to execute on reconnect"
  echo "$VAR_SCRIPTNAME -e                      Excecute speedtest every connection check"
  echo
}

PRINT_MANAGESERVICE() {
  PRINT_HR
  echo "Use the command:"
  echo -e "                                               sudo systemctl$COLOR_GREEN start$COLOR_RESET netcheck"
  echo -e "                                                             $COLOR_RED stop$COLOR_RESET netcheck"
  echo "To manage the service."
  PRINT_HR
}

PRINT_INSTALL() {
  echo
  echo "Installing this library will allow tests of network connection speed."
  echo "https://github.com/sivel/speedtest-cli"
  echo "Installation is a single python file, saved in:"
  echo "$VAR_SCRIPTLOC"
  echo
  echo "Install in this directory now? (y/n)"
}

PRINT_INSTALLING() {
  echo
  echo "Installing https://github.com/sivel/speedtest-cli ..."
}

PRINT_LOGDEST() {
  echo "Logging to:        $VAR_LOGFILE"
}

PRINT_LOGSTART() {
  echo "************ Monitoring started at: $(date "+%a %d %b %Y %H:%M:%S %Z") ************" >> $VAR_LOGFILE
  echo -e "************$COLOR_GREEN Monitoring started at: $(date "+%a %d %b %Y %H:%M:%S %Z") $COLOR_RESET************"
}

PRINT_DISCONNECTED() {
  echo "$STRING_2 $(date "+%a %d %b %Y %H:%M:%S %Z")" >> $VAR_LOGFILE
  echo -e $COLOR_RED"$STRING_2 $(date "+%a %d %b %Y %H:%M:%S %Z")"$COLOR_RESET
}

DISCONNECTED_EVENT_HOOK() {
  if [[ $VAR_ACT_ON_DISCONNECT = true ]]; then :
    COMMAND="$VAR_DISCONNECT_SCRIPT &"
    echo -e $COLOR_CYAN"$STRING_2 EXEC $COMMAND"$COLOR_RESET
    eval "$COMMAND"
  fi
}

PRINT_RECONNECTED() {
  echo "$STRING_1 $(date "+%a %d %b %Y %H:%M:%S %Z")" >> $VAR_LOGFILE
  echo -e $COLOR_GREEN"$STRING_1 $(date "+%a %d %b %Y %H:%M:%S %Z")"$COLOR_RESET
}

RECONNECTED_EVENT_HOOK() {
  if [[ $VAR_ACT_ON_RECONNECT = true ]]; then :
    COMMAND="$VAR_RECONNECT_SCRIPT $1 &"
    echo -e $COLOR_CYAN"$STRING_1 EXEC $COMMAND"$COLOR_RESET
    eval "$COMMAND"
  fi
}

CHECK_EVENT_HOOK() {
  if [[ $VAR_ACT_ON_CHECK = true ]]; then :
    COMMAND="$VAR_CHECK_SCRIPT $1 &"
    eval "$COMMAND"
  fi
}

PRINT_DURATION() {
  echo "$STRING_3 $(($VAR_DURATION / 60)) minutes and $(($VAR_DURATION % 60)) seconds." | tee -a $VAR_LOGFILE
  echo "$STRING_4" | tee -a $VAR_LOGFILE
}

PRINT_LOGGING_TERMINATED() {
  echo
  echo "************ Monitoring ended at:   $(date "+%a %d %b %Y %H:%M:%S %Z") ************" >> $VAR_LOGFILE
  echo -e "************$COLOR_RED Monitoring ended at:   $(date "+%a %d %b %Y %H:%M:%S %Z") $COLOR_RESET************"
}

GET_LOCAL_IP() {
  ifconfig | sed -En 's/127.0.0.1//;s/.*inet (addr:)?(([0-9]*\.){3}[0-9]*).*/\2/p' | sed -e 's/^/                   http:\/\//' | sed -e "s/.*/&:$1/"
  echo
}

START_WEBSERVER() {
  # Debian 11 and above drops the python symlink
  if [ "$(grep -Ei 'bullseye' /etc/*release)" ]; then
    VAR_PYTHON_EXEC=python3
  else
    VAR_PYTHON_EXEC=python
  fi

  # Find python version and start corresponding webserver
  VAR_PYTHON_VERSION=$($VAR_PYTHON_EXEC -c 'import sys; print(sys.version_info[0])')
  case $VAR_PYTHON_VERSION in
    2)
      (cd $VAR_SCRIPTLOC/log; $VAR_PYTHON_EXEC -m SimpleHTTPServer $1 &) &> /dev/null  
    ;;
    3)
      (cd $VAR_SCRIPTLOC/log; $VAR_PYTHON_EXEC -m http.server $1 &) &> /dev/null
    ;;
  esac
}

SETUP_WEBSERVER() {
  if [[ $VAR_ENABLE_WEBINTERFACE = true ]]; then :
    if [[ $VAR_CUSTOM_LOG = true ]]; then :
      echo -e "Web Interface:    $COLOR_RED Not Available $COLOR_RESET"
      echo -e "Custom log destinations are not supported by webinterface"
    else
      echo -e "Web Interface:    $COLOR_GREEN Enabled $COLOR_RESET"
      if [[ $VAR_CUSTOM_WEB_PORT = false ]]; then :
        echo -e "                   http://localhost:$VAR_WEB_PORT"
        GET_LOCAL_IP $VAR_WEB_PORT
        START_WEBSERVER $VAR_WEB_PORT
      else
        echo -e "                   http://localhost:$VAR_CUSTOM_WEB_PORT"
        GET_LOCAL_IP $VAR_CUSTOM_WEB_PORT
        START_WEBSERVER $VAR_CUSTOM_WEB_PORT
      fi
    fi
  fi
}

CHECK_FOR_SPEEDTEST() {
  if [[ $VAR_SPEEDTEST_DISABLED = false ]]; then :
    if [ -f "$VAR_SCRIPTLOC/speedtest-cli.py" ] || [ -f "$VAR_SCRIPTLOC/speedtest-cli" ]; then
        echo -e "SpeedTest-CLI:    $COLOR_GREEN Installed $COLOR_RESET"
        VAR_SPEEDTEST_READY=true
    elif command -v speedtest >/dev/null 2>&1; then
        echo -e "Speedtest-CLI by Ookla:    $COLOR_GREEN Installed $COLOR_RESET"
        VAR_SPEEDTEST_CLI_READY=true
    else
        echo -e "SpeedTest-CLI:    $COLOR_RED Not Installed $COLOR_RESET"
        INSTALL_SPEEDTEST
    fi
    if [ -f "$VAR_SCRIPTLOC/speedtest-cli" ]; then
      mv $VAR_SCRIPTLOC/speedtest-cli $VAR_SCRIPTLOC/speedtest-cli.py
    fi
  else
      echo -e "SpeedTest-CLI:    $COLOR_RED Disabled $COLOR_RESET"
  fi
}

INSTALL_SPEEDTEST() {
  PRINT_INSTALL
  read -r response
  if [[ $response =~ ^([yY][eE][sS]|[yY])$ ]]; then
    PRINT_INSTALLING
    wget -q -O "$VAR_SCRIPTLOC/speedtest-cli.py" https://raw.githubusercontent.com/sivel/speedtest-cli/master/speedtest.py
    chmod +x "$VAR_SCRIPTLOC/speedtest-cli.py"
    PRINT_NL
    CHECK_FOR_SPEEDTEST
  else
    VAR_SPEEDTEST_DISABLED=true
  fi
}

RUN_SPEEDTEST() {
  $VAR_SCRIPTLOC/speedtest-cli.py --simple --secure | sed 's/^/                                                 /' | tee -a $VAR_LOGFILE
}

RUN_SPEEDTEST_CLI() {
  local attempts=10
  local speedtest_output
  local retry_delay=4  # Delay in seconds

  echo "Starting speed test..."

  # Loop to run speedtest multiple times or until download speed is obtained
  while [[ $attempts -gt 0 ]]; do
    speedtest_output="$(speedtest -f json-pretty)"

    # Check if speedtest output contains download speed
    if echo "$speedtest_output" | jq -e '.download' >/dev/null 2>&1; then
      break
    fi

    ((attempts--))
    sleep $retry_delay  # Add delay between retries
  done

  # If speed test was successful (check for download data)
  if echo "$speedtest_output" | jq -e '.download' >/dev/null 2>&1; then
    # Extract raw values from JSON
    download_bandwidth=$(echo "$speedtest_output" | jq '.download.bandwidth')
    upload_bandwidth=$(echo "$speedtest_output" | jq '.upload.bandwidth')
    latency=$(echo "$speedtest_output" | jq '.ping.latency')
    packet_loss=$(echo "$speedtest_output" | jq '.packetLoss')
    server_name=$(echo "$speedtest_output" | jq -r '.server.name')
    server_location=$(echo "$speedtest_output" | jq -r '.server.location')
    server_country=$(echo "$speedtest_output" | jq -r '.server.country')
    server_ip=$(echo "$speedtest_output" | jq -r '.server.ip')
    isp=$(echo "$speedtest_output" | jq -r '.isp')
    interface_name=$(echo "$speedtest_output" | jq -r '.interface.name')
    is_vpn=$(echo "$speedtest_output" | jq -r '.interface.isVpn')
    external_ip=$(echo "$speedtest_output" | jq -r '.interface.externalIp')
    result_url=$(echo "$speedtest_output" | jq -r '.result.url')
    jitter=$(echo "$speedtest_output" | jq '.ping.jitter')

    # Convert bandwidth (bytes/sec to Mbps)
    download=$(awk "BEGIN {printf \"%.2f Mbps\", $download_bandwidth * 8 / 1000000}")
    upload=$(awk "BEGIN {printf \"%.2f Mbps\", $upload_bandwidth * 8 / 1000000}")
    # Format latency, jitter, packet loss
    latency_fmt=$(awk "BEGIN {printf \"%.2f ms\", $latency}")
    jitter_fmt=$(awk "BEGIN {printf \"%.2f ms\", $jitter}")
    packet_loss_fmt=$(awk "BEGIN {printf \"%.1f%%\", $packet_loss}")

    echo "Download: $download" | tee -a "$VAR_LOGFILE"
    echo "Upload: $upload" | tee -a "$VAR_LOGFILE"
    echo "Latency: $latency_fmt" | tee -a "$VAR_LOGFILE"
    echo "Packet Loss: $packet_loss_fmt" | tee -a "$VAR_LOGFILE"

    # Log additional fields
    echo "" | tee -a "$VAR_LOGFILE"
    echo "Server: $server_name, $server_location, $server_country" | tee -a "$VAR_LOGFILE"
    echo "ISP: $isp" | tee -a "$VAR_LOGFILE"
    echo "External IP: $external_ip (VPN: $is_vpn)" | tee -a "$VAR_LOGFILE"
    echo "Jitter: $jitter_fmt" | tee -a "$VAR_LOGFILE"
    echo "Result URL: $result_url" | tee -a "$VAR_LOGFILE"
  else
    echo "Failed to obtain download speed" | tee -a "$VAR_LOGFILE"
  fi
}

NET_CHECK() {
  while true; do
    # Check for network connection
    CONNECTIVIY_RESULT=$(curl -m 20 --retry 5 -s -w "%{http_code}" $VAR_HOST)
    if [ ${CONNECTIVIY_RESULT} = ${VAR_EXPECTED_HTTP_CODE} ]; then
      if [ $VAR_ENABLE_ALWAYS_SPEEDTEST = true ] && [ $VAR_CONNECTED = true ]; then :
        echo "$STRING_5" | tee -a $VAR_LOGFILE
        if [[ $VAR_SPEEDTEST_READY = true ]]; then :
          RUN_SPEEDTEST
        elif [[ $VAR_SPEEDTEST_CLI_READY = true ]]; then :
          RUN_SPEEDTEST_CLI
        else
          echo "Didn't run Speedtest-CLI!"
        fi
        PRINT_HR | tee -a $VAR_LOGFILE
      fi
      # We are currently online
      # Did we just reconnect?
      if [[ $VAR_CONNECTED = false ]]; then :
        PRINT_RECONNECTED
        VAR_DURATION=$SECONDS
        PRINT_DURATION
        if [[ $VAR_SPEEDTEST_READY = true ]]; then :
          PRINT_HR | tee -a $VAR_LOGFILE
          RUN_SPEEDTEST
        elif [[ $VAR_SPEEDTEST_CLI_READY = true ]]; then :
          PRINT_HR | tee -a $VAR_LOGFILE
          RUN_SPEEDTEST_CLI
        fi
        PRINT_HR | tee -a $VAR_LOGFILE
        SECONDS=0
        VAR_CONNECTED=true
        RECONNECTED_EVENT_HOOK $VAR_DURATION
      fi
    else
      # We are offline
      if [[ $VAR_CONNECTED = false ]]; then :
          # We were already disconnected
        else
          # We just disconnected
          PRINT_DISCONNECTED
          DISCONNECTED_EVENT_HOOK
          SECONDS=0
          VAR_CONNECTED=false
      fi
    fi
    CHECK_EVENT_HOOK
    sleep $VAR_CHECK_TIME

  done

}

INSTALL_AS_SERVICE_SYSTEMD() {
  if ! command -v systemctl &> /dev/null; then
    echo "Systemctl not found."
    echo "Netcheck can only be installed as a service on systems using systemctl."
    echo "You will need to manually setup Netcheck as a service on your system."
    exit
  else 
    FILE=/etc/systemd/system/netcheck.service
    if [ -f "$FILE" ]; then
      echo "Netcheck already installed as a service."
      PRINT_MANAGESERVICE
      exit
    else
      echo "You will need to authenticate using sudo to install."
      echo "Installing netcheck as a service..."
      sudo tee -a /etc/systemd/system/netcheck.service <<EOL >/dev/null
[Unit]
Description=Netcheck Service

[Service]
WorkingDirectory=$VAR_SCRIPTLOC/
ExecStart=$VAR_SCRIPTLOC/$VAR_SCRIPTNAME

[Install]
WantedBy=multi-user.target
EOL
      sudo systemctl enable netcheck.service >/dev/null
      PRINT_MANAGESERVICE
      echo "Would you like to start netcheck as a service now?"
      echo -n "(y/n): "
      read answer
      if [ "$answer" != "${answer#[Yy]}" ] ;then
        sudo systemctl start netcheck
        exit
      else
        exit
      fi
    fi
  fi
}

INSTALL_AS_SERVICE_LAUNCHD() {
  if [[ "$(uname)" != "Darwin" ]]; then
    echo "This function is only for macOS (Darwin)."
    return 1
  fi

  LAUNCH_AGENT_DIR="$HOME/Library/LaunchAgents"
  LABEL="com.netcheck.service"
  PLIST_PATH="$LAUNCH_AGENT_DIR/${LABEL}.plist"

  mkdir -p "$LAUNCH_AGENT_DIR"

  if [ -f "$PLIST_PATH" ]; then
    echo "Netcheck is already installed as a launchd service."
    echo "To manage it: launchctl unload/load $PLIST_PATH"
    return 0
  fi

  echo "Creating launchd service for Netcheck at: $PLIST_PATH"

  cat > "$PLIST_PATH" <<EOL
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" 
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
  <dict>
    <key>Label</key>
    <string>${LABEL}</string>

    <key>ProgramArguments</key>
    <array>
      <string>${VAR_SCRIPTLOC}/${VAR_SCRIPTNAME}</string>
    </array>

    <key>WorkingDirectory</key>
    <string>${VAR_SCRIPTLOC}</string>

    <key>RunAtLoad</key>
    <true/>

    <key>KeepAlive</key>
    <true/>
  </dict>
</plist>
EOL

  echo "Loading Netcheck launchd service..."
  launchctl load "$PLIST_PATH"

  PRINT_HR
  echo "✅ Netcheck has been installed as a macOS launch agent."
  echo "To start it manually:  launchctl start $LABEL"
  echo "To stop it:            launchctl stop $LABEL"
  echo "To remove it:          launchctl unload $PLIST_PATH && rm $PLIST_PATH"
  echo "To check service:      launchctl list | grep $LABEL"
  PRINT_HR
  exit
}

UNINSTALL_SERVICE_LAUNCHD() {
  if [[ "$(uname)" != "Darwin" ]]; then
    echo "This function is only supported on macOS."
    return 1
  fi

  local LABEL="com.netcheck.service"
  local PLIST_PATH="$HOME/Library/LaunchAgents/${LABEL}.plist"

  if [ ! -f "$PLIST_PATH" ]; then
    echo "⚠️  No launchd service found for Netcheck at:"
    echo "   $PLIST_PATH"
    return 1
  fi

  echo "Unloading Netcheck launchd service..."
  launchctl unload "$PLIST_PATH"

  echo "Removing service plist file..."
  rm -f "$PLIST_PATH"

  echo "🧹 Cleanup complete."
  echo "❌ Netcheck has been removed from launchd."
}

CLEANUP() {
  if [[ $VAR_INSTALL_AS_SERVICE = false ]]; then :
    PRINT_LOGGING_TERMINATED
  fi
  if [[ $VAR_ENABLE_WEBINTERFACE = true ]]; then :
    echo "Shutting down webinterface..."
    kill 0
  fi
}

trap CLEANUP EXIT
while getopts "f:d:r:t:c:u:p:whelp-sie" opt; do
  case $opt in
    f)
      echo "Logging to custom file: $OPTARG"
      VAR_LOGFILE=$OPTARG
      VAR_CUSTOM_LOG=true
      ;;
    d)
      echo "Executing $OPTARG script on disconnect"
      VAR_DISCONNECT_SCRIPT=$OPTARG
      VAR_ACT_ON_DISCONNECT=true
      ;;
    r)
      echo "Executing $OPTARG script on reconnect"
      VAR_RECONNECT_SCRIPT=$OPTARG
      VAR_ACT_ON_RECONNECT=true
      ;;
    t)
      echo "Executing $OPTARG script on check"
      VAR_CHECK_SCRIPT=$OPTARG
      VAR_ACT_ON_CHECK=true
      ;;
    c)
      echo "Checking connection every: $OPTARG seconds"
      VAR_CHECK_TIME=$OPTARG
      ;;
    u)
      echo "Checking host: $OPTARG"
      VAR_HOST=$OPTARG
      ;;
    p)
      echo "Port set to: $OPTARG"
      VAR_CUSTOM_WEB_PORT=$OPTARG
      ;;
    w)
      VAR_ENABLE_WEBINTERFACE=true
      ;;
    s)
      VAR_SPEEDTEST_DISABLED=true
      ;;
    i) 
      VAR_INSTALL_AS_SERVICE=true
      ;;
    e)
      VAR_ENABLE_ALWAYS_SPEEDTEST=true
      ;;
    h)
      PRINT_HELP
      exit 1
      ;;
    \?)
      echo "Invalid option: -$OPTARG (try -help for clues)"
      exit 1
      ;;
    :)
      echo "Option -$OPTARG requires an argument."
      exit 1
      ;;
  esac
done

if [[ $VAR_INSTALL_AS_SERVICE = true ]]; then :
  case "$(uname)" in
  "Linux")
    if command -v systemctl &>/dev/null; then
      INSTALL_AS_SERVICE_SYSTEMD
    fi
    ;;
  "Darwin")
    INSTALL_AS_SERVICE_LAUNCHD
    ;;
  *)
    echo "Unsupported OS"
    ;;
  esac
fi
PRINT_HR
SETUP_WEBSERVER
CHECK_FOR_SPEEDTEST
PRINT_LOGDEST
PRINT_LOGSTART
if [[ $VAR_SPEEDTEST_READY = true ]]; then :
  echo "$STRING_5" | tee -a $VAR_LOGFILE
  RUN_SPEEDTEST
  PRINT_HR | tee -a $VAR_LOGFILE
elif [[ $VAR_SPEEDTEST_CLI_READY = true ]]; then :
  echo "$STRING_5" | tee -a $VAR_LOGFILE
  RUN_SPEEDTEST_CLI
  PRINT_HR | tee -a $VAR_LOGFILE
fi
NET_CHECK
