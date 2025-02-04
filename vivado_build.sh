#!/bin/bash

# Exit on any error
set -e


source /tools/Xilinx/Vivado/2024.2/settings64.sh

# Check if Vivado is in PATH
if ! command -v vivado &> /dev/null; then
    echo "Error: Vivado is not found in PATH"
    echo "Please source Vivado settings first:"
    echo "source /tools/Xilinx/Vivado/2023.2/settings64.sh  # Adjust path as needed"
    exit 1
fi

# Directory containing this script
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# Create vivado logs directory if it doesn't exist
mkdir -p "${SCRIPT_DIR}/vivado/logs"

# Set Vivado log file locations
export XILINX_JOURNAL_FILE="${SCRIPT_DIR}/vivado/logs/vivado.jou"
export XILINX_LOG_FILE="${SCRIPT_DIR}/vivado/logs/vivado.log"

# Generate the TCL script if it doesn't exist or if libraries.yml is newer
if [ ! -f "${SCRIPT_DIR}/vivado_build.tcl" ] || [ "${SCRIPT_DIR}/libraries.yml" -nt "${SCRIPT_DIR}/vivado_build.tcl" ]; then
    echo "Generating Vivado TCL script..."
    "${SCRIPT_DIR}/generate_vivado_tcl.sh"
fi

# Common Vivado options for quieter output
VIVADO_OPTS="-nojournal -nolog -notrace"

# Create the project and optionally build
if [ "$1" == "build" ]; then
    echo "Creating project and running implementation..."
    vivado -mode batch $VIVADO_OPTS -source "${SCRIPT_DIR}/vivado_build.tcl" -tclargs "build"
elif [ "$1" == "gui" ]; then
    echo "Opening project in Vivado GUI..."
    vivado $VIVADO_OPTS -source "${SCRIPT_DIR}/vivado_build.tcl"
else
    echo "Creating project only..."
    vivado -mode batch $VIVADO_OPTS -source "${SCRIPT_DIR}/vivado_build.tcl"
fi