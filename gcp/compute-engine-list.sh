#!/bin/bash

# Ensure jq is installed
if ! command -v jq &> /dev/null
then
    echo "jq could not be found. Please install jq to use this script."
    exit 1
fi

# Function to extract disk details when initializeParams is missing
get_disk_details() {
    local disk_url="$1"
    local disk_zone
    local disk_name
    local disk_info

    # Extract zone and disk name from the disk URL
    disk_zone=$(echo "$disk_url" | awk -F'/zones/' '{print $2}' | awk -F'/' '{print $1}')
    disk_name=$(echo "$disk_url" | awk -F'/disks/' '{print $2}')

    # Describe the disk to get its details
    disk_info=$(gcloud compute disks describe "$disk_name" --zone="$disk_zone" --format="json" 2>/dev/null)

    if [ -z "$disk_info" ]; then
        echo "N/A"
        echo "N/A"
        echo "N/A"
    else
        DISK_SIZE_GB=$(echo "$disk_info" | jq -r '.sizeGb // "N/A"')
        DISK_TYPE_FULL=$(echo "$disk_info" | jq -r '.type // "N/A"')
        DISK_TYPE=$(basename "$DISK_TYPE_FULL")
        SOURCE_IMAGE_URL=$(echo "$disk_info" | jq -r '.sourceImage // "N/A"')
        OS_IMAGE_NAME=$(basename "$SOURCE_IMAGE_URL")
        echo "$DISK_SIZE_GB" "$DISK_TYPE" "$OS_IMAGE_NAME"
    fi
}

# Print header
printf "%-25s %-15s %-20s %-6s %-10s %-10s %-15s %-30s\n" \
    "INSTANCE_NAME" "MACHINE_FAMILY" "MACHINE_TYPE" "VCPUs" "Memory(GB)" "Disk(GB)" "Disk_Type" "OS_Image_Name"
printf "%.s-" {1..130}
echo

# List all instances in all zones
gcloud compute instances list --format="json" | jq -c '.[]' | while read -r instance; do
    # Extract basic instance info
    NAME=$(echo "$instance" | jq -r '.name')
    MACHINE_TYPE_FULL=$(echo "$instance" | jq -r '.machineType')
    ZONE_URL=$(echo "$instance" | jq -r '.zone')
    ZONE=$(basename "$ZONE_URL")

    # Get machine type details
    MACHINE_TYPE=$(basename "$MACHINE_TYPE_FULL") # e.g., e2-standard-2
    MACHINE_FAMILY=$(echo "$MACHINE_TYPE" | grep -oE '^[a-z]+') # Extract family prefix, e.g., e2

    MACHINE_INFO=$(gcloud compute machine-types describe "$MACHINE_TYPE" --zone="$ZONE" --format="json" 2>/dev/null)
    if [ -z "$MACHINE_INFO" ]; then
        VCPUS="N/A"
        MEMORY_GB="N/A"
    else
        VCPUS=$(echo "$MACHINE_INFO" | jq -r '.guestCpus // "N/A"')
        MEMORY_MB=$(echo "$MACHINE_INFO" | jq -r '.memoryMb // "0"')
        MEMORY_GB=$(awk "BEGIN {printf \"%.2f\", $MEMORY_MB/1024}")
    fi

    # Extract boot disk information
    BOOT_DISK=$(echo "$instance" | jq -r '.disks[] | select(.boot==true)')

    # Check if initializeParams exist
    INIT_PARAMS=$(echo "$BOOT_DISK" | jq -r 'has("initializeParams")')

    if [ "$INIT_PARAMS" == "true" ]; then
        DISK_SIZE_GB=$(echo "$BOOT_DISK" | jq -r '.initializeParams.diskSizeGb // "N/A"')
        DISK_TYPE_FULL=$(echo "$BOOT_DISK" | jq -r '.initializeParams.diskType // "N/A"')
        DISK_TYPE=$(basename "$DISK_TYPE_FULL")
        IMAGE_URL=$(echo "$BOOT_DISK" | jq -r '.initializeParams.sourceImage // "N/A"')
        OS_IMAGE_NAME=$(basename "$IMAGE_URL")
    else
        # Extract disk source URL
        DISK_SOURCE=$(echo "$BOOT_DISK" | jq -r '.source // ""')

        if [ -z "$DISK_SOURCE" ] || [ "$DISK_SOURCE" == "null" ]; then
            DISK_SIZE_GB="N/A"
            DISK_TYPE="N/A"
            OS_IMAGE_NAME="N/A"
        else
            # Get disk details by describing the disk
            read -r DISK_SIZE_GB DISK_TYPE OS_IMAGE_NAME <<< $(get_disk_details "$DISK_SOURCE")
        fi
    fi

    # Handle cases where disk details might still be missing
    DISK_SIZE_GB=${DISK_SIZE_GB:-"N/A"}
    DISK_TYPE=${DISK_TYPE:-"N/A"}
    OS_IMAGE_NAME=${OS_IMAGE_NAME:-"N/A"}

    # Print the information
    printf "%-25s %-15s %-20s %-6s %-10s %-10s %-15s %-30s\n" \
        "$NAME" "$MACHINE_FAMILY" "$MACHINE_TYPE" "$VCPUS" "$MEMORY_GB" "$DISK_SIZE_GB" "$DISK_TYPE" "$OS_IMAGE_NAME"
done
