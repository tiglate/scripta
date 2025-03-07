#!/bin/bash
###############################################################################
#    _____ __             __     _____                 _         
#   / ___// /_____ ______/ /_   / ___/___  ______   __(_)_______ 
#   \__ \/ __/ __ `/ ___/ __/   \__ \/ _ \/ ___/ | / / / ___/ _ \
#  ___/ / /_/ /_/ / /  / /_    ___/ /  __/ /   | |/ / / /__/  __/
# /____/\__/\__,_/_/   \__/   /____/\___/_/    |___/_/\___/\___/ 
# 
# Generic script to start a Java application (especially Spring Boot apps).
#
# The script also checks if the jar is already running (using a PID file) and
# prints the process PID after starting the service.
###############################################################################

# Constants
readonly HEAP_DUMP_PATH="/tmp"
readonly NATIVE_LIB_PATH="/opt/mqm/java/lib64:/var/mqm/exits64"
DEFAULT_JAVA_VERSION="13"

# Global variables (used only in main, passed to functions if needed)
java_version="${DEFAULT_JAVA_VERSION}"
service_name=""
service_jar=""
service_port=""
spring_profile=""
logging_file_path=""
config_dir=""

# Print usage/help message.
print_help() {
  cat <<EOF
Usage: $0 [options]

Options:
  -j, --java=<version>         Java version to use (13 or 17). Default: ${DEFAULT_JAVA_VERSION}
  -n, --name=<service name>      Service name. Default: jar filename without .jar.
  -f, --file=<path/to/app.jar>   Path to the jar file to execute. (Mandatory)
  -p, --port=<port>              Port for Spring Boot to listen on (0-65535). Optional.
  -r, --profile=<profile>        Active Spring Boot profile [dev, test, qa, uat, prod]. Optional.
  -l, --log=<path/to/log/dir>    Directory where logs will be saved. Optional.
  -c, --config-dir=<conf_dir>    Directory for external configuration. Optional.
  -h, --help                   Show this help message.

Example:
  $0 -j 17 -n my-service -f /opt/myapp/myapp.jar -p 8080 -r prod -l /var/log/myapp -c /opt/myapp/config
EOF
}

# Function to validate the jar file exists and is readable.
validate_jar() {
  if [[ ! -f "$service_jar" ]]; then
    echo "Error: Jar file '$service_jar' does not exist."
    exit 1
  fi
  if [[ ! -r "$service_jar" ]]; then
    echo "Error: Jar file '$service_jar' is not readable."
    exit 1
  fi
}

# Function to validate port number if provided.
validate_port() {
  if [[ -n "$service_port" ]]; then
    if ! [[ "$service_port" =~ ^[0-9]+$ ]] || [ "$service_port" -lt 0 ] || [ "$service_port" -gt 65535 ]; then
      echo "Error: Port must be a numeric value between 0 and 65535."
      exit 1
    fi
  fi
}

# Function to validate Java version.
validate_java_version() {
  if ! [[ "$java_version" == "13" || "$java_version" == "17" ]]; then
    echo "Error: Java version must be 13 or 17."
    exit 1
  fi
}

# Function to validate service name.
validate_service_name() {
  # Service name must start with a letter and contain no spaces.
  if ! [[ "$service_name" =~ ^[A-Za-z][A-Za-z0-9_-]*$ ]]; then
    echo "Error: Service name must start with a letter and contain no spaces."
    exit 1
  fi
}

# Check if the service is already running using a PID file.
check_already_running() {
  local pid_file="${service_name}.pid"
  if [[ -f "$pid_file" ]]; then
    local pid
    pid=$(cat "$pid_file")
    if kill -0 "$pid" 2>/dev/null; then
      echo "Service '$service_name' is already running with PID $pid."
      exit 0
    else
      echo "Found stale PID file. Removing..."
      rm -f "$pid_file"
    fi
  fi
}

# Parse command-line arguments.
parse_args() {
  if [[ $# -eq 0 ]]; then
    print_help
    exit 1
  fi

  while [[ $# -gt 0 ]]; do
    case "$1" in
      -j|--java)
        if [[ "$1" == "--java" ]]; then
          shift
          java_version="$1"
        else
          java_version="$2"
          shift
        fi
        ;;
      --java=*)
        java_version="${1#*=}"
        ;;
      -n|--name)
        if [[ "$1" == "--name" ]]; then
          shift
          service_name="$1"
        else
          service_name="$2"
          shift
        fi
        ;;
      --name=*)
        service_name="${1#*=}"
        ;;
      -f|--file)
        if [[ "$1" == "--file" ]]; then
          shift
          service_jar="$1"
        else
          service_jar="$2"
          shift
        fi
        ;;
      --file=*)
        service_jar="${1#*=}"
        ;;
      -p|--port)
        if [[ "$1" == "--port" ]]; then
          shift
          service_port="$1"
        else
          service_port="$2"
          shift
        fi
        ;;
      --port=*)
        service_port="${1#*=}"
        ;;
      -r|--profile)
        if [[ "$1" == "--profile" ]]; then
          shift
          spring_profile="$1"
        else
          spring_profile="$2"
          shift
        fi
        ;;
      --profile=*)
        spring_profile="${1#*=}"
        ;;
      -l|--log)
        if [[ "$1" == "--log" ]]; then
          shift
          logging_file_path="$1"
        else
          logging_file_path="$2"
          shift
        fi
        ;;
      --log=*)
        logging_file_path="${1#*=}"
        ;;
      -c|--config-dir)
        if [[ "$1" == "--config-dir" ]]; then
          shift
          config_dir="$1"
        else
          config_dir="$2"
          shift
        fi
        ;;
      --config-dir=*)
        config_dir="${1#*=}"
        ;;
      -h|--help)
        print_help
        exit 0
        ;;
      *)
        echo "Unknown parameter: $1"
        print_help
        exit 1
        ;;
    esac
    shift
  done

  # Validate mandatory jar file parameter.
  if [[ -z "$service_jar" ]]; then
    echo "Error: The --file parameter is mandatory."
    print_help
    exit 1
  fi

  # Derive service name from jar if not provided.
  if [[ -z "$service_name" ]]; then
    service_name=$(basename "$service_jar" .jar)
  fi
}

# Build the Java command based on the provided arguments.
build_java_command() {
  local jvm_options="-Xms512m -Mmx2G -Djava.security.edg=file:/dev/urandom -XX:+HeapDumpOnOutOfMemoryError -XX:HeapDumpPath=${HEAP_DUMP_PATH} -Djava.library.path=${NATIVE_LIB_PATH}"
  
  # If config_dir is provided, add logging.config and spring.config.location options.
  if [[ -n "$config_dir" ]]; then
    jvm_options+=" -Dlogging.config=${config_dir}/logback.xml"
    spring_config_arg="--spring.config.location=file://${config_dir}/"
  else
    spring_config_arg=""
  fi

  # Environment variables for the Java process.
  env_vars="spring.application.name=${service_name}"
  if [[ -n "$logging_file_path" ]]; then
    env_vars+=" logging.file.path=${logging_file_path}"
  fi

  # Build Spring Boot command line parameters.
  spring_args="--spring.config.name=${service_name}"
  if [[ -n "$service_port" ]]; then
    spring_args+=" --server.port=${service_port}"
  fi
  if [[ -n "$spring_profile" ]]; then
    spring_args+=" --spring.profile.active=${spring_profile}"
  fi
  if [[ -n "$spring_config_arg" ]]; then
    spring_args+=" ${spring_config_arg}"
  fi

  # Determine JAVA_HOME based on java_version
  if [[ "$java_version" == "13" ]]; then
    # For example purposes, assume JAVA_HOME_13 is defined.
    JAVA_BIN="${JAVA_HOME_13:-/usr/lib/jvm/java-13-openjdk}/bin/java"
  elif [[ "$java_version" == "17" ]]; then
    JAVA_BIN="${JAVA_HOME_17:-/usr/lib/jvm/java-17-openjdk}/bin/java"
  else
    echo "Unsupported Java version: ${java_version}"
    exit 1
  fi

  # Final command construction.
  cmd="nohup env ${env_vars} ${JAVA_BIN} ${jvm_options} -jar \"${service_jar}\" ${spring_args} &"
  echo "$cmd"
}

# Launch the service and write the PID to a file.
launch_service() {
  local pid_file="${service_name}.pid"
  # Build the command.
  local cmd
  cmd=$(build_java_command)
  echo "Starting service with command:"
  echo "${cmd}"
  
  # Evaluate the command.
  eval "${cmd}"

  # Give the process a moment to start.
  sleep 2

  # Find the PID of the newly started process. We assume the service jar appears in the process list.
  local pid
  pid=$(pgrep -f "${service_jar}" | head -n 1)
  if [[ -z "$pid" ]]; then
    echo "Error: Failed to start service."
    exit 1
  fi

  echo "$pid" > "$pid_file"
  echo "Service '${service_name}' started with PID: $pid"
}

# Main function.
main() {
  parse_args "$@"
  validate_java_version
  validate_jar
  validate_port
  validate_service_name
  check_already_running
  launch_service
}

# Run main function.
main "$@"