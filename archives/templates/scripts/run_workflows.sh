#!/bin/bash

# This script is a wrapper that prepares multiple things for use at FNLCR prior to running the workflows.

# Write a function to output the key-value pairs
output_json_format() {
    params=("$@")
    for var in "${params[@]}"; do
        echo -n "\"$var\": \"${!var}\", "
    done
}

export USING_TEMPLATES=1

# These are variables from the module .lua files
params1=(CANDLE SITE TURBINE_HOME)

# This is the result from:
#   submit_script="/data/BIDS-HPC/public/candle-dev/Supervisor/templates/scripts/submit_candle_job.sh"
#   params=( $(grep "^export " $submit_script | grep -v "export USE_CANDLE=" | awk -v ORS=" " '{split($2,arr,"="); print arr[1]}'))
params2=(MODEL_SCRIPT DEFAULT_PARAMS_FILE PYTHON_BIN_PATH EXEC_PYTHON_MODULE SUPP_MODULES SUPP_PYTHONPATH WORKFLOW_TYPE WORKFLOW_SETTINGS_FILE EXPERIMENTS MODEL_NAME OBJ_RETURN PROCS WALLTIME GPU_TYPE)

# These are variables from run_workflows.sh
params3=(CPUS_PER_TASK MEM_PER_NODE PPN)

# For now set the default Python module for execution to be the same as that used for the CANDLE/Swift/T build
# We assume that the modules for the build are a single Python module
export DEFAULT_PYTHON_MODULE="$MODULES_FOR_BUILD"

# These are constants referring to the CANDLE-compliant wrapper Python script
export MODEL_PYTHON_DIR="$CANDLE/Supervisor/templates/scripts"
export MODEL_PYTHON_SCRIPT="candle_compliant_wrapper"

# Set a proportional number of processors to use on the node
export CPUS_PER_TASK=14
if [ "x$(echo $GPU_TYPE | awk '{print tolower($1)}')" == "xk20x" ]; then
    export CPUS_PER_TASK=16
fi

# Set a proportional amount of memory to use on the node
if [ "x$(echo $GPU_TYPE | awk '{print tolower($1)}')" == "xk20x" ] || [ "x$(echo $GPU_TYPE | awk '{print tolower($1)}')" == "xk80" ]; then
    export MEM_PER_NODE="60G"
else
    export MEM_PER_NODE="30G"
fi

# Run one MPI process (GPU process) per node on Biowulf
export PPN="1"

# Create the experiments directory if it doesn't already exist
if [ ! -d $EXPERIMENTS ]; then
    mkdir -p $EXPERIMENTS && echo "Experiments directory created: $EXPERIMENTS"
fi

# For running the workflows themselves, load the module with which Swift/T was built
module load $MODULES_FOR_BUILD

# If doing the UPF workflow...
if [ "x$WORKFLOW_TYPE" == "xupf" ]; then

    # If a restart job is requested...
    if [ -n "$RESTART_FROM_EXP" ]; then

        # Ensure the metadata JSON file from the experiment from which we're restarting exists
        metadata_file=$EXPERIMENTS/$RESTART_FROM_EXP/metadata.json
        if [ ! -f $metadata_file ]; then
            echo "Error: metadata.json does not exist in the requested restart experiment $EXPERIMENTS/$RESTART_FROM_EXP"
            exit
        fi

        # Create the new restart UPF
        upf_new="upf-restart.txt"
        python $CANDLE/Supervisor/templates/scripts/restart.py $metadata_file > $upf_new

        # If the new UPF is empty, then there's nothing to do, so quit
        if [ -s $upf_new ]; then # if it's NOT empty...
            export WORKFLOW_SETTINGS_FILE="$(pwd)/$upf_new"
        else
            echo "Error: Job is complete; nothing to do"
            rm -f $upf_new
            exit
        fi

    fi

# If doing the mlrMBO workflow...
elif [ "x$WORKFLOW_TYPE" == "xmlrMBO" ]; then

    export R_FILE="mlrMBO-mbo.R"
    #export SH_TIMEOUT=${SH_TIMEOUT:-}
    #export IGNORE_ERRORS=${IGNORE_ERRORS:-0}

fi

# Write the dictionary of the metadata in JSON format
tmp="$(output_json_format "${params1[@]}")$(output_json_format "${params2[@]}")$(output_json_format "${params3[@]}")"
echo "{${tmp:0:${#tmp}-2}}" > metadata.json

# If we want to run the wrapper using CANDLE...
if [ "${USE_CANDLE:-1}" -eq 1 ]; then
    "$CANDLE/Supervisor/workflows/$WORKFLOW_TYPE/swift/workflow.sh" "$SITE" -a      "$CANDLE/Supervisor/workflows/common/sh/cfg-sys-$SITE.sh" "$WORKFLOW_SETTINGS_FILE" "$MODEL_NAME"
    # if [ "x$WORKFLOW_TYPE" == "xupf" ]; then
    #     #$EMEWS_PROJECT_ROOT/swift/workflow.sh                           $SITE  -a       $CFG_SYS                                                  $THIS/upf-1.txt
    #     "$CANDLE/Supervisor/workflows/$WORKFLOW_TYPE/swift/workflow.sh" "$SITE" -a      "$CANDLE/Supervisor/workflows/common/sh/cfg-sys-$SITE.sh" "$WORKFLOW_SETTINGS_FILE"
    # elif [ "x$WORKFLOW_TYPE" == "xmlrMBO" ]; then
    #     #$EMEWS_PROJECT_ROOT/swift/workflow.sh                           $SITE  $RUN_DIR $CFG_SYS                                                 $CFG_PRM                   $MODEL_NAME
    #     "$CANDLE/Supervisor/workflows/$WORKFLOW_TYPE/swift/workflow.sh" "$SITE" -a      "$CANDLE/Supervisor/workflows/common/sh/cfg-sys-$SITE.sh" "$WORKFLOW_SETTINGS_FILE" "$MODEL_NAME"
    # fi
# ...otherwise, run the wrapper alone, outside of CANDLE
else
    python "$MODEL_PYTHON_DIR/$MODEL_PYTHON_SCRIPT.py"
fi