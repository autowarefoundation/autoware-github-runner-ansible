#!/bin/bash
#
# cleanup-runner.sh — Reclaim disk space on a GitHub Actions runner
#
# Tasks:
#   1. Record baseline disk & Docker usage
#   2. Clean the runner temp directory
#   3. Reset runner home directory
#   4. List all Docker images (pre-cleanup)
#   5. Stop all running containers
#   6. Remove all stopped containers
#   7. Remove all but the N most recent images
#   8. Prune dangling/intermediate image layers
#   9. Remove all local volumes
#  10. Prune build cache
#  11. Report post-cleanup status
#

KEEP_IMAGES=15

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

banner() {
    echo
    echo "──── $1 ────"
}

info()    { echo "  $1"; }
warn()    { echo "  ⚠ $1" >&2; }
success() { echo "  ✓ $1"; }

disk_summary() {
    df -h / | tail -1 | awk '{printf "%s used of %s (%s free)\n", $3, $2, $4}'
}

image_count() {
    docker images -q | sort -u | wc -l
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

echo "=========================================="
echo "  GitHub Runner Cleanup"
echo "  $(date '+%Y-%m-%d %H:%M:%S')"
echo "=========================================="

# 1. Baseline snapshot
banner "1. Baseline"
info "Disk : $(disk_summary)"
info "Images: $(image_count) unique"
docker system df
count_before=$(image_count)

# 2. Clean runner temp directory
banner "2. Runner Temp"
if [[ -n "${RUNNER_TEMP:-}" && -d "$RUNNER_TEMP" ]]; then
    info "Cleaning $RUNNER_TEMP"
    find "$RUNNER_TEMP" -mindepth 1 -delete 2>/dev/null || warn "Some temp files could not be removed"
    success "Done"
else
    info "RUNNER_TEMP is not set or missing — skipping"
fi

# 3. Reset runner home directory
banner "3. Reset Runner Home"
if [[ -n "${GITHUB_ACTIONS:-}" ]]; then
    RUNNER_HOME="${HOME:-/github/home}"
    if [[ -d "$RUNNER_HOME" ]]; then
        find "$RUNNER_HOME" -mindepth 1 -delete 2>/dev/null || warn "Some files could not be removed"
        success "Cleaned $RUNNER_HOME"
    else
        info "$RUNNER_HOME does not exist — skipping"
    fi
else
    info "Not running as a job hook — skipping home cleanup"
fi

# 4. List images before cleanup
banner "4. Docker Images (pre-cleanup)"
docker images --format 'table {{.Repository}}\t{{.Tag}}\t{{.ID}}\t{{.CreatedSince}}\t{{.Size}}'

# 5. Stop all running containers
banner "5. Stop Running Containers"
if running=$(docker ps -q) && [[ -n "$running" ]]; then
    echo "$running" | xargs docker stop
    success "Stopped $(echo "$running" | wc -l) container(s)"
else
    info "No running containers"
fi

# 6. Remove all stopped containers
banner "6. Remove Stopped Containers"
docker container prune -f

# 7. Remove all but the newest N images
banner "7. Image Cleanup (keeping newest $KEEP_IMAGES)"

# Build a sorted list: newest-first, one line per unique image ID
image_list=$(
    docker images -q | sort -u | while read -r id; do
        ts=$(docker inspect --format '{{.Created}}' "$id" 2>/dev/null) || continue
        echo "$ts $id"
    done | sort -r
)
total=$(echo "$image_list" | grep -c . || true)

if [[ $total -le $KEEP_IMAGES ]]; then
    info "Only $total image(s) present — nothing to remove"
else
    # Split into keep / remove sets
    keep_ids=$(echo "$image_list" | head -n "$KEEP_IMAGES" | awk '{print $2}')
    remove_ids=$(echo "$image_list" | tail -n +$((KEEP_IMAGES + 1)) | awk '{print $2}')
    remove_count=$(echo "$remove_ids" | wc -l)

    info "Keeping $KEEP_IMAGES, removing $remove_count"
    echo
    info "Keeping:"
    echo "$keep_ids" | while read -r id; do
        tags=$(docker inspect --format '{{join .RepoTags ", "}}' "$id" 2>/dev/null)
        info "  $id  ${tags:-<none>}"
    done

    echo
    info "Removing:"
    echo "$remove_ids" | while read -r id; do
        tags=$(docker inspect --format '{{join .RepoTags ", "}}' "$id" 2>/dev/null)
        info "  $id  ${tags:-<none>}"

        # Untag all references first, then force-remove the ID
        docker inspect --format '{{range .RepoTags}}{{.}}{{"\n"}}{{end}}' "$id" 2>/dev/null |
            grep -v '^$' |
            while read -r tag; do
                docker rmi "$tag" 2>/dev/null || true
            done
        docker rmi -f "$id" 2>/dev/null || warn "Could not remove $id"
    done
fi

# 8. Prune dangling / intermediate layers
banner "8. Prune Dangling Layers"
docker image prune -f

# 9. Remove all local volumes
banner "9. Remove All Volumes"
if volumes=$(docker volume ls -q) && [[ -n "$volumes" ]]; then
    vol_count=$(echo "$volumes" | wc -l)
    echo "$volumes" | xargs docker volume rm -f 2>/dev/null || warn "Some volumes could not be removed"
    success "Removed $vol_count volume(s)"
else
    info "No volumes found"
fi

# 10. Prune build cache and networks
banner "10. Prune Build Cache & Networks"
docker builder prune -f 2>/dev/null || true
docker network prune -f 2>/dev/null || true

# 11. Post-cleanup report
banner "11. Post-Cleanup Report"
docker images --format 'table {{.Repository}}\t{{.Tag}}\t{{.ID}}\t{{.CreatedSince}}\t{{.Size}}'
echo
count_after=$(image_count)
info "Images : $count_after (removed $((count_before - count_after)))"
info "Disk   : $(disk_summary)"
echo
docker system df
echo
success "Cleanup complete"
