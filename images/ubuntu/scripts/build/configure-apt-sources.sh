#!/bin/bash -e
################################################################################
##  File:  configure-apt-sources.sh
##  Desc:  Configure apt sources with failover from the cloud provider mirror
##         (Azure or AWS EC2) to the Ubuntu archives.
################################################################################

source $HELPER_SCRIPTS/os.sh

if is_ubuntu22; then
    sources_file="/etc/apt/sources.list"
    cloud_template="/etc/cloud/templates/sources.list.ubuntu.tmpl"
else
    sources_file="/etc/apt/sources.list.d/ubuntu.sources"
    cloud_template="/etc/cloud/templates/sources.list.ubuntu.deb822.tmpl"
fi

# Detect the cloud-provided regional archive mirror already configured in the image
# (azure.archive.ubuntu.com on Azure, <region>.ec2.archive.ubuntu.com on AWS).
primary_mirror=$(grep -oiE 'http://[a-z0-9.-]*archive\.ubuntu\.com/ubuntu/?' "$sources_file" | head -n1)
primary_mirror="${primary_mirror%/}/"

touch /etc/apt/apt-mirrors.txt

printf "%s\tpriority:1\n" "$primary_mirror" | tee -a /etc/apt/apt-mirrors.txt
printf "https://archive.ubuntu.com/ubuntu/\tpriority:2\n" | tee -a /etc/apt/apt-mirrors.txt
printf "https://security.ubuntu.com/ubuntu/\tpriority:3\n" | tee -a /etc/apt/apt-mirrors.txt

sed -i "s|${primary_mirror}|mirror+file:/etc/apt/apt-mirrors.txt|" "$sources_file"

# Apt changes to survive Cloud Init
cp -f "$sources_file" "$cloud_template"
