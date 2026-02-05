#!/bin/bash

echo "GITHUB_WORKSPACE=$GITHUB_WORKSPACE"

ls -al "$GITHUB_WORKSPACE"

echo

echo "RUNNER_TEMP=$RUNNER_TEMP"

ls -al "$RUNNER_TEMP"

echo

# Check if RUNNER_TEMP is set and the directory exists
if [[ -n $RUNNER_TEMP && -d $RUNNER_TEMP ]]; then
    echo "Cleaning up contents of: $RUNNER_TEMP"

    # Remove all contents but not the folder itself
    sudo rm -rf "${RUNNER_TEMP:?}/"*
    sudo rm -rf "${RUNNER_TEMP:?}/".* 2>/dev/null || true # Remove hidden files, skip . and ..
else
    echo "RUNNER_TEMP is not set or does not exist. Skipping cleanup."
fi

# Number of most recent images to keep
keep_last_x=15

echo "=== STEP 1: All Docker Images (Before Cleanup) ==="
docker images --format 'Repository: {{.Repository}} | Tag: {{.Tag}} | ID: {{.ID}} | Created: {{.CreatedSince}} | Size: {{.Size}}'
echo

# Stop all running containers
echo "=== STEP 2: Stopping All Running Containers ==="
running_containers=$(docker ps -q)
if [[ -n $running_containers ]]; then
    echo "Found running containers. Stopping them now..."
    docker stop $running_containers
    echo "All containers stopped."
else
    echo "No running containers found."
fi
echo

# Get all unique image IDs
echo "Collecting unique image metadata..."
image_list=$(docker images --format '{{.ID}}' | sort | uniq |
    while read -r id; do
        created=$(docker inspect --format '{{.Created}}' "$id" 2>/dev/null)
        echo "$created $id"
    done | sort -r)

# Preview images to be removed
echo "=== STEP 3: Images That Will Be REMOVED (Keeping last $keep_last_x) ==="
to_remove=$(echo "$image_list" | tail -n +$((keep_last_x + 1)))
echo "$to_remove" | awk '{printf "ID: %s | Created: %s\n", $2, $1}'

# Actually remove them
echo
echo "Removing images..."
echo "$to_remove" | awk '{print $2}' | xargs -r docker rmi -f
echo

# Show remaining images
echo "=== STEP 4: Remaining Docker Images (After Cleanup) ==="
docker images --format 'Repository: {{.Repository}} | Tag: {{.Tag}} | ID: {{.ID}} | Created: {{.CreatedSince}} | Size: {{.Size}}'
