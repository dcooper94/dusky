#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# ARCH/HYPRLAND TOUCHPAD DETECTOR (Polyglot Wrapper)
# -----------------------------------------------------------------------------
# Elite DevOps Features:
# 1. Forward Compatible: Finds the best Python (3.14+) available.
# 2. Self-Healing: Rebuilds venv if system Python upgrades break it.
# 3. Idempotent: Only installs deps if absolutely missing.
# -----------------------------------------------------------------------------

set -e

# --- CONFIGURATION ---
APP_NAME="wayclick"
CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/$APP_NAME"
MIN_PY_MAJOR=3
MIN_PY_MINOR=14

# --- HELPER: Find Best Python ---
find_python() {
    # Check specific versions first (future-proofing), then generic 'python3'
    # We look for 3.16 down to 3.14, then system default.
    for candidate in python3.16 python3.15 python3.14 python3; do
        if command -v "$candidate" &>/dev/null; then
            # Verify version meets >= 3.14 requirement
            if "$candidate" -c "import sys; sys.exit(0 if sys.version_info >= ($MIN_PY_MAJOR, $MIN_PY_MINOR) else 1)"; then
                echo "$candidate"
                return 0
            fi
        fi
    done
    return 1
}

# 1. Resolve Python Interpreter
PYTHON_BIN=$(find_python) || {
    echo "Error: No suitable Python >= ${MIN_PY_MAJOR}.${MIN_PY_MINOR} found."
    exit 1
}

# 2. Define Venv Path based on the FOUND python version
# (This prevents using a py3.14 venv with a py3.15 binary)
PY_VER_STR=$("$PYTHON_BIN" -c "import sys; print(f'{sys.version_info.major}.{sys.version_info.minor}')")
VENV_DIR="$CACHE_DIR/venv-py$PY_VER_STR"

# 3. Self-Healing Venv Check
# If venv exists but the binary inside is broken (common after Arch upgrades), nuke it.
if [ -d "$VENV_DIR" ]; then
    if ! "$VENV_DIR/bin/python" -c "import sys" &>/dev/null; then
        echo ":: System Python upgraded? Venv is broken. Rebuilding..."
        rm -rf "$VENV_DIR"
    fi
fi

# 4. Create Venv (Idempotent)
if [ ! -d "$VENV_DIR" ]; then
    echo ":: Initializing venv for $PYTHON_BIN in $VENV_DIR..."
    mkdir -p "$CACHE_DIR"
    "$PYTHON_BIN" -m venv "$VENV_DIR"
fi

# 5. Install Dependencies (Idempotent)
# Check import first. 100x faster than running pip install every time.
if ! "$VENV_DIR/bin/python" -c "import evdev" &> /dev/null; then
    echo ":: Installing 'evdev'..."
    "$VENV_DIR/bin/pip" install evdev --quiet --disable-pip-version-check
fi

# 6. Execute Payload
"$VENV_DIR/bin/python" - << 'EOF'
import evdev
import sys
import os

# ANSI Colors
GREEN = "\033[1;32m"
YELLOW = "\033[1;33m"
RED = "\033[1;31m"
RESET = "\033[0m"

try:
    # Get all devices
    devices = [evdev.InputDevice(path) for path in evdev.list_devices()]
    
    print(f"{'NAME':<40} | {'PHYS':<20} | {'TYPE GUESS'}")
    print("-" * 90)

    for dev in devices:
        caps = dev.capabilities()
        
        # EV_KEY=1, EV_ABS=3
        has_keys = 1 in caps
        has_abs = 3 in caps
        
        # Heuristic Logic
        if has_keys and has_abs:
            color = YELLOW
            guess = "TRACKPAD/TABLET"
        elif has_keys and not has_abs:
            color = RED
            guess = "KEYBOARD"
        else:
            color = GREEN
            guess = "OTHER/MOUSE"
            
        # Clean up names for display
        name = dev.name[:40]
        phys = dev.phys[:20] if dev.phys else "N/A"
        
        print(f"{color}{name:<40}{RESET} | {phys:<20} | {guess}")

except OSError as e:
    if e.errno == 13: # Permission Denied
        # Robust user detection for the error message
        import pwd
        current_user = pwd.getpwuid(os.getuid()).pw_name
        
        print(f"{RED}ERROR: Permission Denied{RESET}")
        print(f"User '{current_user}' cannot read /dev/input/ devices.")
        print(f"Run this command: {YELLOW}sudo usermod -aG input {current_user}{RESET}")
        print("Then log out and log back in.")
        sys.exit(1)
    else:
        raise e
EOF
