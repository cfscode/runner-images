################################################################################
##  File:  Install-PowerShellModules.ps1
##  Desc:  Install modules for PowerShell
################################################################################

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

Import-Module "$env:HELPER_SCRIPTS/../tests/Helpers.psm1"

# Retry module installation to tolerate transient gallery/download corruption
# (e.g. truncated .nupkg: "End of Central Directory record could not be found").
function Install-ModuleWithRetry {
    param(
        [Parameter(Mandatory)] [hashtable] $Params,
        [int] $Retries = 5,
        [int] $Interval = 30
    )
    for ($attempt = 1; $attempt -le $Retries; $attempt++) {
        try {
            Install-Module @Params
            return
        } catch {
            if ($attempt -eq $Retries) { throw }
            Write-Warning "Install-Module $($Params.Name) failed (attempt $attempt/$Retries): $($_.Exception.Message)"
            Write-Warning "Waiting $Interval seconds before retrying..."
            Start-Sleep -Seconds $Interval
        }
    }
}

# Specifies the installation policy
Set-PSRepository -InstallationPolicy Trusted -Name PSGallery

# Try to update PowerShellGet before the actual installation
Install-Module -Name PowerShellGet -Force
Update-Module -Name PowerShellGet -Force

# Install PowerShell modules
$modules = (Get-ToolsetContent).powershellModules

foreach($module in $modules) {
    $moduleName = $module.name

    Write-Host "Installing ${moduleName} module"
    if ($module.versions) {
        foreach ($version in $module.versions) {
            Write-Host " - $version"
            Install-ModuleWithRetry -Params @{ Name = $moduleName; RequiredVersion = $version; Scope = "AllUsers"; SkipPublisherCheck = $true; Force = $true }
        }
    } else {
        Install-ModuleWithRetry -Params @{ Name = $moduleName; Scope = "AllUsers"; SkipPublisherCheck = $true; Force = $true }
    }
}

Invoke-PesterTests -TestFile "PowerShellModules" -TestName "PowerShellModules"
