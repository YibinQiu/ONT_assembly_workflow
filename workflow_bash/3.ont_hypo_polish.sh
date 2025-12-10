#!/bin/bash

# Hypo Assembler Script for ONT Data
# Usage: 3.ont_hypo_polish.sh -d DRAFT_ASSEMBLY -l LONG_READS -1 SHORT_READS_1 -2 SHORT_READS_2 -o OUTPUT_DIR [-t THREADS] [-g GENOME_SIZE] [-k KMER_LENGTH] [-H HYPO_ASSEMBLER_DIR] [-C LONG_READ_COVERAGE] [-c SHORT_READ_COVERAGE] [-p HYPO_BATCH_NUMBER]

# Default values
DRAFT_ASSEMBLY=""
LONG_READS=""
SHORT_READS_1=""
SHORT_READS_2=""
OUTPUT_DIR=""
THREADS=24
GENOME_SIZE="2.5G"
KMER_LENGTH=17
HYPO_ASSEMBLER_DIR=""
SORT_THREADS=20
SORT_MEM="7G"
KMCMEM=12
LONG_READ_COVERAGE=25
SHORT_READ_COVERAGE=25
HYPO_BATCH_NUMBER=20

# Function to display usage instructions
usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Required options:"
    echo "  -d DRAFT_ASSEMBLY      Path to draft assembly fasta file (required)"
    echo "  -l LONG_READS          Path to long-read ONT data (required)"
    echo "  -1 SHORT_READS_1       Path to first short-read WGS file (required)"
    echo "  -2 SHORT_READS_2       Path to second short-read WGS file (required)"
    echo "  -o OUTPUT_DIR          Output directory for assembly results (required)"
    echo "  -H HYPO_ASSEMBLER_DIR  Path to hypo-assembler installation directory (required)"
    echo ""
    echo "Optional options:"
    echo "  -t THREADS             Number of threads to use (default: 24)"
    echo "  -g GENOME_SIZE         Estimated genome size (default: 2.5G)"
    echo "  -k KMER_LENGTH         Kmer length for solid kmer detection (default: 17)"
    echo "  -C LONG_READ_COVERAGE  Estimated long-read coverage depth (default: 25)"
    echo "  -c SHORT_READ_COVERAGE Estimated short-read coverage depth (default: 25)"
    echo "  -p HYPO_BATCH_NUMBER   Number of batches for hypo processing (default: 20)"
    echo "  -h                     Display this help message"
    echo ""
    echo "Example:"
    echo "  bash 3.ont_hypo_polish.sh -d /path/to/draft.fasta \\"
    echo "    -l /path/to/long_reads.fastq.gz -1 /path/to/short_1.fq.gz -2 /path/to/short_2.fq.gz \\"
    echo "    -o /path/to/output -t 24 -g 2.5G -k 17 -H /path/to/hypo-assembler \\"
    echo "    -C 25 -c 25 -p 20"
    exit 1
}

# Parse command line arguments
while getopts "d:l:1:2:o:t:g:k:H:C:c:p:h" opt; do
    case $opt in
        d) DRAFT_ASSEMBLY="$OPTARG" ;;
        l) LONG_READS="$OPTARG" ;;
        1) SHORT_READS_1="$OPTARG" ;;
        2) SHORT_READS_2="$OPTARG" ;;
        o) OUTPUT_DIR="$OPTARG" ;;
        t) THREADS="$OPTARG" ;;
        g) GENOME_SIZE="$OPTARG" ;;
        k) KMER_LENGTH="$OPTARG" ;;
        H) HYPO_ASSEMBLER_DIR="$OPTARG" ;;
        C) LONG_READ_COVERAGE="$OPTARG" ;;
        c) SHORT_READ_COVERAGE="$OPTARG" ;;
        p) HYPO_BATCH_NUMBER="$OPTARG" ;;
        h) usage ;;
        *) echo "Invalid option: -$OPTARG" >&2; usage ;;
    esac
done

# Validate required parameters
if [[ -z "$DRAFT_ASSEMBLY" || -z "$LONG_READS" || -z "$SHORT_READS_1" || -z "$SHORT_READS_2" || -z "$OUTPUT_DIR" || -z "$HYPO_ASSEMBLER_DIR" ]]; then
    echo "Error: Missing required parameters!"
    usage
fi

# Validate thread count is a positive integer
if ! [[ "$THREADS" =~ ^[0-9]+$ ]] || [[ "$THREADS" -lt 1 ]]; then
    echo "Error: Thread count must be a positive integer"
    usage
fi

# Validate kmer length is a positive integer
if ! [[ "$KMER_LENGTH" =~ ^[0-9]+$ ]] || [[ "$KMER_LENGTH" -lt 1 ]]; then
    echo "Error: Kmer length must be a positive integer"
    usage
fi

# Validate coverage parameters are positive integers
if ! [[ "$LONG_READ_COVERAGE" =~ ^[0-9]+$ ]] || [[ "$LONG_READ_COVERAGE" -lt 1 ]]; then
    echo "Error: Long-read coverage must be a positive integer"
    usage
fi

if ! [[ "$SHORT_READ_COVERAGE" =~ ^[0-9]+$ ]] || [[ "$SHORT_READ_COVERAGE" -lt 1 ]]; then
    echo "Error: Short-read coverage must be a positive integer"
    usage
fi

# Validate hypo batch number is a positive integer
if ! [[ "$HYPO_BATCH_NUMBER" =~ ^[0-9]+$ ]] || [[ "$HYPO_BATCH_NUMBER" -lt 1 ]]; then
    echo "Error: Hypo batch number must be a positive integer"
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
check_file_exists "$DRAFT_ASSEMBLY" "Draft assembly"
check_file_exists "$LONG_READS" "Long-read ONT"
check_file_exists "$SHORT_READS_1" "Short-read WGS 1"
check_file_exists "$SHORT_READS_2" "Short-read WGS 2"

# Validate hypo-assembler directory
if [[ ! -d "$HYPO_ASSEMBLER_DIR" ]]; then
    echo "Error: Hypo-assembler directory does not exist: $HYPO_ASSEMBLER_DIR"
    exit 1
fi

# Check for required tools
if ! command -v minimap2 &> /dev/null; then
    echo "Error: minimap2 not found. Please ensure it is installed and in your PATH"
    echo "You can install minimap2 using: conda install -c bioconda minimap2"
    exit 1
fi

if ! command -v samtools &> /dev/null; then
    echo "Error: samtools not found. Please ensure it is installed and in your PATH"
    echo "You can install samtools using: conda install -c bioconda samtools"
    exit 1
fi

if ! command -v hypo &> /dev/null; then
    echo "Error: hypo not found. Please ensure it is installed and in your PATH"
    echo "Note: hypo is part of hypo-assembler package"
    exit 1
fi

# Check for hypo-assembler scripts
if [[ ! -f "$HYPO_ASSEMBLER_DIR/run_all/scan_misjoin.py" ]]; then
    echo "Error: scan_misjoin.py not found in $HYPO_ASSEMBLER_DIR/run_all/"
    exit 1
fi

if [[ ! -f "$HYPO_ASSEMBLER_DIR/run_all/run_overlap.sh" ]]; then
    echo "Error: run_overlap.sh not found in $HYPO_ASSEMBLER_DIR/run_all/"
    exit 1
fi

if [[ ! -f "$HYPO_ASSEMBLER_DIR/run_all/run_scaffold.sh" ]]; then
    echo "Error: run_scaffold.sh not found in $HYPO_ASSEMBLER_DIR/run_all/"
    exit 1
fi

# Create output directory
mkdir -p "$OUTPUT_DIR"
if [[ $? -ne 0 ]]; then
    echo "Error: Failed to create output directory: $OUTPUT_DIR"
    exit 1
fi

# Add hypo-assembler scripts to PATH
export PATH="$HYPO_ASSEMBLER_DIR/run_all:${PATH}"

# Create temp directory
TEMP_DIR="$OUTPUT_DIR/tempdir"
mkdir -p "$TEMP_DIR"

echo "======================================================"
echo "Hypo Assembler Started"
echo "Time: $(date +"%Y-%m-%d %T")"
echo "Draft Assembly: $DRAFT_ASSEMBLY"
echo "Long Reads: $LONG_READS"
echo "Short Reads 1: $SHORT_READS_1"
echo "Short Reads 2: $SHORT_READS_2"
echo "Genome Size: $GENOME_SIZE"
echo "Threads: $THREADS"
echo "Kmer Length: $KMER_LENGTH"
echo "Long-read Coverage: $LONG_READ_COVERAGE"
echo "Short-read Coverage: $SHORT_READ_COVERAGE"
echo "Hypo Batch Number: $HYPO_BATCH_NUMBER"
echo "Output Directory: $OUTPUT_DIR"
echo "Hypo-assembler Directory: $HYPO_ASSEMBLER_DIR"
echo "======================================================"

# Change to output directory
cd "$OUTPUT_DIR" || {
    echo "Error: Cannot change to output directory: $OUTPUT_DIR"
    exit 1
}

# STEP 0: Create shorts.txt file
echo "Creating shorts.txt file..."
echo "$SHORT_READS_1" > "$TEMP_DIR/shorts.txt"
echo "$SHORT_READS_2" >> "$TEMP_DIR/shorts.txt"

# STEP 1: Mapping long reads to draft
echo "STEP 1: Mapping long reads to draft"
LONG_BAM="$TEMP_DIR/long_align.bam"
if [[ ! -f "$LONG_BAM" ]]; then
    echo "Mapping long reads to draft"
    minimap2 -ax map-ont -t "$THREADS" "$DRAFT_ASSEMBLY" "$LONG_READS" | \
        samtools view -bS | \
        samtools sort -@ "$SORT_THREADS" -m "$SORT_MEM" -o "$LONG_BAM"
    
    if [[ $? -ne 0 ]]; then
        echo "Error: Failed to map long reads to draft assembly"
        exit 1
    fi
else
    echo "Long read alignment BAM file already exists, skipping mapping"
fi

# STEP 2: Getting solid kmers
echo "STEP 2: Getting solid kmers"
SUK_BV="$TEMP_DIR/SUK_k${KMER_LENGTH}.bv"
if [[ ! -f "$SUK_BV" ]]; then
    echo "Getting solid kmers"
    suk -k "$KMER_LENGTH" -i "@$TEMP_DIR/shorts.txt" -t "$THREADS" -m "$KMCMEM" -e -w "$TEMP_DIR/suk_kmc" -o "$TEMP_DIR/SUK" 2>&1 | tee "$TEMP_DIR/suk.log"
    
    if [[ $? -ne 0 ]]; then
        echo "Error: Failed to get solid kmers"
        exit 1
    fi
else
    echo "Solid kmer file already exists, skipping kmer detection"
fi

# STEP 3: Scanning misjoin
echo "STEP 3: Scanning misjoin"
MISJOIN_FA="$TEMP_DIR/misjoin.fa"
if [[ ! -f "$MISJOIN_FA" ]]; then
    echo "Scanning misjoin"
    python "$HYPO_ASSEMBLER_DIR/run_all/scan_misjoin.py" "$DRAFT_ASSEMBLY" "$LONG_BAM" "$MISJOIN_FA" 2>&1 | tee -a "$TEMP_DIR/misjoin.log"
    
    if [[ $? -ne 0 ]]; then
        echo "Error: Failed to scan misjoin"
        exit 1
    fi
else
    echo "Misjoin file already exists, skipping misjoin scanning"
fi

# STEP 4: Finding overlaps
echo "STEP 4: Finding overlaps"
OVERLAP_FA="$TEMP_DIR/overlap.fa"
if [[ ! -f "$OVERLAP_FA" ]]; then
    echo "Finding overlaps"
    sh "$HYPO_ASSEMBLER_DIR/run_all/run_overlap.sh" -k "$SUK_BV" -i "$MISJOIN_FA" -l "$LONG_READS" -t "$THREADS" -o "$TEMP_DIR/overlap" -T "$TEMP_DIR/overlap_temp" 2>&1 | tee -a "$TEMP_DIR/overlap.log"
    
    if [[ $? -ne 0 ]]; then
        echo "Error: Failed to find overlaps"
        exit 1
    fi
else
    echo "Overlap file already exists, skipping overlap finding"
fi

# STEP 5: Realignment for polishing
echo "STEP 5: Realignment for polishing"
OVERLAP_LONG_BAM="$TEMP_DIR/overlap_long.bam"
if [[ ! -f "$OVERLAP_LONG_BAM" ]]; then
    echo "Realignment for polishing (long reads)"
    minimap2 -I 64G -ax map-ont -t "$THREADS" "$OVERLAP_FA" "$LONG_READS" | \
        samtools view -bS | \
        samtools sort -@ "$SORT_THREADS" -m "$SORT_MEM" -o "$OVERLAP_LONG_BAM"
    
    if [[ $? -ne 0 ]]; then
        echo "Error: Failed to realign long reads for polishing"
        exit 1
    fi
else
    echo "Overlap long read alignment already exists, skipping realignment"
fi

OVERLAP_SHORT_BAM="$TEMP_DIR/overlap_short.bam"
if [[ ! -f "$OVERLAP_SHORT_BAM" ]]; then
    echo "Realignment for polishing (short reads)"
    minimap2 -I 64G -ax sr -t "$THREADS" "$OVERLAP_FA" "$SHORT_READS_1" "$SHORT_READS_2" | \
        samtools view -bS | \
        samtools sort -@ "$SORT_THREADS" -m "$SORT_MEM" -o "$OVERLAP_SHORT_BAM"
    
    if [[ $? -ne 0 ]]; then
        echo "Error: Failed to realign short reads for polishing"
        exit 1
    fi
else
    echo "Overlap short read alignment already exists, skipping realignment"
fi

# STEP 6: Polishing
echo "STEP 6: Polishing"
POLISHED_1_FA="$TEMP_DIR/polished_1.fa"
if [[ ! -f "$POLISHED_1_FA" ]]; then
    echo "Polishing with parameters:"
    echo "  Long-read coverage: $LONG_READ_COVERAGE"
    echo "  Short-read coverage: $SHORT_READ_COVERAGE"
    echo "  Batch number: $HYPO_BATCH_NUMBER"
    
    hypo -d "$OVERLAP_FA" -s "$GENOME_SIZE" -B "$OVERLAP_LONG_BAM" -C "$LONG_READ_COVERAGE" -b "$OVERLAP_SHORT_BAM" -r "@$TEMP_DIR/shorts.txt" -c "$SHORT_READ_COVERAGE" -L "$KMCMEM" -t "$THREADS" -o "$TEMP_DIR/polished" -p "$HYPO_BATCH_NUMBER" 2>&1 | tee "$TEMP_DIR/polish.log"
    
    if [[ $? -ne 0 ]]; then
        echo "Error: Failed to polish assembly"
        exit 1
    fi
else
    echo "Polished assembly already exists, skipping polishing"
fi

# STEP 7: Scaffolding
echo "STEP 7: Scaffolding"
SCAFFOLD_1_FA="$TEMP_DIR/scaffold_1.fa"
if [[ ! -f "$SCAFFOLD_1_FA" ]]; then
    echo "Scaffolding"
    sh "$HYPO_ASSEMBLER_DIR/run_all/run_scaffold.sh" -k "$SUK_BV" -i "$TEMP_DIR/polished_1.fa" -I "$TEMP_DIR/polished_2.fa" -l "$LONG_READS" -t "$THREADS" -o "$TEMP_DIR/scaffold" -T "$TEMP_DIR" 2>&1 | tee "$TEMP_DIR/scaffold.log"
    
    if [[ $? -ne 0 ]]; then
        echo "Error: Failed to scaffold assembly"
        exit 1
    fi
    
    # Copy final scaffold files to output directory
    cp "$TEMP_DIR/scaffold_1.fa" "$OUTPUT_DIR/scaffold_1.fa"
    cp "$TEMP_DIR/scaffold_2.fa" "$OUTPUT_DIR/scaffold_2.fa"
    echo "Final scaffold files copied to:"
    echo "  $OUTPUT_DIR/scaffold_1.fa"
    echo "  $OUTPUT_DIR/scaffold_2.fa"
else
    echo "Scaffold files already exist, skipping scaffolding"
    
    # Copy final scaffold files to output directory if not already present
    if [[ ! -f "$OUTPUT_DIR/scaffold_1.fa" ]]; then
        cp "$TEMP_DIR/scaffold_1.fa" "$OUTPUT_DIR/scaffold_1.fa"
    fi
    if [[ ! -f "$OUTPUT_DIR/scaffold_2.fa" ]]; then
        cp "$TEMP_DIR/scaffold_2.fa" "$OUTPUT_DIR/scaffold_2.fa"
    fi
fi

echo "======================================================"
echo "Hypo Assembler Completed"
echo "Time: $(date +"%Y-%m-%d %T")"
echo "Output Directory: $OUTPUT_DIR"
echo "Final assembly files:"
echo "  $OUTPUT_DIR/scaffold_1.fa"
echo "  $OUTPUT_DIR/scaffold_2.fa"
echo "======================================================"
