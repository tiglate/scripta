#!/bin/bash
###############################################################################
# check_service_status.sh
#
# Script to check the status of a running Java (Spring Boot) service.
#
# Description:
#   If a PID is provided, the script checks if that process is running.
#   If a jar file name is provided, the script uses 'pgrep -f' to find a process
#   whose command line includes the jar file name.
#
#   If both options are provided, the script prioritizes the PID option.
#
#   The script validates the inputs and prints a message indicating whether the
#   service is running, along with the PID if applicable.
###############################################################################

# Function to print usage information.
print_help() {
  cat <<EOF
Usage: $0 [options]

Options:
  -p, --pid=<pid>       Specify the process ID of the service.
  -f, --file=<jar>      Specify the jar file name to locate the service process.
  -h, --help            Display this help message.

Examples:
  $0 -p 12345
  $0 --file=my-app.jar
EOF
}

# Function to check if a given process ID is running.
is_running() {
  local pid="$1"
  if kill -0 "$pid" 2>/dev/null; then
    return 0
  else
    return 1
  fi
}

# Function to validate that the provided PID is numeric.
validate_pid() {
  local pid="$1"
  if ! [[ "$pid" =~ ^[0-9]+$ ]]; then
    echo "Error: PID must be a numeric value." >&2
    exit 1
  fi
}

# Parse command-line arguments.
pid_arg=""
file_arg=""

if [[ $# -eq 0 ]]; then
  print_help
  exit 1
fi

while [[ $# -gt 0 ]]; do
  case "$1" in
    -p|--pid)
      if [[ "$1" == "--pid" ]]; then
        shift
        pid_arg="$1"
      else
        pid_arg="$2"
        shift
      fi
      ;;
    --pid=*)
      pid_arg="${1#*=}"
      ;;
    -f|--file)
      if [[ "$1" == "--file" ]]; then
        shift
        file_arg="$1"
      else
        file_arg="$2"
        shift
      fi
      ;;
    --file=*)
      file_arg="${1#*=}"
      ;;
    -h|--help)
      print_help
      exit 0
      ;;
    *)
      echo "Unknown parameter: $1" >&2
      print_help
      exit 1
      ;;
  esac
  shift
done

# If both PID and file arguments are provided, prioritize PID.
if [[ -n "$pid_arg" ]]; then
  validate_pid "$pid_arg"
  if is_running "$pid_arg"; then
    echo "Service is running with PID $pid_arg."
  else
    echo "No running process found with PID $pid_arg."
  fi
elif [[ -n "$file_arg" ]]; then
  # Attempt to find the process by searching for the jar file name.
  pid_found=$(pgrep -f "$file_arg" | head -n 1)
  if [[ -z "$pid_found" ]]; then
    echo "No running process found for jar file '$file_arg'."
    exit 1
  else
    echo "Service found for jar file '$file_arg' with PID $pid_found."
  fi
else
  echo "Error: You must provide either a PID or a jar file name." >&2
  print_help
  exit 1
fi
