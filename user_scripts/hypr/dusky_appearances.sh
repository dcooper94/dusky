#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# Dusky Appearances (v6.1 - Syntax Fix)
# -----------------------------------------------------------------------------
# Target: Arch Linux / Hyprland / UWSM
# Description: Tabbed TUI to modify hyprland appearance.conf.
# Changelog:   v6.1: Replaced invalid 'readonly -i' with 'declare -ri'.
# -----------------------------------------------------------------------------

set -euo pipefail

# --- Configuration ---
readonly CONFIG_FILE="${HOME}/.config/hypr/edit_here/source/appearance.conf"
declare -ri MAX_DISPLAY_ROWS=12
declare -ri BOX_INNER_WIDTH=64
declare -ri ITEM_START_ROW=5
declare -ri ADJUST_THRESHOLD=30

# --- ANSI Constants ---
readonly C_RESET=$'\033[0m'
readonly C_CYAN=$'\033[1;36m'
readonly C_GREEN=$'\033[1;32m'
readonly C_MAGENTA=$'\033[1;35m'
readonly C_RED=$'\033[1;31m'
readonly C_WHITE=$'\033[1;37m'
readonly C_GREY=$'\033[1;30m'
readonly C_INVERSE=$'\033[7m'
readonly CLR_EOL=$'\033[K'
readonly CLR_EOS=$'\033[J'
readonly CURSOR_HOME=$'\033[H'
readonly CURSOR_HIDE=$'\033[?25l'
readonly CURSOR_SHOW=$'\033[?25h'
readonly MOUSE_ON=$'\033[?1000h\033[?1002h\033[?1006h'
readonly MOUSE_OFF=$'\033[?1000l\033[?1002l\033[?1006l'

# --- State ---
declare -i SELECTED_ROW=0
declare -i CURRENT_TAB=0
readonly -a TABS=("Layout" "Decoration" "Blur" "Shadow" "Snap")
declare -ri TAB_COUNT=${#TABS[@]}

# Zones for mouse clicks
declare -a TAB_ZONES=()

# --- Data Structures ---
declare -A ITEM_MAP      # label -> config
declare -A VALUE_CACHE   # label -> cached value
declare -A CONFIG_CACHE  # key|block -> raw file value
declare -a TAB_ITEMS_0=() TAB_ITEMS_1=() TAB_ITEMS_2=() TAB_ITEMS_3=() TAB_ITEMS_4=()

# --- Registration ---
register() {
    local -i tab_idx=$1
    local label=$2 config=$3
    ITEM_MAP["$label"]=$config
    local -n tab_ref="TAB_ITEMS_${tab_idx}"
    tab_ref+=("$label")
}

# --- DEFINITIONS ---

# Tab 0: Layout & General
register 0 "Gaps In"            "gaps_in|int||0|100|1"
register 0 "Gaps Out"           "gaps_out|int||0|100|1"
register 0 "Gaps Workspaces"    "gaps_workspaces|int|general|0|100|1"
register 0 "Border Size"        "border_size|int||0|10|1"
register 0 "Resize on Border"   "resize_on_border|bool|general|||"
register 0 "Allow Tearing"      "allow_tearing|bool|general|||"

# Tab 1: Decoration
register 1 "Rounding"           "rounding|int||0|30|1"
register 1 "Rounding Power"     "rounding_power|float||0.0|10.0|0.1"
register 1 "Active Opacity"     "active_opacity|float||0.1|1.0|0.05"
register 1 "Inactive Opacity"   "inactive_opacity|float||0.1|1.0|0.05"
register 1 "Fullscreen Opacity" "fullscreen_opacity|float||0.1|1.0|0.05"
register 1 "Dim Inactive"       "dim_inactive|bool||||"
register 1 "Dim Strength"       "dim_strength|float||0.0|1.0|0.05"
register 1 "Dim Special"        "dim_special|float||0.0|1.0|0.05"

# Tab 2: Blur
register 2 "Blur Enabled"       "enabled|bool|blur|||"
register 2 "Blur Size"          "size|int|blur|1|20|1"
register 2 "Blur Passes"        "passes|int|blur|1|10|1"
register 2 "Blur Xray"          "xray|bool|blur|||"
register 2 "Blur Noise"         "noise|float|blur|0.0|1.0|0.01"
register 2 "Blur Contrast"      "contrast|float|blur|0.0|2.0|0.05"
register 2 "Blur Brightness"    "brightness|float|blur|0.0|2.0|0.05"
register 2 "Blur Popups"        "popups|bool|blur|||"
register 2 "Blur Vibrancy"      "vibrancy|float|blur|0.0|1.0|0.05"

# Tab 3: Shadow
register 3 "Shadow Enabled"     "enabled|bool|shadow|||"
register 3 "Shadow Range"       "range|int|shadow|0|100|1"
register 3 "Shadow Power"       "render_power|int|shadow|1|4|1"
register 3 "Shadow Sharp"       "sharp|bool|shadow|||"
register 3 "Shadow Scale"       "scale|float|shadow|0.0|1.1|0.05"
register 3 "Shadow Ignore Win"  "ignore_window|bool|shadow|||"
register 3 "Shadow Color"       "color_toggle|action|shadow|||"

# Tab 4: Snap
register 4 "Snap Enabled"       "enabled|bool|snap|||"
register 4 "Snap Window Gap"    "window_gap|int|snap|0|50|1"
register 4 "Snap Monitor Gap"   "monitor_gap|int|snap|0|50|1"
register 4 "Snap Border Overlap" "border_overlap|bool|snap|||"

# --- DEFAULTS ---
declare -A DEFAULTS=(
    ["Gaps In"]=6
    ["Gaps Out"]=12
    ["Gaps Workspaces"]=0
    ["Border Size"]=2
    ["Resize on Border"]=false
    ["Allow Tearing"]=true
    ["Rounding"]=6
    ["Rounding Power"]=6.0
    ["Active Opacity"]=1.0
    ["Inactive Opacity"]=1.0
    ["Fullscreen Opacity"]=1.0
    ["Dim Inactive"]=true
    ["Dim Strength"]=0.2
    ["Dim Special"]=0.8
    ["Blur Enabled"]=false
    ["Blur Size"]=4
    ["Blur Passes"]=2
    ["Blur Xray"]=false
    ["Blur Noise"]=0.0117
    ["Blur Contrast"]=0.8916
    ["Blur Brightness"]=0.8172
    ["Blur Popups"]=false
    ["Blur Vibrancy"]=0.1696
    ["Shadow Enabled"]=false
    ["Shadow Range"]=35
    ["Shadow Power"]=2
    ["Shadow Sharp"]=false
    ["Shadow Scale"]=1.0
    ["Shadow Ignore Win"]=true
    ["Shadow Color"]='rgba(1a1a1aee)'
    ["Snap Enabled"]=false
    ["Snap Window Gap"]=10
    ["Snap Monitor Gap"]=10
    ["Snap Border Overlap"]=false
)

# --- Helpers ---
log_err() { printf '%s[ERROR]%s %s\n' "$C_RED" "$C_RESET" "$1" >&2; }

cleanup() {
    printf '%s%s%s' "$MOUSE_OFF" "$CURSOR_SHOW" "$C_RESET"
    clear
}

# Escape special characters for sed replacement (using | as delimiter)
escape_sed_replacement() {
    local s=$1
    s=${s//\\/\\\\}  # Escape Backslash first
    s=${s//|/\\|}    # Escape the Sed Delimiter
    s=${s//&/\\&}    # Escape Ampersand
    s=${s//$'\n'/\\$'\n'} # Escape Newlines
    printf '%s' "$s"
}

trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

# --- Core Logic ---

# CACHE ENGINE: Reads the entire file once.
# Optimized to handle blocks safely.
populate_config_cache() {
    CONFIG_CACHE=()
    local key_part value_part key_name

    while IFS='=' read -r key_part value_part; do
        [[ -z "$key_part" ]] && continue
        CONFIG_CACHE["$key_part"]=$value_part
        
        # Fallback for "First Match Anywhere"
        key_name=${key_part%%|*}
        if [[ -z ${CONFIG_CACHE["$key_name|"]:-} ]]; then
            CONFIG_CACHE["$key_name|"]=$value_part
        fi
    done < <(awk '
        BEGIN { depth=0 }
        
        # Skip comment-only lines
        /^[[:space:]]*#/ { next }
        
        {
            line = $0
            sub(/#.*/, "", line) # Strip inline comments
            
            # Detect Block Opening: "block_name {"
            # Modified Regex: Allows alphanumeric, underscores, dots, colons, hyphens
            # This supports "device:mouse-name {" or "plugin:name {"
            if (match(line, /[a-zA-Z0-9_.:-]+[[:space:]]*\{/)) {
                block_start = RSTART
                block_len = RLENGTH
                block_str = substr(line, block_start, block_len)
                sub(/[[:space:]]*\{/, "", block_str) # Remove brace/spaces
                
                depth++
                block_stack[depth] = block_str
            }
            
            # Detect Key = Value
            if (line ~ /=/) {
                eq_pos = index(line, "=")
                if (eq_pos > 0) {
                    key = substr(line, 1, eq_pos - 1)
                    val = substr(line, eq_pos + 1)
                    
                    # Trim Whitespace
                    gsub(/^[[:space:]]+|[[:space:]]+$/, "", key)
                    gsub(/^[[:space:]]+|[[:space:]]+$/, "", val)
                    
                    if (key != "") {
                        current_block = (depth > 0) ? block_stack[depth] : ""
                        print key "|" current_block "=" val
                    }
                }
            }
            
            # Detect Block Closing
            # Simple brace counting, sufficient for standard configs
            n = gsub(/\}/, "}", line)
            while (n > 0 && depth > 0) {
                depth--
                n--
            }
        }
    ' "$CONFIG_FILE")
}

write_value_to_file() {
    local key=$1 new_val=$2 block=${3:-}
    local safe_val
    safe_val=$(escape_sed_replacement "$new_val")

    if [[ -n $block ]]; then
        sed --follow-symlinks -i \
            "/^[[:space:]]*${block}[[:space:]]*{/,/^[[:space:]]*}/ {
                s|^\([[:space:]]*${key}[[:space:]]*=[[:space:]]*\)[^#[:space:]]*|\1${safe_val}|
            }" "$CONFIG_FILE"
    else
        sed --follow-symlinks -i \
            "s|^\([[:space:]]*${key}[[:space:]]*=[[:space:]]*\)[^#[:space:]]*|\1${safe_val}|" \
            "$CONFIG_FILE"
    fi

    # Update Memory Cache
    CONFIG_CACHE["$key|$block"]=$new_val
    if [[ -z $block ]]; then
        CONFIG_CACHE["$key|"]=$new_val
    fi
}

load_tab_values() {
    local -n items_ref="TAB_ITEMS_${CURRENT_TAB}"
    local item key type block val

    for item in "${items_ref[@]}"; do
        IFS='|' read -r key type block _ _ _ <<< "${ITEM_MAP[$item]}"

        if [[ $key == "color_toggle" ]]; then
            val=${CONFIG_CACHE["color|shadow"]:-}
        else
            val=${CONFIG_CACHE["$key|$block"]:-}
        fi
        
        VALUE_CACHE["$item"]=${val:-unset}
    done
}

modify_value() {
    local label=$1
    local -i direction=$2
    local key type block min max step current new_val

    IFS='|' read -r key type block min max step <<< "${ITEM_MAP[$label]}"
    current=${VALUE_CACHE[$label]:-}
    [[ $current == "unset" ]] && current=""

    case $type in
        int)
            if [[ ! $current =~ ^-?[0-9]+$ ]]; then current=${min:-0}; fi
            local -i int_step=${step:-1}
            local -i int_val=$current
            # Arithmetic guard for set -e
            (( int_val += direction * int_step )) || :
            
            if [[ -n $min ]] && (( int_val < min )); then int_val=$min; fi
            if [[ -n $max ]] && (( int_val > max )); then int_val=$max; fi
            new_val=$int_val
            ;;
        float)
            if [[ ! $current =~ ^-?[0-9]*\.?[0-9]+$ ]]; then current=${min:-0.0}; fi
            new_val=$(awk -v c="$current" -v dir="$direction" -v s="${step:-0.1}" \
                          -v mn="$min" -v mx="$max" '
                BEGIN {
                    val = c + (dir * s)
                    if (mn != "" && val < mn) val = mn
                    if (mx != "" && val > mx) val = mx
                    printf "%.4g", val
                }
            ')
            ;;
        bool)
            [[ $current == "true" ]] && new_val="false" || new_val="true"
            ;;
        action)
            if [[ $key == "color_toggle" ]]; then
                key="color"
                [[ $current == *'$primary'* ]] && new_val='rgba(1a1a1aee)' || new_val='$primary'
            else
                return 0
            fi
            ;;
        *) return 0 ;;
    esac

    write_value_to_file "$key" "$new_val" "$block"
    VALUE_CACHE["$label"]=$new_val
}

set_absolute_value() {
    local label=$1 new_val=$2
    local key type block
    IFS='|' read -r key type block _ _ _ <<< "${ITEM_MAP[$label]}"
    
    [[ $key == "color_toggle" ]] && key="color"
    
    write_value_to_file "$key" "$new_val" "$block"
    VALUE_CACHE["$label"]=$new_val
}

reset_defaults() {
    local -n items_ref="TAB_ITEMS_${CURRENT_TAB}"
    local item def_val
    
    for item in "${items_ref[@]}"; do
        def_val=${DEFAULTS[$item]:-}
        [[ -n $def_val ]] && set_absolute_value "$item" "$def_val"
    done
}

# --- UI Rendering ---

draw_ui() {
    local buf=""
    local -i i current_col=3
    
    buf+="${CURSOR_HOME}"
    
    # Top Border
    buf+="${C_MAGENTA}┌"
    buf+=$(printf '─%.0s' $(seq 1 $BOX_INNER_WIDTH))
    buf+="┐${C_RESET}"$'\n'
    
    # Header - Centered with Variables
    local title="Dusky Appearances ${C_CYAN}v6.1"
    local -i title_len=22  # FIXED: Corrected length from 23 to 22
    local -i left_pad=$(( (BOX_INNER_WIDTH - title_len) / 2 ))
    local -i right_pad=$(( BOX_INNER_WIDTH - title_len - left_pad ))
    
    buf+="${C_MAGENTA}│"
    buf+=$(printf '%*s' "$left_pad" '')
    buf+="${C_WHITE}Dusky Appearances ${C_CYAN}v6.1${C_MAGENTA}"
    buf+=$(printf '%*s' "$right_pad" '')
    buf+="│${C_RESET}"$'\n'
    
    local tab_line="${C_MAGENTA}│ "
    TAB_ZONES=()
    
    for (( i = 0; i < TAB_COUNT; i++ )); do
        local name=${TABS[i]}
        local -i len=${#name}
        local -i zone_start=$current_col
        
        if (( i == CURRENT_TAB )); then
            tab_line+="${C_CYAN}${C_INVERSE} ${name} ${C_RESET}${C_MAGENTA}│ "
        else
            tab_line+="${C_GREY} ${name} ${C_MAGENTA}│ "
        fi
        
        TAB_ZONES+=("${zone_start}:$(( zone_start + len + 1 ))")
        (( current_col += len + 4 )) || :
    done
    
    # Border Alignment Fix
    local -i tab_line_len=$(( current_col - 1 ))
    local -i pad_needed=$(( BOX_INNER_WIDTH - tab_line_len + 1 ))
    
    if (( pad_needed > 0 )); then
        tab_line+=$(printf '%*s' "$pad_needed" '')
    fi
    tab_line+="${C_MAGENTA}│${C_RESET}"
    
    buf+="${tab_line}"$'\n'
    buf+="${C_MAGENTA}└"
    buf+=$(printf '─%.0s' $(seq 1 $BOX_INNER_WIDTH))
    buf+="┘${C_RESET}"$'\n'

    local -n items_ref="TAB_ITEMS_${CURRENT_TAB}"
    local -i count=${#items_ref[@]}
    local item val display

    # Clamp selection
    if (( count == 0 )); then SELECTED_ROW=0;
    elif (( SELECTED_ROW >= count )); then SELECTED_ROW=$(( count - 1 ));
    elif (( SELECTED_ROW < 0 )); then SELECTED_ROW=0; fi

    for (( i = 0; i < count; i++ )); do
        item=${items_ref[i]}
        val=${VALUE_CACHE[$item]:-unset}

        case $val in
            true)         display="${C_GREEN}ON${C_RESET}" ;;
            false)        display="${C_RED}OFF${C_RESET}" ;;
            unset)        display="${C_RED}unset${C_RESET}" ;;
            *'$primary'*) display="${C_MAGENTA}Dynamic${C_RESET}" ;;
            *)            display="${C_WHITE}${val}${C_RESET}" ;;
        esac

        if (( i == SELECTED_ROW )); then
            buf+="${C_CYAN} ➤ ${C_INVERSE}"
            buf+=$(printf '%-22s' "$item")
            buf+="${C_RESET} : ${display}${CLR_EOL}"$'\n'
        else
            buf+="   "
            buf+=$(printf ' %-22s' "$item")
            buf+=" : ${display}${CLR_EOL}"$'\n'
        fi
    done

    for (( i = count; i < MAX_DISPLAY_ROWS; i++ )); do
        buf+="${CLR_EOL}"$'\n'
    done

    buf+=$'\n'"${C_CYAN} [Tab] Category  [r] Reset  [←/→ h/l] Adjust  [↑/↓ j/k] Nav  [q] Quit${C_RESET}"$'\n'
    buf+="${C_CYAN} File: ${C_WHITE}${CONFIG_FILE}${C_RESET}${CLR_EOL}${CLR_EOS}"
    
    printf '%s' "$buf"
}

# --- Input Handling ---

navigate() {
    local -i dir=$1
    local -n items_ref="TAB_ITEMS_${CURRENT_TAB}"
    local -i count=${#items_ref[@]}
    
    (( count == 0 )) && return 0
    (( SELECTED_ROW += dir )) || :
    
    if (( SELECTED_ROW < 0 )); then SELECTED_ROW=$(( count - 1 ));
    elif (( SELECTED_ROW >= count )); then SELECTED_ROW=0; fi
}

adjust() {
    local -i dir=$1
    local -n items_ref="TAB_ITEMS_${CURRENT_TAB}"
    [[ ${#items_ref[@]} -eq 0 ]] && return 0
    modify_value "${items_ref[SELECTED_ROW]}" "$dir"
}

switch_tab() {
    local -i dir=${1:-1}
    (( CURRENT_TAB += dir )) || :
    if (( CURRENT_TAB >= TAB_COUNT )); then CURRENT_TAB=0;
    elif (( CURRENT_TAB < 0 )); then CURRENT_TAB=$(( TAB_COUNT - 1 )); fi
    SELECTED_ROW=0
    load_tab_values
    clear
}

set_tab() {
    local -i idx=$1
    if (( idx != CURRENT_TAB && idx >= 0 && idx < TAB_COUNT )); then
        CURRENT_TAB=$idx
        SELECTED_ROW=0
        load_tab_values
        clear
    fi
}

handle_mouse() {
    local input=$1
    local -i button x y i
    local type zone start end
    
    if [[ $input =~ ^\[\<([0-9]+)\;([0-9]+)\;([0-9]+)([Mm])$ ]]; then
        button=${BASH_REMATCH[1]}
        x=${BASH_REMATCH[2]}
        y=${BASH_REMATCH[3]}
        type=${BASH_REMATCH[4]}
        
        [[ $type != "M" ]] && return 0

        if (( y == 3 )); then
            for (( i = 0; i < TAB_COUNT; i++ )); do
                zone=${TAB_ZONES[i]}
                start=${zone%%:*}
                end=${zone##*:}
                if (( x >= start && x <= end )); then
                    set_tab "$i"
                    return 0
                fi
            done
        fi
        
        local -n items_ref="TAB_ITEMS_${CURRENT_TAB}"
        local -i count=${#items_ref[@]}
        
        if (( y >= ITEM_START_ROW && y < ITEM_START_ROW + count )); then
            SELECTED_ROW=$(( y - ITEM_START_ROW ))
            if (( x > ADJUST_THRESHOLD )); then
                (( button == 0 )) && adjust 1 || adjust -1
            fi
        fi
    fi
}

# --- Main ---

main() {
    # Permissions & Existence Check
    [[ ! -f $CONFIG_FILE ]] && { log_err "Config not found: $CONFIG_FILE"; exit 1; }
    [[ ! -r $CONFIG_FILE ]] && { log_err "Config not readable: $CONFIG_FILE"; exit 1; }
    [[ ! -w $CONFIG_FILE ]] && { log_err "Config not writable: $CONFIG_FILE"; exit 1; }
    
    command -v awk &>/dev/null || { log_err "Required: awk"; exit 1; }
    command -v sed &>/dev/null || { log_err "Required: sed"; exit 1; }

    populate_config_cache
    printf '%s%s' "$MOUSE_ON" "$CURSOR_HIDE"
    load_tab_values
    clear

    local key seq char
    while true; do
        draw_ui
        
        # Safe Read Loop
        if ! IFS= read -rsn1 key; then continue; fi
        
        if [[ $key == $'\x1b' ]]; then
            seq=""
            # Timeout increased to 20ms for reliability
            while IFS= read -rsn1 -t 0.02 char; do
                seq+="$char"
            done
            
            case $seq in
                '[Z')               switch_tab -1 ;;
                '[A'|'OA')          navigate -1 ;;
                '[B'|'OB')          navigate 1 ;;
                '[C'|'OC')          adjust 1 ;;
                '[D'|'OD')          adjust -1 ;;
                '['*'<'*)           handle_mouse "$seq" ;;
            esac
        else
            case $key in
                k|K)            navigate -1 ;;
                j|J)            navigate 1 ;;
                l|L)            adjust 1 ;;
                h|H)            adjust -1 ;;
                $'\t')          switch_tab 1 ;;
                r|R)            reset_defaults ;;
                q|Q|$'\x03')    break ;;
            esac
        fi
    done
}

main
