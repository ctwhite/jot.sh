#!/usr/bin/env bash

# --- Bash Logger & Tracer (jot::) ---
#
# A comprehensive logging and tracing library for Bash scripts using the 'jot::'
# namespace.
#
# Features:
#   - Multiple log levels (DEBUG, INFO, WARNING, ERROR, CRITICAL, FATAL)
#   - Customizable log output formats (for console and file)
#   - JSON output format for machine readability
#   - Conditional ANSI coloring for console output (uses tput)
#   - Optional 'bat' integration for richer tracebacks and xtrace output
#   - File logging (appends to a specified file)
#   - Syslog integration via `logger` command
#   - Inclusion of caller information (script, function, line number)
#   - Function definition site location (path:line) in logs
#   - Traceback generation on error or explicitly
#   - Single-frame context display
#   - Simple backtrace utility
#   - Xtrace (set -x) management with custom PS4 (and optional bat styling)
#   - Exit handler and jot::fatal function
#
# Dependencies:
#   - Bash 4.3+ (for namerefs, associative arrays, `${VAR^^}`, etc.)
#   - `tput` (for colored console output)
#   - `date`, `sed`, `realpath` (or `readlink -f` as fallback)
#   - `logger` command (for syslog integration, if used)
#   - `bat` command (optional, for enhanced tracebacks and xtrace styling)
#   - An external `clasp.bash` library providing `clasp::parse` and `clasp::set`.
#     The logger expects `clasp::parse` to handle an optspec string, populate a
#     nameref associative array for named/flag options, and a nameref indexed array
#     for positional arguments. It expects `clasp::set` to populate local variables
#     from the associative array. The `optspec` used by `jot::log` is:
#     "level:l,fmt,trace:t#f,ctx:x#f,msg#p"
#
# Configuration (Set these environment variables or define them before sourcing):
#   - JOT_USE_COLORS (true|false): Enable/disable ANSI colors. Default: true.
#   - JOT_TRACE_SHOW_SOURCE_LINE (true|false): Show source line in text tracebacks.
#     Default: true.
#   - JOT_LOG_PATH_MAX_COMPONENTS (integer): Max path components for shortened paths.
#     Default: 3.
#   - JOT_LOG_TO_CONSOLE (true|false): Log to stdout/stderr. Default: true.
#   - JOT_LOG_FILE_PATH (string): Absolute path to a log file. If set, logs are
#     appended. Default: "" (none).
#   - JOT_LOG_TEXT_FORMAT_CONSOLE (string): printf-style format for console text logs.
#     Default: "(%script%) [%timestamp%] [%level%] (%func_loc%) (%func%│%line%) %message%"
#   - JOT_LOG_TEXT_FORMAT_FILE (string): printf-style format for file text logs.
#     Default: "%timestamp% [%level%] %script%:%func%@%line% (%func_loc%): %message%"
#   - JOT_OUTPUT_FORMAT (text|json): Overall log output format. Default: "text".
#   - JOT_USE_BAT (true|false): Try to use 'bat' for richer tracebacks and xtrace.
#     Default: true.
#   - JOT_BAT_THEME_TRACE_CONTEXT (string): Bat theme for trace context.
#     Default: '1337'.
#   - JOT_BAT_THEME_TRACE_LINES (string): Bat theme for trace code lines.
#     Default: 'Dracula'.
#   - JOT_BAT_THEME_XTRACE (string): Bat theme for xtrace output.
#     Default: 'gruvbox-dark'.
#   - JOT_LOG_TO_SYSLOG (true|false): Send logs to syslog. Default: false.
#   - JOT_SYSLOG_TAG (string): Tag for syslog. Default: script name.
#   - JOT_SYSLOG_FACILITY (string): Syslog facility. Default: "user".
#   - JOT_SYSLOG_LEVEL_MAP_STRING (string): Maps logger levels to syslog priorities
#     (e.g., "ERROR=err,INFO=info").
#     Default: "CRITICAL=crit,ERROR=err,WARNING=warning,INFO=notice,DEBUG=debug"
#   - JOT_TIMESTAMP_FORMAT (string): Format string for `date`.
#     Default: "+%Y-%m-%dT%H:%M:%S".
#   - LOG_LEVEL (DEBUG|INFO|WARNING|ERROR|CRITICAL): Global log level.
#     Default: "DEBUG". (Note: LOG_LEVEL is traditional, not JOT_ prefixed)
#
# Placeholders for format strings:
#   %timestamp%, %level%, %script%, %func_loc%, %func%, %line%, %message%
# ---

# --- Configuration (Defaults) ---
JOT_USE_COLORS="${JOT_USE_COLORS:-true}"
JOT_TRACE_SHOW_SOURCE_LINE="${JOT_TRACE_SHOW_SOURCE_LINE:-true}"
JOT_LOG_PATH_MAX_COMPONENTS="${JOT_LOG_PATH_MAX_COMPONENTS:-3}"
JOT_LOG_TO_CONSOLE="${JOT_LOG_TO_CONSOLE:-true}"
JOT_LOG_FILE_PATH="${JOT_LOG_FILE_PATH:-}"
JOT_LOG_TEXT_FORMAT_CONSOLE="${JOT_LOG_TEXT_FORMAT_CONSOLE:-"(%script%) [%timestamp%] [%level%] (%func_loc%) (%func%│%line%) %message%"}"
JOT_LOG_TEXT_FORMAT_FILE="${JOT_LOG_TEXT_FORMAT_FILE:-"%timestamp% [%level%] %script%:%func%@%line% (%func_loc%): %message%"}"
JOT_OUTPUT_FORMAT="${JOT_OUTPUT_FORMAT:-text}"
JOT_USE_BAT="${JOT_USE_BAT:-true}"
JOT_BAT_THEME_TRACE_CONTEXT="${JOT_BAT_THEME_TRACE_CONTEXT:-'1337'}"
JOT_BAT_THEME_TRACE_LINES="${JOT_BAT_THEME_TRACE_LINES:-'Dracula'}"
JOT_BAT_THEME_XTRACE="${JOT_BAT_THEME_XTRACE:-'gruvbox-dark'}"
JOT_LOG_TO_SYSLOG="${JOT_LOG_TO_SYSLOG:-false}"
JOT_SYSLOG_TAG="${JOT_SYSLOG_TAG:-}" # Defaults to script name in jot::log
JOT_SYSLOG_FACILITY="${JOT_SYSLOG_FACILITY:-user}"
JOT_SYSLOG_LEVEL_MAP_STRING="${JOT_SYSLOG_LEVEL_MAP_STRING:-"CRITICAL=crit,ERROR=err,WARNING=warning,INFO=notice,DEBUG=debug"}"
JOT_TIMESTAMP_FORMAT="${JOT_TIMESTAMP_FORMAT:-+%Y-%m-%dT%H:%M:%S}"
# --- End of Configuration ---

# --- Internal Logger Helper: Path Resolution ---
_jot::resolve_path() {
  local path_to_resolve="$1"
  local resolved_path=""
  if command -v realpath &>/dev/null; then
    resolved_path=$(realpath -L "${path_to_resolve}" 2>/dev/null)
  fi
  if [[ -z "${resolved_path}" ]] && command -v readlink &>/dev/null; then
    resolved_path=$(readlink -f "${path_to_resolve}" 2>/dev/null)
  fi
  if [[ -n "${resolved_path}" ]]; then
    printf "%s" "${resolved_path}"
  else
    printf "%s" "${path_to_resolve}" # Fallback
  fi
}

# --- Internal Logger Helper: Filesystem ---
_jot::whereisfunc() {
  if [[ -z "$1" ]]; then return 1; fi
  shopt -s extdebug
  declare -F "$1"
  shopt -u extdebug
}

# --- Color Definitions ---
c_reset=$(tput sgr0 2>/dev/null)
c_bold=$(tput bold 2>/dev/null)
c_underline=$(tput smul 2>/dev/null)
c_blink=$(tput blink 2>/dev/null)
c_reverse=$(tput smso 2>/dev/null)
c_italics=$(tput sitm 2>/dev/null)
c_black=$(tput setaf 0 2>/dev/null)
c_blue=$(tput setaf 4 2>/dev/null)
c_dark_blue=$(tput setaf 33 2>/dev/null)
c_power_blue=$(tput setaf 153 2>/dev/null)
c_magenta=$(tput setaf 5 2>/dev/null)
c_orange=$(tput setaf 166 2>/dev/null)
c_purple=$(tput setaf 125 2>/dev/null)
c_red=$(tput setaf 1 2>/dev/null)
c_yellow=$(tput setaf 3 2>/dev/null)
c_lime_yellow=$(tput setaf 190 2>/dev/null)
c_green=$(tput setaf 2 2>/dev/null)
c_white=$(tput setaf 7 2>/dev/null)
c_cyan=$(tput setaf 6 2>/dev/null)
declare -A c_ansi
c_ansi=(
  ['black']="${c_black}" ['red']="${c_red}" ['green']="${c_green}"
  ['yellow']="${c_yellow}" ['lime_yellow']="${c_lime_yellow}"
  ['orange']="${c_orange}" ['blue']="${c_blue}" ['power_blue']="${c_power_blue}"
  ['dark_blue']="${c_dark_blue}" ['purple']="${c_purple}"
  ['magenta']="${c_magenta}" ['cyan']="${c_cyan}"
  ['user_cyan_37']="$(tput setaf 37 2>/dev/null)" ['white']="${c_white}"
)

# --- Internal Logger Helper: Color Formatting Utility ---
_jot::color_format() {
  local color="white"
  local bold=false underline=false blink=false italics=false
  local reverse=false
  local newline=true
  local seq
  local tput_failed=false
  [[ -z "${c_reset}" ]] && tput_failed=true
  local -a varargs=()
  while [[ $# -gt 0 ]]; do
    case ${1} in
    -c | --color)
      color="${2}"
      shift
      ;;
    -s | --seq)
      ! ${tput_failed} && seq=$(tput setaf "$2" 2>/dev/null)
      shift
      ;;
    -i | --italics) italics=true ;; -b | --bold) bold=true ;;
    -r | --reverse) reverse=true ;; -u | --underline) underline=true ;;
    -n | --no-newline) newline=false ;; --blink) blink=true ;;
    --)
      shift
      varargs+=("$@")
      break
      ;;
    -* | --*)
      echo "_jot::color_format [Error] Unknown option: ${1}" >&2
      return 1
      ;;
    *) varargs+=("${1}") ;;
    esac
    shift
  done
  local msg="${varargs[*]}"
  if ${tput_failed}; then
    echo -ne "${msg}"
    if ${newline}; then echo; fi
    return 0
  fi
  if [[ -z ${seq} ]]; then
    if [[ -v "c_ansi[${color}]" ]]; then
      seq="${c_ansi[${color}]}"
    else seq="${c_ansi['white']}"; fi
  fi
  [[ -z "${seq}" ]] && seq="${c_ansi['white']}" # Default if still empty
  [[ ${bold} == true ]] && seq="${c_bold}${seq}"
  [[ ${underline} == true ]] && seq="${c_underline}${seq}"
  [[ ${blink} == true ]] && seq="${c_blink}${seq}"
  [[ ${italics} == true ]] && seq="${c_italics}${seq}"
  [[ ${reverse} == true ]] && seq="${c_reverse}${seq}"
  seq="${seq}${msg}${c_reset}"
  echo -ne "${seq}"
  if ${newline}; then echo; fi
}

# --- Internal Logger Helper Functions ---
_jot::to_upper() { printf "%s" "${1^^}"; }
_jot::shorten_path() {
  local full_path="$1"
  local max_c="${2:-${JOT_LOG_PATH_MAX_COMPONENTS}}"
  local short_path="${full_path}"
  if [[ -n "${full_path}" ]]; then
    local temp_path="${full_path#/}"
    local -a parts=()
    local old_ifs="${IFS}"
    IFS='/' read -r -a parts <<<"${temp_path}"
    IFS="${old_ifs}"
    local num_parts=${#parts[@]}
    if [[ ${num_parts} -gt ${max_c} ]]; then
      local start_idx=$((num_parts - max_c))
      short_path=".../${parts[*]:${start_idx}}"
    fi
    if [[ "${full_path}" == /* && "${short_path}" != "..."/* && ${num_parts} -gt 0 ]]; then
      short_path="/${short_path}"
    fi
  fi
  printf "%s" "${short_path}"
}
_jot::format_log_segment() {
  local text_to_format="$1"
  shift
  if [[ "${JOT_USE_COLORS}" == true && -n "${c_reset}" ]]; then
    _jot::color_format -n "${@}" "${text_to_format}"
  else
    printf "%s" "${text_to_format}"
  fi
}
_jot::json_escape() {
  local string="$1"
  string="${string//\\/\\\\}"   # Escape backslashes first
  string="${string//\"/\\\"}"   # Escape double quotes
  string="${string//	/\\t}"     # Escape tabs
  string="${string//$'\n'/\\n}" # Escape newlines
  string="${string//$'\r'/\\r}" # Escape carriage returns
  printf "%s" "$string"
}
_jot::build_json_log_string() {
  local ts="$1" level="$2" script="$3" func="$4" line="$5" func_loc="$6" msg="$7"
  ts=$(_jot::json_escape "$ts")
  level=$(_jot::json_escape "$level")
  script=$(_jot::json_escape "$script")
  func=$(_jot::json_escape "$func")
  func_loc=$(_jot::json_escape "$func_loc")
  msg=$(_jot::json_escape "$msg")
  printf '{"timestamp":"%s","level":"%s","script":"%s","function":"%s",' \
    "${ts}" "${level}" "${script}" "${func}"
  printf '"line":%s,"func_def_loc":"%s","message":"%s"}' \
    "${line}" "${func_loc}" "${msg}" # No comma before closing brace
}

# --- Internal Trace Helper Functions ---
_jot::should_use_bat() {
  if [[ "${JOT_USE_BAT}" == true ]] && command -v bat &>/dev/null; then
    return 0 # true
  else
    return 1 # false
  fi
}
_jot::format_trace_frame() {
  local lineno="$1"
  local src_path="$2"
  local func_name="$3"
  local -i preview_window=10
  if _jot::should_use_bat; then
    local -a func_meta=()
    local func_def_start_line=""
    local is_script_or_main=false
    if [[ "${func_name}" == "(${src_path##*/})" ||
      "${func_name}" == "(main)" ||
      "${func_name}" == "<main>" ||
      "${func_name}" =~ ^\<.*\>$ ]]; then
      is_script_or_main=true
    fi
    if ! ${is_script_or_main}; then
      read -ra func_meta <<<"$(_jot::whereisfunc "${func_name}")"
      if [[ ${#func_meta[@]} -eq 3 ]]; then func_def_start_line="${func_meta[1]}"; fi
    fi
    local context_str
    local display_range_start
    if [[ -n "${func_def_start_line}" ]]; then
      context_str=$(printf 'File "%s:%s", line %s, in %s' \
        "$(_jot::shorten_path "${src_path}" 4)" \
        "${func_def_start_line}" "${lineno}" "${func_name}")
      display_range_start="${func_def_start_line}"
    else
      context_str=$(printf 'File "%s", line %s, in %s' \
        "$(_jot::shorten_path "${src_path}" 4)" "${lineno}" "${func_name}")
      display_range_start=$((lineno - preview_window))
    fi
    [[ "${display_range_start}" -lt 1 ]] && display_range_start=1
    local display_range_end="${lineno}"
    [[ "${display_range_end}" -lt "${display_range_start}" ]] &&
      display_range_end="${display_range_start}"

    local bat_context
    bat_context=$(bat --language=bash --paging=never \
      --color=always --decorations=always \
      --theme="${JOT_BAT_THEME_TRACE_CONTEXT}" --style=snip \
      <<<"${context_str}" 2>/dev/null)
    local bat_lines
    bat_lines=$(bat "${src_path}" --language=bash --paging=never \
      --color=always --decorations=always \
      --theme="${JOT_BAT_THEME_TRACE_LINES}" --style=numbers,grid,snip \
      --highlight-line="${lineno}" \
      --line-range="${display_range_start}:${display_range_end}" 2>/dev/null)
    printf "\n   %s\n%s" "${bat_context}" "${bat_lines}"
  else # Text fallback
    local frame_s_file="$(_jot::format_log_segment "File" --color "white")"
    local frame_s_src="\"$(_jot::shorten_path "${src_path}" 4)\""
    frame_s_src="$(_jot::format_log_segment "${frame_s_src}" --color "cyan")"
    local frame_s_line_lit="$(_jot::format_log_segment "line" --color "white")"
    local frame_s_lineno="$(_jot::format_log_segment "${lineno}" --color "yellow")"
    local frame_s_in="$(_jot::format_log_segment "in" --color "white")"
    local frame_s_func="$(_jot::format_log_segment "${func_name}" -b --color "green")"
    local frame_str=$(printf '  %s %s, %s %s, %s %s' \
      "${frame_s_file}" "${frame_s_src}" "${frame_s_line_lit}" \
      "${frame_s_lineno}" "${frame_s_in}" "${frame_s_func}")
    if [[ "${JOT_TRACE_SHOW_SOURCE_LINE}" == true && -r "${src_path}" ]]; then
      local src_line
      src_line=$(sed -n "${lineno}p" "${src_path}" 2>/dev/null ||
        echo "    <Source line not readable or file not found: ${src_path}>")
      frame_str+=$'\n'"    ${src_line}"
    fi
    printf "%s\n" "${frame_str}"
  fi
}

# --- Public Trace API Functions (now under jot:: namespace) ---
jot::get_formatted_callstack_string() {
  local -i skip_frames_count=${1:-0}
  local ignore_src_regex=${2:-""}
  local -i start_idx=$((1 + skip_frames_count)) # Skip this function
  local -i stack_depth=${#FUNCNAME[@]}
  local traceback_str=""
  for ((i = start_idx; i < stack_depth; i++)); do
    local func_name="${FUNCNAME[${i}]}"
    [[ -z "${func_name}" ]] && func_name="(main)"
    if [[ ${i} -eq $((stack_depth - 1)) && "${func_name}" != "(main)" ]]; then
      func_name="<${func_name}>" # Mark oldest frame
    fi
    local src_path="${BASH_SOURCE[${i}]}"
    local line_num="${BASH_LINENO[$((i - 1))]}"
    if [[ -n "${ignore_src_regex}" && "${src_path}" =~ ${ignore_src_regex} ]]; then
      continue
    fi
    traceback_str+=$(_jot::format_trace_frame "${line_num}" "${src_path}" "${func_name}")
  done
  if [[ -n "${traceback_str}" ]]; then
    local header_str="Traceback (most recent call last):"
    if _jot::should_use_bat; then
      header_str=$(bat --language=bash --paging=never --color=always \
        --decorations=always --theme="${JOT_BAT_THEME_TRACE_LINES}" \
        --style=snip <<<"${header_str}" 2>/dev/null)
      printf "\n   %s%s\n" "${header_str}" "${traceback_str}"
    else
      printf "\n%s\n%s" \
        "$(_jot::format_log_segment "${header_str}" --color "white" -b)" \
        "${traceback_str}"
    fi
  else printf ""; fi
}
jot::get_formatted_context_string() {
  local -i skip_frames_count=${1:-0}
  local ignore_src_regex=${2:-""}
  local -i target_idx=$((1 + skip_frames_count)) # Skip this function
  local context_output_str=""
  if [[ ${target_idx} -lt ${#FUNCNAME[@]} ]]; then
    local func_name="${FUNCNAME[${target_idx}]}"
    [[ -z "${func_name}" ]] && func_name="(main)"
    local src_path="${BASH_SOURCE[${target_idx}]}"
    local line_num="${BASH_LINENO[$((target_idx - 1))]}"
    if ! ([[ -n "${ignore_src_regex}" &&
      "${src_path}" =~ ${ignore_src_regex} ]]); then
      context_output_str=$(_jot::format_trace_frame "${line_num}" \
        "${src_path}" "${func_name}")
    fi
  fi
  if [[ -n "${context_output_str}" ]]; then
    local header_str="Context:"
    if _jot::should_use_bat && [[ -n "${context_output_str}" ]]; then
      header_str=$(bat --language=bash --paging=never --color=always \
        --decorations=always --theme="${JOT_BAT_THEME_TRACE_LINES}" \
        --style=snip <<<"${header_str}" 2>/dev/null)
      printf "\n   %s%s\n" "${header_str}" "${context_output_str}"
    elif [[ -n "${context_output_str}" ]]; then
      printf "\n%s\n%s" \
        "$(_jot::format_log_segment "${header_str}" --color "white" -b)" \
        "${context_output_str}"
    fi
  else printf ""; fi
}
jot::get_simple_callstack_string() {
  local -i skip_frames_count=${1:-0}
  local -i frame_idx=0
  local output_str=""
  output_str+="$(_jot::format_log_segment "Simple Backtrace (newest first):" \
    --color "white" -b)"$'\n'
  local -i actual_start_frame=$((skip_frames_count + 1)) # Skip this function
  while true; do
    local frame_info
    frame_info=$(caller "${frame_idx}" 2>/dev/null) || break
    if [[ ${frame_idx} -ge ${actual_start_frame} ]]; then
      output_str+="  ${frame_info}"$'\n'
    fi
    ((frame_idx++))
  done
  local header_only_check
  header_only_check="$(_jot::format_log_segment \
    "Simple Backtrace (newest first):" --color "white" -b)"$'\n'
  if [[ "${output_str}" == "${header_only_check}" ]]; then
    output_str="" # No frames added
  else
    output_str="${output_str%\\n}" # Trim final newline if frames were added
  fi
  printf "%s" "${output_str}"
}

# --- Logger Core API ---
jot::log() {
  if ! declare -F clasp::parse >/dev/null ||
    ! declare -F clasp::set >/dev/null; then
    printf "LOGGER ERROR: clasp::parse or clasp::set not found. Sourced?\n" >&2
    printf "FALLBACK LOG: %s %s\n" "${1#--level }" "${*:2}" >&2
    return 1
  fi
  local -r optspec="level:l,fmt,trace:t#f,ctx:x#f,msg#p"
  local -A kwargs=()
  local -a argv=()
  if ! clasp::parse "${optspec}" kwargs argv -- "${*@Q}"; then
    printf "%s\n" \
      "$(_jot::color_format -n --color "red" \
        "$0:jot::log: Failed to parse arguments.")" >&2
    return 2
  fi
  local level="${LOG_LEVEL:-DEBUG}"
  local fmt='%s'
  local trace=false
  local ctx=false
  clasp::set kwargs level fmt trace ctx
  if [[ ${#argv[@]} -eq 0 ]]; then
    printf "%s\n" \
      "$(_jot::color_format -n --color "red" \
        "$0:jot::log: Log message required.")" >&2
    return 1
  fi

  local -i srclen=${#BASH_SOURCE[@]}
  local -i calling_ctx_idx=0
  local logger_script_path
  logger_script_path=$(_jot::resolve_path "${BASH_SOURCE[0]}")
  for ((i = 0; i < srclen; i++)); do
    local src_path_iter
    src_path_iter=$(_jot::resolve_path "${BASH_SOURCE[${i}]}")
    if [[ "${src_path_iter}" != "${logger_script_path}" ]]; then
      calling_ctx_idx=${i}
      break
    fi
  done

  local raw_timestamp
  raw_timestamp=$(date "${JOT_TIMESTAMP_FORMAT}")
  local raw_uc_level
  raw_uc_level=$(_jot::to_upper "${level}")
  local raw_entry_script_name="${BASH_SOURCE[-1]##*/}"
  local raw_calling_func_name="${FUNCNAME[${calling_ctx_idx}]}"
  [[ -z "${raw_calling_func_name}" ]] &&
    raw_calling_func_name="(${BASH_SOURCE[${calling_ctx_idx}]##*/})"
  local raw_calling_line_no="${BASH_LINENO[$((calling_ctx_idx - 1))]}"
  local raw_func_location_str
  local -a func_meta=()
  if [[ "${raw_calling_func_name}" != "(${BASH_SOURCE[${calling_ctx_idx}]##*/})" &&
    "${raw_calling_func_name}" != "(main)" ]]; then
    read -ra func_meta <<<"$(_jot::whereisfunc "${raw_calling_func_name}")"
  fi
  if [[ ${#func_meta[@]} -eq 3 ]]; then
    local func_def_path_short
    func_def_path_short=$(_jot::shorten_path \
      "${func_meta[2]}")
    raw_func_location_str="${func_def_path_short}:${func_meta[1]}"
  else
    local calling_script_path_short # Corrected variable name
    calling_script_path_short=$(_jot::shorten_path "${BASH_SOURCE[${calling_ctx_idx}]}")
    raw_func_location_str="${calling_script_path_short}"
  fi

  local user_msg
  user_msg=$(printf "${fmt}" "${argv[*]}")
  local console_trace_ctx_output=""
  local file_trace_ctx_output=""
  local original_jot_use_colors="${JOT_USE_COLORS}"
  local original_jot_use_bat="${JOT_USE_BAT}"
  if [[ "${trace}" == true ]]; then
    console_trace_ctx_output=$(jot::trace 0)
    JOT_USE_COLORS=false
    JOT_USE_BAT=false
    file_trace_ctx_output=$(jot::trace 0)
    JOT_USE_COLORS="${original_jot_use_colors}"
    JOT_USE_BAT="${original_jot_use_bat}"
  elif [[ "${ctx}" == true ]]; then
    console_trace_ctx_output=$(jot::context 0)
    JOT_USE_COLORS=false
    JOT_USE_BAT=false
    file_trace_ctx_output=$(jot::context 0)
    JOT_USE_COLORS="${original_jot_use_colors}"
    JOT_USE_BAT="${original_jot_use_bat}"
  fi
  local console_final_msg="${user_msg}${console_trace_ctx_output}"
  local file_final_msg="${user_msg}${file_trace_ctx_output}"

  if [[ "${JOT_OUTPUT_FORMAT:-text}" == "json" ]]; then
    local json_log_string
    json_log_string=$(_jot::build_json_log_string \
      "${raw_timestamp}" "${raw_uc_level}" "${raw_entry_script_name}" \
      "${raw_calling_func_name}" "${raw_calling_line_no}" \
      "${raw_func_location_str}" "${file_final_msg}")
    if [[ "${JOT_LOG_TO_CONSOLE:-true}" == true ]]; then
      printf "%s\n" "${json_log_string}"
    fi
    if [[ -n "${JOT_LOG_FILE_PATH:-}" ]]; then
      if ! printf "%s\n" "${json_log_string}" >>"${JOT_LOG_FILE_PATH}"; then
        printf "LOGGER ERROR: JSON: Could not write to log file %s\n" \
          "${JOT_LOG_FILE_PATH}" >&2
      fi
    fi
    if [[ "${JOT_LOG_TO_SYSLOG:-false}" == true ]] &&
      command -v logger &>/dev/null; then
      local syslog_tag="${JOT_SYSLOG_TAG:-${raw_entry_script_name}}"
      local syslog_priority_keyword="notice"
      logger -t "${syslog_tag}" \
        -p "${JOT_SYSLOG_FACILITY}.${syslog_priority_keyword}" \
        -- "${json_log_string}"
    fi
    return 0
  fi

  local console_log_line=""
  if [[ "${JOT_LOG_TO_CONSOLE:-true}" == true ]]; then
    local console_format_string="${JOT_LOG_TEXT_FORMAT_CONSOLE}"
    local colored_ts="$(_jot::format_log_segment "${raw_timestamp}" --color "white" -i)"
    local -A lvl_colors=(['INFO']="green" ['DEBUG']="blue" ['WARNING']="orange"
      ['ERROR']="red" ['CRITICAL']="red")
    local lvl_color_name="${lvl_colors[${raw_uc_level}]:-white}"
    local lvl_opts=("--color" "${lvl_color_name}")
    if [[ "${raw_uc_level}" == "ERROR" || "${raw_uc_level}" == "CRITICAL" ]]; then
      lvl_opts+=("-b")
    fi
    local colored_lvl="$(_jot::format_log_segment "${raw_uc_level}" "${lvl_opts[@]}")"
    local colored_script="$(_jot::format_log_segment "${raw_entry_script_name}" \
      --color "cyan")"
    local colored_func_loc="$(_jot::format_log_segment "${raw_func_location_str}" \
      --color "magenta")"
    local colored_func="$(_jot::format_log_segment "${raw_calling_func_name}" \
      --color "white")"
    local colored_line="$(_jot::format_log_segment "${raw_calling_line_no}" \
      --color "white")"
    console_log_line="${console_format_string}"
    console_log_line="${console_log_line//\%timestamp\%/${colored_ts}}"
    console_log_line="${console_log_line//\%level\%/${colored_lvl}}"
    console_log_line="${console_log_line//\%script\%/${colored_script}}"
    console_log_line="${console_log_line//\%func_loc\%/${colored_func_loc}}"
    console_log_line="${console_log_line//\%func\%/${colored_func}}"
    console_log_line="${console_log_line//\%line\%/${colored_line}}"
    console_log_line="${console_log_line//\%message\%/${console_final_msg}}"
    printf "%s\n" "${console_log_line}"
  fi

  local file_log_line=""
  if [[ -n "${JOT_LOG_FILE_PATH:-}" ||
    "${JOT_LOG_TO_SYSLOG:-false}" == true ]]; then
    local file_format_string="${JOT_LOG_TEXT_FORMAT_FILE}"
    file_log_line="${file_format_string}"
    file_log_line="${file_log_line//\%timestamp\%/${raw_timestamp}}"
    file_log_line="${file_log_line//\%level\%/${raw_uc_level}}"
    file_log_line="${file_log_line//\%script\%/${raw_entry_script_name}}"
    file_log_line="${file_log_line//\%func_loc\%/${raw_func_location_str}}"
    file_log_line="${file_log_line//\%func\%/${raw_calling_func_name}}"
    file_log_line="${file_log_line//\%line\%/${raw_calling_line_no}}"
    file_log_line="${file_log_line//\%message\%/${file_final_msg}}"
  fi

  if [[ -n "${JOT_LOG_FILE_PATH:-}" ]]; then
    if ! printf "%s\n" "${file_log_line}" >>"${JOT_LOG_FILE_PATH}"; then
      printf "LOGGER ERROR: Text: Could not write to log file %s\n" \
        "${JOT_LOG_FILE_PATH}" >&2
    fi
  fi

  if [[ "${JOT_LOG_TO_SYSLOG:-false}" == true ]] &&
    command -v logger &>/dev/null; then
    local syslog_tag="${JOT_SYSLOG_TAG:-${raw_entry_script_name}}"
    declare -A syslog_level_map
    local OLD_IFS="$IFS"
    IFS=','
    local entry
    for entry in $JOT_SYSLOG_LEVEL_MAP_STRING; do
      IFS='=' read -r key val <<<"$entry"
      syslog_level_map["$key"]="$val"
    done
    IFS="$OLD_IFS"
    local syslog_priority_keyword="${syslog_level_map[${raw_uc_level}]:-notice}"
    logger -t "${syslog_tag}" \
      -p "${JOT_SYSLOG_FACILITY}.${syslog_priority_keyword}" \
      -- "${file_log_line}"
  fi
}

# --- Public Logger API Functions ---
jot::error() { jot::log --level "ERROR" --trace "${@}"; }
jot::warn() { jot::log --level "WARNING" --trace "${@}"; }
jot::debug() { jot::log --level "DEBUG" "${@}"; }
jot::info() { jot::log --level "INFO" "${@}"; }
jot::critical() { jot::log --level "CRITICAL" --trace "${@}"; }

jot::fatal() {
  local message="${1:-"Fatal error occurred"}"
  local exit_code="${2:-1}"
  local original_format="${JOT_OUTPUT_FORMAT}"
  local original_console="${JOT_LOG_TO_CONSOLE}"
  local original_use_bat="${JOT_USE_BAT}"
  local original_use_colors="${JOT_USE_COLORS}"
  JOT_OUTPUT_FORMAT="text"
  JOT_LOG_TO_CONSOLE=true
  JOT_USE_BAT=false
  JOT_USE_COLORS=true

  jot::log --level "CRITICAL" --trace "${message}"

  JOT_OUTPUT_FORMAT="${original_format}"
  JOT_LOG_TO_CONSOLE="${original_console}"
  JOT_USE_BAT="${original_use_bat}"
  JOT_USE_COLORS="${original_use_colors}"
  exit "${exit_code}"
}

jot::trace() {
  local -i depth_offset=${1:-0}
  local logger_script_path
  logger_script_path=$(_jot::resolve_path \
    "${BASH_SOURCE[0]}")
  jot::get_formatted_callstack_string $((1 + depth_offset)) \
    "^${logger_script_path}\$"
}
jot::context() {
  local -i depth_offset=${1:-0}
  local logger_script_path
  logger_script_path=$(_jot::resolve_path \
    "${BASH_SOURCE[0]}")
  jot::get_formatted_context_string $((1 + 1 + depth_offset)) \
    "^${logger_script_path}\$"
}

# --- Logger API: Xtrace Management ---
__jot_original_PS4_xtrace="${PS4}"
__jot_xtrace_is_active=false
__jot_original_PS4_xtrace_saved_once=false
__jot_xtrace_bat_pipe_active=false

jot::xtrace_on() {
  if [[ "${__jot_xtrace_is_active}" == true ]]; then return; fi
  if [[ "${__jot_original_PS4_xtrace_saved_once}" == false ]]; then
    __jot_original_PS4_xtrace="${PS4}"
    __jot_original_PS4_xtrace_saved_once=true
  fi
  if [[ "${JOT_USE_BAT}" == true ]] &&
    command -v bat &>/dev/null && command -v sed &>/dev/null; then
    exec 4>&2 # Save original stderr to fd 4
    # Pipe stderr through sed (filter) then bat, outputting to original stderr (fd 4)
    # shellcheck disable=SC2094
    exec 2> >(exec sed -E '/^(\+ )?(set \+[vx]|\+\s*jot::.*)$/d' |
      exec bat --paging=never --color=always \
        --theme="${JOT_BAT_THEME_XTRACE}" --language=bash \
        --decorations=always --style=plain >&4)
    PS4="" # Clear PS4; bat provides styling.
    __jot_xtrace_bat_pipe_active=true
  else
    PS4='+ [${BASH_SOURCE##*/}:${LINENO}] ${FUNCNAME[0]:+${FUNCNAME[0]}():} '
    __jot_xtrace_bat_pipe_active=false
  fi
  set -x
  __jot_xtrace_is_active=true
}
jot::xtrace_off() {
  if [[ "${__jot_xtrace_is_active}" == false ]]; then return; fi
  set +x
  if [[ "${__jot_xtrace_bat_pipe_active}" == true ]]; then
    exec 2>&4 # Restore original stderr from fd 4
    exec 4>&- # Close fd 4
    __jot_xtrace_bat_pipe_active=false
  fi
  PS4="${__jot_original_PS4_xtrace}"
  __jot_xtrace_is_active=false
}

jot::simple_backtrace() {
  local -i depth_offset=${1:-0}
  jot::get_simple_callstack_string $((1 + depth_offset))
}

jot::exit_handler() {
  local -i error_code="$?"
  [[ "${error_code}" -eq 0 ]] && return
  local original_format="${JOT_OUTPUT_FORMAT}"
  local original_colors="${JOT_USE_COLORS}"
  local original_bat="${JOT_USE_BAT}"
  JOT_OUTPUT_FORMAT="text"
  JOT_USE_COLORS=true
  JOT_USE_BAT=false

  printf "\n%s\n" "$(_jot::format_log_segment \
    "--- EXIT HANDLER (Error Code: ${error_code}) ---" --color "red" -b)" >&2
  local stderr_content=""
  if [[ -n "${stderr_log:-}" && -f "${stderr_log}" ]]; then
    stderr_content=$(tail -n 1 "${stderr_log}" 2>/dev/null)
    if [[ -n "${stderr_content}" ]]; then
      printf "Last line from %s: %s\n" \
        "$(_jot::format_log_segment "${stderr_log}" --color "yellow")" \
        "${stderr_content}" >&2
    fi
  else
    printf "%s\n" "$(_jot::format_log_segment \
      "(No stderr_log configured or found for additional error details)" \
      --color "yellow" -i)" >&2
  fi
  printf "%s\n" "$(_jot::format_log_segment "Call Stack at Exit:" \
    --color "white")" >&2
  local bt_output
  bt_output=$(jot::simple_backtrace 0)
  if [[ -n "${bt_output}" ]]; then
    printf "%s\n" "${bt_output}" >&2
  else
    printf "  %s\n" "$(_jot::format_log_segment \
      "(No backtrace available or stack too shallow)" --color "yellow" -i)" >&2
  fi
  printf "%s\n\n" "$(_jot::format_log_segment "Exiting due to error!" \
    --color "red" -b)" >&2

  JOT_OUTPUT_FORMAT="${original_format}"
  JOT_USE_COLORS="${original_colors}"
  JOT_USE_BAT="${original_bat}"
}

# --- Example Usage ---
: <<'END_OF_EXAMPLES'

# --- Prerequisite: Mock clasp::parse and clasp::set if not available ---
# For standalone testing of this logger script without a full clasp.bash,
# you can use these minimal mock functions.
# **DO NOT USE THESE MOCKS IN PRODUCTION if you have a real clasp.bash.**
if ! declare -F clasp::parse >/dev/null; then
    echo "Mocking clasp::parse for example usage." >&2
    function clasp::parse() {
        local optspec="$1"; local -n p_kwargs="$2"; local -n p_argv="$3"; shift 3
        p_kwargs=(); p_argv=()
        while [[ $# -gt 0 ]]; do
            case "$1" in
                --level) p_kwargs["level"]="$2"; shift 2 ;;
                --fmt) p_kwargs["fmt"]="$2"; shift 2 ;;
                --trace) p_kwargs["trace"]="true"; shift ;;
                --ctx) p_kwargs["ctx"]="true"; shift ;;
                *) p_argv+=("$1"); shift ;;
            esac
        done
    }
fi
if ! declare -F clasp::set >/dev/null; then
    echo "Mocking clasp::set for example usage." >&2
    function clasp::set() {
        local -n p_kwargs="$1"; shift
        for var_name in "$@"; do
            if [[ -v "p_kwargs[${var_name}]" ]]; then
                printf -v "$var_name" "%s" "${p_kwargs[${var_name}]}"
            fi
        done
    }
fi
# --- End of Mock clasp ---


# --- Example Main Function ---
function example_main() {
    echo "--- Logger Example Usage (jot:: namespace) ---"

    # 1. Basic logging levels
    jot::debug "This is a debug message. Might not show depending on LOG_LEVEL."
    jot::info "Informational message about script progress."
    jot::warn "A warning about a potential issue."
    jot::error "An error occurred (trace included by jot::error)."
    jot::critical "A critical error, but script continues (trace included)."

    # 2. Logging with trace and context
    echo -e "\n--- Trace and Context Examples ---"
    function inner_func() {
        jot::info --trace "Info message with a full trace from inner_func."
        jot::warn --ctx "Warning with context from inner_func."
    }
    function outer_func() {
        jot::debug "Entering outer_func."
        inner_func
        jot::info "Exiting outer_func."
    }
    outer_func

    # 3. File Logging (configure JOT_LOG_FILE_PATH)
    echo -e "\n--- File Logging Example ---"
    export JOT_LOG_FILE_PATH="/tmp/example_app_jot.log"
    echo "File logging enabled to: ${JOT_LOG_FILE_PATH}"
    jot::info "This message will go to console (if enabled) AND ${JOT_LOG_FILE_PATH}."
    jot::info --trace "This message with trace will also go to file (uncolored)."
    echo "Check ${JOT_LOG_FILE_PATH} for output."
    # rm -f "${JOT_LOG_FILE_PATH}" # Clean up

    # 4. JSON Output (configure JOT_OUTPUT_FORMAT)
    echo -e "\n--- JSON Output Example ---"
    export JOT_OUTPUT_FORMAT="json"
    echo "JSON output enabled."
    jot::info "This is an info message in JSON format."
    jot::error --trace "This error with trace will be in JSON."
    export JOT_OUTPUT_FORMAT="text" # Switch back
    echo "Switched back to text output."

    # 5. Syslog (configure JOT_LOG_TO_SYSLOG)
    echo -e "\n--- Syslog Example (Conceptual - check your syslog) ---"
    # export JOT_LOG_TO_SYSLOG=true
    # export JOT_SYSLOG_TAG="MyJotExampleApp"
    # jot::info "This message should go to syslog with tag MyJotExampleApp."
    # export JOT_LOG_TO_SYSLOG=false
    echo "(Syslog example commented out by default.)"

    # 6. Xtrace Management (with optional bat styling)
    echo -e "\n--- Xtrace Example ---"
    jot::xtrace_on
    echo "Xtrace is now ON. The following commands will be traced."
    local my_variable="hello world"
    echo "My variable is: ${my_variable}"
    jot::xtrace_off
    echo "Xtrace is now OFF."

    # 7. Custom Timestamp and Log Format
    echo -e "\n--- Custom Format Example ---"
    export JOT_TIMESTAMP_FORMAT="+%H:%M:%S (%Z)"
    export JOT_LOG_TEXT_FORMAT_CONSOLE="[%level% @ %timestamp%] %func%: %message%"
    jot::info "Log message with custom timestamp and format."
    # Reset to defaults
    export JOT_TIMESTAMP_FORMAT="+%Y-%m-%dT%H:%M:%S"
    export JOT_LOG_TEXT_FORMAT_CONSOLE="(%script%) [%timestamp%] [%level%] (%func_loc%) (%func%│%line%) %message%"

    # 8. Exit Handler and jot::fatal
    echo -e "\n--- Exit Handler & Fatal Example ---"
    echo "Setting up exit trap. Next, jot::fatal will be called."
    # trap jot::exit_handler EXIT

    # Test jot::fatal
    # Note: jot::fatal will exit the script. Comment out to run subsequent examples.
    # jot::fatal "This is a fatal error simulation from example_main." 33

    echo "If you see this, jot::fatal was commented out."
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    export LOG_LEVEL="${LOG_LEVEL:-DEBUG}"
    example_main
fi
END_OF_EXAMPLES
