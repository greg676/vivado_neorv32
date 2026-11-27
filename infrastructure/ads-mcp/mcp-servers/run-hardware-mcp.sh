#!/bin/bash
export ADS_PROFILE=/mnt/<data-disk>/ai-design-studio/project.profile.json
exec python3 /mnt/<data-disk>/ai-design-studio/mcp/hardware-debug/server.py
