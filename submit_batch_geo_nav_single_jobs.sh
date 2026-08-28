#!/bin/bash
# Usage: ./submit_batch_geo_nav_single_jobs.sh 2016-11-01 
# Submit one batch_geo_nav_single.pbs job for one analysis date. 

set -euo pipefail
BASE_DIR="/gpfs01/v2/Q9157/momoe/geo_polar_blended_sst/Linux_JCUHPC/blended_home"
LOG_DIR="${BASE_DIR}/Logs"
ANALYSIS_DATE="$1"
DEPENDENCY_JOB_ID="${2:-}"
TAR_DATE=$(date --utc \
	--date="${ANALYSIS_DATE}T00:00:00Z" \
	"+%Y%m%d"
)
GEO_NAV_PBS="${BASE_DIR}/Software/batch_geo_nav_single.pbs"
LOG_FILE="${LOG_DIR}/geo_nav_${ANALYSIS_DATE}.log"


echo "📅 Submitting batch_geo_nav_single.pbs job for $TAR_DATE" >&2 
echo

if [[ -n "$DEPENDENCY_JOB_ID" ]]; then
    echo "  Dependency    : afterok:$DEPENDENCY_JOB_ID" >&2

    JOB_ID=$(
        qsub \
            -W depend=afterok:"$DEPENDENCY_JOB_ID" \
            -v tar_date="$TAR_DATE" \
            -o "$LOG_FILE" \
            "$GEO_NAV_PBS"
    )
else
    echo "  Dependency    : none" >&2

    JOB_ID=$(
        qsub \
            -v tar_date="$TAR_DATE" \
            -o "$LOG_FILE" \
            "$GEO_NAV_PBS"
    )
fi

# -------------------------------------------------------------------------
# Validate qsub result
# -------------------------------------------------------------------------

if [[ -z "$JOB_ID" ]]; then
    fail "qsub did not return a job ID for $ANALYSIS_DATE."
fi

echo "Geo-navigation job submitted successfully: $JOB_ID" >&2

# IMPORTANT:
# Print only the job ID to standard output. The workflow controller captures
# this value and uses it as the dependency for generate_oi_input_data.
printf '%s\n' "$JOB_ID"

