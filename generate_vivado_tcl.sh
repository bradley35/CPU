#!/bin/bash

# Exit on any error
set -e

# Configuration files
INPUT_FILE="libraries.yml"
OUTPUT_FILE="vivado_build.tcl"

echo "Starting Vivado TCL script generation..."

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

echo "Reading project configuration from $INPUT_FILE..."

# Get FPGA part number from YAML, default to Arty S7-25 if not specified
FPGA_PART=$(yq '.fpga.part' "$INPUT_FILE")
if [ "$FPGA_PART" = "null" ]; then
    echo "No FPGA part specified, defaulting to Arty S7-25 (xc7s25csga324-1)"
    FPGA_PART="xc7s25csga324-1"
else
    echo "Using FPGA part: $FPGA_PART"
fi

# Get top level information for synthesis
TOP_LEVEL=$(yq '.top_level.synthesis.entity' "$INPUT_FILE")
TOP_LIB=$(yq '.top_level.synthesis.library' "$INPUT_FILE")
echo "Top level entity: $TOP_LEVEL in library: $TOP_LIB"

echo "Generating initial project setup..."

# Start generating the TCL script
cat << 'EOF_SCRIPT' > "$OUTPUT_FILE"
# Set the reference directory for source file relative paths
set root_dir [file normalize [file dirname [info script]]]

# Set project properties
set project_name "fpga_project"
set project_dir "${root_dir}/vivado"

# Enable VHDL 2008 at the global level
set_param project.enableVHDL2008 1
EOF_SCRIPT

# Add the device variable (needs separate heredoc since it contains a bash variable)
echo "set device \"$FPGA_PART\"" >> "$OUTPUT_FILE"

# Continue with the main script
cat << 'EOF_SCRIPT' >> "$OUTPUT_FILE"
# Create project directory if it doesn't exist
file mkdir $project_dir

# Create project with VHDL 2008 enabled from the start
create_project -force $project_name $project_dir -part $device
set_property target_language VHDL [current_project]

# Create filesets if they don't exist
if {[string equal [get_filesets -quiet sources_1] ""]} {
  create_fileset -srcset sources_1
}

if {[string equal [get_filesets -quiet constrs_1] ""]} {
  create_fileset -constrset constrs_1
}

EOF_SCRIPT

echo "Processing library sources..."

# Add library sources
NUM_LIBS=$(yq '.libraries | length' "$INPUT_FILE")
for ((i=0; i<$NUM_LIBS; i++)); do
    LIB_NAME=$(yq ".libraries.[$i].name" "$INPUT_FILE")
    LIB_PATH=$(yq ".libraries.[$i].path" "$INPUT_FILE")
    LIB_PATH=${LIB_PATH#./}  # Remove leading ./ if present
    
    echo "  Adding library: $LIB_NAME from path: $LIB_PATH"
    
    echo "# Add files for library $LIB_NAME" >> "$OUTPUT_FILE"
    echo "add_files -fileset sources_1 -norecurse [glob -nocomplain \${root_dir}/$LIB_PATH/*.vhd]" >> "$OUTPUT_FILE"
    echo "set_property library $LIB_NAME [get_files -of_objects [get_filesets sources_1] \${root_dir}/$LIB_PATH/*.vhd]" >> "$OUTPUT_FILE"
    # Add VHDL 2008 property for each library's files
    echo "set_property file_type {VHDL 2008} [get_files -of_objects [get_filesets sources_1] \${root_dir}/$LIB_PATH/*.vhd]" >> "$OUTPUT_FILE"
    echo "" >> "$OUTPUT_FILE"
done

echo "Setting top level configuration..."

# Add top level configuration
echo "# Set top module" >> "$OUTPUT_FILE"
echo "set_property top $TOP_LEVEL [current_fileset]" >> "$OUTPUT_FILE"
echo "set_property top_lib $TOP_LIB [current_fileset]" >> "$OUTPUT_FILE"
echo "" >> "$OUTPUT_FILE"

echo "Processing constraint files..."

# Add constraint files
NUM_CONSTRAINTS=$(yq '.fpga.constraints | length' "$INPUT_FILE")
if [ "$NUM_CONSTRAINTS" != "null" ] && [ "$NUM_CONSTRAINTS" -gt 0 ]; then
    for ((i=0; i<$NUM_CONSTRAINTS; i++)); do
        XDC_PATH=$(yq ".fpga.constraints.[$i].path" "$INPUT_FILE")
        XDC_NAME=$(yq ".fpga.constraints.[$i].name" "$INPUT_FILE")
        XDC_TARGETS=$(yq ".fpga.constraints.[$i].targets | join(\", \")" "$INPUT_FILE")
        XDC_PATH=${XDC_PATH#./}
        
        echo "  Adding constraint: $XDC_NAME ($XDC_PATH) for targets: $XDC_TARGETS"
        
        echo "# Add constraint file: $XDC_NAME" >> "$OUTPUT_FILE"
        echo "if {[file exists \${root_dir}/$XDC_PATH]} {" >> "$OUTPUT_FILE"
        echo "    add_files -fileset constrs_1 -norecurse \${root_dir}/$XDC_PATH" >> "$OUTPUT_FILE"
        echo "    set targets {}" >> "$OUTPUT_FILE"
        echo "    foreach target [split \"$XDC_TARGETS\" \",\"] {" >> "$OUTPUT_FILE"
        echo "        set target [string trim \$target]" >> "$OUTPUT_FILE"
        echo "        if {\$target eq \"synth\"} {" >> "$OUTPUT_FILE"
        echo "            lappend targets \"SYNTHESIS\"" >> "$OUTPUT_FILE"
        echo "        } elseif {\$target eq \"impl\"} {" >> "$OUTPUT_FILE"
        echo "            lappend targets \"IMPLEMENTATION\"" >> "$OUTPUT_FILE"
        echo "        }" >> "$OUTPUT_FILE"
        echo "    }" >> "$OUTPUT_FILE"
        echo "    set_property USED_IN \$targets [get_files \${root_dir}/$XDC_PATH]" >> "$OUTPUT_FILE"
        echo "} else {" >> "$OUTPUT_FILE"
        echo "    puts \"Warning: Constraint file \${root_dir}/$XDC_PATH not found\"" >> "$OUTPUT_FILE"
        echo "}" >> "$OUTPUT_FILE"
        echo "" >> "$OUTPUT_FILE"
    done
else
    echo "  No constraint files specified"
fi

echo "Adding build configuration..."

# Add the final build configuration
cat << EOF_SCRIPT >> "$OUTPUT_FILE"
# Create synthesis run
if {[string equal [get_runs -quiet synth_1] ""]} {
    create_run -name synth_1 -part \$device -flow {Vivado Synthesis 2023} -strategy "Vivado Synthesis Defaults" -constrset constrs_1
} else {
    set_property strategy "Vivado Synthesis Defaults" [get_runs synth_1]
    set_property flow "Vivado Synthesis 2023" [get_runs synth_1]
}

# Create implementation run
if {[string equal [get_runs -quiet impl_1] ""]} {
    create_run -name impl_1 -part \$device -flow {Vivado Implementation 2023} -strategy "Vivado Implementation Defaults" -constrset constrs_1 -parent_run synth_1
} else {
    set_property strategy "Vivado Implementation Defaults" [get_runs impl_1]
    set_property flow "Vivado Implementation 2023" [get_runs impl_1]
}

# Set the current impl run
current_run -implementation [get_runs impl_1]

puts "Project created successfully"

# Optionally, run synthesis and implementation
if {[string equal [lindex \$argv 0] "build"]} {
    launch_runs synth_1 -jobs 4
    wait_on_run synth_1
    
    if {[get_property PROGRESS [get_runs synth_1]] == "100%"} {
        puts "Synthesis completed successfully"
        
        launch_runs impl_1 -to_step write_bitstream -jobs 4
        wait_on_run impl_1
        
        if {[get_property PROGRESS [get_runs impl_1]] == "100%"} {
            puts "Implementation and bitstream generation completed successfully"
            file mkdir \${root_dir}/output
            file copy -force \${project_dir}/\${project_name}.runs/impl_1/$TOP_LEVEL.bit \${root_dir}/output/
            puts "Bitstream copied to output directory"
        } else {
            puts "Implementation failed"
            exit 1
        }
    } else {
        puts "Synthesis failed"
        exit 1
    }
}
EOF_SCRIPT

echo "Successfully generated $OUTPUT_FILE"