#!/bin/bash

# Exit on any error
set -e

if [ "$(uname)" != "Darwin" ]; then
   export CC=gcc-12
fi

# Check if yq is installed (for YAML parsing)
if ! command -v yq &> /dev/null; then
    echo "Error: yq is required but not installed. Please install yq first."
    echo "Install with: sudo apt-get install yq   # For Ubuntu/Debian"
    echo "Or: brew install yq                     # For MacOS"
    exit 1
fi

# Configuration file
CONFIG_FILE="libraries.yml"

if [ ! -f "$CONFIG_FILE" ]; then
    echo "Error: Configuration file $CONFIG_FILE not found"
    exit 1
fi

# Clean up previous builds but preserve waves
rm -rf lib/*.cf
rm -f *.cf

# Create library directories
mkdir -p lib/waves

# Map libraries to their directories
ghdl --clean || true
ghdl --remove || true

# Function to analyze a library path
analyze_library_path() {
    local lib_name=$1
    local lib_path=$2
    
    echo "  Analyzing path: $lib_path"
    
    # Check if source directory exists and contains files
    if [ ! -d "$lib_path" ] || [ -z "$(ls -A $lib_path/*.vhd 2>/dev/null)" ]; then
        echo "  Warning: Source directory $lib_path empty or missing"
        return 0  # Continue with other paths
    fi
    
    # Analyze sources
    ghdl -a --std=08 -fsynopsys --work=$lib_name --workdir="lib" -P./lib $lib_path/*.vhd
}

# Get number of libraries
NUM_LIBS=$(yq eval '.libraries | length' "$CONFIG_FILE")

# Process each library in order (assumes dependencies are listed in correct order)
for ((i=0; i<$NUM_LIBS; i++)); do
    LIB_NAME=$(yq eval ".libraries[$i].name" "$CONFIG_FILE")
    echo "Analyzing library: $LIB_NAME"
    
    # Process each path for the library
    NUM_PATHS=$(yq eval ".libraries[$i].paths | length" "$CONFIG_FILE")
    for ((j=0; j<$NUM_PATHS; j++)); do
        LIB_PATH=$(yq eval ".libraries[$i].paths[$j]" "$CONFIG_FILE")
        analyze_library_path "$LIB_NAME" "$LIB_PATH"
    done
done

# Get top level information for simulation
TOP_LEVEL=$(yq eval '.top_level.simulation.entity' "$CONFIG_FILE")
TOP_LIB=$(yq eval '.top_level.simulation.library' "$CONFIG_FILE")

# Elaborate the design
echo "Elaborating design..."
ghdl -e -fsynopsys --std=08 --work=$TOP_LIB --workdir="lib" -o "lib/$TOP_LEVEL" -P./lib $TOP_LEVEL

# Create timestamp for unique VCD file
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
WAVE_FILE="./lib/waves/wave_${TIMESTAMP}.ghw"

# Run the simulation
echo "Running simulation..."
cd lib
ghdl -r -fsynopsys --std=08 --work=$TOP_LIB $TOP_LEVEL --wave="../${WAVE_FILE}"
cd ..

echo "Simulation complete! Wave file created at ${WAVE_FILE}"

# Prompt to open waveform
read -p "Would you like to open the waveform in GTKWave? (y/n) " -n 1 -r
echo    # Move to a new line
if [[ $REPLY =~ ^[Yy]$ ]]; then
    if command -v gtkwave &> /dev/null; then
        if [ "$(uname)" != "Darwin" ]; then
            export GDK_BACKEND=x11
        fi
        gtkwave "${WAVE_FILE}"
    else
        echo "Error: GTKWave is not installed or not in PATH"
        exit 1
    fi
fi