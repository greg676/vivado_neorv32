#!/bin/bash
# browser-puppeteer-mcp wrapper
export ADS_PROFILE=/mnt/<data-disk>/ai-design-studio/project.profile.json
: "${NVM_DIR:=$HOME/.nvm}"
exec "${NVM_DIR}/versions/node/current/bin/mcp-server-puppeteer"
