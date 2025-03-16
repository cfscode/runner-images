#!/bin/bash
set -euo pipefail

# Description:
#   This script queries AWS for the latest AMI matching the given filter,
#   extracts the server version from the AMI name, and then runs the Packer build,
#   passing the version as a variable.

# Extract the server version from the latest matching AMI.
server_version=$(aws ec2 describe-images \
  --owners 099720109477 \
  --filters "Name=name,Values=ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*" \
  --query 'Images | sort_by(@, &CreationDate)[-1].Name' \
  --output text | sed 's/.*server-//')

echo "Found server version: ${server_version}"

# Retrieve the latest stable GitHub Runner version using the GitHub API.
# The '/latest' endpoint returns the latest non-prerelease, non-draft release.
latest_github_runner=$(curl -s https://api.github.com/repos/actions/runner/releases/latest | jq -r .tag_name)
latest_github_runner="${latest_github_runner#v}"

echo "Found GitHub Runner version: ${latest_github_runner}"

# Run the Packer build with the retrieved values.
(
  cd ./images/ubuntu/templates/
  packer_template="ubuntu-24.04.pkr.hcl"
  export PKR_VAR_server_version="${server_version}"
  export PKR_VAR_github_runner_version="${latest_github_runner}"
  packer init "$packer_template"
  packer validate "$packer_template"
  packer build "$packer_template"
)
