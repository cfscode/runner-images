packer {
  required_plugins {
    amazon = {
      version = ">= 1.0.0"
      source  = "github.com/hashicorp/amazon"
    }
  }
}

locals {
  ami_name = var.managed_image_name != "" ? var.managed_image_name : "packer-${var.image_os}-${var.image_version}"
}

#########################
# Variable Definitions  #
#########################

# AWS-specific variables
variable "aws_region" {
  type    = string
  default = "us-west-2"
}

variable "associate_public_ip_address" {
  type    = bool
  default = true
}

variable "aws_tags" {
  type    = map(string)
  default = {}
}

# Variables common to both templates
variable "vm_size" {
  type    = string
  default = "t3.large"
}

variable "image_folder" {
  type    = string
  default = "/imagegeneration"
}

variable "helper_script_folder" {
  type    = string
  default = "/imagegeneration/helpers"
}

variable "installer_script_folder" {
  type    = string
  default = "/imagegeneration/installers"
}

variable "imagedata_file" {
  type    = string
  default = "/imagegeneration/imagedata.json"
}

variable "image_os" {
  type    = string
  default = "ubuntu24"
}

variable "image_version" {
  type    = string
  default = "dev"
}

variable "install_password" {
  type      = string
  default   = ""
  sensitive = true
}

variable "managed_image_name" {
  type    = string
  default = ""
}

#########################
# AWS Builder Section   #
#########################

source "amazon-ebs" "build_image" {
  region        = var.aws_region
  instance_type = var.vm_size
  ssh_username  = "ubuntu"

  source_ami_filter {
    filters = {
      "name"                = "ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"
      "virtualization-type" = "hvm"
    }
    owners      = ["099720109477"]
    most_recent = true
  }

  ami_name                    = local.ami_name
  ami_description             = "AMI built with Packer"
  associate_public_ip_address = var.associate_public_ip_address
  tags                        = var.aws_tags

  launch_block_device_mappings {
    device_name           = "/dev/sda1"
    volume_size           = 30
    volume_type           = "gp3"
    delete_on_termination = true
  }
}


#########################
# Build and Provision   #
#########################

build {
  sources = ["source.amazon-ebs.build_image"]

  provisioner "shell" {
    execute_command = "sudo sh -c '{{ .Vars }} {{ .Path }}'"
    inline          = [
      "mkdir ${var.image_folder}",
      "chmod 777 ${var.image_folder}"
    ]
  }

  provisioner "file" {
    destination = "${var.helper_script_folder}"
    source      = "./../scripts/helpers"
  }

  provisioner "shell" {
    execute_command = "sudo sh -c '{{ .Vars }} {{ .Path }}'"
    script          = "./../scripts/build/configure-apt-mock.sh"
  }

  provisioner "shell" {
    environment_vars = [
      "HELPER_SCRIPTS=${var.helper_script_folder}",
      "DEBIAN_FRONTEND=noninteractive",
    ]
    execute_command  = "sudo sh -c '{{ .Vars }} {{ .Path }}'"
    scripts          = [
      "./../scripts/build/install-ms-repos.sh",
      "./../scripts/build/configure-apt-sources.sh",
      "./../scripts/build/configure-apt.sh",
    ]
  }

  provisioner "shell" {
    execute_command = "sudo sh -c '{{ .Vars }} {{ .Path }}'"
    script          = "./../scripts/build/configure-limits.sh"
  }

  provisioner "file" {
    destination = "${var.installer_script_folder}"
    source      = "./../scripts/build"
  }

  provisioner "file" {
    destination = "${var.image_folder}"
    sources     = [
      "./../assets/post-gen",
      "./../scripts/tests",
    ]
  }

  provisioner "file" {
    destination = "${var.installer_script_folder}/toolset.json"
    source      = "./../toolsets/toolset-2404.json"
  }

  provisioner "shell" {
    execute_command = "sudo sh -c '{{ .Vars }} {{ .Path }}'"
    inline          = [
      "mv ${var.image_folder}/post-gen ${var.image_folder}/post-generation",
    ]
  }

  provisioner "shell" {
    environment_vars = [
      "IMAGE_VERSION=${var.image_version}",
      "IMAGEDATA_FILE=${var.imagedata_file}"
    ]
    execute_command  = "sudo sh -c '{{ .Vars }} {{ .Path }}'"
    scripts          = ["./../scripts/build/configure-image-data.sh"]
  }

  provisioner "shell" {
    environment_vars = [
      "IMAGE_VERSION=${var.image_version}",
      "IMAGE_OS=${var.image_os}",
      "HELPER_SCRIPTS=${var.helper_script_folder}"
    ]
    execute_command  = "sudo sh -c '{{ .Vars }} {{ .Path }}'"
    scripts          = ["./../scripts/build/configure-environment.sh"]
  }

  provisioner "shell" {
    environment_vars = [
      "DEBIAN_FRONTEND=noninteractive",
      "HELPER_SCRIPTS=${var.helper_script_folder}",
      "INSTALLER_SCRIPT_FOLDER=${var.installer_script_folder}"
    ]
    execute_command  = "sudo sh -c '{{ .Vars }} {{ .Path }}'"
    scripts          = ["./../scripts/build/install-apt-vital.sh"]
  }

  provisioner "shell" {
    environment_vars = [
      "HELPER_SCRIPTS=${var.helper_script_folder}",
      "INSTALLER_SCRIPT_FOLDER=${var.installer_script_folder}"
    ]
    execute_command  = "sudo sh -c '{{ .Vars }} {{ .Path }}'"
    scripts          = ["./../scripts/build/install-powershell.sh"]
  }

  provisioner "shell" {
    environment_vars = [
      "HELPER_SCRIPTS=${var.helper_script_folder}",
      "INSTALLER_SCRIPT_FOLDER=${var.installer_script_folder}"
    ]
    execute_command  = "sudo sh -c '{{ .Vars }} pwsh -f {{ .Path }}'"
    scripts          = [
      "./../scripts/build/Install-PowerShellModules.ps1",
    ]
  }

  provisioner "shell" {
    environment_vars = [
      "HELPER_SCRIPTS=${var.helper_script_folder}",
      "INSTALLER_SCRIPT_FOLDER=${var.installer_script_folder}",
      "DEBIAN_FRONTEND=noninteractive"
    ]
    execute_command  = "sudo sh -c '{{ .Vars }} {{ .Path }}'"
    scripts          = [
      "./../scripts/build/install-apt-common.sh",
      "./../scripts/build/configure-dpkg.sh",
      "./../scripts/build/install-zstd.sh",
      "./../scripts/build/install-actions-cache.sh",
      "./../scripts/build/install-runner-package.sh",
      "./../scripts/build/install-aws-tools.sh",
      "./../scripts/build/install-cmake.sh",
      "./../scripts/build/install-container-tools.sh",
      "./../scripts/build/install-git.sh",
      "./../scripts/build/install-git-lfs.sh",
      "./../scripts/build/install-github-cli.sh",
      "./../scripts/build/install-github-runner.sh",
      "./../scripts/build/install-java-tools.sh",
      "./../scripts/build/install-mysql.sh",
      "./../scripts/build/install-nvm.sh",
      "./../scripts/build/install-nodejs.sh",
      "./../scripts/build/install-ruby.sh",
      "./../scripts/build/install-yq.sh",
      "./../scripts/build/install-pypy.sh",
      "./../scripts/build/install-python.sh",
    ]
  }

  provisioner "shell" {
    environment_vars = [
      "HELPER_SCRIPTS=${var.helper_script_folder}",
      "INSTALLER_SCRIPT_FOLDER=${var.installer_script_folder}",
      "DOCKERHUB_PULL_IMAGES=NO",
    ]
    execute_command  = "sudo sh -c '{{ .Vars }} {{ .Path }}'"
    scripts          = ["./../scripts/build/install-docker.sh"]
  }

  provisioner "shell" {
    environment_vars = [
      "HELPER_SCRIPTS=${var.helper_script_folder}",
      "DEBIAN_FRONTEND=noninteractive",
      "INSTALLER_SCRIPT_FOLDER=${var.installer_script_folder}"
    ]
    execute_command  = "/bin/sh -c '{{ .Vars }} {{ .Path }}'"
    scripts          = ["./../scripts/build/install-homebrew.sh"]
  }

  provisioner "shell" {
    environment_vars = ["HELPER_SCRIPTS=${var.helper_script_folder}"]
    execute_command  = "sudo sh -c '{{ .Vars }} {{ .Path }}'"
    scripts          = ["./../scripts/build/configure-snap.sh"]
  }

  # Note: The following cleanup command was using the Azure Linux agent (waagent) to deprovision.
  # For AWS you might instead want to run a cloud-init clean or other cleanup tasks.
  provisioner "shell" {
    execute_command   = "sudo sh -c '{{ .Vars }} {{ .Path }}'"
    expect_disconnect = true
    inline            = [
      "echo 'Reboot VM'",
      "sudo reboot",
    ]
  }

  provisioner "shell" {
    execute_command     = "sudo sh -c '{{ .Vars }} {{ .Path }}'"
    pause_before        = "1m0s"
    scripts             = ["./../scripts/build/cleanup.sh"]
    start_retry_timeout = "10m"
  }

  provisioner "shell" {
    environment_vars = [
      "HELPER_SCRIPT_FOLDER=${var.helper_script_folder}",
      "INSTALLER_SCRIPT_FOLDER=${var.installer_script_folder}",
      "IMAGE_FOLDER=${var.image_folder}"
    ]
    execute_command  = "sudo sh -c '{{ .Vars }} {{ .Path }}'"
    scripts          = ["./../scripts/build/configure-system.sh"]
  }

  # Replace the Azure-specific deprovision command with an AWS-appropriate one (if needed)
  provisioner "shell" {
    execute_command = "sudo sh -c '{{ .Vars }} {{ .Path }}'"
    inline          = [
      "sleep 30",
      "sudo cloud-init clean"
    ]
  }
}
