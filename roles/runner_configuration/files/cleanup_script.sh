#!/bin/bash

keep_last_x=4
# List all images, sort by creation date, get the image IDs, skip the last x, and remove the rest
docker images --format "{{.CreatedAt}} {{.ID}}" | sort -r | awk '{print $5}' | tail -n +$((keep_last_x + 1)) | xargs -r docker rmi -f
