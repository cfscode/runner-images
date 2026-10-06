packer {
  required_plugins {
    amazon = {
      version = ">= 1.0.0"
      source  = "github.com/hashicorp/amazon"
    }
  }
}

locals {
  ts          = timestamp()
  no_dash     = replace(local.ts, "-", "")
  no_colon    = replace(local.no_dash, ":", "")
  no_t        = replace(local.no_colon, "T", "")
  no_z        = replace(local.no_t, "Z", "")
  epoch_like  = replace(local.no_z, ".", "")
  ami_name    = "runner/${var.github_runner_version}/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-${var.server_version}/${local.epoch_like}"
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

variable "server_version" {
  type    = string
}

variable "github_runner_user" {
  type    = string
  default = "runner"
}

variable "github_runner_version" {
  type    = string
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
    volume_size           = 50
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
    environment_vars = ["HELPER_SCRIPTS=${var.helper_script_folder}", "IMAGE_VERSION=${var.image_version}", "IMAGEDATA_FILE=${var.imagedata_file}"]
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
      "${path.root}/../scripts/build/install-actions-cache.sh",
      "${path.root}/../scripts/build/install-apt-common.sh",
      "${path.root}/../scripts/build/install-azcopy.sh",
      "${path.root}/../scripts/build/install-azure-cli.sh",
      "${path.root}/../scripts/build/install-azure-devops-cli.sh",
      "${path.root}/../scripts/build/install-bicep.sh",
      "${path.root}/../scripts/build/install-apache.sh",
      "${path.root}/../scripts/build/install-aws-tools.sh",
      "${path.root}/../scripts/build/install-clang.sh",
      "${path.root}/../scripts/build/install-swift.sh",
      "${path.root}/../scripts/build/install-cmake.sh",
      "${path.root}/../scripts/build/install-codeql-bundle.sh",
      "${path.root}/../scripts/build/install-awf.sh",
      "${path.root}/../scripts/build/install-container-tools.sh",
      "${path.root}/../scripts/build/install-dotnetcore-sdk.sh",
      "${path.root}/../scripts/build/install-microsoft-edge.sh",
      "${path.root}/../scripts/build/install-gcc-compilers.sh",
      "${path.root}/../scripts/build/install-firefox.sh",
      "${path.root}/../scripts/build/install-gfortran.sh",
      "${path.root}/../scripts/build/install-git.sh",
      "${path.root}/../scripts/build/install-git-lfs.sh",
      "${path.root}/../scripts/build/install-github-cli.sh",
      "${path.root}/../scripts/build/install-google-chrome.sh",
      "${path.root}/../scripts/build/install-google-cloud-cli.sh",
      "${path.root}/../scripts/build/install-haskell.sh",
      "${path.root}/../scripts/build/install-java-tools.sh",
      "${path.root}/../scripts/build/install-kubernetes-tools.sh",
      "${path.root}/../scripts/build/install-miniconda.sh",
      "${path.root}/../scripts/build/install-kotlin.sh",
      "${path.root}/../scripts/build/install-mysql.sh",
      "${path.root}/../scripts/build/install-nginx.sh",
      "${path.root}/../scripts/build/install-nvm.sh",
      "${path.root}/../scripts/build/install-nodejs.sh",
      "${path.root}/../scripts/build/install-copilot-cli.sh",
      "${path.root}/../scripts/build/install-bazel.sh",
      "${path.root}/../scripts/build/install-php.sh",
      "${path.root}/../scripts/build/install-postgresql.sh",
      "${path.root}/../scripts/build/install-pulumi.sh",
      "${path.root}/../scripts/build/install-ruby.sh",
      "${path.root}/../scripts/build/install-rust.sh",
      "${path.root}/../scripts/build/install-julia.sh",
      "${path.root}/../scripts/build/install-selenium.sh",
      "${path.root}/../scripts/build/install-packer.sh",
      "${path.root}/../scripts/build/install-vcpkg.sh",
      "${path.root}/../scripts/build/configure-dpkg.sh",
      "${path.root}/../scripts/build/install-yq.sh",
      "${path.root}/../scripts/build/install-android-sdk.sh",
      "${path.root}/../scripts/build/install-pypy.sh",
      "${path.root}/../scripts/build/install-python.sh",
      "${path.root}/../scripts/build/install-zstd.sh",
      "${path.root}/../scripts/build/install-ninja.sh"
    ]
  }

  provisioner "shell" {
    environment_vars = ["HELPER_SCRIPTS=${var.helper_script_folder}", "INSTALLER_SCRIPT_FOLDER=${var.installer_script_folder}"]
    execute_command  = "sudo sh -c '{{ .Vars }} {{ .Path }}'"
    scripts          = ["./../scripts/build/install-docker.sh"]
  }

  provisioner "shell" {
    environment_vars = [
      "HELPER_SCRIPTS=${var.helper_script_folder}",
      "DEBIAN_FRONTEND=noninteractive",
      "INSTALLER_SCRIPT_FOLDER=${var.installer_script_folder}",
    ]
    execute_command  = "/bin/sh -c '{{ .Vars }} {{ .Path }}'"
    scripts          = ["./../scripts/build/install-homebrew.sh"]
  }

  provisioner "shell" {
    environment_vars = ["HELPER_SCRIPTS=${var.helper_script_folder}"]
    execute_command  = "sudo sh -c '{{ .Vars }} {{ .Path }}'"
    scripts          = ["./../scripts/build/configure-snap.sh"]
  }

  provisioner "shell" {
    execute_command = "sudo sh -c '{{ .Vars }} {{ .Path }}'"
    script          = "${path.root}/../scripts/build/list-dpkg.sh"
  }

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
    pause_before        = "5m0s"
    scripts             = ["${path.root}/../scripts/build/cleanup.sh"]
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
    environment_vars = ["HELPER_SCRIPTS=${var.helper_script_folder}"]
    execute_command  = "sudo sh -c '{{ .Vars }} {{ .Path }}'"
    scripts          = ["${path.root}/../scripts/build/post-build-validation.sh"]
  }

  provisioner "shell" {
    execute_command = "sudo sh -c '{{ .Vars }} {{ .Path }}'"
    inline          = [
      "sleep 30",
      "sudo cloud-init clean"
    ]
  }
}
