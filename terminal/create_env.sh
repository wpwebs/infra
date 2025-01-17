#!/bin/bash

# Exit immediately if a command exits with a non-zero status
set -e

# Determine the virtual environment name
venv_dir=".${1:-$(basename "$(pwd)")}"

# Check if Python 3 is installed
if ! command -v python3 &> /dev/null; then
    echo "Python 3 is not installed. Please install it and try again."
    exit 1
fi

# Create the virtual environment
if [ -d "$venv_dir" ]; then
    echo "Virtual environment directory $venv_dir already exists. Using existing environment."
else
    echo "Creating a virtual environment in $venv_dir..."
    python3 -m venv "$venv_dir"
fi

# Activate the virtual environment
echo "Activating the virtual environment..."
source "$venv_dir/bin/activate"

# Upgrade pip
echo "Upgrading pip..."
python3 -m pip install --upgrade pip

# Install dependencies from requirements.txt
if [ -f "requirements.txt" ]; then
    echo "Installing dependencies from requirements.txt..."
    pip install -r requirements.txt
else
    echo "requirements.txt not found. Skipping dependency installation."
fi

# Success message
echo "Virtual environment setup is complete in $venv_dir."
echo "To activate the virtual environment, run:"
echo "source $venv_dir/bin/activate"
