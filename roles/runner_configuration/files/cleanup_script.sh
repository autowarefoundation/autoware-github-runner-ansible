#!/bin/bash

set -euo pipefail

echo "=========================================="
echo "  GitHub Runner Cleanup Script"
echo "  $(date '+%Y-%m-%d %H:%M:%S')"
echo "=========================================="
echo

# --- STEP 0: Disk usage before cleanup ---
echo "=== STEP 0: Disk & Docker Usage (Before Cleanup) ==="
df -h / | tail -1 | awk '{printf "Disk: %s used of %s (%s free)\n", $3, $2, $4}'
echo
docker system df
echo

# --- STEP 1: Clean RUNNER_TEMP ---
echo "=== STEP 1: Runner Temp Cleanup ==="
if [[ -n "${GITHUB_WORKSPACE:-}" && -d "$GITHUB_WORKSPACE" ]]; then
    echo "GITHUB_WORKSPACE=$GITHUB_WORKSPACE"
    ls -al "$GITHUB_WORKSPACE"
else
    echo "GITHUB_WORKSPACE is not set or does not exist. Skipping."
fi
echo

if [[ -n "${RUNNER_TEMP:-}" && -d "$RUNNER_TEMP" ]]; then
    echo "Cleaning up contents of: $RUNNER_TEMP"
    sudo rm -rf "${RUNNER_TEMP:?}/"*
    sudo rm -rf "${RUNNER_TEMP:?}/".* 2>/dev/null || true
    echo "Done."
else
    echo "RUNNER_TEMP is not set or does not exist. Skipping."
fi
echo

# --- STEP 2: Show all Docker images before cleanup ---
echo "=== STEP 2: All Docker Images (Before Cleanup) ==="
docker images -a --format 'table {{.Repository}}\t{{.Tag}}\t{{.ID}}\t{{.CreatedSince}}\t{{.Size}}'
echo
total_before=$(docker images -a --format '{{.ID}}' | sort -u | wc -l)
echo "Total unique images (including intermediate): $total_before"
echo

# --- STEP 3: Stop and remove all containers ---
echo "=== STEP 3: Stopping All Running Containers ==="
running_containers=$(docker ps -q)
if [[ -n "$running_containers" ]]; then
    echo "Found running containers. Stopping them now..."
    docker stop $running_containers
    echo "All containers stopped."
else
    echo "No running containers found."
fi
echo

echo "Removing all stopped containers..."
docker container prune -f
echo

# --- STEP 4: Remove old images (keep most recent N) ---
# Number of most recent images to keep
keep_last_x=15

echo "=== STEP 4: Image Cleanup (Keeping newest $keep_last_x) ==="
echo "Collecting unique image metadata..."

# Use -a to include intermediate layers
image_list=$(docker images -a --format '{{.ID}}' | sort -u |
    while read -r id; do
        created=$(docker inspect --format '{{.Created}}' "$id" 2>/dev/null) || continue
        echo "$created $id"
    done | sort -r)

total_images=$(echo "$image_list" | grep -c . || true)
echo "Found $total_images unique images."

if [[ $total_images -le $keep_last_x ]]; then
    echo "Only $total_images images found (<= $keep_last_x). No age-based removal needed."
else
    to_remove=$(echo "$image_list" | tail -n +$((keep_last_x + 1)))
    remove_count=$(echo "$to_remove" | grep -c . || true)
    echo "Removing $remove_count images..."
    echo "$to_remove" | awk '{printf "  ID: %s | Created: %s\n", $2, $1}'
    echo

    echo "$to_remove" | awk '{print $2}' | xargs -r docker rmi -f 2>&1 | grep -v "image is referenced" || true
fi
echo

# --- STEP 5: Prune dangling images, unused volumes, and build cache ---
echo "=== STEP 5: Docker System Prune ==="

echo "Pruning dangling images..."
docker image prune -f
echo

echo "Pruning unused volumes..."
docker volume prune -f
echo

echo "Pruning build cache..."
docker builder prune -f 2>/dev/null || true
echo

# --- STEP 6: Summary ---
echo "=== STEP 6: Post-Cleanup Status ==="
docker images -a --format 'table {{.Repository}}\t{{.Tag}}\t{{.ID}}\t{{.CreatedSince}}\t{{.Size}}'
echo

total_after=$(docker images -a --format '{{.ID}}' | sort -u | wc -l)
echo "Images removed: $((total_before - total_after)) (was $total_before, now $total_after)"
echo

docker system df
echo

df -h / | tail -1 | awk '{printf "Disk: %s used of %s (%s free)\n", $3, $2, $4}'
echo
echo "Cleanup complete."
