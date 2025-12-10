#!/bin/bash

# Lifton Script for Gene Annotation Transfer
# Usage: bash 5.lifton_annotation.sh -r REFERENCE -1 PATCHED_1 -2 PATCHED_2 -g GFF3 -P PROTEINS -T TRANSCRIPTS -o OUTPUT_DIR [-t THREADS]

# Default values
REFERENCE=""
PATCHED_1=""
PATCHED_2=""
GFF3=""
PROTEINS=""
TRANSCRIPTS=""
OUTPUT_DIR=""
THREADS=24

# Function to display usage instructions
usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Required options:"
    echo "  -r REFERENCE          Path to reference genome fasta file (required)"
    echo "  -1 PATCHED_1          Path to first patched assembly file (ragtag.patch.fasta) (required)"
    echo "  -2 PATCHED_2          Path to second patched assembly file (ragtag.patch.fasta) (required)"
    echo "  -g GFF3               Path to reference GFF3 annotation file (required)"
    echo "  -P PROTEINS           Path to reference proteins fasta file (required)"
    echo "  -T TRANSCRIPTS        Path to reference transcripts fasta file (required)"
    echo "  -o OUTPUT_DIR         Output directory for Lifton results (required)"
    echo ""
    echo "Optional options:"
    echo "  -t THREADS            Number of threads to use (default: 24)"
    echo "  -h                    Display this help message"
    echo ""
    echo "Example:"
    echo "  bash 5.lifton_annotation.sh -r /path/to/reference.fasta \\"
    echo "    -1 /path/to/patched_1.fasta -2 /path/to/patched_2.fasta \\"
    echo "    -g /path/to/annotation.gff3 -P /path/to/proteins.fa -T /path/to/transcripts.fa \\"
    echo "    -o /path/to/output -t 24"
    exit 1
}

# Parse command line arguments
while getopts "r:1:2:g:P:T:o:t:h" opt; do
    case $opt in
        r) REFERENCE="$OPTARG" ;;
        1) PATCHED_1="$OPTARG" ;;
        2) PATCHED_2="$OPTARG" ;;
        g) GFF3="$OPTARG" ;;
        P) PROTEINS="$OPTARG" ;;
        T) TRANSCRIPTS="$OPTARG" ;;
        o) OUTPUT_DIR="$OPTARG" ;;
        t) THREADS="$OPTARG" ;;
        h) usage ;;
        *) echo "Invalid option: -$OPTARG" >&2; usage ;;
    esac
done

# Validate required parameters
if [[ -z "$REFERENCE" || -z "$PATCHED_1" || -z "$PATCHED_2" || -z "$GFF3" || -z "$PROTEINS" || -z "$TRANSCRIPTS" || -z "$OUTPUT_DIR" ]]; then
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
check_file_exists "$PATCHED_1" "Patched assembly 1"
check_file_exists "$PATCHED_2" "Patched assembly 2"
check_file_exists "$GFF3" "GFF3 annotation"
check_file_exists "$PROTEINS" "Proteins fasta"
check_file_exists "$TRANSCRIPTS" "Transcripts fasta"

# Check if lifton is available
if ! command -v lifton &> /dev/null; then
    echo "Error: lifton not found. Please ensure lifton is installed and in your PATH"
    exit 1
fi

# Check if miniprot is available
if ! command -v miniprot &> /dev/null; then
    echo "Error: miniprot not found. Please ensure miniprot is installed and in your PATH"
    exit 1
fi

# Create output directory
mkdir -p "$OUTPUT_DIR"
if [[ $? -ne 0 ]]; then
    echo "Error: Failed to create output directory: $OUTPUT_DIR"
    exit 1
fi

echo "======================================================"
echo "Lifton Annotation Pipeline Started"
echo "Time: $(date +"%Y-%m-%d %T")"
echo "Reference: $REFERENCE"
echo "Patched Assembly 1: $PATCHED_1"
echo "Patched Assembly 2: $PATCHED_2"
echo "GFF3 Annotation: $GFF3"
echo "Proteins: $PROTEINS"
echo "Transcripts: $TRANSCRIPTS"
echo "Threads: $THREADS"
echo "Output Directory: $OUTPUT_DIR"
echo "======================================================"

# Function to process a single haplotype
process_haplotype() {
    local haplotype_num=$1
    local patched_file=$2
    local output_base_dir="$OUTPUT_DIR/hap_${haplotype_num}"
    
    echo "Processing Haplotype ${haplotype_num}"
    
    # Create output directories
    mkdir -p "$output_base_dir/miniprot" "$output_base_dir/liftoff"
    
    # Get GFF3 basename
    local gff_basename=$(basename "$GFF3")
    local output_gff="$output_base_dir/lifton_${haplotype_num}.gff"
    
    # Copy GFF3 file to output directory
    cp "$GFF3" "$output_base_dir/$gff_basename"
    
    # Create empty database files to avoid lifton errors
    touch "$output_base_dir/${gff_basename}_db"
    touch "$output_base_dir/miniprot/miniprot.gff3_db"
    touch "$output_base_dir/liftoff/liftoff.gff3_db"
    
    echo "Created empty database files to avoid lifton errors"
    
    # Run miniprot
    echo "Step 1: Running miniprot for haplotype ${haplotype_num}"
    local miniprot_gff="$output_base_dir/miniprot/miniprot.gff3"
    
    echo "Executing: miniprot -t $THREADS --gff-only \"$patched_file\" \"$PROTEINS\" > \"$miniprot_gff\""
    
    miniprot -t "$THREADS" --gff-only "$patched_file" "$PROTEINS" > "$miniprot_gff"
    
    if [[ $? -ne 0 ]]; then
        echo "Error: miniprot failed for haplotype ${haplotype_num}"
        return 1
    fi
    
    # Check if miniprot output file exists
    if [[ ! -f "$miniprot_gff" ]]; then
        echo "Error: miniprot output file not found: $miniprot_gff"
        return 1
    fi
    
    # Run single lifton command
    echo "Step 2: Running lifton for haplotype ${haplotype_num}"
    
    echo "Executing: lifton -t $THREADS -g \"$output_base_dir/$gff_basename\" -P \"$PROTEINS\" -T \"$TRANSCRIPTS\" -o \"$output_gff\" -M \"$miniprot_gff\" -copies \"$patched_file\" \"$REFERENCE\""
    
    lifton -t "$THREADS" -g "$output_base_dir/$gff_basename" -P "$PROTEINS" -T "$TRANSCRIPTS" -o "$output_gff" -M "$miniprot_gff" -copies "$patched_file" "$REFERENCE"
    
    if [[ $? -ne 0 ]]; then
        echo "Error: lifton failed for haplotype ${haplotype_num}"
        return 1
    fi
    
    # Check if final output file exists
    if [[ ! -f "$output_gff" ]]; then
        echo "Error: Final lifton output file not found: $output_gff"
        return 1
    fi
    
    # Check if liftoff.gff3 was generated
    local liftoff_gff="$output_base_dir/liftoff/liftoff.gff3"
    if [[ -f "$liftoff_gff" ]]; then
        echo "Liftoff GFF3 file generated: $liftoff_gff"
    else
        echo "Warning: liftoff.gff3 file was not generated"
    fi
    
    echo "Successfully processed haplotype ${haplotype_num}"
    echo "  Output GFF: $output_gff"
    echo "  Miniprot GFF: $miniprot_gff"
    echo "  Liftoff GFF: $liftoff_gff"
    
    return 0
}

# Process both haplotypes
echo "Processing both haplotypes..."
echo "======================================================"

# Process Haplotype 1
echo "Starting processing of Haplotype 1..."
process_haplotype "1" "$PATCHED_1"
HAP_1_EXIT_CODE=$?

if [[ $HAP_1_EXIT_CODE -eq 0 ]]; then
    echo "Haplotype 1 processing completed successfully"
else
    echo "Haplotype 1 processing failed with exit code: $HAP_1_EXIT_CODE"
fi

echo "======================================================"

# Process Haplotype 2
echo "Starting processing of Haplotype 2..."
process_haplotype "2" "$PATCHED_2"
HAP_2_EXIT_CODE=$?

if [[ $HAP_2_EXIT_CODE -eq 0 ]]; then
    echo "Haplotype 2 processing completed successfully"
else
    echo "Haplotype 2 processing failed with exit code: $HAP_2_EXIT_CODE"
fi

echo "======================================================"
echo "Lifton Annotation Pipeline Completed"
echo "Time: $(date +"%Y-%m-%d %T")"
echo "Output Directory: $OUTPUT_DIR"
echo "Haplotype 1 exit code: $HAP_1_EXIT_CODE"
echo "Haplotype 2 exit code: $HAP_2_EXIT_CODE"
echo "======================================================"

# Determine overall exit code
if [[ $HAP_1_EXIT_CODE -eq 0 && $HAP_2_EXIT_CODE -eq 0 ]]; then
    echo "Success: Both haplotypes processed successfully"
    exit 0
else
    echo "Warning: One or both haplotypes failed"
    exit 1
fi
