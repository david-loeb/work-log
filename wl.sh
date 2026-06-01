#!/usr/bin/env bash

# Define constant var for file path of CSV
# note: the double quotes supress `~` expansion, so u have to use the `$HOME` 
# variable instead
CSV_FILE="$HOME/Desktop/work_log.csv"

# Create the CSV file if it doesn't exist, with the header row
if [ ! -f "$CSV_FILE" ]; then
    echo "date,day,start_time,end_time,activity,description" > "$CSV_FILE"
fi

# Function that finds the "active row" ie row w/ start time but no end time
# `$4` is "end_time" column, so it finds the line where this col is blank
# The END action `print found+0` is structured so that if there is no line
#   that meets the condition, ie no lines have a blank end_time, the `found`
#   variable will be empty, so we add 0 to it to ensure that the output will
#   be 0 in these cases
# The above situation happens when we don't have an active session going, and we
#   can use this info to throw an error if we try to run `stop`
# The reason it's set up with the `END` statement is that, in case there are
#   multiple rows that match this condition, it will only print the last such
#   row. There should never be multiple rows in this situation, but i guess
#   it's not so bad to have this extra logic, as it makes it a bit safer, in
#   case somehow an end time gets accidently deleted above or something
_find_active_line_num() {
    awk -F',' 'NR > 1 && $4 == "" { found = NR } END { print found+0 }' "$CSV_FILE"
}

# Case statement that executes diff set of commands based on the value of the
# first arg (ie either `start`, `stop`, `status`, or anything else)
case "$1" in
    start)
        # If there is no second argument after `start`, throw error, since 
        # an activity is required
        if [ -z "$2" ]; then
            echo "Error: please provide an activity name."
            echo "Usage: wl start [activity] [optional description]"
            exit 1
        fi

        ACTIVE=$(_find_active_line_num)
        # If ACTIVE is not 0, it means we have an active session going, so we 
        # cant use `start`, so we need to throw an error
        if [ "$ACTIVE" -gt 0 ]; then
            # This does an extra step of printing the activity name of the 
            # active session - really not necessary but whatev as long as 
            # the script still runs like instantly
            CURRENT=$(awk -F',' -v n="$ACTIVE" 'NR==n { print $5 }' "$CSV_FILE")
            echo "Error: session already active — \"$CURRENT\". Run 'wl stop' first."
            exit 1
        fi

        # Saves current date, day of week, and time in variables
        DATE=$(date +"%Y-%m-%d")
        DAY=$(date +"%a")
        START_TIME=$(date +"%H:%M:%S")
        # Saves arg 2 in a variable (seems unnecessary...?)
        ACTIVITY="$2"
        # Saves description as args 3 and onward, spliced into a single 
        # space-separated string (kind of unnecessary since i wont do >3 args)
        DESCRIPTION="${*:3}"
        printf '%s,%s,%s,,%s,%s\n' "$DATE" "$DAY" "$START_TIME" "$ACTIVITY" "$DESCRIPTION" >> "$CSV_FILE"
        echo "Started: $ACTIVITY at $START_TIME"
        ;;

    stop)
        ACTIVE=$(_find_active_line_num)
        # If active line equals 0, ie there is no active session, it means we 
        # cant run `stop`, so need to throw an error
        if [ "$ACTIVE" -eq 0 ]; then
            echo "Error: no active session. Run 'wl start [activity]' first."
            exit 1
        fi

        # Define END_TIME and ACTIVITY variables
        END_TIME=$(date +"%H:%M:%S")
        ACTIVITY=$(awk -F',' -v n="$ACTIVE" 'NR==n { print $5 }' "$CSV_FILE")

        # The awk prog sets up an action to be run for the active line only
        # which finds the character number of the comma that precedes the 
        # end_time col (`idx`), then re-prints this line by concatenating
        # three pieces: the line through that comma at the `idx` point,
        # then the time stored in the END_TIME variable above (which we've 
        # defined for awk as `t`), and then the remainder of the line beginning
        # with the comma that signifies end of end_time column and start of next
        # col (ie the activity col).
        # The `next` command ends this activity, telling awk to exit the program
        # for this record now, rather than running the next activity.
        # The next activity is just to print the whole record as-is, and this
        # action is taken for all the other records (since they do not match
        # the condition NR == n, ie they are not the currently active line)

        # The file replacement .tmp thing is set up so that only if the awk 
        # succeeds (and thus the original CSV has the actions performed
        # on it and gets written to the .tmp file) does the mv get executed,
        # which renames the .tmp to the original file name, thus overwriting
        # it (and leaving no trace of an extra file).
        awk -v n="$ACTIVE" -v t="$END_TIME" '
            NR == n {
                idx = index($0, ",,")
                print substr($0, 1, idx) t substr($0, idx + 1)
                next
            }
            { print }
        ' "$CSV_FILE" > "$CSV_FILE.tmp" && mv "$CSV_FILE.tmp" "$CSV_FILE"

        echo "Stopped: $ACTIVITY at $END_TIME"
        ;;

    status)
        ACTIVE=$(_find_active_line_num)
        if [ "$ACTIVE" -eq 0 ]; then
            echo "No active session."
        else
            # Gets the active line as a single string
            # Since no action supplied, it just does the default, ie print
            # the entire record, and it does this only for the active line,
            # ie the one where NR==n
            LINE=$(awk -F',' -v n="$ACTIVE" 'NR==n' "$CSV_FILE")
            # The `cut` grabs the field numbers specified by the `-f` flag and 
            # saves as the variables
            DATE=$(echo "$LINE" | cut -d',' -f1)
            DAY=$(echo "$LINE" | cut -d',' -f2)
            START=$(echo "$LINE" | cut -d',' -f3)
            ACTIVITY=$(echo "$LINE" | cut -d',' -f5)
            DESCRIPTION=$(echo "$LINE" | cut -d',' -f6-)
            # If the description field is not empty (aka is non-zero)
            if [ -n "$DESCRIPTION" ]; then
                echo "Active: $ACTIVITY — $DESCRIPTION (started $DAY $DATE at $START)"
            else
                echo "Active: $ACTIVITY (started $DAY $DATE at $START)"
            fi
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
