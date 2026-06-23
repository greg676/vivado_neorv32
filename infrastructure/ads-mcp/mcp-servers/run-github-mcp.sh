#!/bin/bash
export GITHUB_TOKEN=$(gh auth token)
export ADS_PROFILE=/mnt/data-1tb/ai-design-studio/project.profile.json
exec /home/greg-jack/.nvm/versions/node/v22.22.1/bin/mcp-server-github
