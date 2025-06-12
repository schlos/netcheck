#!/usr/bin/env bash

# Made to work with Linux and MacOS (Bash 3.2)
# Not compatible with Bash 4+ features (no associative arrays)

set -o nounset

log="log/connection.log"

IS_MACOS=false
[[ "$(uname)" == "Darwin" ]] && IS_MACOS=true

# Configuration: Set which day the week starts on ("Sunday" or "Monday")
WEEK_START="Monday"

# Parse CLI options
space=" "
style="square"

while [[ $# -gt 0 ]]; do
    case "$1" in
        -s|--style)
            style="$2"
            shift
            ;;
        -n|--no-space)
            space=""
            ;;
        -f)
            log="$2"
            shift
            ;;
        *)
            echo "Unexpected option: $1" >&2
            exit 1
            ;;
    esac
    shift
done

# Set character style
case "$style" in
    square)
        char_full="■"
        char_void="□" # No data 
        ;;
    block)
        char_full="█"
        char_void="░" # No data
        ;;
    plus)
        char_full="✚"
        char_void="•"
        ;;
    *)
        echo "error: style '$style' not recognized (square block plus)" >&2
        exit 1
        ;;
esac

# Date helper functions
parse_date_to_epoch() {
    local input="$1"
    if $IS_MACOS; then
        date -j -f "%a %d %b %Y %T %Z" "$input" +"%s" 2>/dev/null || echo 0
    else
        date -d "$input" +"%s"
    fi
}

calc_since_timestamp() {
    if $IS_MACOS; then
        # Calculate timestamp for 1 year ago + 1 day - weekday offset (Sunday=0)
        # On macOS date +%u gives 1=Mon..7=Sun, so adjust accordingly
        dow=$(date +%u)
        # Convert Monday=1..Sunday=7 to Sunday=0..Saturday=6
        dow=$((dow % 7))
        date -v-1y -v+1d -v-"$dow"d +"%s"
    else
        # GNU date: 1 year ago + 1 day - weekday offset (Sunday=0)
        dow=$(date +%u)
        dow=$((dow % 7))
        date -d "$(date -d '1 year ago + 1 day' +"%F") -${dow} day" +"%s"
    fi
}

date_offset() {
    local weeks="$1"
    if $IS_MACOS; then
        date -v-1y -v+"${weeks}"w "+%b"
    else
        date -d "1 year ago + ${weeks} weeks" "+%b"
    fi
}

# Adjust day names and indexing based on WEEK_START
if [[ "$(echo "$WEEK_START" | tr '[:upper:]' '[:lower:]')" == "monday" ]]; then
    name_of_days=("Mon" "Tue" "Wed" "Thu" "Fri" "Sat" "Sun" "")
    week_start_offset=1  # Monday=1 for date +%u
else
    name_of_days=("Sun" "Mon" "Tue" "Wed" "Thu" "Fri" "Sat" "")
    week_start_offset=0  # Sunday=0
fi

# Data structures
commits_per_day_keys=()
commits_per_day_values=()
commits_max=0
since=$(calc_since_timestamp)

# Helper function to increment count for day_index without associative arrays
day_keys=()
day_values=()
increment_day_count() {
    local key="$1"
    local found=0
    local i
    for i in "${!day_keys[@]}"; do
        if [ "${day_keys[$i]}" = "$key" ]; then
            day_values[$i]=$(( day_values[$i] + 1 ))
            found=1
            break
        fi
    done
    if [ $found -eq 0 ]; then
        day_keys+=("$key")
        day_values+=(1)
    fi
}

# Parse the log file and count LINK DOWN entries per day
while IFS= read -r line; do
    if [[ "$line" =~ LINK\ DOWN:[[:space:]]+(.*) ]]; then
        datetime="${BASH_REMATCH[1]}"
        ts=$(parse_date_to_epoch "$datetime")
        [ "$ts" -eq 0 ] && continue
        # Calculate day index relative to since timestamp
        day_diff=$(( (ts - since) / 86400 ))

        # Get weekday number for the event (1=Mon..7=Sun)
        if $IS_MACOS; then
            weekday=$(date -r "$ts" +%u)
        else
            weekday=$(date -d "@$ts" +%u)
        fi

        # Adjust day index based on WEEK_START
        if [[ "$(echo "$WEEK_START" | tr '[:upper:]' '[:lower:]')" == "monday" ]]; then
            # Monday=0..Sunday=6
            day_index=$((weekday - 1))
        else
            # Sunday=0..Saturday=6
            day_index=$((weekday % 7))
        fi

        # Calculate key as week number * 7 + day_index
        week_n=$(( day_diff / 7 ))
        key=$(( week_n * 7 + day_index ))

        increment_day_count "$key"
    fi
done < "$log"

# Transfer counted data to commits_per_day arrays and find max count
for i in "${!day_keys[@]}"; do
    commits_per_day_keys+=("${day_keys[$i]}")
    commits_per_day_values+=("${day_values[$i]}")
    if [ "${day_values[$i]}" -gt "$commits_max" ]; then
        commits_max="${day_values[$i]}"
    fi
done

# Print month headers
#current_month=""
current_month=$(date "+%b")
limit_columns=$(( 2 - ${#space} ))
weeks_in_month=$(( limit_columns + 1 ))

#printf "\e[m "
printf "\e[m    "
for week_n in $(seq 0 52); do
    month_week=$(date_offset "$week_n")
    if [[ "$current_month" != "$month_week" ]]; then
        current_month="$month_week"
        weeks_in_month=0
        printf "%-3s%s" "${current_month:0:3}" "$space"
    elif [[ $weeks_in_month -gt $limit_columns ]]; then
        printf " %s" "$space"
    fi
    weeks_in_month=$(( weeks_in_month + 1 ))
done
printf "\n"

# Grid range: fixed to 7×53 = 371 days
grid_days=371

for day_n in $(seq 0 6); do
    # Map day_n to actual day index based on WEEK_START
    if [[ "$(echo "$WEEK_START" | tr '[:upper:]' '[:lower:]')" == "monday" ]]; then
        day_index=$(( (day_n + 1) % 7 ))  # Monday=0 at day_n=0
    else
        day_index=$day_n  # Sunday=0 at day_n=0
    fi

    printf '\e[m%-4s' "${name_of_days[day_n]}"
    for week_n in $(seq 0 52); do
        key=$(( week_n * 7 + day_index ))
        value=""
        # Manual lookup
        for i in "${!commits_per_day_keys[@]}"; do
            if [ "${commits_per_day_keys[$i]}" = "$key" ]; then
                value="${commits_per_day_values[$i]}"
                break
            fi
        done

        if [ -n "$value" ] && [ "$commits_max" -ne 0 ]; then
            scaled=$(( value * 100 / commits_max ))
            if (( scaled <= 5 )); then
                printf "\x1b[38;5;250m%s%s" "$char_full" "$space"
            elif (( scaled <= 25 )); then
                printf "\x1b[38;5;22m%s%s" "$char_full" "$space"
            elif (( scaled <= 50 )); then
                printf "\x1b[38;5;28m%s%s" "$char_full" "$space"
            elif (( scaled <= 75 )); then
                printf "\x1b[38;5;34m%s%s" "$char_full" "$space"
            else
                printf "\x1b[38;5;40m%s%s" "$char_full" "$space"
            fi
        elif [ "$key" -lt "$grid_days" ]; then
            printf "\x1b[38;5;250m%s%s" "$char_void" "$space"
        else
            printf " %s" "$space"
        fi
    done
    printf "\n"
done

# Legend
printf "\n"
printf "\e[m Less "
#printf "\x1b[38;5;250m%s " "$char_void"
printf "\x1b[38;5;250m%s " "$char_full"
printf "\x1b[38;5;22m%s " "$char_full"
printf "\x1b[38;5;28m%s " "$char_full"
printf "\x1b[38;5;34m%s " "$char_full"
printf "\x1b[38;5;40m%s " "$char_full"
printf "\e[m More\n"
printf "\n"
printf "\e[m No data "
printf "\x1b[38;5;250m%s " "$char_void"
printf "\n"
