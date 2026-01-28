#!/bin/bash

# Script to toggle chat input enabled/disabled state
# Usage: ./change_chat_input.sh --chat-id "chat_id" --enabled yes|no

CHAT_ID=""
ENABLED=""

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --chat-id|-id)
            CHAT_ID="$2"
            shift 2
            ;;
        --enabled|-e)
            ENABLED="$2"
            shift 2
            ;;
        -h|--help)
            echo "Usage: $0 --chat-id \"chat_id\" --enabled yes|no"
            echo ""
            echo "Options:"
            echo "  --chat-id, -id ID       Chat ID to toggle input for (required)"
            echo "  --enabled, -e yes|no   Enable (yes) or disable (no) the input (required)"
            echo "  -h, --help              Show this help message"
            echo ""
            echo "Examples:"
            echo "  $0 --chat-id \"abc123\" --enabled no"
            echo "  $0 --chat-id \"abc123\" --enabled yes"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            echo "Use -h or --help for usage information"
            exit 1
            ;;
    esac
done

# Validate required parameters
if [ -z "$CHAT_ID" ]; then
    echo "Error: Chat ID is required. Use --chat-id \"chat_id\""
    exit 1
fi

if [ -z "$ENABLED" ]; then
    echo "Error: Enabled state is required. Use --enabled yes|no"
    exit 1
fi

# Normalize enabled value
ENABLED_LOWER=$(echo "$ENABLED" | tr '[:upper:]' '[:lower:]')
if [ "$ENABLED_LOWER" = "yes" ] || [ "$ENABLED_LOWER" = "true" ] || [ "$ENABLED_LOWER" = "1" ]; then
    ENABLED_BOOL="true"
elif [ "$ENABLED_LOWER" = "no" ] || [ "$ENABLED_LOWER" = "false" ] || [ "$ENABLED_LOWER" = "0" ]; then
    ENABLED_BOOL="false"
else
    echo "Error: --enabled must be 'yes' or 'no' (got: $ENABLED)"
    exit 1
fi

cd "$(dirname "$0")/backend" || exit 1

# Export variables for Python
export CHAT_ID
export ENABLED_BOOL

python3 << 'PYEOF'
import sys
import os
import asyncio

# Set minimal environment variables needed for database access
if "WEBUI_AUTH" not in os.environ:
    os.environ["WEBUI_AUTH"] = "False"

# Load WEBUI_SECRET_KEY from file if not in environment (same as server does)
if "WEBUI_SECRET_KEY" not in os.environ or os.environ.get("WEBUI_SECRET_KEY") == "":
    from pathlib import Path
    
    # Check multiple possible locations for the key file
    script_dir = Path(os.path.dirname(os.path.abspath(__file__)))
    possible_paths = [
        script_dir / ".webui_secret_key",  # In backend directory
        script_dir.parent / ".webui_secret_key",  # In root directory
        Path.cwd() / ".webui_secret_key",  # Current working directory
        Path("/app") / ".webui_secret_key",  # Docker app directory
        Path("/app/backend") / ".webui_secret_key",  # Docker backend directory
    ]
    
    for key_file in possible_paths:
        if key_file.exists():
            os.environ["WEBUI_SECRET_KEY"] = key_file.read_text().strip()
            break

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from open_webui.internal.db import SessionLocal
from open_webui.models.chats import Chats
from open_webui.socket.main import get_event_emitter

# Get arguments from environment
chat_id = os.environ.get("CHAT_ID")
enabled = os.environ.get("ENABLED_BOOL", "true").lower() == "true"

try:
    db = SessionLocal()
    try:
        # Get chat by ID
        chat = Chats.get_chat_by_id(chat_id, db=db)
        
        if not chat:
            print(f"Error: Chat with ID '{chat_id}' not found", file=sys.stderr)
            sys.exit(1)
        
        user_id = chat.user_id
        
        # Get event emitter
        event_emitter = get_event_emitter(
            {
                "user_id": user_id,
                "chat_id": chat_id,
                "message_id": "",
            },
            update_db=False,
        )
        
        if not event_emitter:
            print(f"Error: Could not create event emitter", file=sys.stderr)
            sys.exit(1)
        
        # Emit the event
        async def emit_event():
            await event_emitter({
                "type": "chat:input:toggle",
                "data": {"enabled": enabled},
            })
        
        # Run the async function
        asyncio.run(emit_event())
        
        if enabled:
            print(f"Success: Chat input enabled for chat ID: {chat_id}")
        else:
            print(f"Success: Chat input disabled for chat ID: {chat_id}")
            
    finally:
        db.close()
except Exception as e:
    print(f"Error: {e}", file=sys.stderr)
    import traceback
    traceback.print_exc()
    sys.exit(1)
PYEOF
