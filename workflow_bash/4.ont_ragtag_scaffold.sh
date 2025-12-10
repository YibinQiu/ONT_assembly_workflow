#!/bin/bash

# RagTag Script for Genome Assembly Correction, Scaffolding and Patching
# Usage: bash 4.ont_ragtag_scaffold.sh -r REFERENCE -1 QUERY_1 -2 QUERY_2 -l LONG_READS -o OUTPUT_DIR [-t THREADS] [-T READ_TYPE]

# Default values
REFERENCE=""
QUERY_1=""
QUERY_2=""
LONG_READS=""
OUTPUT_DIR=""
THREADS=24
READ_TYPE="ont"

# Function to display usage instructions
usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Required options:"
    echo "  -r REFERENCE          Path to reference genome fasta file (required)"
    echo "  -1 QUERY_1            Path to first query assembly file (scaffold_1.fa) (required)"
    echo "  -2 QUERY_2            Path to second query assembly file (scaffold_2.fa) (required)"
    echo "  -l LONG_READS         Path to long-read ONT data (required)"
    echo "  -o OUTPUT_DIR         Output directory for RagTag results (required)"
    echo ""
    echo "Optional options:"
    echo "  -t THREADS            Number of threads to use (default: 24)"
    echo "  -T READ_TYPE          Read type for RagTag correct (default: ont)"
    echo "  -h                    Display this help message"
    echo ""
    echo "Example:"
    echo "  bash 4.ont_ragtag_scaffold.sh -r /path/to/reference.fasta \\"
    echo "    -1 /path/to/scaffold_1.fa -2 /path/to/scaffold_2.fa \\"
    echo "    -l /path/to/long_reads.fastq.gz -o /path/to/output \\"
    echo "    -t 24 -T ont"
    exit 1
}

# Parse command line arguments
while getopts "r:1:2:l:o:t:T:h" opt; do
    case $opt in
        r) REFERENCE="$OPTARG" ;;
        1) QUERY_1="$OPTARG" ;;
        2) QUERY_2="$OPTARG" ;;
        l) LONG_READS="$OPTARG" ;;
        o) OUTPUT_DIR="$OPTARG" ;;
        t) THREADS="$OPTARG" ;;
        T) READ_TYPE="$OPTARG" ;;
        h) usage ;;
        *) echo "Invalid option: -$OPTARG" >&2; usage ;;
    esac
done

# Validate required parameters
if [[ -z "$REFERENCE" || -z "$QUERY_1" || -z "$QUERY_2" || -z "$LONG_READS" || -z "$OUTPUT_DIR" ]]; then
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

# Validate input files
check_file_exists "$REFERENCE" "Reference genome"
check_file_exists "$QUERY_1" "Query assembly 1"
check_file_exists "$QUERY_2" "Query assembly 2"
check_file_exists "$LONG_READS" "Long-read ONT"

# Check if ragtag.py is available
if ! command -v ragtag.py &> /dev/null; then
    echo "Error: ragtag.py not found. Please ensure RagTag is installed and in your PATH"
    echo "You can install RagTag using: conda install -c bioconda ragtag"
    exit 1
fi

# Create output directory
mkdir -p "$OUTPUT_DIR"
if [[ $? -ne 0 ]]; then
    echo "Error: Failed to create output directory: $OUTPUT_DIR"
    exit 1
fi

echo "======================================================"
echo "RagTag Assembly Pipeline Started"
echo "Time: $(date +"%Y-%m-%d %T")"
echo "Reference: $REFERENCE"
echo "Query 1: $QUERY_1"
echo "Query 2: $QUERY_2"
echo "Long Reads: $LONG_READS"
echo "Read Type: $READ_TYPE"
echo "Threads: $THREADS"
echo "Output Directory: $OUTPUT_DIR"
echo "======================================================"

# Change to output directory
cd "$OUTPUT_DIR" || {
    echo "Error: Cannot change to output directory: $OUTPUT_DIR"
    exit 1
}

# Function to process a single query assembly
process_query() {
    local query_num=$1
    local query_file=$2
    
    echo "Processing Query $query_num"
    
    # Create directories for this query
    local correct_dir="${OUTPUT_DIR}/correct_${query_num}"
    local scaffold_dir="${OUTPUT_DIR}/scaffold_${query_num}"
    local patch_dir="${OUTPUT_DIR}/patch_${query_num}"
    
    mkdir -p "$correct_dir" "$scaffold_dir" "$patch_dir"
    
    # Step 1: Correct
    echo "Step 1: Correcting Query $query_num"
    echo "Executing: ragtag.py correct \"$REFERENCE\" \"$query_file\" -o \"$correct_dir\" -t $THREADS -R \"$LONG_READS\" -T $READ_TYPE"
    
    ragtag.py correct "$REFERENCE" "$query_file" -o "$correct_dir" -t "$THREADS" -R "$LONG_READS" -T "$READ_TYPE"
    
    if [[ $? -ne 0 ]]; then
        echo "Error: RagTag correct failed for Query $query_num"
        return 1
    fi
    
    # Check if corrected file exists
    local corrected_file="$correct_dir/ragtag.correct.fasta"
    if [[ ! -f "$corrected_file" ]]; then
        echo "Error: Corrected file not found: $corrected_file"
        return 1
    fi
    
    # Step 2: Scaffold
    echo "Step 2: Scaffolding Query $query_num"
    echo "Executing: ragtag.py scaffold \"$REFERENCE\" \"$corrected_file\" -o \"$scaffold_dir\" -t $THREADS"
    
    ragtag.py scaffold "$REFERENCE" "$corrected_file" -o "$scaffold_dir" -t "$THREADS"
    
    if [[ $? -ne 0 ]]; then
        echo "Error: RagTag scaffold failed for Query $query_num"
        return 1
    fi
    
    # Check if scaffold file exists
    local scaffold_file="$scaffold_dir/ragtag.scaffold.fasta"
    if [[ ! -f "$scaffold_file" ]]; then
        echo "Error: Scaffold file not found: $scaffold_file"
        return 1
    fi
    
    # Step 3: Patch
    echo "Step 3: Patching Query $query_num"
    echo "Executing: ragtag.py patch \"$scaffold_file\" \"$REFERENCE\" -o \"$patch_dir\" -t $THREADS"
    
    ragtag.py patch "$scaffold_file" "$REFERENCE" -o "$patch_dir" -t "$THREADS"
    
    if [[ $? -ne 0 ]]; then
        echo "Error: RagTag patch failed for Query $query_num"
        return 1
    fi
    
    # Check if patched file exists
    local patched_file="$patch_dir/ragtag.patch.fasta"
    if [[ ! -f "$patched_file" ]]; then
        echo "Warning: Patched file not found: $patched_file"
    else
        echo "Successfully processed Query $query_num"
        echo "  Corrected file: $corrected_file"
        echo "  Scaffold file: $scaffold_file"
        echo "  Patched file: $patched_file"
    fi
    
    return 0
}

# Process both query assemblies
echo "Processing both query assemblies..."
echo "======================================================"

# Process Query 1
echo "Starting processing of Query 1..."
process_query "1" "$QUERY_1"
QUERY_1_EXIT_CODE=$?

if [[ $QUERY_1_EXIT_CODE -eq 0 ]]; then
    echo "Query 1 processing completed successfully"
else
    echo "Query 1 processing failed with exit code: $QUERY_1_EXIT_CODE"
fi

echo "======================================================"

# Process Query 2
echo "Starting processing of Query 2..."
process_query "2" "$QUERY_2"
QUERY_2_EXIT_CODE=$?

if [[ $QUERY_2_EXIT_CODE -eq 0 ]]; then
    echo "Query 2 processing completed successfully"
else
    echo "Query 2 processing failed with exit code: $QUERY_2_EXIT_CODE"
fi

echo "======================================================"
echo "RagTag Assembly Pipeline Completed"
echo "Time: $(date +"%Y-%m-%d %T")"
echo "Output Directory: $OUTPUT_DIR"
echo "Query 1 exit code: $QUERY_1_EXIT_CODE"
echo "Query 2 exit code: $QUERY_2_EXIT_CODE"
echo "======================================================"

# Determine overall exit code
if [[ $QUERY_1_EXIT_CODE -eq 0 && $QUERY_2_EXIT_CODE -eq 0 ]]; then
    echo "Success: Both query assemblies processed successfully"
    exit 0
else
    echo "Warning: One or both query assemblies failed"
    exit 1
fi
