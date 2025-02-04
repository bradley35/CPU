#!/bin/bash

# Exit on any error
set -e

# Configuration files
INPUT_FILE="libraries.yml"
OUTPUT_FILE="vhdl_ls.toml"

# Check if yq is installed
if ! command -v yq &> /dev/null; then
    echo "Error: yq is required but not installed. Please install yq first."
    echo "Install with: sudo apt-get install yq   # For Ubuntu/Debian"
    echo "Or: brew install yq                     # For MacOS"
    exit 1
fi

# Check if input file exists
if [ ! -f "$INPUT_FILE" ]; then
    echo "Error: Input file $INPUT_FILE not found"
    exit 1
fi

# Create the TOML file with standard header
echo 'standard = "2008"' > "$OUTPUT_FILE"
echo '[libraries]' >> "$OUTPUT_FILE"

# Get number of libraries
NUM_LIBS=$(yq eval '.libraries | length' "$INPUT_FILE")

# Process each library
for ((i=0; i<$NUM_LIBS; i++)); do
    LIB_NAME=$(yq eval ".libraries[$i].name" "$INPUT_FILE")
    
    # Start library entry
    echo "$LIB_NAME.files = [" >> "$OUTPUT_FILE"
    
    # Get all paths for this library
    NUM_PATHS=$(yq eval ".libraries[$i].paths | length" "$INPUT_FILE")
    for ((j=0; j<$NUM_PATHS; j++)); do
        LIB_PATH=$(yq eval ".libraries[$i].paths[$j]" "$INPUT_FILE")
        
        # Remove leading ./ from path if present
        LIB_PATH=${LIB_PATH#./}
        
        # Add path to TOML
        # Add comma if not the last path
        if [ $j -lt $((NUM_PATHS-1)) ]; then
            echo "    '$LIB_PATH/*.vhd'," >> "$OUTPUT_FILE"
        else
            echo "    '$LIB_PATH/*.vhd'" >> "$OUTPUT_FILE"
        fi
    done
    
    # Close library entry
    echo "]" >> "$OUTPUT_FILE"
    
    # Add blank line between libraries for readability
    if [ $i -lt $((NUM_LIBS-1)) ]; then
        echo "" >> "$OUTPUT_FILE"
    fi
done

echo "Generated $OUTPUT_FILE successfully!"