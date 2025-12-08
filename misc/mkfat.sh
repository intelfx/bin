#!/bin/bash

set -eo pipefail
shopt -s lastpipe
. lib.sh


# Default values
DEFAULT_SIZE="1G"
DEFAULT_LABEL="FATDISK"

_usage() {
    cat << EOF
$ARGV0 - FAT image tool

USAGE:
    $ARGV0 create <image_file> <source>... [options]
    $ARGV0 extract <image_file> <directory> [options]

COMMANDS:
    create      Create FAT disk image from source directories/files
    extract     Extract FAT disk image to directory (auto-detects partition table)

OPTIONS:
    -s, --size SIZE         New image size (default: $DEFAULT_SIZE)
    -L, --label LABEL       Volume label (default: $DEFAULT_LABEL)
    -p, --partition TYPE    Partition table type: mbr, none (default: mbr)
    -F, --fat-size SIZE     FAT size: 12, 16, 32 (default: auto-detect by size)
    -h, --help              Show this help
    -v, --verbose           Verbose output

SOURCE ARG SYNTAX (rsync-like):
    path/to/dir/ : dir/* -> IMAGE:/*
                   (copy contents of directory into image root)
    path/to/dir  : dir/* -> IMAGE:/dir/*
                   (copy directory itself into image root)
    path/to/file : file  -> IMAGE:/file
                   (copy file into image root)

    Note: A single directory source argument is interpreted

EXAMPLES:
    # Create image from directory contents
    $ARGV0 create disk.img /path/to/dir -s 500M -l "MYDISK"

    # Create image with multiple sources
    $ARGV0 create disk.img /path/to/dir1/ /path/to/dir2 file.txt -s 500M

    # Create raw FAT16 image (no partition table)
    $ARGV0 create disk.img /path/to/dir -s 100M -p none --fat-type 16

    # Extract image (auto-detects partition table)
    $ARGV0 extract disk.img /path/to/output

EOF
}

logv() {
    if (( VERBOSE )); then
        log "$@"
    fi
}
error() {
    err "$@"
}

check_dependencies() {
    local missing=()

    # Check for mtools commands
    for cmd in mformat mcopy mdir mmd; do
        if ! command -v "$cmd" &>/dev/null; then
            missing+=("mtools")
            break
        fi
    done

    # Check for partitioning tools
    if ! command -v sfdisk &>/dev/null; then
        missing+=("util-linux (sfdisk)")
    fi

    # Check for bscalc
    if ! command -v bscalc &>/dev/null; then
        missing+=("bscalc")
    fi

    # Check for truncate
    if ! command -v truncate &>/dev/null; then
        missing+=("coreutils (truncate)")
    fi

    if [[ ${missing+set} ]]; then
        die "Missing required tools: $(join , "${missing[@]@Q}")"
    fi
}

calculate_sectors() {
    local size_str="$1"

    # Use bscalc to parse human-readable size, remove "B" suffix
    local size_bytes
    size_bytes=$(bscalc -b "$size_str" | grep -Eo '[0-9]+')

    # Calculate sectors (512 bytes each)
    echo $((size_bytes / 512))
}

detect_partition_offset() {
    local img_file="$1"

    # Try to detect MBR partition table
    local partition_info
    partition_info=$(sfdisk -d "$img_file" 2>/dev/null | grep -E "start=.*type=" | head -n1 || true)

    if [[ -n "$partition_info" ]]; then
        local start_sector
        start_sector=$(echo "$partition_info" | sed -n 's/.*start=\s*\([0-9]*\).*/\1/p')

        if [[ -n "$start_sector" && "$start_sector" -gt 0 ]]; then
            logv "Detected MBR partition starting at sector $start_sector"
            echo "$start_sector"
            return 0
        fi
    fi

    # No partition table detected
    logv "No partition table detected, treating as raw FAT image"
    echo "0"
}

get_offset_spec() {
    local offset="$1"

    if [[ "$offset" -eq 0 ]]; then
        echo ""
    else
        echo "@@$((offset * 512))"
    fi
}

create_image() {
    local img_file="$1"
    local size="$2"
    local label="$3"
    local fat_type="$4"
    local partition_type="$5"
    shift 5
    local sources=("$@")

    # Convert to absolute path to avoid issues with cd
    img_file=$(realpath "$img_file")

    local total_sectors
    total_sectors=$(calculate_sectors "$size")

    local partition_offset=0
    local partition_sectors="$total_sectors"

    if [[ "$partition_type" == "mbr" ]]; then
        logv "Creating MBR-partitioned FAT image..."

        # Create empty image using truncate
        logv "Creating ${total_sectors}-sector image file"
        truncate -s 0 "$img_file"
        truncate -s $((total_sectors * 512)) "$img_file"

        # Create MBR partition table with one FAT partition
        logv "Creating MBR partition table"
        local fat_id
        case "$fat_type" in
            12) fat_id="01" ;;  # FAT12
            16) fat_id="06" ;;  # FAT16
            32) fat_id="0c" ;;  # FAT32 LBA
            *) fat_id="0c" ;;   # Default to FAT32
        esac

        # Use sfdisk to create partition (start at 2048 sectors = 1MB)
        {
            echo "label: dos"
            echo "start=2048, type=$fat_id, bootable"
        } | sfdisk "$img_file" >/dev/null

        partition_offset=2048
        partition_sectors=$((total_sectors - partition_offset))
    else
        logv "Creating bare FAT image (no partition table)..."
    fi

    # Get mtools offset specification
    local offset_spec
    offset_spec=$(get_offset_spec "$partition_offset")

    # Format the FAT filesystem
    logv "Creating FAT${fat_type} filesystem"
    local fat_opts=()
    if [[ "$fat_type" ]]; then
        fat_opts+=(-F "$fat_type")
    fi

    mformat -i "$img_file$offset_spec" -v "$label" -T "$partition_sectors" "${fat_opts[@]}" :: \
        || die "Failed to create filesystem"

    # Copy sources to image
    if [[ ${sources+set} ]]; then
        logv "Copying sources to image"
        copy_sources_to_fat "$img_file$offset_spec" "${sources[@]}"
    fi

    logv "Image created: $img_file"
}

copy_sources_to_fat() {
    local img_spec="$1"
    shift
    local sources=("$@")

    # Special case: single directory without trailing slash should copy contents
    if [[ ${#sources[@]} -eq 1 && -d "${sources[0]}" && "${sources[0]}" != */ ]]; then
        logv "Single directory detected, copying contents"
        copy_source_to_fat "${sources[0]}/" "$img_spec"
        return
    fi

    # Process each source
    for source in "${sources[@]}"; do
        copy_source_to_fat "$source" "$img_spec"
    done
}

copy_source_to_fat() {
    local source="$1"
    local img_spec="$2"

    # Prepare mcopy options
    local mcopy_opts=("-bspQm")
    if (( VERBOSE )); then
        mcopy_opts+=("-v")
    fi

    if [[ "$source" == */ ]]; then
        # Source ends with slash - copy contents
        source="${source%/}"
        if [[ ! -d "$source" ]]; then
            die "Source is not a directory: ${source@Q}"
        fi
        logv "Copying contents of directory: $source"
        mcopy -i "$img_spec" "${mcopy_opts[@]}" "$source"/* :: \
            || die "Failed to copy directory contents from ${source@Q}"
    elif [[ -d "$source" ]]; then
        # Source is directory without slash - copy directory itself
        logv "Copying directory: $source as $(basename "$source")"
        mcopy -i "$img_spec" "${mcopy_opts[@]}" "$source" :: \
            || die "Failed to copy directory ${source@Q}"
    elif [[ -f "$source" ]]; then
        # Source is a file
        logv "Copying file: $source"
        mcopy -i "$img_spec" "${mcopy_opts[@]}" "$source" :: \
            || die "Failed to copy file ${source@Q}"
    else
        die "Source does not exist: ${source@Q}"
    fi
}

extract_image() {
    local img_file="$1"
    local dst_dir="$2"

    # Convert to absolute path to avoid issues with cd
    img_file=$(realpath "$img_file")

    # Auto-detect partition offset
    local partition_offset
    partition_offset=$(detect_partition_offset "$img_file")

    # Get mtools offset specification
    local offset_spec
    offset_spec=$(get_offset_spec "$partition_offset")

    logv "Extracting FAT image to: $dst_dir"

    # Create destination directory
    mkdir -p "$dst_dir"

    # Prepare mcopy options for extraction
    local mcopy_opts=("-bspQm")
    if (( VERBOSE )); then
        mcopy_opts+=("-v")
    fi

    # Extract all contents recursively with preserved attributes
    logv "Extracting all contents recursively"
    (cd "$dst_dir" && mcopy -i "$img_file$offset_spec" "${mcopy_opts[@]}" "::/*" . ) || {
        # Handle case where root directory might be empty or have issues
        warn "Direct extraction failed, trying alternative approach"
        mcopy -i "$img_file$offset_spec" "${mcopy_opts[@]}" :: "$dst_dir/"
    } || die "Failed to extract image contents"

    logv "Image extracted successfully to: $dst_dir"
}


#
# args
#

COMMAND=""
IMG_FILE=""
SOURCES=()
DST=""
SIZE="$DEFAULT_SIZE"
LABEL="$DEFAULT_LABEL"
PARTITION_TYPE="mbr"
FAT_TYPE=""
VERBOSE=0

# declare -A _args=(
#     [-h|--help]=ARG_USAGE
#     #[--]=ARGS
# )
# parse_args _args "$@" || usage
# [[ ! $ARG_USAGE ]] || usage

while [[ $# -gt 0 ]]; do
    case $1 in
        create|extract)
            COMMAND="$1"
            shift
            ;;
        -s|--size)
            SIZE="$2"
            shift 2
            ;;
        -l|--label)
            LABEL="$2"
            shift 2
            ;;
        -p|--partition)
            PARTITION_TYPE="$2"
            shift 2
            ;;
        -f|--fat-type)
            FAT_TYPE="$2"
            shift 2
            ;;
        -v|--verbose)
            VERBOSE=1
            shift
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        -*)
            die "Unknown option: $1"
            ;;
        *)
            if [[ -z "$IMG_FILE" ]]; then
                IMG_FILE="$1"
            elif [[ "$COMMAND" == "create" ]]; then
                SOURCES+=("$1")
            elif [[ -z "$DST" ]]; then
                DST="$1"
            else
                die "Too many arguments"
            fi
            shift
            ;;
    esac
done

# Validate arguments
if [[ -z "$COMMAND" ]]; then
    die "No command specified. Use 'create' or 'extract'."
fi

if [[ -z "$IMG_FILE" ]]; then
    die "Image file must be specified"
fi

if [[ "$COMMAND" == "create" && ${#SOURCES[@]} -eq 0 ]]; then
    die "At least one source must be specified for create command"
fi

if [[ "$COMMAND" == "extract" && -z "$DST" ]]; then
    die "Destination directory must be specified for extract command"
fi

if [[ "$PARTITION_TYPE" != "mbr" && "$PARTITION_TYPE" != "none" ]]; then
    die "Partition type must be 'mbr' or 'none'"
fi

if [[ -n "$FAT_TYPE" && "$FAT_TYPE" != "12" && "$FAT_TYPE" != "16" && "$FAT_TYPE" != "32" ]]; then
    die "FAT type must be 12, 16, or 32"
fi

# Check dependencies
check_dependencies

# Execute command
case "$COMMAND" in
    create)
        create_image "$IMG_FILE" "$SIZE" "$LABEL" "$FAT_TYPE" "$PARTITION_TYPE" "${SOURCES[@]}"
        ;;
    extract)
        if [[ ! -f "$IMG_FILE" ]]; then
            die "Source image file does not exist: ${IMG_FILE@Q}"
        fi
        extract_image "$IMG_FILE" "$DST"
        ;;
esac

say "All done"
