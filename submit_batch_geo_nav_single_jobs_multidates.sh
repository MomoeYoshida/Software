#!/bin/bash
# Usage: ./submit_batch_geo_nav_single_jobs.sh 20250111 20250331
# Submits one PBS job per day in the range, using Calendar dates

start_date="$1"
end_date="$2"

if [ -z "$start_date" ] || [ -z "$end_date" ]; then
    echo "Usage: $0 <start_date: YYYYMMDD> <end_date: YYYYMMDD>"
    exit 1
fi

# Convert to epoch seconds
start_sec=$(date -d "$start_date" +%s)
end_sec=$(date -d "$end_date" +%s)

if [ $? -ne 0 ]; then
    echo "❌ ERROR: Invalid date format. Use YYYYMMDD."
    exit 1
fi

current_sec=$start_sec

echo "📅 Submitting batch_geo_nav_single.pbs jobs from $start_date → $end_date"
echo

while [ "$current_sec" -le "$end_sec" ]; do
    tar_date=$(date -d "@$current_sec" +%Y%m%d)

    echo "📤 Submitting job for $tar_date"
    qsub -v tar_date=$tar_date batch_geo_nav_single.pbs

    sleep 0.5  # Avoid overloading scheduler

    # Next day
    current_sec=$((current_sec + 86400))
done

echo
echo "✅ All jobs submitted!"
