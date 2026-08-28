#!/bin/bash

# =============================================================================
# submit_make_op_sst_workflow.sh
#
# Purpose:
#   Submit the complete daily operational SST workflow.
#
# Required command:
#   ./submit_make_op_sst_workflow.sh YYYY-MM-DD
#
# Example:
#   ./submit_make_op_sst_workflow.sh 2016-11-01
#
# Workflow:
#
#   1. Check the preceding day's SST analysis and SST variability files.
#
#      If either file is missing:
#        a. Download OSTIA for the preceding day and preceding ten days.
#        b. Run init_files_OSTIA.m.
#        c. Run init_all_biases.m.
#
#   2. For each analysis day:
#
#      If the required L3C data do not exist:
#        a. Download one day of L2P data.
#        b. Run the geo-navigation job.
#
#      Then:
#        c. Run generate_oi_input_data.m.
#        d. Delete temporary L2P data, if L2P was downloaded.
#        e. Run update_all_biases.m.
#        f. Run generate_oi_sst.m.
#
#   3. Repeat for the configured number of analysis days.
#
# Notes:
#   - All jobs are submitted immediately.
#   - PBS afterok dependencies enforce the processing order.
#   - A downstream job will not start if its prerequisite job fails.
# =============================================================================

set -euo pipefail

# =============================================================================
# 1. User and project configuration
# =============================================================================

BASE_DIR="/gpfs01/v2/Q9157/momoe/geo_polar_blended_sst/Linux_JCUHPC/blended_home"

SOFTWARE_DIR="${BASE_DIR}/Software"
DATA_DIR="${BASE_DIR}/Data"
ANALYSIS_DIR="${BASE_DIR}/Analysis"
L3C_DIR="${BASE_DIR}/Input_ssts"
LOG_DIR="${BASE_DIR}/Logs"

# -----------------------------------------------------------------------------
# Number of consecutive analysis days
#
# You only need to enter the start date on the command line.
# Change this setting when you want to process multiple consecutive days.
# -----------------------------------------------------------------------------

NUMBER_OF_DAYS=1

# -----------------------------------------------------------------------------
# MATLAB processing settings
# -----------------------------------------------------------------------------

STREAM="nrt" # not used
DIRECTION=1

# -----------------------------------------------------------------------------
# PBS and shell scripts
#
# Adjust these paths if your actual scripts are stored in another directory.
# -----------------------------------------------------------------------------

PBS_DOWNLOAD_OSTIA="${SOFTWARE_DIR}/download_podaac_ostiadata.pbs"
PBS_INIT_OSTIA_BIASES="${SOFTWARE_DIR}/run_init_ostia_biases.pbs"

PBS_DOWNLOAD_L2P="${SOFTWARE_DIR}/download_podaac_l2pdata.pbs"
GEO_NAV_SUBMIT_SCRIPT="${SOFTWARE_DIR}/submit_batch_geo_nav_single_jobs.sh"

PBS_GENERATE_OI_INPUT="${SOFTWARE_DIR}/run_generate_oi_input_data.pbs"
PBS_DELETE_L2P="${SOFTWARE_DIR}/delete_l2p_data.pbs"
PBS_UPDATE_ALL_BIASES="${SOFTWARE_DIR}/run_update_all_biases.pbs"
PBS_GENERATE_OI_SST="${SOFTWARE_DIR}/run_generate_oi_sst.pbs"

# =============================================================================
# 2. Helper functions
# =============================================================================

print_usage()
{
    cat <<EOF
Usage:
  $0 YYYY-MM-DD

Example:
  $0 2016-11-01
EOF
}


fail()
{
    echo "ERROR: $*" >&2
    exit 1
}


check_required_file()
{
    local required_file="$1"

    if [[ ! -f "$required_file" ]]; then
        fail "Required file does not exist: $required_file"
    fi
}


check_executable_file()
{
    local required_file="$1"

    if [[ ! -f "$required_file" ]]; then
        fail "Required script does not exist: $required_file"
    fi

    if [[ ! -x "$required_file" ]]; then
        fail "Required script is not executable: $required_file
Run:
  chmod u+x \"$required_file\""
    fi
}


validate_date()
{
    local input_date="$1"
    local parsed_date

    if [[ ! "$input_date" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
        fail "Date must use YYYY-MM-DD format. Received: $input_date"
    fi

    if ! parsed_date=$(
        date --utc \
            --date="${input_date}T00:00:00Z" \
            "+%Y-%m-%d" 2>/dev/null
    ); then
        fail "Could not parse date: $input_date"
    fi

    if [[ "$parsed_date" != "$input_date" ]]; then
        fail "Invalid calendar date: $input_date"
    fi
}


get_year()
{
    date --utc \
        --date="${1}T00:00:00Z" \
        "+%Y"
}


get_doy3()
{
    # Return zero-padded day of year, such as 001, 031, or 305.
    date --utc \
        --date="${1}T00:00:00Z" \
        "+%j"
}


get_doy_integer()
{
    local doy3

    doy3=$(get_doy3 "$1")

    # The 10# prefix forces decimal interpretation.
    echo $((10#$doy3))
}


analysis_outputs_exist()
{
    local year="$1"
    local doy3="$2"

    local analysis_file
    local variability_file

    analysis_file="${ANALYSIS_DIR}/sst_analysis_${year}_${doy3}.mat"
    variability_file="${ANALYSIS_DIR}/sst_variability_${year}_${doy3}.mat"

    [[ -f "$analysis_file" && -f "$variability_file" ]]
}


l3c_data_exist()
{
    local analysis_date="$1"
    local date_compact

    date_compact=$(
        date --utc \
            --date="${analysis_date}T00:00:00Z" \
            "+%Y%m%d"
    )

    # Search recursively because L3C files may be stored in subdirectories.
    #
    # Adjust this filename test if your L3C filenames do not contain YYYYMMDD.
    find "$L3C_DIR" \
        -type f \
        -name "*${date_compact}*" \
        -print -quit 2>/dev/null |
        grep -q .
}


submit_job()
{
    local job_id

    job_id=$(qsub "$@")

    if [[ -z "$job_id" ]]; then
        fail "qsub did not return a PBS job ID."
    fi

    printf '%s\n' "$job_id"
}


submit_afterok()
{
    local preceding_job_id="$1"
    shift

    local job_id

    if [[ -z "$preceding_job_id" ]]; then
        fail "submit_afterok was called without a preceding PBS job ID."
    fi

    job_id=$(
        qsub \
            -W depend=afterok:"$preceding_job_id" \
            "$@"
    )

    if [[ -z "$job_id" ]]; then
        fail "qsub did not return a PBS job ID."
    fi

    printf '%s\n' "$job_id"
}


submit_with_optional_dependency()
{
    local preceding_job_id="$1"
    shift

    if [[ -n "$preceding_job_id" ]]; then
        submit_afterok "$preceding_job_id" "$@"
    else
        submit_job "$@"
    fi
}


print_job()
{
    local stage_name="$1"
    local job_id="$2"
    local dependency="${3:-none}"

    printf "  %-30s %s\n" "${stage_name}:" "$job_id"
    printf "  %-30s %s\n" "Dependency:" "$dependency"
}


record_job()
{
    local analysis_date="$1"
    local stage_name="$2"
    local job_id="$3"
    local dependency="${4:-none}"

    {
        echo "Analysis date: $analysis_date"
        echo "Stage: $stage_name"
        echo "Job ID: $job_id"
        echo "Dependency: $dependency"
        echo
    } >> "$WORKFLOW_RECORD"
}


# =============================================================================
# 3. Validate the command-line argument
# =============================================================================

if [[ $# -ne 1 ]]; then
    print_usage
    exit 1
fi

START_DATE="$1"

validate_date "$START_DATE"

if ! [[ "$NUMBER_OF_DAYS" =~ ^[1-9][0-9]*$ ]]; then
    fail "NUMBER_OF_DAYS must be a positive integer."
fi

if ! [[ "$DIRECTION" =~ ^-?[0-9]+$ ]]; then
    fail "DIRECTION must be an integer."
fi

# =============================================================================
# 4. Check commands, directories, PBS files, and shell scripts
# =============================================================================

if ! command -v qsub >/dev/null 2>&1; then
    fail "The qsub command is not available."
fi

mkdir -p "$LOG_DIR"
mkdir -p "$ANALYSIS_DIR"
mkdir -p "$L3C_DIR"

check_required_file "$PBS_DOWNLOAD_OSTIA"
check_required_file "$PBS_INIT_OSTIA_BIASES"
check_required_file "$PBS_DOWNLOAD_L2P"
check_required_file "$PBS_GENERATE_OI_INPUT"
check_required_file "$PBS_DELETE_L2P"
check_required_file "$PBS_UPDATE_ALL_BIASES"
check_required_file "$PBS_GENERATE_OI_SST"

check_executable_file "$GEO_NAV_SUBMIT_SCRIPT"

# =============================================================================
# 5. Create a workflow submission record
# =============================================================================

SUBMISSION_TIMESTAMP=$(date "+%Y%m%d_%H%M%S")

WORKFLOW_RECORD="${LOG_DIR}/make_op_sst_workflow_${START_DATE}_${SUBMISSION_TIMESTAMP}.txt"

{
    echo "============================================================"
    echo "make_op_sst workflow submission"
    echo "============================================================"
    echo "Submission time : $(date)"
    echo "Submission host : $(hostname)"
    echo "Submitted by    : ${USER:-unknown}"
    echo "Start date      : $START_DATE"
    echo "Number of days  : $NUMBER_OF_DAYS"
    echo "Stream          : $STREAM"
    echo "Direction       : $DIRECTION"
    echo "============================================================"
    echo
} > "$WORKFLOW_RECORD"

# =============================================================================
# 6. Calculate the day before the analysis start date
# =============================================================================

PREVIOUS_DATE=$(
    date --utc \
        --date="${START_DATE}T00:00:00Z -1 day" \
        "+%Y-%m-%d"
)

PREVIOUS_YEAR=$(get_year "$PREVIOUS_DATE")
PREVIOUS_DOY3=$(get_doy3 "$PREVIOUS_DATE")
PREVIOUS_DAY_OF_YEAR=$(get_doy_integer "$PREVIOUS_DATE")

PREVIOUS_ANALYSIS_FILE="${ANALYSIS_DIR}/sst_analysis_${PREVIOUS_YEAR}_${PREVIOUS_DOY3}.mat"
PREVIOUS_VARIABILITY_FILE="${ANALYSIS_DIR}/sst_variability_${PREVIOUS_YEAR}_${PREVIOUS_DOY3}.mat"

# TAR_DATE passed to download_podaac_ostiadata.pbs.
#
# The PBS job calculates:
#   PREV_DATE = TAR_DATE minus 10 days
#   END_DATE  = TAR_DATE plus 1 day
OSTIA_TARGET_DATE="${PREVIOUS_DATE}T00:00:00Z"

echo "============================================================"
echo "Submitting make_op_sst workflow"
echo "============================================================"
echo "Analysis start date      : $START_DATE"
echo "Previous date            : $PREVIOUS_DATE"
echo "Previous year            : $PREVIOUS_YEAR"
echo "Previous day of year     : $PREVIOUS_DAY_OF_YEAR"
echo "Previous day-of-year DDD : $PREVIOUS_DOY3"
echo "Number of analysis days  : $NUMBER_OF_DAYS"
echo "Stream                   : $STREAM"
echo "Direction                : $DIRECTION"
echo "Workflow record          : $WORKFLOW_RECORD"
echo "============================================================"

# LAST_JOB_ID is the job that must finish before the next stage can start.
LAST_JOB_ID=""

# =============================================================================
# 7. Step 1: Initialize preceding-day OSTIA files and biases when needed
# =============================================================================

echo
echo "============================================================"
echo "Step 1: Check preceding-day SST files"
echo "============================================================"
echo "Analysis file:"
echo "  $PREVIOUS_ANALYSIS_FILE"
echo "Variability file:"
echo "  $PREVIOUS_VARIABILITY_FILE"

if analysis_outputs_exist "$PREVIOUS_YEAR" "$PREVIOUS_DOY3"; then

    echo
    echo "Both preceding-day files already exist."
    echo "OSTIA download and initial bias creation will be skipped."

    {
        echo "Preceding-day initialization"
        echo "Status: skipped"
        echo "Reason: both required preceding-day files exist"
        echo "Analysis file: $PREVIOUS_ANALYSIS_FILE"
        echo "Variability file: $PREVIOUS_VARIABILITY_FILE"
        echo
    } >> "$WORKFLOW_RECORD"

else

    echo
    echo "One or both preceding-day files are missing."
    echo "Submitting the OSTIA initialization chain."

    # -------------------------------------------------------------------------
    # Step 1.1: Download OSTIA
    # -------------------------------------------------------------------------

    OSTIA_LOG="${LOG_DIR}/download_ostia_${PREVIOUS_DATE}.log"

    JOB_DOWNLOAD_OSTIA=$(
        submit_job \
            -o "$OSTIA_LOG" \
            -v TAR_DATE="$OSTIA_TARGET_DATE" \
            "$PBS_DOWNLOAD_OSTIA"
    )

    print_job \
        "Download OSTIA" \
        "$JOB_DOWNLOAD_OSTIA"

    record_job \
        "$PREVIOUS_DATE" \
        "Download OSTIA" \
        "$JOB_DOWNLOAD_OSTIA"

    # -------------------------------------------------------------------------
    # Step 1.2: Run init_files_OSTIA.m and init_all_biases.m
    # -------------------------------------------------------------------------

    INIT_OSTIA_LOG="${LOG_DIR}/init_ostia_biases_${PREVIOUS_DATE}.log"

    JOB_INIT_OSTIA_BIASES=$(
        submit_afterok "$JOB_DOWNLOAD_OSTIA" \
            -o "$INIT_OSTIA_LOG" \
            -v YEAR="$PREVIOUS_YEAR",DAY_OF_YEAR="$PREVIOUS_DAY_OF_YEAR" \
            "$PBS_INIT_OSTIA_BIASES"
    )

    print_job \
        "Initialize OSTIA/biases" \
        "$JOB_INIT_OSTIA_BIASES" \
        "$JOB_DOWNLOAD_OSTIA"

    record_job \
        "$PREVIOUS_DATE" \
        "Initialize OSTIA and biases" \
        "$JOB_INIT_OSTIA_BIASES" \
        "$JOB_DOWNLOAD_OSTIA"

    LAST_JOB_ID="$JOB_INIT_OSTIA_BIASES"

fi

# =============================================================================
# 8. Process each analysis date
# =============================================================================

for ((day_offset = 0; day_offset < NUMBER_OF_DAYS; day_offset++)); do

    ANALYSIS_DATE=$(
        date --utc \
            --date="${START_DATE}T00:00:00Z +${day_offset} days" \
            "+%Y-%m-%d"
    )

    YEAR=$(get_year "$ANALYSIS_DATE")
    DOY3=$(get_doy3 "$ANALYSIS_DATE")
    DAY_OF_YEAR=$(get_doy_integer "$ANALYSIS_DATE")

    ANALYSIS_FILE="${ANALYSIS_DIR}/sst_analysis_${YEAR}_${DOY3}.mat"
    VARIABILITY_FILE="${ANALYSIS_DIR}/sst_variability_${YEAR}_${DOY3}.mat"

    echo
    echo "============================================================"
    echo "Analysis date: $ANALYSIS_DATE"
    echo "============================================================"
    echo "Year        : $YEAR"
    echo "Day of year : $DAY_OF_YEAR"
    echo "DDD format  : $DOY3"
    echo "Analysis    : $ANALYSIS_FILE"
    echo "Variability : $VARIABILITY_FILE"
    echo "Predecessor : ${LAST_JOB_ID:-none}"
    echo "============================================================"

    {
        echo "============================================================"
        echo "Daily analysis"
        echo "Analysis date: $ANALYSIS_DATE"
        echo "Year: $YEAR"
        echo "Day of year: $DAY_OF_YEAR"
        echo "DDD format: $DOY3"
        echo "Initial predecessor: ${LAST_JOB_ID:-none}"
        echo "============================================================"
        echo
    } >> "$WORKFLOW_RECORD"

    L2P_WAS_SUBMITTED=false

    # =========================================================================
    # Step 2: Prepare L3C data
    # =========================================================================

    echo
    echo "Step 2: Check L3C data for $ANALYSIS_DATE"

    if l3c_data_exist "$ANALYSIS_DATE"; then

        echo "L3C data already exist for $ANALYSIS_DATE."
        echo "L2P download and geo-navigation and generate_oi_input_data and L2P delete will be skipped."

        {
            echo "L3C status: existing"
            echo "L2P download: skipped"
            echo "Geo-navigation: skipped"
	    echo "generate_oi_input_data: skipped"
            echo "L2P delete: skipped"
        } >> "$WORKFLOW_RECORD"

    else

        echo "L3C data do not exist for $ANALYSIS_DATE."
        echo "Submitting L2P download and geo-navigation."

        # ---------------------------------------------------------------------
        # Step 2.1: Download one day of L2P data
        # ---------------------------------------------------------------------

        L2P_LOG="${LOG_DIR}/download_l2p_${ANALYSIS_DATE}.log"

        JOB_DOWNLOAD_L2P=$(
            submit_with_optional_dependency "$LAST_JOB_ID" \
                -o "$L2P_LOG" \
                -v ANALYSIS_DATE="$ANALYSIS_DATE" \
                "$PBS_DOWNLOAD_L2P"
        )

        print_job \
            "Download L2P" \
            "$JOB_DOWNLOAD_L2P" \
            "${LAST_JOB_ID:-none}"

        record_job \
            "$ANALYSIS_DATE" \
            "Download L2P" \
            "$JOB_DOWNLOAD_L2P" \
            "${LAST_JOB_ID:-none}"

        L2P_WAS_SUBMITTED=true

        # ---------------------------------------------------------------------
        # Step 2.2: Submit one geo-navigation job
        #
        # submit_batch_geo_nav_single_jobs.sh:
        #   $1 = analysis date in YYYY-MM-DD format
        #   $2 = preceding PBS job ID
        #
        # The shell script converts the date to YYYYMMDD and passes:
        #   tar_date=YYYYMMDD
        #
        # to batch_geo_nav_single.pbs.
        # ---------------------------------------------------------------------

        JOB_GEO_NAV=$(
            "$GEO_NAV_SUBMIT_SCRIPT" \
                "$ANALYSIS_DATE" \
                "$JOB_DOWNLOAD_L2P"
        )

	# Remove any accidental carriage return.
	JOB_GEO_NAV="${JOB_GEO_NAV//$'\r'/}"

        if [[ -z "$JOB_GEO_NAV" ]]; then
            fail "Geo-navigation submission returned no PBS job ID."
        fi

        print_job \
            "Geo-navigation" \
            "$JOB_GEO_NAV" \
            "$JOB_DOWNLOAD_L2P"

        record_job \
            "$ANALYSIS_DATE" \
            "Geo-navigation" \
            "$JOB_GEO_NAV" \
            "$JOB_DOWNLOAD_L2P"

        LAST_JOB_ID="$JOB_GEO_NAV"


	# =========================================================================
	# Step 2.3: Run generate_oi_input_data.m
	# =========================================================================

	echo
	echo "Submitting generate_oi_input_data for $ANALYSIS_DATE."

	GENERATE_INPUT_LOG="${LOG_DIR}/generate_oi_input_${ANALYSIS_DATE}.log"

	JOB_GENERATE_OI_INPUT=$(
	submit_with_optional_dependency "$LAST_JOB_ID" \
	    -o "$GENERATE_INPUT_LOG" \
	    -v YEAR="$YEAR",DAY_OF_YEAR="$DAY_OF_YEAR",STREAM="$STREAM" \
	    "$PBS_GENERATE_OI_INPUT"
	)

	print_job \
	"Generate OI input" \
	"$JOB_GENERATE_OI_INPUT" \
	"${LAST_JOB_ID:-none}"

	record_job \
	"$ANALYSIS_DATE" \
	"Generate OI input" \
	"$JOB_GENERATE_OI_INPUT" \
	"${LAST_JOB_ID:-none}"

	LAST_JOB_ID="$JOB_GENERATE_OI_INPUT"

	# =========================================================================
	# Step 2.4: Delete temporary L2P data
	#
	# Run cleanup only when this workflow submitted the L2P download.
	# =========================================================================

	if [[ "$L2P_WAS_SUBMITTED" == true ]]; then

	echo
	echo "Submitting L2P cleanup for $ANALYSIS_DATE."

	DELETE_L2P_LOG="${LOG_DIR}/delete_l2p_${ANALYSIS_DATE}.log"

	JOB_DELETE_L2P=$(
	    submit_afterok "$LAST_JOB_ID" \
		-o "$DELETE_L2P_LOG" \
		-v ANALYSIS_DATE="$ANALYSIS_DATE" \
		"$PBS_DELETE_L2P"
	)

	print_job \
	    "Delete temporary L2P" \
	    "$JOB_DELETE_L2P" \
	    "$LAST_JOB_ID"

	record_job \
	    "$ANALYSIS_DATE" \
	    "Delete temporary L2P" \
	    "$JOB_DELETE_L2P" \
	    "$LAST_JOB_ID"

	LAST_JOB_ID="$JOB_DELETE_L2P"

	else

	echo "L2P cleanup skipped because this workflow did not download L2P."

	{
	    echo "L2P cleanup: skipped"
	    echo "Reason: L3C data existed before submission"
	    echo
	} >> "$WORKFLOW_RECORD"

	fi





    fi

    # =========================================================================
    # Step 3: Run update_all_biases.m
    # =========================================================================

    echo
    echo "Step 3: Submitting update_all_biases for $ANALYSIS_DATE."

    UPDATE_BIASES_LOG="${LOG_DIR}/update_all_biases_${ANALYSIS_DATE}.log"

    JOB_UPDATE_ALL_BIASES=$(
        submit_afterok "$LAST_JOB_ID" \
            -o "$UPDATE_BIASES_LOG" \
            -v YEAR="$YEAR",DAY_OF_YEAR="$DAY_OF_YEAR",DIRECTION="$DIRECTION" \
            "$PBS_UPDATE_ALL_BIASES"
    )

    print_job \
        "Update all biases" \
        "$JOB_UPDATE_ALL_BIASES" \
        "$LAST_JOB_ID"

    record_job \
        "$ANALYSIS_DATE" \
        "Update all biases" \
        "$JOB_UPDATE_ALL_BIASES" \
        "$LAST_JOB_ID"

    LAST_JOB_ID="$JOB_UPDATE_ALL_BIASES"

    # =========================================================================
    # Step 4: Run generate_oi_sst.m
    # =========================================================================

    echo
    echo "Step 4: Submitting generate_oi_sst for $ANALYSIS_DATE."

    GENERATE_OI_SST_LOG="${LOG_DIR}/generate_oi_sst_${ANALYSIS_DATE}.log"

    JOB_GENERATE_OI_SST=$(
        submit_afterok "$LAST_JOB_ID" \
            -o "$GENERATE_OI_SST_LOG" \
            -v YEAR="$YEAR",DAY_OF_YEAR="$DAY_OF_YEAR",DIRECTION="$DIRECTION" \
            "$PBS_GENERATE_OI_SST"
    )

    print_job \
        "Generate OI SST" \
        "$JOB_GENERATE_OI_SST" \
        "$LAST_JOB_ID"

    record_job \
        "$ANALYSIS_DATE" \
        "Generate OI SST" \
        "$JOB_GENERATE_OI_SST" \
        "$LAST_JOB_ID"

    # =========================================================================
    # Step 5: Preserve the chronological daily chain
    #
    # The first job for the following day must wait for this day's final SST
    # generation job.
    # =========================================================================

    LAST_JOB_ID="$JOB_GENERATE_OI_SST"

    {
        echo "Final job for $ANALYSIS_DATE: $LAST_JOB_ID"
        echo
    } >> "$WORKFLOW_RECORD"

done

# =============================================================================
# 9. Final summary
# =============================================================================

echo
echo "============================================================"
echo "Workflow submission completed successfully"
echo "============================================================"
echo "Analysis start date : $START_DATE"
echo "Number of days      : $NUMBER_OF_DAYS"
echo "Final submitted job : ${LAST_JOB_ID:-none}"
echo "Workflow record     : $WORKFLOW_RECORD"
echo
echo "Monitor your jobs with:"
echo "  qstat -u \"$USER\""
echo
echo "Inspect the workflow record with:"
echo "  cat \"$WORKFLOW_RECORD\""
echo "============================================================"

{
    echo "============================================================"
    echo "Workflow submission completed"
    echo "Completion time: $(date)"
    echo "Final submitted job: ${LAST_JOB_ID:-none}"
    echo "============================================================"
} >> "$WORKFLOW_RECORD"
