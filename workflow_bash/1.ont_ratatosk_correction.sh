#!/bin/bash

# ONT data correction script (based on Ratatosk)
# Usage: bash 1.ont_ratatosk_correction -w WORK_DIR -l ONT_FILE -s WGS_FILE1,WGS_FILE2 -t ONT_TYPE -o OUTPUT_DIR [-n SAMPLE_NAME]

# Default values
WORK_DIR=""
ONT_FILE=""
WGS_FILES=""
ONT_TYPE="R10"  # Default is R10
OUTPUT_DIR=""
SAMPLE_NAME=""
MAX_LR_BQ=90

# Function to display usage instructions
usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Required options:"
    echo "  -w WORK_DIR      Working directory containing Ratatosk.nf (required)"
    echo "  -l ONT_FILE      Path to ONT (long-read) sequencing data file (required)"
    echo "  -s WGS_FILES     Paths to paired-end WGS (short-read) files, comma-separated (required, exactly 2 files)"
    echo "  -o OUTPUT_DIR    Output directory for results (required)"
    echo ""
    echo "Optional options:"
    echo "  -t ONT_TYPE      ONT sequencing type (R9 or R10, default: R10)"
    echo "  -n SAMPLE_NAME   Sample name (optional, inferred from filename if not specified)"
    echo "  -h               Display this help message"
    echo ""
    echo "Example:"
    echo "  bash 1.ont_ratatosk_correction -w /path/to/Ratatosk_nf \\"
    echo "    -l /path/to/ont_data/SAMPLE.fq.gz \\"
    echo "    -s /path/to/wgs_data/SAMPLE_1.fq.gz,/path/to/wgs_data/SAMPLE_2.fq.gz \\"
    echo "    -t R10 -o /path/to/output -n SAMPLE"
    exit 1
}

# Parse command line arguments
while getopts "w:l:s:t:o:n:h" opt; do
    case $opt in
        w) WORK_DIR="$OPTARG" ;;
        l) ONT_FILE="$OPTARG" ;;
        s) WGS_FILES="$OPTARG" ;;
        t) ONT_TYPE="$OPTARG" ;;
        o) OUTPUT_DIR="$OPTARG" ;;
        n) SAMPLE_NAME="$OPTARG" ;;
        h) usage ;;
        *) echo "Invalid option: -$OPTARG" >&2; usage ;;
    esac
done

# Validate required parameters
if [[ -z "$WORK_DIR" || -z "$ONT_FILE" || -z "$WGS_FILES" || -z "$OUTPUT_DIR" ]]; then
    echo "Error: Missing required parameters!"
    usage
fi

# Validate ONT_TYPE parameter
if [[ "$ONT_TYPE" != "R9" && "$ONT_TYPE" != "R10" ]]; then
    echo "Error: ONT_TYPE must be either R9 or R10"
    usage
fi

# Set max_lr_bq based on ONT type
if [[ "$ONT_TYPE" == "R9" ]]; then
    MAX_LR_BQ=40
elif [[ "$ONT_TYPE" == "R10" ]]; then
    MAX_LR_BQ=90
fi

# If sample name not specified, infer from ONT file
if [[ -z "$SAMPLE_NAME" ]]; then
    # Extract basename from file path
    ONT_BASENAME=$(basename "$ONT_FILE")
    SAMPLE_NAME="${ONT_BASENAME%%.*}"
    echo "Note: Sample name not specified, using inferred name: $SAMPLE_NAME"
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

# Validate ONT file
check_file_exists "$ONT_FILE" "ONT"

# Validate WGS files - must be exactly two comma-separated files
IFS=',' read -ra WGS_FILES_ARRAY <<< "$WGS_FILES"
if [[ ${#WGS_FILES_ARRAY[@]} -ne 2 ]]; then
    echo "Error: Exactly two comma-separated WGS files required. Found: ${#WGS_FILES_ARRAY[@]}"
    echo "Usage: -s file1.fq.gz,file2.fq.gz"
    exit 1
fi

# Check each WGS file
for wgs_file in "${WGS_FILES_ARRAY[@]}"; do
    check_file_exists "$wgs_file" "WGS"
done

# Validate work directory and Ratatosk.nf
if [[ ! -d "$WORK_DIR" ]]; then
    echo "Error: Working directory does not exist: $WORK_DIR"
    exit 1
fi

if [[ ! -f "$WORK_DIR/Ratatosk.nf" ]]; then
    echo "Error: Ratatosk.nf file not found in working directory: $WORK_DIR"
    exit 1
fi

# Create output directory
mkdir -p "$OUTPUT_DIR/$SAMPLE_NAME"
if [[ $? -ne 0 ]]; then
    echo "Error: Failed to create output directory: $OUTPUT_DIR/$SAMPLE_NAME"
    exit 1
fi

echo "======================================================"
echo "ONT Data Correction Started"
echo "Time: $(date +"%Y-%m-%d %T")"
echo "Sample: $SAMPLE_NAME"
echo "ONT Type: $ONT_TYPE (max_lr_bq: $MAX_LR_BQ)"
echo "ONT File: $ONT_FILE"
echo "WGS Files: ${WGS_FILES_ARRAY[0]}, ${WGS_FILES_ARRAY[1]}"
echo "Working Directory: $WORK_DIR"
echo "Output Directory: $OUTPUT_DIR/$SAMPLE_NAME"
echo "======================================================"

# Prepare FASTQ file
FASTQ_FILE="$OUTPUT_DIR/$SAMPLE_NAME/${SAMPLE_NAME}.fastq"

if [[ ! -f "$FASTQ_FILE" ]]; then
    echo "Generating FASTQ file..."
    
    # Create temporary files
    TMP_FILE1="$OUTPUT_DIR/$SAMPLE_NAME/${SAMPLE_NAME}.tmp1"
    TMP_FILE2="$OUTPUT_DIR/$SAMPLE_NAME/${SAMPLE_NAME}.tmp2"
    
    # Process first WGS file
    echo "Processing first WGS file: ${WGS_FILES_ARRAY[0]}"
    if [[ "${WGS_FILES_ARRAY[0]}" == *.gz ]]; then
        zcat "${WGS_FILES_ARRAY[0]}" | awk '{LID=(NR-1)%4; if (LID==0) {print substr($0, 1, length($0)-2)} else {print $0}}' > "$TMP_FILE1" &
    else
        cat "${WGS_FILES_ARRAY[0]}" | awk '{LID=(NR-1)%4; if (LID==0) {print substr($0, 1, length($0)-2)} else {print $0}}' > "$TMP_FILE1" &
    fi
    PID1=$!
    
    # Process second WGS file
    echo "Processing second WGS file: ${WGS_FILES_ARRAY[1]}"
    if [[ "${WGS_FILES_ARRAY[1]}" == *.gz ]]; then
        zcat "${WGS_FILES_ARRAY[1]}" | awk '{LID=(NR-1)%4; if (LID==0) {print substr($0, 1, length($0)-2)} else {print $0}}' > "$TMP_FILE2" &
    else
        cat "${WGS_FILES_ARRAY[1]}" | awk '{LID=(NR-1)%4; if (LID==0) {print substr($0, 1, length($0)-2)} else {print $0}}' > "$TMP_FILE2" &
    fi
    PID2=$!
    
    # Wait for both processes to complete
    wait $PID1 $PID2
    
    # Merge the files
    echo "Mixing temporary files..."
    cat "$TMP_FILE1" "$TMP_FILE2" > "$FASTQ_FILE"
    
    # Clean up temporary files
    rm -f "$TMP_FILE1" "$TMP_FILE2"
    
    echo "FASTQ file generated: $FASTQ_FILE"
else
    echo "FASTQ file already exists, skipping generation step"
fi

# Check FASTQ file size
FASTQ_SIZE=$(stat -c%s "$FASTQ_FILE" 2>/dev/null || stat -f%z "$FASTQ_FILE" 2>/dev/null)
if [[ $FASTQ_SIZE -eq 0 ]]; then
    echo "Error: Generated FASTQ file is empty"
    exit 1
fi

# Run Ratatosk
echo "Running Ratatosk..."
cd "$WORK_DIR" || {
    echo "Error: Cannot change to working directory: $WORK_DIR"
    exit 1
}

# Check if nextflow is available
if ! command -v nextflow &> /dev/null; then
    echo "Error: nextflow not found. Please ensure it is installed and in your PATH"
    exit 1
fi

# Run Ratatosk pipeline
echo "Executing command:"
echo "nextflow run -profile cluster Ratatosk.nf \\"
echo "  --in_lr_fq \"$ONT_FILE\" \\"
echo "  --in_sr_fq \"$FASTQ_FILE\" \\"
echo "  --out_dir \"$OUTPUT_DIR/$SAMPLE_NAME/\" \\"
echo "  --max_lr_bq $MAX_LR_BQ"

nextflow run -profile cluster Ratatosk.nf \
    --in_lr_fq "$ONT_FILE" \
    --in_sr_fq "$FASTQ_FILE" \
    --out_dir "$OUTPUT_DIR/$SAMPLE_NAME/" \
    --max_lr_bq "$MAX_LR_BQ"

NEXTFLOW_EXIT_CODE=$?

echo "======================================================"
echo "ONT Data Correction Completed"
echo "Time: $(date +"%Y-%m-%d %T")"
echo "Sample: $SAMPLE_NAME"
echo "Exit Code: $NEXTFLOW_EXIT_CODE"
echo "======================================================"

# Return result based on exit code
if [[ $NEXTFLOW_EXIT_CODE -eq 0 ]]; then
    echo "Success: Ratatosk pipeline completed successfully"
    exit 0
else
    echo "Error: Ratatosk pipeline failed with exit code: $NEXTFLOW_EXIT_CODE"
    exit $NEXTFLOW_EXIT_CODE
fi
