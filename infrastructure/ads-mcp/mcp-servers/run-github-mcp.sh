#!/bin/bash
export GITHUB_TOKEN=$(gh auth token)
export ADS_PROFILE=/mnt/<data-disk>/ai-design-studio/project.profile.json
: "${NVM_DIR:=$HOME/.nvm}"
exec "${NVM_DIR}/versions/node/current/bin/mcp-server-github"
