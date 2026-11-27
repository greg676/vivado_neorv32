#!/bin/bash
export ADS_PROFILE=/mnt/<data-disk>/ai-design-studio/project.profile.json

# Extract allowed directories from profile
ALLOWED_DIRS=$(python3 -c "
import json, os
with open('$ADS_PROFILE') as f:
    p = json.load(f)
roots = p['filesystem']['read_roots'] + p['filesystem']['write_roots']
roots = [os.path.expanduser(r) for r in roots]
# Only include dirs that exist
roots = [r for r in roots if os.path.isdir(r)]
print(' '.join(roots))
")

: "${NVM_DIR:=$HOME/.nvm}"
exec "${NVM_DIR}/versions/node/current/bin/mcp-server-filesystem" $ALLOWED_DIRS
