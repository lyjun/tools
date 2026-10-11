#!/bin/bash

# Catppuccin Mocha Color Palette
# Reference: https://github.com/catppuccin/catppuccin

# Text colors
ROSEWATER="\033[38;2;245;224;220m"
FLAMINGO="\033[38;2;242;205;205m"
PINK="\033[38;2;245;194;231m"
MAUVE="\033[38;2;203;166;247m"
RED="\033[38;2;243;139;168m"
MAROON="\033[38;2;235;160;172m"
PEACH="\033[38;2;250;179;135m"
YELLOW="\033[38;2;249;226;175m"
GREEN="\033[38;2;166;227;161m"
TEAL="\033[38;2;148;226;213m"
SKY="\033[38;2;137;220;235m"
SAPPHIRE="\033[38;2;116;199;236m"
BLUE="\033[38;2;137;180;250m"
LAVENDER="\033[38;2;180;190;254m"

# Surface colors
TEXT="\033[38;2;205;214;244m"
SUBTEXT1="\033[38;2;186;194;222m"
SUBTEXT0="\033[38;2;166;173;200m"
OVERLAY2="\033[38;2;147;153;178m"
OVERLAY1="\033[38;2;127;132;156m"
OVERLAY0="\033[38;2;108;112;134m"
SURFACE2="\033[38;2;88;91;112m"
SURFACE1="\033[38;2;69;71;90m"
SURFACE0="\033[38;2;49;50;68m"

RESET="\033[0m"
BOLD="\033[1m"
DIM="\033[2m"

# Get directory with Fish-style path shortening
# Replace home directory with ~
dir="${PWD/#$HOME/~}"

# Apply Fish-style shortening: shorten all components except the last
IFS='/' read -ra parts <<< "$dir"
shortened_parts=()

for i in "${!parts[@]}"; do
    part="${parts[$i]}"

    # Skip empty parts (from leading /)
    if [[ -z "$part" ]]; then
        shortened_parts+=("")
        continue
    fi

    # Keep ~ as-is
    if [[ "$part" == "~" ]]; then
        shortened_parts+=("~")
        continue
    fi

    # Keep the last part in full
    if [[ $i -eq $((${#parts[@]} - 1)) ]]; then
        shortened_parts+=("$part")
    else
        # Shorten middle parts to first character
        shortened_parts+=("${part:0:1}")
    fi
done

# Reconstruct the path
dir=$(IFS=/; echo "${shortened_parts[*]}")

# Get git info
git_info=""
if git rev-parse --git-dir > /dev/null 2>&1; then
    branch=$(git branch --show-current 2>/dev/null || echo "detached")

    # Count staged, modified, untracked files
    staged=$(git diff --cached --name-only 2>/dev/null | wc -l | tr -d ' ')
    modified=$(git diff --name-only 2>/dev/null | wc -l | tr -d ' ')
    untracked=$(git ls-files --others --exclude-standard 2>/dev/null | wc -l | tr -d ' ')

    git_status=""
    [[ $staged -gt 0 ]] && git_status="${git_status}+${staged}"
    [[ $modified -gt 0 ]] && git_status="${git_status}~${modified}"
    [[ $untracked -gt 0 ]] && git_status="${git_status}?${untracked}"

    if [[ -n "$git_status" ]]; then
        git_info=" ${GREEN}${branch}${RESET} ${YELLOW}[${git_status}]${RESET}"
    else
        git_info=" ${GREEN}${branch}${RESET}"
    fi
fi

# Get subscription plan (cached for 24 hours, cleared on reboot via /tmp)
PLAN_CACHE="/tmp/claude-statusline-plan-cache"
PLAN_CACHE_MAX_AGE=86400
plan_display=""
if [[ ! -f "$PLAN_CACHE" ]] || [[ $(($(date +%s) - $(stat -f %m "$PLAN_CACHE" 2>/dev/null || echo 0))) -gt $PLAN_CACHE_MAX_AGE ]]; then
    plan_type=$(claude auth status 2>/dev/null | jq -r '.subscriptionType // ""' 2>/dev/null)
    if [[ -n "$plan_type" ]]; then
        plan_display="$(echo "$plan_type" | awk '{print toupper(substr($0,1,1)) substr($0,2)}')"
        echo "$plan_display" > "$PLAN_CACHE"
    fi
else
    plan_display=$(cat "$PLAN_CACHE")
fi

# Read JSON input from stdin
input=$(cat)

# Detect git worktree (linked worktree has separate .git file, not directory)
worktree_indicator=""
if git rev-parse --git-dir 2>/dev/null | grep -q '\.git/worktrees/'; then
    worktree_indicator=" ${MAUVE}[wt]${RESET}"
fi

# Get model name from JSON
model=$(echo "$input" | jq -r '.model.id // "unknown"')
case "$model" in
    *opus*)   model_display="opus";   model_color="$RED"    ;;
    *sonnet*) model_display="sonnet"; model_color="$GREEN"  ;;
    *haiku*)  model_display="haiku";  model_color="$TEAL"   ;;
    *fable*)  model_display="fable";  model_color="$MAUVE"  ;;
    *)        model_display="$model"; model_color="$PEACH"  ;;
esac

# Extract version (e.g. claude-opus-4-7[1m] -> 4.7) and append to display
model_version=$(echo "$model" | sed -nE 's/.*(opus|sonnet|haiku)-([0-9]+)-([0-9]+).*/\2.\3/p')
# Fable uses a single-number version (e.g. claude-fable-5 -> 5)
[[ -z "$model_version" ]] && model_version=$(echo "$model" | sed -nE 's/.*fable-([0-9]+).*/\1/p')
if [[ -n "$model_version" && "$model_display" != "$model" ]]; then
    model_display="${model_display} ${model_version}"
fi

# Get output style from JSON
output_style_name=$(echo "$input" | jq -r '.output_style.name // "default"')
output_style=""
if [[ -n "$output_style_name" && "$output_style_name" != "default" && "$output_style_name" != "auto" ]]; then
    output_style=" ${BLUE}[${output_style_name}]${RESET}"
fi

# Get think mode status from JSON
think_mode=$(echo "$input" | jq -r '.thinking.enabled // false')
think_indicator=""
if [[ "$think_mode" == "true" ]]; then
    think_indicator=" ${LAVENDER}💭${RESET}"
fi

# Get effort level: session value from stdin JSON, falling back to persisted settings
effort=$(echo "$input" | jq -r '.effort.level // ""')
if [[ -z "$effort" && "$model" != *"haiku"* ]]; then
    effort=$(jq -r '.effortLevel // ""' ~/.claude/settings.json 2>/dev/null)
fi
effort_display=""
if [[ -n "$effort" ]]; then
    case "$effort" in
        low|medium) effort_color="$SUBTEXT0" ;;
        high) effort_color="$YELLOW" ;;
        xhigh|max) effort_color="$RED" ;;
        *) effort_color="$SUBTEXT0" ;;
    esac
    if [[ "$think_mode" == "true" ]]; then
        effort_display=" ${effort_color}(${LAVENDER}💭${effort_color} ${effort})${RESET}"
        think_indicator=""
    else
        effort_display=" ${effort_color}(${effort})${RESET}"
    fi
fi

# Get context window usage from JSON
total_input=$(echo "$input" | jq -r '.context_window.total_input_tokens // 0')
total_output=$(echo "$input" | jq -r '.context_window.total_output_tokens // 0')
window_size=$(echo "$input" | jq -r '.context_window.context_window_size // 0')
used_pct=$(echo "$input" | jq -r '.context_window.used_percentage // 0')

context_display=""
if [[ $window_size -gt 0 ]]; then
    # Round percentage to integer
    used_int=${used_pct%.*}
    [[ -z "$used_int" ]] && used_int=0

    # Calculate remaining percentage
    remaining_int=$((100 - used_int))

    # Choose color and emoji based on remaining percentage
    if [[ $remaining_int -gt 50 ]]; then
        ctx_color="$GREEN"
        battery_emoji="🔋"  # 充足
    elif [[ $remaining_int -gt 20 ]]; then
        ctx_color="$YELLOW"
        battery_emoji="🪫"  # 警告
    else
        ctx_color="$RED"
        battery_emoji="⚡"  # 危急
    fi

    context_display=" ${SUBTEXT0}|${RESET} ${ctx_color}ctx: ${remaining_int}% ${battery_emoji}${RESET}"
fi

# Get rate limits from JSON
rate_display=""
five_hour_pct=$(echo "$input" | jq -r '.rate_limits.five_hour.used_percentage // empty')
five_hour_reset=$(echo "$input" | jq -r '.rate_limits.five_hour.resets_at // empty')
seven_day_pct=$(echo "$input" | jq -r '.rate_limits.seven_day.used_percentage // empty')
seven_day_reset=$(echo "$input" | jq -r '.rate_limits.seven_day.resets_at // empty')

# Format seconds to ceiling hours (e.g. 3660s -> 2h, 60s -> 1h, 0s -> 0h)
format_hours_ceil() {
    local secs=$1
    [[ $secs -le 0 ]] && echo "0h" && return
    echo "$(( (secs + 3599) / 3600 ))h"
}

now=$(date +%s)

if [[ -n "$five_hour_pct" || -n "$seven_day_pct" ]]; then
    rate_parts=""

    if [[ -n "$five_hour_pct" ]]; then
        five_int=${five_hour_pct%.*}
        [[ -z "$five_int" ]] && five_int=0
        five_remain=$((100 - five_int))

        if [[ $five_remain -gt 50 ]]; then
            rate_5h_color="$GREEN"
        elif [[ $five_remain -gt 20 ]]; then
            rate_5h_color="$YELLOW"
        else
            rate_5h_color="$RED"
        fi

        five_secs_left=$((five_hour_reset - now))
        if [[ $five_secs_left -le 0 ]]; then
            five_countdown="↓ 0:00"
        else
            five_h=$((five_secs_left / 3600))
            five_m=$(( (five_secs_left % 3600) / 60 ))
            five_countdown=$(printf "↓ %d:%02d" "$five_h" "$five_m")
        fi
        rate_parts="${rate_5h_color}${five_countdown} ${five_remain}%${RESET}"
    fi

    if [[ -n "$seven_day_pct" ]]; then
        seven_int=${seven_day_pct%.*}
        [[ -z "$seven_int" ]] && seven_int=0
        seven_remain=$((100 - seven_int))

        if [[ $seven_remain -gt 50 ]]; then
            rate_7d_color="$GREEN"
        elif [[ $seven_remain -gt 20 ]]; then
            rate_7d_color="$YELLOW"
        else
            rate_7d_color="$RED"
        fi

        seven_secs=$((seven_day_reset - now))
        if [[ $seven_secs -ge 86400 ]]; then
            seven_countdown="↓ $(( (seven_secs + 86399) / 86400 ))d"
        else
            seven_countdown="↓ $(format_hours_ceil $seven_secs)"
        fi
        [[ -n "$rate_parts" ]] && rate_parts="${rate_parts} ${SUBTEXT0}/${RESET} "
        rate_parts="${rate_parts}${rate_7d_color}${seven_countdown} ${seven_remain}%${RESET}"
    fi

    rate_display=" ${SUBTEXT0}|${RESET} ${rate_parts}"
fi

# Get prompt cache stats from JSON (absent before the first API response of a session)
cache_display=""
cache_observed=$(echo "$input" | jq -r '.prompt_cache.caching_observed // false')
if [[ "$cache_observed" == "true" ]]; then
    cache_warm=$(echo "$input" | jq -r '.prompt_cache.warm // false')
    hit_ratio=$(echo "$input" | jq -r '.prompt_cache.hit_ratio // empty')

    if [[ "$cache_warm" != "true" ]]; then
        # Cold cache: the next turn re-sends the whole prompt, so flag it over the ratio.
        # last_miss_cause.causes[0] names why, from a closed set; abbreviated to keep the
        # line short. unknown/likely_server_side aren't actionable, so they render bare.
        miss_cause=$(echo "$input" | jq -r '.prompt_cache.last_miss_cause.causes[0] // empty')
        case "$miss_cause" in
            system_prompt_changed) miss_short="sys"    ;;
            tools_changed)         miss_short="tools"  ;;
            model_changed)         miss_short="model"  ;;
            messages_rewritten)    miss_short="rewind" ;;
            ttl_expired_5m)        miss_short="ttl5m"  ;;
            ttl_expired_1h)        miss_short="ttl1h"  ;;
            *)                     miss_short=""       ;;
        esac
        if [[ -n "$miss_short" ]]; then
            cache_display=" ${SUBTEXT0}|${RESET} ${RED}♻ cold·${miss_short}${RESET}"
        else
            cache_display=" ${SUBTEXT0}|${RESET} ${RED}♻ cold${RESET}"
        fi
    elif [[ -n "$hit_ratio" && "$hit_ratio" != "null" ]]; then
        hit_int=$(awk -v r="$hit_ratio" 'BEGIN { printf "%d", r * 100 }')

        if [[ $hit_int -ge 80 ]]; then
            cache_color="$GREEN"
        elif [[ $hit_int -ge 50 ]]; then
            cache_color="$YELLOW"
        else
            cache_color="$RED"
        fi

        cache_display=" ${SUBTEXT0}|${RESET} ${cache_color}♻ ${hit_int}%${RESET}"
    fi
fi

# Get session cost from JSON
cost_display=""
total_cost=$(echo "$input" | jq -r '.cost.total_cost_usd // empty')
if [[ -n "$total_cost" && "$total_cost" != "null" ]]; then
    cost_fmt=$(awk -v c="$total_cost" 'BEGIN {
        if (c >= 100) printf "$%d", c
        else if (c >= 10) printf "$%.1f", c
        else printf "$%.2f", c
    }')
    cost_display=" ${SUBTEXT0}|${RESET} ${OVERLAY1}💰 ${cost_fmt}${RESET}"
fi

# Get current time (HH:MM)
current_time=$(date +"%H:%M")

# Get username
username="${USER}"

# Build user segment with plan badge
user_segment="${YELLOW}${username}${RESET}"
if [[ -n "$plan_display" ]]; then
    user_segment="${YELLOW}${username}${RESET} ${TEAL}[${plan_display}]${RESET}"
fi

# Build status line (two lines to avoid truncation)
line1="${PINK}${dir}${RESET}${git_info}${worktree_indicator}"
line2="${model_color}${model_display}${RESET}${effort_display}${output_style}${think_indicator}${context_display}${rate_display}${cache_display}${cost_display} ${SUBTEXT0}|${RESET} ${MAUVE}${current_time}${RESET} ${SUBTEXT0}|${RESET} ${user_segment}"
printf "%b\n%b\n" "$line1" "$line2"
