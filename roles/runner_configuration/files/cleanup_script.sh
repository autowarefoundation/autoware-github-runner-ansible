#!/bin/bash
#
# cleanup-runner.sh — Reclaim disk space on a GitHub Actions runner
#
# Tasks:
#   1. Record baseline disk & Docker usage
#   2. Clean the runner temp directory
#   3. List all Docker images (pre-cleanup)
#   4. Stop all running containers
#   5. Remove all stopped containers
#   6. Remove all but the N most recent images
#   7. Prune dangling/intermediate image layers
#   8. Prune unused volumes
#   9. Prune build cache
#  10. Report post-cleanup status
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

# 3. List images before cleanup
banner "3. Docker Images (pre-cleanup)"
docker images --format 'table {{.Repository}}\t{{.Tag}}\t{{.ID}}\t{{.CreatedSince}}\t{{.Size}}'

# 4. Stop all running containers
banner "4. Stop Running Containers"
if running=$(docker ps -q) && [[ -n "$running" ]]; then
    echo "$running" | xargs docker stop
    success "Stopped $(echo "$running" | wc -l) container(s)"
else
    info "No running containers"
fi

# 5. Remove all stopped containers
banner "5. Remove Stopped Containers"
docker container prune -f

# 6. Remove all but the newest N images
banner "6. Image Cleanup (keeping newest $KEEP_IMAGES)"

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

# 7. Prune dangling / intermediate layers
banner "7. Prune Dangling Layers"
docker image prune -f

# 8. Prune unused volumes
banner "8. Prune Unused Volumes"
docker volume prune -f

# 9. Prune build cache and networks
banner "9. Prune Build Cache & Networks"
docker builder prune -f 2>/dev/null || true
docker network prune -f 2>/dev/null || true

# 10. Post-cleanup report
banner "10. Post-Cleanup Report"
docker images --format 'table {{.Repository}}\t{{.Tag}}\t{{.ID}}\t{{.CreatedSince}}\t{{.Size}}'
echo
count_after=$(image_count)
info "Images : $count_after (removed $((count_before - count_after)))"
info "Disk   : $(disk_summary)"
echo
docker system df
echo
success "Cleanup complete"
