#!/bin/bash

# Script to add a message to a chat
# Usage: ./message_chat.sh -msg "message text" -id "chat_id"

CHAT_ID=""
MESSAGE=""

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -msg|--message)
            MESSAGE="$2"
            shift 2
            ;;
        -id|--id)
            CHAT_ID="$2"
            shift 2
            ;;
        -h|--help)
            echo "Usage: $0 -msg \"message text\" -id \"chat_id\""
            echo ""
            echo "Options:"
            echo "  -msg, --message TEXT    Message content to add"
            echo "  -id, --id ID           Chat ID to add message to"
            echo "  -h, --help             Show this help message"
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
    echo "Error: Chat ID is required. Use -id \"chat_id\""
    exit 1
fi

if [ -z "$MESSAGE" ]; then
    echo "Error: Message is required. Use -msg \"message text\""
    exit 1
fi

cd "$(dirname "$0")/backend" || exit 1

# Export variables for Python
export CHAT_ID
export MESSAGE

python3 << 'PYEOF'
import sys
import os
import uuid
import time

# Set minimal environment variables needed for database access
# IMPORTANT: Don't override WEBUI_SECRET_KEY - use the actual one from environment or file
# The secret key must match what the running server uses
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
            print(f"DEBUG: Loaded WEBUI_SECRET_KEY from {key_file}")
            break

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from open_webui.internal.db import SessionLocal
from open_webui.models.chats import Chat, Chats

# Get arguments from environment
chat_id = os.environ.get("CHAT_ID")
message_content = os.environ.get("MESSAGE")

try:
    # Use the Chats model methods for proper handling
    chat_model = Chats.get_chat_by_id(chat_id)
    
    if not chat_model:
        print(f"Error: Chat with ID '{chat_id}' not found", file=sys.stderr)
        sys.exit(1)
    
    # Get user_id from chat for Socket.IO event
    user_id = chat_model.user_id
    
    # Get chat data
    chat_data = chat_model.chat or {}
    history = chat_data.get("history", {})
    messages = history.get("messages", {})
    
    # Generate new message ID
    message_id = str(uuid.uuid4())
    timestamp = int(time.time())
    
    # Get the current last message (if any) to set as parent
    current_id = history.get("currentId")
    parent_id = None
    
    if current_id and current_id in messages:
        parent_id = current_id
        # Add this new message as a child of the parent
        if "childrenIds" not in messages[parent_id]:
            messages[parent_id]["childrenIds"] = []
        messages[parent_id]["childrenIds"].append(message_id)
    
    # Create the new message (can be "user" or "assistant")
    # Set role to "assistant" to make messages appear as from AI, or "user" for user messages
    message_role = os.environ.get("MESSAGE_ROLE", "user")  # Default to "user", can be set to "assistant"
    new_message = {
        "id": message_id,
        "role": message_role,
        "content": message_content,
        "parentId": parent_id,
        "childrenIds": [],
        "timestamp": timestamp,
        "done": True,  # Mark as done to prevent input from getting stuck
        "model": "Assistant 1"  # Placeholder model name for script-created messages
    }
    
    # Add message to history
    messages[message_id] = new_message
    history["messages"] = messages
    history["currentId"] = message_id
    
    # Update chat data - preserve all existing fields
    chat_data["history"] = history
    if "updated_at" not in chat_data:
        chat_data["updated_at"] = timestamp
    
    # Use the model's update method which handles sanitization properly
    updated_chat = Chats.update_chat_by_id(chat_id, chat_data)
    
    if updated_chat:
        # Emit Socket.IO events - try direct emit first (works if Redis manager is enabled)
        # If that fails, fall back to HTTP API
        try:
            import asyncio
            from open_webui.socket.main import sio, WEBSOCKET_MANAGER
            from open_webui.env import WEBSOCKET_MANAGER as ENV_WEBSOCKET_MANAGER
            
            # Check if Redis manager is enabled - if so, direct emit should work
            use_direct_emit = (WEBSOCKET_MANAGER == "redis" or ENV_WEBSOCKET_MANAGER == "redis")
            print(f"DEBUG: WEBSOCKET_MANAGER={WEBSOCKET_MANAGER}, use_direct_emit={use_direct_emit}")
            
            if use_direct_emit:
                # Try direct Socket.IO emit (works with Redis manager)
                async def emit_events():
                    await sio.emit(
                        "events",
                        {
                            "chat_id": chat_id,
                            "message_id": message_id,
                            "data": {
                                "type": "chat:tags",
                                "data": None,
                            },
                        },
                        room=f"user:{user_id}",
                    )
                    print(f"DEBUG: Direct emit - chat:tags event sent to room user:{user_id}")
                
                try:
                    loop = asyncio.get_event_loop()
                except RuntimeError:
                    loop = asyncio.new_event_loop()
                    asyncio.set_event_loop(loop)
                
                loop.run_until_complete(emit_events())
                print(f"DEBUG: Direct Socket.IO emit completed")
            else:
                # Fall back to HTTP API if Redis manager not enabled
                import requests
                from open_webui.utils.auth import create_token, decode_token
                from datetime import timedelta
                from open_webui.env import WEBUI_SECRET_KEY
                
                # Verify we have the secret key
                if not WEBUI_SECRET_KEY or WEBUI_SECRET_KEY == "":
                    print(f"DEBUG: WARNING - WEBUI_SECRET_KEY is empty, token may not work", file=sys.stderr)
                else:
                    print(f"DEBUG: WEBUI_SECRET_KEY is set (length: {len(WEBUI_SECRET_KEY)})")
                
                expires_delta = timedelta(hours=1)
                auth_token = create_token(data={"id": user_id}, expires_delta=expires_delta)
                
                # Verify token can be decoded
                decoded = decode_token(auth_token)
                if decoded and decoded.get("id") == user_id:
                    print(f"DEBUG: Token created and verified for user_id: {user_id}")
                else:
                    print(f"DEBUG: WARNING - Token verification failed", file=sys.stderr)
                
                api_base_url = os.environ.get("WEBUI_API_URL", "http://localhost:8080")
                api_endpoint = f"{api_base_url}/api/v1/chats/{chat_id}/messages/{message_id}/event"
                
                headers = {
                    "Content-Type": "application/json",
                    "Authorization": f"Bearer {auth_token}"
                }
                
                event_payload = {"type": "chat:tags", "data": {}}
                response = requests.post(api_endpoint, json=event_payload, headers=headers, timeout=5)
                
                if response.status_code == 200:
                    print(f"DEBUG: HTTP API - chat:tags event emitted successfully")
                else:
                    print(f"DEBUG: HTTP API failed (HTTP {response.status_code}): {response.text}", file=sys.stderr)
                    # Try to get more details about the error
                    try:
                        error_detail = response.json()
                        print(f"DEBUG: Error detail: {error_detail}", file=sys.stderr)
                    except:
                        print(f"DEBUG: Response text: {response.text}", file=sys.stderr)
                
        except Exception as e:
            print(f"DEBUG: Could not emit Socket.IO events: {e}", file=sys.stderr)
            import traceback
            traceback.print_exc()
        
        print(f"Message added successfully to chat '{chat_id}'")
        print(f"Message ID: {message_id}")
    else:
        print(f"Error: Failed to update chat", file=sys.stderr)
        sys.exit(1)
        
except Exception as e:
    print(f"Error: {e}", file=sys.stderr)
    import traceback
    traceback.print_exc()
    sys.exit(1)
PYEOF
