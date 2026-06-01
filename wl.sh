#!/usr/bin/env bash

CSV_FILE="$HOME/Desktop/work_log.csv"

if [ ! -f "$CSV_FILE" ]; then
    echo "date,day,start_time,end_time,activity,description" > "$CSV_FILE"
fi

# Active row is found as line a blank end_time field
# The END setup ensures that it will be the last line w/ empty end_time field
#   The only line that should ever have blank end_time should be last line,
#   but this approach safeguards against possibility that an earlier line does
# If no line is found w/ blank end_time, this will print 0 due to the `+0` part
_find_active_line_num() {
    awk -F',' 'NR > 1 && $4 == "" { found = NR } END { print found+0 }' "$CSV_FILE"
}

case "$1" in
    start)
        if [ -z "$2" ]; then
            echo "Error: please provide an activity name."
            exit 1
        fi

        ACTIVE=$(_find_active_line_num)
        if [ "$ACTIVE" -gt 0 ]; then
            echo "Error: session already active"
            exit 1
        fi

        DATE=$(date +"%Y-%m-%d")
        DAY=$(date +"%a")
        START_TIME=$(date +"%H:%M:%S")
        printf '%s,%s,%s,,%s,%s\n' "$DATE" "$DAY" "$START_TIME" "$2" "${*:3}" >> "$CSV_FILE"
        ;;

    stop)
        ACTIVE=$(_find_active_line_num)
        if [ "$ACTIVE" -eq 0 ]; then
            echo "Error: no active session"
            exit 1
        fi

        END_TIME=$(date +"%H:%M:%S")

        awk -v n="$ACTIVE" -v t="$END_TIME" '
            NR == n {
                idx = index($0, ",,")
                print substr($0, 1, idx) t substr($0, idx + 1)
                next
            }
            { print }
        ' "$CSV_FILE" > "$CSV_FILE.tmp" && mv "$CSV_FILE.tmp" "$CSV_FILE"
        ;;

    status)
        ACTIVE=$(_find_active_line_num)
        if [ "$ACTIVE" -eq 0 ]; then
            echo "No active session"
        else
            echo "Active"
        fi
        ;;

    *)
        echo "Usage:"
        echo "  wl start [activity] [description]   Start tracking an activity"
        echo "  wl stop                             Stop the current activity"
        echo "  wl status                           Show active session"
        echo ""
        echo "CSV: $CSV_FILE"
        ;;
esac
