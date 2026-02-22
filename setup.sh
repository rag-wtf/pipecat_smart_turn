#!/bin/bash

# Check if the script is being sourced or executed
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "Error: This script must be sourced, not executed." >&2
    echo "Please run 'source setup.sh' instead." >&2
    exit 1
fi

# This script sets up the development environment for the Dart project.
# It installs the Dart SDK and other necessary dependencies.
# It is intended to be sourced, e.g., `source setup.sh`, so that
# the environment variables are set in the current shell.

set -e

echo "--- Starting Environment Setup ---"

# --- Install Dart SDK ---
echo "Installing Dart SDK..."
sudo apt-get update
sudo apt-get install -y apt-transport-https wget
wget -qO- https://dl-ssl.google.com/linux/linux_signing_key.pub | sudo apt-key add -
sudo sh -c 'wget -qO- https://storage.googleapis.com/download.dartlang.org/linux/debian/dart_stable.list > /etc/apt/sources.list.d/dart_stable.list'
sudo apt-get update
sudo apt-get install -y dart

# --- Configure Environment ---
echo "Configuring environment variables..."

# Update PATH for the current session
export PATH="$HOME/.pub-cache/bin:$PATH"
echo "Updated PATH for current session: $PATH"

# --- Persist PATH for future sessions ---
echo "Updating shell configuration for future sessions..."
BASHRC_FILE="$HOME/.bashrc"
touch "$BASHRC_FILE" # Ensure .bashrc exists

# Add Pub cache to PATH
PUB_CACHE_PATH_LINE='export PATH="$HOME/.pub-cache/bin:$PATH"'
if ! grep -qF -- "$PUB_CACHE_PATH_LINE" "$BASHRC_FILE"; then
    echo '' >> "$BASHRC_FILE"
    echo '# Add Pub cache to PATH' >> "$BASHRC_FILE"
    echo "$PUB_CACHE_PATH_LINE" >> "$BASHRC_FILE"
    echo "Added Pub cache to PATH in $BASHRC_FILE"
else
    echo "Pub cache PATH already exists in $BASHRC_FILE"
fi

echo "To apply changes, run 'source $BASHRC_FILE' or start a new terminal session."

# --- Install Dependencies ---
echo "Installing project dependencies..."

# Install very_good_cli
echo "Installing very_good_cli..."
dart pub global activate very_good_cli

# Retrieve project packages
echo "Running dart pub get..."
dart pub get

echo "--- Environment Setup Complete ---"
