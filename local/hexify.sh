#!/usr/bin/env bash

# usage: run  `./local/hexify.sh ./path/to/contract.cdc` from project root
#   |-> outputs the hex encoded Cadence code with imports dynamically sourced from ./flow.json

set -e

# Default network
ENV="testing"
FILE=""
SEPARATOR="none"

# Parse flags and file argument
while [[ $# -gt 0 ]]; do
  case "$1" in
    -n|--network)
      ENV="$2"
      shift 2
      ;;
    -sep|--separator)
      SEPARATOR="$2"
      shift 2
      ;;
    -*)
      echo "Unknown option: $1"
      exit 1
      ;;
    *)
      FILE="$1"
      shift
      ;;
  esac
done

if [ -z "$FILE" ]; then
  echo "Usage: $0 [--network <name>] [--separator <phrase>] <PATH_TO_FILE>"
  exit 1
fi

FLOW_JSON="./flow.json"

if [ ! -f "$FLOW_JSON" ]; then
  echo "Error: $FLOW_JSON not found"
  exit 1
fi

# Extract imported contract names from source file
IMPORTS=$(grep -oE 'import "[^"]+"' "$FILE" | sed 's/import "\(.*\)"/\1/')

# Prepare temp files
TMP_SED=$(mktemp)
TMP_MAP=$(mktemp)
TMP_MISSING=$(mktemp)

# Process each import
echo "$IMPORTS" | while read -r name; do
  # Try to find the contract in dependencies or contracts
  dep_exists=$(jq -r --arg name "$name" '.dependencies[$name] != null' "$FLOW_JSON")
  contract_exists=$(jq -r --arg name "$name" '.contracts[$name] != null' "$FLOW_JSON")

  if [ "$dep_exists" != "true" ] && [ "$contract_exists" != "true" ]; then
    echo "⚠️  Missing dependency or contract: $name" >> "$TMP_MISSING"
    continue
  fi

  # Try to get the address from dependencies first, then contracts
  address=$(jq -r --arg name "$name" --arg env "$ENV" '
    .dependencies[$name].aliases[$env] // .contracts[$name].aliases[$env] // empty
  ' "$FLOW_JSON")

  if [ -z "$address" ]; then
    echo "⚠️  No '$ENV' alias for dependency or contract: $name" >> "$TMP_MISSING"
    continue
  fi

  echo "s|import \"$name\"|import $name from 0x$address|g" >> "$TMP_SED"
  echo "$name=0x$address" >> "$TMP_MAP"
done

# Apply replacements to get processed content
PROCESSED_CONTENT=$(sed -f "$TMP_SED" "$FILE")

# Handle separator logic
if [ "$SEPARATOR" != "none" ]; then
  # Create temporary files for splitting
  TMP_CONTENT=$(mktemp)
  TMP_PARTS_DIR=$(mktemp -d)
  
  # Write processed content to temp file
  printf '%s' "$PROCESSED_CONTENT" > "$TMP_CONTENT"
  
  # Split content on separator using awk
  awk -v sep="$SEPARATOR" -v parts_dir="$TMP_PARTS_DIR" '
  BEGIN { 
    # Read entire file into a variable
    content = ""
    while ((getline line < ARGV[1]) > 0) {
      content = content line "\n"
    }
    close(ARGV[1])
    
    # Remove the trailing newline we added
    if (length(content) > 0) {
      content = substr(content, 1, length(content) - 1)
    }
    
    # Split content on separator
    n = split(content, parts, sep)
    
    # Write each part to a separate file
    for (i = 1; i <= n; i++) {
      filename = parts_dir "/part_" (i-1)
      print parts[i] > filename
      close(filename)
    }
    
    # Write the number of parts
    count_file = parts_dir "/count"
    print n > count_file
    close(count_file)
    
    exit
  }' "$TMP_CONTENT"
  
  # Read the number of parts
  if [ -f "$TMP_PARTS_DIR/count" ]; then
    part_count=$(cat "$TMP_PARTS_DIR/count")
  else
    part_count=0
  fi
  
  # Build array of hexified parts
  printf "["
  first=true
  
  for i in $(seq 0 $((part_count - 1))); do
    if [ -f "$TMP_PARTS_DIR/part_$i" ]; then
      if [ "$first" = false ]; then
        printf ","
      fi
      first=false
      
      # Hexify this part
      hex_result=$(xxd -p < "$TMP_PARTS_DIR/part_$i" | tr -d '\n')
      printf "\"%s\"" "$hex_result"
    fi
  done
  
  printf "]\n"
  
  # Clean up temp files
  rm -rf "$TMP_CONTENT" "$TMP_PARTS_DIR"
else
  # Original behavior - hexify entire content
  echo "$PROCESSED_CONTENT" | xxd -p | tr -d '\n'
  echo
fi

# Output diagnostics
if [ -s "$TMP_MAP" ]; then
  echo -e "\n\n✅ Resolved contract addresses (network: $ENV):"
  cat "$TMP_MAP"
fi

if [ -s "$TMP_MISSING" ]; then
  echo -e "\n\n⚠️  Warnings:"
  cat "$TMP_MISSING"
fi

# Clean up
rm -f "$TMP_SED" "$TMP_MAP" "$TMP_MISSING"
