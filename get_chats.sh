#!/bin/bash

cd "$(dirname "$0")/backend" || exit 1

python3 << 'EOF'
import sys
import os

# Set minimal environment variables needed for database access
# These prevent the ValueError about missing WEBUI_SECRET_KEY
if "WEBUI_AUTH" not in os.environ:
    os.environ["WEBUI_AUTH"] = "False"
if "WEBUI_SECRET_KEY" not in os.environ:
    os.environ["WEBUI_SECRET_KEY"] = "dummy-key-for-script"

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from open_webui.internal.db import SessionLocal
from open_webui.models.chats import Chat

try:
    db = SessionLocal()
    try:
        chats = db.query(Chat).order_by(Chat.created_at.desc()).all()
        for chat in chats:
            title = chat.title or "Untitled"
            print(f"{chat.id} | {title}")
    finally:
        db.close()
except Exception as e:
    print(f"Error: {e}", file=sys.stderr)
    sys.exit(1)
EOF
