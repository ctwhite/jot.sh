# jot Bash Logger & Tracer

**A comprehensive and highly configurable logging and tracing library for Bash scripts.**

`jot` provides a robust set of features to enhance your Bash scripts with flexible logging, detailed tracebacks, and useful debugging utilities. It aims to bring sophisticated logging capabilities, commonly found in other languages, to the Bash scripting environment.

## Features

* **Multiple Log Levels:** Supports standard levels: `DEBUG`, `INFO`, `WARNING`, `ERROR`, `CRITICAL`, and a `FATAL` level that logs and exits.
* **Customizable Output:**
  * **Text Formatting:** Define custom log line formats for both console and file outputs using placeholders (e.g., `%timestamp%`, `%level%`, `%func%`, `%message%`).
  * **JSON Output:** Switch to structured JSON logging for easy parsing and integration with log management systems.
* **Flexible Output Channels:**
  * **Console:** Logs to `stdout`/`stderr` with optional ANSI coloring.
  * **File:** Appends logs to a specified file (uncolored by default for file output).
  * **Syslog:** Integrates with the system logger via the `logger` command.
* **Rich Contextual Information:**
  * Includes timestamp, log level, script name, calling function name, and line number.
  * Displays the function definition site (file:line) for better code navigation.
* **Advanced Tracing & Debugging:**
  * **Tracebacks:** Generate detailed call stacks on error or explicitly, showing file paths, line numbers, and function names.
  * **Context Display:** Log a single stack frame to show the immediate context of a log call.
  * **`bat` Integration (Optional):** If `bat` is installed, tracebacks and context can be syntax-highlighted for enhanced readability.
  * **`xtrace` Management:** Helper functions (`jot::xtrace_on`, `jot::xtrace_off`) to manage `set -x` output, with optional `bat` styling for the trace.
* **Robust and Configurable:**
  * Graceful fallbacks if `tput` or `bat` are unavailable.
  * Configuration via environment variables (e.g., `JOT_USE_COLORS`, `JOT_LOG_FILE_PATH`, `JOT_OUTPUT_FORMAT`, `LOG_LEVEL`).
  * Customizable timestamp format, path shortening, and syslog parameters.
* **Exit Handling:** Includes an optional `jot::exit_handler` to log information on script termination due to errors.

## Dependencies

* Bash 4.3+ (for namerefs, associative arrays, `${VAR^^}`, etc.)
* `tput` (for colored console output)
* `date`, `sed`
* `realpath` (or `readlink -f` as a fallback)
* `logger` command (if syslog integration is used)
* `bat` command (optional, for enhanced tracebacks and `xtrace` styling)
* **`clasp.bash`:** An external argument parsing library providing `clasp::parse` and `clasp::set` functions. This script must be sourced before `jot.bash`.

## Quick Start

1. **Include the Libraries:**
  
    ```bash
    # Ensure clasp.bash is sourced first if it's a separate file
    # source /path/to/clasp.bash 
    source /path/to/jot.bash # This script
    ```

2. **Configure (Optional - via environment variables or directly in script):**
  
    ```bash
    export LOG_LEVEL="INFO"                         # Set the minimum log level to display
    export JOT_LOG_FILE_PATH="/var/log/myapp.log"   # Enable file logging
    export JOT_OUTPUT_FORMAT="json"                 # Output logs as JSON
    export JOT_USE_BAT=true                         # Enable bat for pretty traces if installed
    ```

3. **Use in your script:**
  
    ```bash
    #!/usr/bin/env bash

    # Source clasp.bash and jot.bash here

    my_function() {
      jot::debug "Processing item: $1"
      if [[ "$1" == "special" ]]; then
        jot::warn --ctx "Special item received, proceeding with caution."
      fi
    }

    jot::info "Script started. User: $(whoami)"
    my_function "item123"

    if some_condition_fails; then
      jot::error --trace "A critical operation failed. See trace for details."
      # Or, for unrecoverable errors:
      # jot::fatal "Unrecoverable error in critical section. Exiting." 127
    fi

    jot::info "Script finished."
    ```

## Configuration Variables

The logger's behavior can be extensively customized using environment variables (all prefixed with `JOT_`, except for the conventional `LOG_LEVEL`):

* `JOT_USE_COLORS` (true|false): Enable/disable ANSI colors. Default: `true`.
* `JOT_TRACE_SHOW_SOURCE_LINE` (true|false): Show source line in text tracebacks. Default: `true`.
* `JOT_LOG_PATH_MAX_COMPONENTS` (integer): Max path components for shortened paths. Default: `3`.
* `JOT_LOG_TO_CONSOLE` (true|false): Log to stdout/stderr. Default: `true`.
* `JOT_LOG_FILE_PATH` (string): Absolute path to a log file. Default: `""` (none).
* `JOT_LOG_TEXT_FORMAT_CONSOLE` (string): Format for console text logs.
    Default: `"(%script%) [%timestamp%] [%level%] (%func_loc%) (%func%│%line%) %message%"`
* `JOT_LOG_TEXT_FORMAT_FILE` (string): Format for file text logs.
    Default: `"%timestamp% [%level%] %script%:%func%@%line% (%func_loc%): %message%"`
* `JOT_OUTPUT_FORMAT` (text|json): Overall log output format. Default: `"text"`.
* `JOT_USE_BAT` (true|false): Use 'bat' for richer output. Default: `true`.
* `JOT_BAT_THEME_TRACE_CONTEXT` (string): Bat theme for trace context. Default: `'1337'`.
* `JOT_BAT_THEME_TRACE_LINES` (string): Bat theme for trace code lines. Default: `'Dracula'`.
* `JOT_BAT_THEME_XTRACE` (string): Bat theme for xtrace output. Default: `'gruvbox-dark'`.
* `JOT_LOG_TO_SYSLOG` (true|false): Send logs to syslog. Default: `false`.
* `JOT_SYSLOG_TAG` (string): Tag for syslog. Default: script name.
* `JOT_SYSLOG_FACILITY` (string): Syslog facility. Default: `"user"`.
* `JOT_SYSLOG_LEVEL_MAP_STRING` (string): Maps logger levels to syslog priorities.
    Default: `"CRITICAL=crit,ERROR=err,WARNING=warning,INFO=notice,DEBUG=debug"`
* `JOT_TIMESTAMP_FORMAT` (string): Format string for `date`. Default: `"+%Y-%m-%dT%H:%M:%S"`.
* `LOG_LEVEL` (DEBUG|INFO|WARNING|ERROR|CRITICAL): Global log level. Default: `"DEBUG"`.

### Format String Placeholders

* `%timestamp%`: Log timestamp
* `%level%`: Log level
* `%script%`: Name of the main entry script
* `%func_loc%`: Function definition location (path:line) or caller script path
* `%func%`: Calling function name
* `%line%`: Calling line number
* `%message%`: The log message (including trace/context if enabled)

## API Functions

* `jot::debug "message" [printf_args...]`
* `jot::info "message" [printf_args...]`
* `jot::warn "message" [printf_args...]` (includes trace by default)
* `jot::error "message" [printf_args...]` (includes trace by default)
* `jot::critical "message" [printf_args...]` (includes trace by default)
* `jot::fatal "message" [exit_code (optional, default 1)]` (logs CRITICAL with trace, then exits)
* `jot::log --level <LEVEL> [--fmt <FORMAT_STR>] [--trace] [--ctx] "message" [printf_args...]` (core logging function)
* `jot::trace [depth_offset]` (returns a formatted traceback string)
* `jot::context [depth_offset]` (returns a formatted context string)
* `jot::simple_backtrace [depth_offset]` (returns a simple `caller` based backtrace string)
* `jot::xtrace_on` / `jot::xtrace_off` (manage `set -x` output)
* `jot::exit_handler` (for use with `trap ... EXIT` or `trap ... ERR`)

## Contributing

Contributions, bug reports, and feature requests are welcome! Please feel free to open an issue or submit a pull request.
