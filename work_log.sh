#!/usr/bin/env bash

DIR="$(dirname "$(readlink "$0")")"
CSV_FILE="$DIR/work_log.txt"

if [ ! -f "$CSV_FILE" ]; then
    echo "date,dow,start_time,end_time,activity,description" > "$CSV_FILE"
fi

# Active row is found as line with blank end_time field
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

        if printf '%s' "$2" | grep -qE '^[0-9][0-9]?:[0-9][0-9]$'; then
            echo "Omit 'start' for manual time entry: 'wl HH:MM <activity>'"
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

        if [ -z "$2" ]; then
            END_TIME=$(date +"%H:%M")
        elif printf '%s' "$2" | grep -qE '^([01][0-9]|2[0-3]):[0-5][0-9]$'; then
            END_TIME="$2"
        else
            echo "Error: argument must be a valid time in HH:MM (or blank)"
            exit 1
        fi

        awk -v n="$ACTIVE" -v t="$END_TIME" '
            NR == n {
                idx = index($0, ",,")
                print substr($0, 1, idx) t substr($0, idx + 1)
                next
            }
            { print }
        ' "$CSV_FILE" > "$CSV_FILE.tmp" && mv "$CSV_FILE.tmp" "$CSV_FILE"
        ;;

    resume)
        ACTIVE=$(_find_active_line_num)
        if [ "$ACTIVE" -gt 0 ]; then
            echo "Error: session already active"
            exit 1
        fi

        DATE=$(date +"%Y-%m-%d")
        DAY=$(date +"%a")
        START_TIME=$(date +"%H:%M")
        LINE=$(tail -n 1 "$CSV_FILE")
        ACTIVITY=$(echo "$LINE" | cut -d ',' -f 5)
        DESCRIPTION=$(echo "$LINE" | cut -d ',' -f 6)
        printf '%s,%s,%s,,%s,%s\n' "$DATE" "$DAY" "$START_TIME" "$ACTIVITY" "$DESCRIPTION" >> "$CSV_FILE"
        ;;

    link)
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
        # Start time is end time of previous session
        LINE=$(tail -n 1 "$CSV_FILE")
        START_TIME="$(echo "$LINE" | cut -d ',' -f 4)"
        printf '%s,%s,%s,,%s,%s\n' "$DATE" "$DAY" "$START_TIME" "$2" "${*:3}" >> "$CSV_FILE"
        ;;

    next)
        ACTIVE=$(_find_active_line_num)
        if [ "$ACTIVE" -eq 0 ]; then
            echo "Error: no active session"
            exit 1
        fi
        if [ -z "$2" ]; then
            echo "Error: provide an activity name"
            exit 1
        fi
        wl stop
        wl link "$2"
        ;;

    undo)
        LAST_LINE_NUM=$(wc -l < "$CSV_FILE")
        ACTIVE=$(_find_active_line_num)
        if [ "$ACTIVE" -gt 0 ]; then
            awk -F ',' -v l="$LAST_LINE_NUM" '
                NR != l 
            ' "$CSV_FILE" > "$CSV_FILE.tmp" && mv "$CSV_FILE.tmp" "$CSV_FILE"
        else 
            awk -F ',' -v l="$LAST_LINE_NUM" '
                NR == l {
                    match($0, /:[0-9][0-9],[0-9][0-9]:/)
                    print substr($0, 1, RSTART + 3) substr($0, RSTART + 9)
                    next
                }
                { print }
            ' "$CSV_FILE" > "$CSV_FILE.tmp" && mv "$CSV_FILE.tmp" "$CSV_FILE"
        fi
        ;;

    edit)
        if [ -z "$2" ]; then
            echo "Error: provide an activity name"
            exit 1
        fi

        ACTIVE=$(_find_active_line_num)
        if [ "$ACTIVE" -eq 0 ]; then
            echo "Error: no active session"
            exit 1
        fi

        LAST_LINE_NUM=$(wc -l < "$CSV_FILE")
        ACTIVITY="$2"
        DESCRIPTION="${*:3}"
        awk -F ',' -v a="$ACTIVITY" -v d="$DESCRIPTION" -v l="$LAST_LINE_NUM" '
            NR == l {
                idx = index($0, ",,")
                print substr($0, 1, idx + 1) a "," d
                next
            }
            { print }
        ' "$CSV_FILE" > "$CSV_FILE.tmp" && mv "$CSV_FILE.tmp" "$CSV_FILE"
        ;;

    # Manually input time(s)
    [01][0-9]:[0-5][0-9] | 2[0-3]:[0-5][0-9])
        if [ -z "$2" ]; then
            echo "Error: provide an activity name"
            exit 1
        fi

        # End time provided
        if printf '%s' "$2" | grep -qE '^([01][0-9]|2[0-3]):[0-5][0-9]$'; then
            if [ -z "$3" ]; then
                echo "Error: provide an activity name"
                exit 1
            fi

            DATE=$(date +"%Y-%m-%d")
            DAY=$(date +"%a")
            printf '%s,%s,%s,%s,%s,%s\n' "$DATE" "$DAY" "$1" "$2" "$3" "${*:4}" >> "$CSV_FILE"
        else
            ACTIVE=$(_find_active_line_num)
            if [ "$ACTIVE" -gt 0 ]; then
                echo "Error: session already active"
                exit 1
            fi

            DATE=$(date +"%Y-%m-%d")
            DAY=$(date +"%a")
            printf '%s,%s,%s,,%s,%s\n' "$DATE" "$DAY" "$1" "$2" "${*:3}" >> "$CSV_FILE"
        fi
        ;;

    # Manually input date & time(s)
    20[2-9][0-9]-[01][1-9]-[0-3][0-9])
        if [ -z "$2" ]; then
            echo "Error: provide time(s) and an activity name"
            exit 1
        fi

        if [ -z "$3" ]; then
            echo "Error: provide an activity name"
            exit 1
        fi

        if ! printf '%s' "$2" | grep -qE '^([01][0-9]|2[0-3]):[0-5][0-9]$'; then
            echo "Error: provide time(s) immediately after date"
            exit 1
        fi

        DAY=$(date -j -f "%Y-%m-%d" "$1" +%a)

        # End time provided
        if printf '%s' "$3" | grep -qE '^([01][0-9]|2[0-3]):[0-5][0-9]$'; then
            if [ -z "$4" ]; then
                echo "Error: provide an activity name"
                exit 1
            fi

            printf '%s,%s,%s,%s,%s,%s\n' "$1" "$DAY" "$2" "$3" "$4" "${*:5}" >> "$CSV_FILE"
        else
            ACTIVE=$(_find_active_line_num)
            if [ "$ACTIVE" -gt 0 ]; then
                echo "Error: session already active"
                exit 1
            fi

            printf '%s,%s,%s,,%s,%s\n' "$1" "$DAY" "$2" "$3" "${*:4}" >> "$CSV_FILE"
        fi
        ;;

    total)
        # WINDOW_START (defined below) is a date and time that represents the 
        #   "beginning" of the day / week, where the time is always set to 6am.
        #   This makes the days effectively start at 6am and run til 6am the
        #   following day.
        # The function concatenates each row's date and time cols to check if 
        #   the combo is greater than WINDOW_START and only uses those rows to 
        #   calculate the total hours.
        # WINDOW_END (defined below) is set to 6am one day or week later than 
        #   the day or week being totaled (and is blank when computing totals
        #   for today or this week).
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
            ""|-d|--day)
                # If no arg, print today's hours
                if [ -z "$3" ]; then
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

                # If arg, print X most recent days (including today)
                elif printf '%s' "$3" | grep -qE '^([0-9]+|w)$'; then
                    if [ $3 == w ]; then
                        NUM_DAYS=6
                    else
                        NUM_DAYS=$(($3 - 1))
                    fi
                    for i in $(seq $NUM_DAYS 0); do
                        if [ "$HOUR" -lt 6 ]; then
                            ((i++))
                        fi
                        WINDOW_START_DATE="$(date -v-${i}d +"%Y-%m-%d")"
                        WINDOW_START="$WINDOW_START_DATE 06:00"
                        WINDOW_END="$(date -j -v+1d -f "%Y-%m-%d" "$WINDOW_START_DATE" "+%Y-%m-%d") 06:00"
                        DAY="$(date -j -f "%Y-%m-%d" "$WINDOW_START_DATE" +%a)"
                        TOTAL=$(_sum_total_hours)
                        echo "$DAY: $TOTAL"
                    done
                else
                    echo "Argument must be an integer or 'w'"
                    exit 1
                fi
                ;;

            -w|--week)
                # If it's currently a Monday btwn 12am & 6am, the Monday that
                #   begins the current week is set to the prior Monday at 6am.
                # Otherwise, it's set to the most recent Monday at 6am, 
                #   including if today is Monday after 6am.
                if [ $(date +"%a") = "Mon" ] && [ "$HOUR" -lt 6 ]; then
                    THIS_MONDAY=$(date -v-1w +"%Y-%m-%d")
                else
                    THIS_MONDAY=$(date -v-monday +"%Y-%m-%d")
                fi

                # If no arg, print this week
                if [ -z "$3" ]; then
                    WINDOW_START="$THIS_MONDAY 06:00"
                    WINDOW_END=""
                    TOTAL=$(_sum_total_hours)
                    echo "This week: $TOTAL"

                # If arg, print X most recent weeks
                elif printf '%s' "$3" | grep -qE '^[0-9]+$'; then
                    for i in $(seq $3 1); do
                        ((i--))
                        # Get Monday that started the last week
                        # -j tells date not to set system clock (and parse input string
                        #   instead)
                        # -v-${i}w subtracts `i` weeks off the input string
                        # -f "%Y-%m-%d" specifies format input string is in
                        # "$THIS_MONDAY" is the input string
                        # "+%Y-%m-%d" is format for output date
                        MONDAY_START=$(date -j -v-${i}w -f "%Y-%m-%d" "$THIS_MONDAY" "+%Y-%m-%d")
                        MONDAY_END=$(date -j -v+1w -f "%Y-%m-%d" "$MONDAY_START" "+%Y-%m-%d")
                        WINDOW_START="$MONDAY_START 06:00"
                        WINDOW_END="$MONDAY_END 06:00"
                        TOTAL=$(_sum_total_hours)

                        START_DATE=$(date -j -f "%Y-%m-%d" "$MONDAY_START" "+%-m-%d")
                        echo "$START_DATE: $TOTAL"
                    done
                else
                    echo "Argument must be an integer"
                    exit 1
                fi
                ;;

            *)
                echo "Error: options are -d (days) and -w (weeks) with optional number"
                exit 1
                ;;
        esac
        ;;

    tail)
        if [ -z "$2" ]; then
            printf "\n$(tail -n 5 "$CSV_FILE")\n\n"
        elif printf '%s' "$2" | grep -qE '^[0-9]+$'; then
            printf "\n$(tail -n $2 "$CSV_FILE")\n\n"
        else
            echo "Argument must be an integer"
            exit 1
        fi
        ;;

    status)
        ACTIVE=$(_find_active_line_num)
        if [ "$ACTIVE" -eq 0 ]; then
            echo "No active session"
        else
            LINE=$(awk -F ',' -v n="$ACTIVE" 'NR == n' "$CSV_FILE")
            ACTIVITY=$(echo "$LINE" | cut -d ',' -f 5)
            START_TIME=$(echo "$LINE" | cut -d ',' -f 3)
            echo "Active: $ACTIVITY @ $START_TIME"
        fi
        ;;

    sort)
        { 
            head -n 1 "$CSV_FILE"; tail -n +2 "$CSV_FILE" | sort -t, -k1,1 -k3,3; 
        } > "$CSV_FILE.tmp" && mv "$CSV_FILE.tmp" "$CSV_FILE"
        ;;
    
    open)
        open "$CSV_FILE"
        ;;

    backup)
        cp "$CSV_FILE" "$DIR/backup/work_log.txt"
        ;;

    prep|act-cat)
        subl "$DIR/../../work-log-dash/scripts/data_prep.R"
        ;;

    map|cat-umb|cat-um)
        subl "$DIR/../../work-log-dash/categories/map.csv"
        ;;

    launch|run|app)
        Rscript -e "library(shiny); shiny::runApp('${DIR}/../../work-log-dash', launch.browser=TRUE)"
        ;;

    *)
        echo "Usage:"
        echo "  wl start <activity> [descr]                         Start tracking activity"
        echo "  wl stop [HH:MM]                                     Stop current activity"
        echo "  wl resume                                           Re-start prior activity"
        echo "  wl link <activity> [descr]                          Start block @ prior stop time"
        echo "  wl next <activity> [descr]                          Run 'stop' then 'link'"
        echo "  wl undo                                             Undo last entry action"
        echo "  wl edit <activity> [descr]                          Edit current activity"
        echo "  wl <HH:MM> [HH:MM] <activity> [descr]               Input time(s) manually"
        echo "  wl <YYYY-MM-DD> <HH:MM> [HH:MM] <activity> [descr]  Input date & time(s) manually"
        echo "  wl total [-d [X w] -w [X]]                          Show total hours worked"
        echo "  wl tail [X]                                         Show most recent entries"
        echo "  wl status                                           Check for active session"
        echo "  wl sort                                             Sort by date & time"
        echo "  wl open                                             Open work_log.txt"
        echo "  wl backup                                           Update backup copy of log"
        echo "  wl prep|act-cat                                     Open activity-category script"
        echo "  wl map|cat-umb|cat-um                               Open category-umbrella map"
        echo "  wl launch|run|app                                   Launch work log dashboard"
        echo "Output: $CSV_FILE"
        ;;
esac
