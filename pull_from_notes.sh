#!/usr/bin/env bash

shopt -s extglob

# Get note; first open the app to ensure it pulls latest version from cloud
osascript -e 'tell application "Notes" to activate'
sleep 2
osascript -e 'tell application "System Events" to set visible of process "Notes" to false'
NOTES="$(osascript -e 'tell app "Notes" to get body of note "work_log"')"
# Notes auto-adds apostrophes sometimes, so remove any present
NOTES="${NOTES//\'/}"

# Put each entry into an array to iterate through
entries=()
while read -r line; do
	entries+=("${line}")
done <<< "$NOTES"

NUM_ENTRY_INDICES=$((${#entries[@]} - 1))

for i in $(seq 2 $NUM_ENTRY_INDICES); do
	# Strip <div> tags and any trailing whitespace
	entry="${entries[${i}]#<div>}"
	entry="${entry%%*([[:space:]])</div>}"
	# Make all lower case
	entry="$(printf '%s' "$entry" | tr '[:upper:]' '[:lower:]')"

	# 'stop' entry: get start time of next activity to use as end time
	if [ "$entry" == "stop" ]; then
		# If next line is missing date but has start time, still use it
		if printf '%s' "${entries[$((${i}+1))]:7}" | grep -qE '^:'; then
			STOP_TIME="${entries[$((${i}+1))]:5:5}"
		else
			STOP_TIME="${entries[$((${i}+1))]:16:5}"
		fi
		eval "wl stop $STOP_TIME"
		continue 2
	fi


	# 'al link' entry: get end time of last activity log entry as start time
	if printf '%s' "$entry" | grep -qE '^al link'; then
		DIR="$(dirname "$(readlink "$0")")"
		ACT_LOG="$DIR/../activity-log/activity_log.txt"
		LINE=$(tail -n 1 "$ACT_LOG")
		DATE="$(echo "$LINE" | cut -d ',' -f 1)"
		START_TIME="$(echo "$LINE" | cut -d ',' -f 3)"
		END_TIME="$(echo "$LINE" | cut -d ',' -f 4)"
		if [ "$START_TIME" \> "$END_TIME" ]; then
			DATE="$(date -j -v+1d -f "%Y-%m-%d" "$DATE" "+%Y-%m-%d")"
		fi
		entry="$DATE $END_TIME ${entry:8}"
	fi
	
	if ! printf '%s' "$entry" | grep -qE '^20[2-9][0-9]-[0-1][0-9]-[0-3][0-9] [0-2][0-9]:[0-9][0-9]'; then
		echo "Error: entries must begin with date & start time (properly formatted)"
		exit 1
	fi

	# If there is just a start time (no end time), get stop time from next line
	if printf '%s' "$entry" | grep -qE '^20[2-9][0-9]-[0-1][0-9]-[0-3][0-9] [0-2][0-9]:[0-9][0-9] (\&quot)?[a-z]'; then
		if [ $i -lt $NUM_ENTRY_INDICES ]; then
			# If next line is missing date but has start time, still use it
			if printf '%s' "${entries[$((${i}+1))]:7}" | grep -qE '^:'; then
				STOP_TIME="${entries[$((${i}+1))]:5:5}"
			else
				STOP_TIME="${entries[$((${i}+1))]:16:5}"
			fi
			entry="${entry:0:17}$STOP_TIME ${entry:17}"
		fi
	fi

	# Add double quotes around activity names
	case "$entry" in
	# If quotes entered in notes app, they are rendered as `&quot`, so need to change
	*\&quot*)
		entry="${entry//\&quot/\"}"
		;;
	# If not entered in notes app, add them 
	*)
		TIME_DATE="${entry%%[[:alpha:]]*}"
		ACTIVITY="${entry#"$TIME_DATE"}"
		entry="${TIME_DATE}\"${ACTIVITY}\""
	esac

	eval "wl $entry"
	status=$?
	if [ "$status" -ne 0 ]; then
		break
	fi
done

if [ "$status" -ne 0 ]; then
	echo "Error: 'wl $entry' failed; remove any successful new entries, fix error, and re-try"
	exit 1
fi

# al sort  # turn off for now so i can easily inspect results
osascript -e 'tell app "Notes" to set body of note "work_log" to "<div><h1>work_log</h1></div><div><br></div>"'
