#!/bin/bash -e
# install-github-runner.sh
# This script creates a "runner" user with no-password sudo privileges,
# downloads and installs GitHub Actions runner version 2.322.0,
# copies /etc/environment into the runner’s .env file so that environment variables are preserved,

RUNNER_VERSION="2.322.0"
RUNNER_USER="runner"
RUNNER_HOME="/home/$RUNNER_USER"
RUNNER_DIR="$RUNNER_HOME/actions-runner"

echo "Runner version: $RUNNER_VERSION"
echo "Runner user: $RUNNER_USER"

# 1. Create the runner user if it doesn't exist
if id "$RUNNER_USER" >/dev/null 2>&1; then
    echo "User '$RUNNER_USER' already exists."
else
    echo "Creating user '$RUNNER_USER'..."
    useradd -m -s /bin/bash "$RUNNER_USER"
fi

# 2. Add runner user to sudoers with no password (if not already present)
if ! grep -q "^${RUNNER_USER} ALL=(ALL) NOPASSWD:ALL" /etc/sudoers; then
    echo "Adding ${RUNNER_USER} to sudoers with no-password privileges..."
    echo "${RUNNER_USER} ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers
fi

# 3. Create runner directory
echo "Creating runner directory: $RUNNER_DIR..."
sudo -u "$RUNNER_USER" mkdir -p "$RUNNER_DIR"
cd "$RUNNER_DIR"

# 4. Download the runner package (if not already downloaded)
RUNNER_TARBALL="actions-runner-linux-x64-$RUNNER_VERSION.tar.gz"
if [ ! -f "$RUNNER_TARBALL" ]; then
    echo "Downloading GitHub Actions runner version $RUNNER_VERSION..."
    wget "https://github.com/actions/runner/releases/download/v$RUNNER_VERSION/$RUNNER_TARBALL"
else
    echo "Runner tarball $RUNNER_TARBALL already exists."
fi

# 5. Extract the runner package
echo "Extracting ${RUNNER_TARBALL}..."
tar xzf "$RUNNER_TARBALL"

# 6. Copy /etc/environment into runner's .env file so that environment variables persist
echo "Copying /etc/environment to $RUNNER_DIR/.env..."
sudo cp /etc/environment "$RUNNER_DIR/.env"
sudo chown $RUNNER_USER:$RUNNER_USER "$RUNNER_DIR/.env"

# 7. Adding permissions to other files

#  - Ruby hostedtoolcache
mkdir -p /opt/hostedtoolcache
chown -R $RUNNER_USER:$RUNNER_USER /opt/hostedtoolcache

#  - SSH known_hosts
KNOWN_HOSTS="$HOME/.ssh/known_hosts"
mkdir -p "$(dirname "$KNOWN_HOSTS")"
touch "$KNOWN_HOSTS"
chown $RUNNER_USER:$RUNNER_USER "$KNOWN_HOSTS"

echo "GitHub Actions self-hosted runner v$RUNNER_VERSION properly configured."
