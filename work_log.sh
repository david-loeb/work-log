#!/usr/bin/env bash

CSV_FILE="$HOME/Desktop/work_log.txt"

if [ ! -f "$CSV_FILE" ]; then
    echo "date,day,start_time,end_time,activity,description" > "$CSV_FILE"
fi

# Active row is found as line a blank end_time field
# The END setup ensures that it will be the last line w/ empty end_time field
#   The only line that should ever have blank end_time should be last line,
#   but this approach safeguards against possibility that an earlier line does
# If no line is found w/ blank end_time, this will print 0 due to the `+0` part
_find_active_line_num() {
    awk -F ',' 'NR > 1 && $4 == "" { found = NR } END { print found+0 }' "$CSV_FILE"
}

case "$1" in
    start)
        if [ -z "$2" ]; then
            echo "Error: provide an activity name"
            exit 1
        fi

        ACTIVE=$(_find_active_line_num)
        if [ "$ACTIVE" -gt 0 ]; then
            echo "Error: session already active"
            exit 1
        fi

        DATE=$(date +"%Y-%m-%d")
        DAY=$(date +"%a")
        START_TIME=$(date +"%H:%M")
        printf '%s,%s,%s,,%s,%s\n' "$DATE" "$DAY" "$START_TIME" "$2" "${*:3}" >> "$CSV_FILE"
        ;;

    stop)
        ACTIVE=$(_find_active_line_num)
        if [ "$ACTIVE" -eq 0 ]; then
            echo "Error: no active session"
            exit 1
        fi

        END_TIME=$(date +"%H:%M")

        awk -v n="$ACTIVE" -v t="$END_TIME" '
            NR == n {
                idx = index($0, ",,")
                print substr($0, 1, idx) t substr($0, idx + 1)
                next
            }
            { print }
        ' "$CSV_FILE" > "$CSV_FILE.tmp" && mv "$CSV_FILE.tmp" "$CSV_FILE"
        ;;

    total)
        # WINDOW_START (defined below) is a date and time that represents the 
        #   "beginning" of the day / week, where the time is always set to 6am.
        #   This lets me effectively have days start at 6am and run til 6am the
        #   following day.
        # The function concatenates each row's date and time cols to check if 
        #   the combo is greater than WINDOW_START and only uses those rows to 
        #   calculate the total hours.
        # WINDOW_END (defined below) is set to blank for today and this week 
        #   totals, and is set to the start of the current week for the last 
        #   week total.
        # The func also adds 24 hours to the end time if it's earlier than the 
        #   start time, which happens when a session goes through midnight.
        _sum_total_hours() {
            awk -F ',' -v ws="$WINDOW_START" -v we="$WINDOW_END" '
                NR > 1 && $4 != "" {
                    row_dt = $1 " " $3
                    if (row_dt >= ws && (we == "" || row_dt < we)) {
                        split($3, start, ":")
                        split($4, end, ":")
                        start_min = start[1] * 60 + start[2]
                        end_min = end[1] * 60 + end[2]
                        if (end_min < start_min) end_min += 1440
                        sum += end_min - start_min
                    }
                }
                END { printf "%.2f", sum / 60 }
            ' "$CSV_FILE"
        }

        HOUR=$(date +"%H")

        case "$2" in
            ""|-d|--day|--today)
                # If it's currently between 12am & 6am, the start window is set 
                #   to the prior day's date at 6am.
                # Otherwise, it's set to today's date at 6am.
                if [ "$HOUR" -lt 6 ]; then
                    WINDOW_START="$(date -v-1d +"%Y-%m-%d") 06:00"
                else
                    WINDOW_START="$(date +"%Y-%m-%d") 06:00"
                fi
                WINDOW_END=""
                TOTAL=$(_sum_total_hours)
                echo "Today: $TOTAL"
                ;;

            -w|-tw|--week|--this-week)
                # If it's currently a Monday btwn 12am & 6am, the Monday that
                #   begins the current week is set to the prior Monday at 6am.
                # Otherwise, it's set to the most recent Monday at 6am, 
                #   including if today is Monday after 6am.
                if [ $(date +"%a") = "Mon" ] && [ "$HOUR" -lt 6 ]; then
                    MONDAY=$(date -v-1w +"%Y-%m-%d")
                else
                    MONDAY=$(date -v-monday +"%Y-%m-%d")
                fi
                WINDOW_START="$MONDAY 06:00"
                WINDOW_END=""
                TOTAL=$(_sum_total_hours)
                echo "This week: $TOTAL"
                ;;

            -lw|--last-week)
                # Get monday that ends last week (ie mon that starts cur week)
                if [ $(date +"%a") = "Mon" ] && [ "$HOUR" -lt 6 ]; then
                    MONDAY_END=$(date -v-1w +"%Y-%m-%d")
                else
                    MONDAY_END=$(date -v-monday +"%Y-%m-%d")
                fi
                # Get Monday that started the last week
                # -j tells date not to set system clock (and parse input string
                #   instead)
                # -v-1w subtracts a week off the input string
                # -f "%Y-%m-%d" specifies format input string is in
                # "$MONDAY_END" is the input string
                # "+%Y-%m-%d" is format for output date
                MONDAY_START=$(date -j -v-1w -f "%Y-%m-%d" "$MONDAY_END" "+%Y-%m-%d")
                WINDOW_START="$MONDAY_START 06:00"
                WINDOW_END="$MONDAY_END 06:00"
                TOTAL=$(_sum_total_hours)
                echo "Last week: $TOTAL"
                ;;

            *)
                echo "Error: options are -d (today), -w (this week), or -lw (last week)"
                ;;
        esac
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
        echo "  wl start [activity] [descrip]   Start tracking an activity"
        echo "  wl stop                         Stop the current activity"
        echo "  wl total [-d -w -lw]            Show total hours worked"
        echo "  wl status                       Check for active session"
        echo ""
        echo "CSV: $CSV_FILE"
        ;;
esac
