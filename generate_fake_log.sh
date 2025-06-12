#!/usr/bin/env bash

# Create directory and log file
mkdir -p log
log_file="log/connection.fake.log"
> "$log_file"

IS_MACOS=false
[[ "$(uname)" == "Darwin" ]] && IS_MACOS=true

# Random integer between 1 and 6
rand_hours=$(( (RANDOM % 6) + 1 ))

# Loop over the past 60 days
for day_offset in $(seq 350 -1 0); do
  # Generate a macOS-compatible timestamp
  if $IS_MACOS; then
    # Base timestamp
    ts=$(date -v-"${day_offset}"d "+%a %d %b %Y %H:%M:%S %Z")
    # +1 hour
    ts_1h=$(date -v-"${day_offset}"d -v+1H "+%a %d %b %Y %H:%M:%S %Z")
    # + random (1–6) hours
    ts_random=$(date -v-"${day_offset}"d -v+1H -v+${rand_hours}H "+%a %d %b %Y %H:%M:%S %Z")

    epoch_1h=$(date -j -f "%a %d %b %Y %T %Z" "$ts_1h" "+%s")
    epoch_random=$(date -j -f "%a %d %b %Y %T %Z" "$ts_random" "+%s")
  else
    ts=$(date -d "${day_offset} days ago" "+%a %d %b %Y %H:%M:%S %Z")
    ts_1h=$(date -d "${day_offset} days ago + 1 hour" "+%a %d %b %Y %H:%M:%S %Z")
    ts_random=$(date -d "${day_offset} days ago + 1 hour + ${rand_hours} hour" "+%a %d %b %Y %H:%M:%S %Z")

    epoch_1h=$(date -d "$ts_1h" "+%s")
    epoch_random=$(date -d "$ts_random" "+%s")
  fi

  # Calculate duration
  delta=$(( epoch_random - epoch_1h ))
  minutes=$(( delta / 60 ))
  seconds=$(( delta % 60 ))

  # Get week number from that timestamp
  if [[ "$(uname)" == "Darwin" ]]; then
    # macOS: parse with -j -f
    week_num=$(date -j -f "%a %d %b %Y %T %Z" "$ts" "+%V")
  else
    # Linux: just use `date -d` with string
    week_num=$(date -d "$ts" "+%V")
  fi
  week_num=$((10#$week_num))

  # 40% chance to add LINK DOWN event
  if (( RANDOM % 10 < 4 )); then
    # 1–3 random events per day
    for _ in $(seq 1 $((RANDOM % 3 + 1))); do
      echo "************ Monitoring started at: $ts ************" >> "$log_file"
      echo "CONNECTED LINK SPEED:" >> "$log_file"
      echo "Download: 45.00 Mbps" >> "$log_file"
      echo "Upload: 12.34 Mbps" >> "$log_file"
      echo "Latency: 5.67 ms" >> "$log_file"
      echo "Packet Loss: 0.0%" >> "$log_file"
      echo "-----------------------------------------------------------------------------" >> "$log_file"
      #echo "" >> "$log_file"
      if (( week_num % 5 != 0 )); then
        echo "LINK DOWN:                                      $ts_1h" >> "$log_file"
        echo "LINK RECONNECTED:                               $ts_random" >> "$log_file"
        echo "TOTAL DOWNTIME:                                 $minutes minutes and $seconds seconds." >> "$log_file"
        echo "RECONNECTED LINK SPEED:                         " >> "$log_file"
      fi
    done
  fi
done

echo "✅ Fake macOS-compatible log generated at: $log_file"
