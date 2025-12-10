#!/bin/bash

# Flye Assembly Script for ONT Data
# Usage: bash 2.ont_flye_assembly.sh -i CORRECTED_ONT_FILE -o OUTPUT_DIR [-t THREADS] [-g GENOME_SIZE]

# Default values
CORRECTED_ONT_FILE=""
OUTPUT_DIR=""
THREADS=64
GENOME_SIZE="2.5g"

# Function to display usage instructions
usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Required options:"
    echo "  -i CORRECTED_ONT_FILE  Path to corrected ONT data file (lr.corrected.fastq.gz) (required)"
    echo "  -o OUTPUT_DIR          Output directory for assembly results (required)"
    echo ""
    echo "Optional options:"
    echo "  -t THREADS             Number of threads to use (default: 64)"
    echo "  -g GENOME_SIZE         Estimated genome size (default: 2.5g)"
    echo "  -h                     Display this help message"
    echo ""
    echo "Example:"
    echo "  bash 2.ont_flye_assembly.sh -i /path/to/corrected/lr.corrected.fastq.gz \\"
    echo "    -o /path/to/assembly/output -t 64 -g 2.5g"
    exit 1
}

# Parse command line arguments
while getopts "i:o:t:g:h" opt; do
    case $opt in
        i) CORRECTED_ONT_FILE="$OPTARG" ;;
        o) OUTPUT_DIR="$OPTARG" ;;
        t) THREADS="$OPTARG" ;;
        g) GENOME_SIZE="$OPTARG" ;;
        h) usage ;;
        *) echo "Invalid option: -$OPTARG" >&2; usage ;;
    esac
done

# Validate required parameters
if [[ -z "$CORRECTED_ONT_FILE" || -z "$OUTPUT_DIR" ]]; then
    echo "Error: Missing required parameters!"
    usage
fi

# Validate thread count is a positive integer
if ! [[ "$THREADS" =~ ^[0-9]+$ ]] || [[ "$THREADS" -lt 1 ]]; then
    echo "Error: Thread count must be a positive integer"
    usage
fi

# Function to check if file exists
check_file_exists() {
    local file="$1"
    local file_type="$2"
    
    if [[ ! -f "$file" ]]; then
        echo "Error: ${file_type} file does not exist: $file"
        exit 1
    fi
}

# Validate input file
check_file_exists "$CORRECTED_ONT_FILE" "Corrected ONT"

# Check if file is gzipped
if [[ "$CORRECTED_ONT_FILE" != *.gz ]]; then
    echo "Warning: Input file is not gzipped. Flye works best with compressed files."
fi

# Create output directory
mkdir -p "$OUTPUT_DIR"
if [[ $? -ne 0 ]]; then
    echo "Error: Failed to create output directory: $OUTPUT_DIR"
    exit 1
fi

echo "======================================================"
echo "Flye Assembly Started"
echo "Time: $(date +"%Y-%m-%d %T")"
echo "Input File: $CORRECTED_ONT_FILE"
echo "Genome Size: $GENOME_SIZE"
echo "Threads: $THREADS"
echo "Output Directory: $OUTPUT_DIR"
echo "======================================================"

# Check if flye is available
if ! command -v flye &> /dev/null; then
    echo "Error: flye not found. Please ensure it is installed and in your PATH"
    echo "You can install flye using: conda install -c bioconda flye"
    exit 1
fi

# Change to output directory for assembly
cd "$OUTPUT_DIR" || {
    echo "Error: Cannot change to output directory: $OUTPUT_DIR"
    exit 1
}

# Check available memory (optional but useful for users)
if command -v free &> /dev/null; then
    AVAILABLE_MEM=$(free -g | awk '/^Mem:/ {print $2}')
    REQUIRED_MEM=$((THREADS * 7500 / 1000))  # Original script used 7500MB per core
    
    if [[ $AVAILABLE_MEM -lt $REQUIRED_MEM ]]; then
        echo "Warning: Available memory ($AVAILABLE_MEM GB) may be less than recommended ($REQUIRED_MEM GB) for $THREADS threads"
    fi
fi

# Run Flye assembly
echo "Running Flye assembly..."
echo "Executing command:"
echo "flye --nano-corr \"$CORRECTED_ONT_FILE\" \\"
echo "  --genome-size $GENOME_SIZE \\"
echo "  -t $THREADS \\"
echo "  --out-dir \"$OUTPUT_DIR\""

flye --nano-corr "$CORRECTED_ONT_FILE" \
  --genome-size "$GENOME_SIZE" \
  -t "$THREADS" \
  --out-dir "$OUTPUT_DIR"

FLYE_EXIT_CODE=$?

echo "======================================================"
echo "Flye Assembly Completed"
echo "Time: $(date +"%Y-%m-%d %T")"
echo "Exit Code: $FLYE_EXIT_CODE"
echo "======================================================"

# Check assembly results
if [[ $FLYE_EXIT_CODE -eq 0 ]]; then
    echo "Success: Flye assembly completed successfully"
    
    # Check if assembly file exists
    ASSEMBLY_FILE="$OUTPUT_DIR/assembly.fasta"
    if [[ -f "$ASSEMBLY_FILE" ]]; then
        echo "Assembly file created: $ASSEMBLY_FILE"
    else
        echo "Warning: Expected assembly file not found at: $ASSEMBLY_FILE"
    fi
    
    exit 0
else
    echo "Error: Flye assembly failed with exit code: $FLYE_EXIT_CODE"
    exit $FLYE_EXIT_CODE
fi
