param (
	[string]$OSVersion = "Windows-Server-2022",
	[string]$ImgPath = "c:\Install\Windows-Server-2022_x64_en.iso"
)
# Copyright 2016 Cloudbase Solutions Srl
#
#    Licensed under the Apache License, Version 2.0 (the "License"); you may
#    not use this file except in compliance with the License. You may obtain
#    a copy of the License at
#
#         http://www.apache.org/licenses/LICENSE-2.0
#
#    Unless required by applicable law or agreed to in writing, software
#    distributed under the License is distributed on an "AS IS" BASIS, WITHOUT
#    WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the
#    License for the specific language governing permissions and limitations
#    under the License.

$ErrorActionPreference = "Stop"
# Select between VHD, VHDX, QCOW2, VMDK or RAW formats.
$vDiskFormat="QCOW2"
# The Windows image file path that will be generated
$virtualDiskPath = "C:\Install\win2022std-image.$($vDiskFormat.ToLower())"
$customPkg = "C:\ImagePrep\custom_resources_path\WinSrv2022\"
$customScripts = "C:\ImagePrep\Scripts\WinSrv2019\"

if (![System.IO.File]::Exists("$($customPkg)PowerShell-core-win-x64.msi")) {
	. C:\ImagePrep\Scripts\Download-PowershellCore.ps1 -DestPath $customPkg -architecture x64 -DestName "PowerShell-core-win-x64.msi"
}

Mount-DiskImage -ImagePath $ImgPath -PassThru | Out-Null
$driveletter = (Get-DiskImage $ImgPath | Get-Volume).DriveLetter

# The wim file path is the installation image on the Windows ISO
$wimFilePath = "$($driveletter):\Sources\install.wim"


# $PWD, Get-Location
$scriptPath =Split-Path -Parent $PWD #| Split-Path
git -C $scriptPath submodule update --init
if ($LASTEXITCODE) {
	Write-Host "ERROR: Failed to update git modules."
    #throw "Failed to update git modules."
}

Write-Host "Script-Path: $scriptPath"
try {
    Join-Path -Path $scriptPath -ChildPath "\WinImageBuilder.psm1" | Remove-Module -ErrorAction SilentlyContinue
    Join-Path -Path $scriptPath -ChildPath "\Config.psm1" | Remove-Module -ErrorAction SilentlyContinue
    Join-Path -Path $scriptPath -ChildPath "\UnattendResources\ini.psm1" | Remove-Module -ErrorAction SilentlyContinue
} finally {
    Join-Path -Path $scriptPath -ChildPath "\WinImageBuilder.psm1" | Import-Module
    Join-Path -Path $scriptPath -ChildPath "\Config.psm1" | Import-Module
    Join-Path -Path $scriptPath -ChildPath "\UnattendResources\ini.psm1" | Import-Module
}

### VirtIO ISO contains all the synthetic drivers for the KVM hypervisor
$virtIOISOPath = "C:\Install\virtio-win-0.1.262.iso"
## Note(avladu): Do not use stable 0.1.126 version because of this bug https://github.com/crobinso/virtio-win-pkg-scripts/issues/10
## Note (atira): Here https://fedorapeople.org/groups/virt/virtio-win/CHANGELOG you can see the changelog for the VirtIO drivers
$virtIODownloadLink = "https://fedorapeople.org/groups/virt/virtio-win/direct-downloads/stable-virtio/virtio-win.iso"

### Download the VirtIO drivers ISO from Fedora
#(New-Object System.Net.WebClient).DownloadFile($virtIODownloadLink, $virtIOISOPath)

# Extra drivers path contains the drivers for the baremetal nodes
# Examples: Chelsio NIC Drivers, Mellanox NIC drivers, LSI SAS drivers, etc.
# The cmdlet will recursively install all the drivers from the folder and subfolders
#$extraDriversPath = "C:\drivers\"

# Every Windows ISO can contain multiple Windows flavors like Core, Standard, Datacenter
# Usually, the second image version is the Standard one
$image = (Get-WimFileImagesInfo -WimFilePath $wimFilePath)[1]
Write-Host "Selected Windows-Version: $($image)."

# The path were you want to create the config fille
$configFilePath = Join-Path $scriptPath "ImageBuilding\$($OSVersion)-config.ini"
Write-Host "Use Config: $($configFilePath)"
New-WindowsImageConfig -ConfigFilePath $configFilePath

#This is an example how to automate the image configuration file according to your needs
Set-IniFileValue -Path $configFilePath -Section "Default" -Key "wim_file_path" -Value $wimFilePath
Set-IniFileValue -Path $configFilePath -Section "Default" -Key "image_name" -Value $image.ImageName
Set-IniFileValue -Path $configFilePath -Section "Default" -Key "image_path" -Value $virtualDiskPath
Set-IniFileValue -Path $configFilePath -Section "Default" -Key "virtual_disk_format" -Value $vDiskFormat
Set-IniFileValue -Path $configFilePath -Section "Default" -Key "image_type" -Value "KVM"
Set-IniFileValue -Path $configFilePath -Section "Default" -Key "disk_layout" -Value "UEFI"
Set-IniFileValue -Path $configFilePath -Section "Default" -Key "product_key" -Value "default_kms_key"
Set-IniFileValue -Path $configFilePath -Section "Default" -Key "shrink_image_to_minimum_size" -Value "True"
Set-IniFileValue -Path $configFilePath -Section "Default" -Key "enable_ping_requests" -Value "True"
Set-IniFileValue -Path $configFilePath -Section "Default" -Key "enable_active_mode" -Value "True"
# For SSH-Server see C:\ImagePrep\Scripts\WinSrv2019\RunBeforeSysprep.ps1
### Set-IniFileValue -Path $configFilePath -Section "Default" -Key "extra_features" -Value "OpenSSH.Server~~~~0.0.1.0,OpenSSH.Client~~~~0.0.1.0"
#Set-IniFileValue -Path $configFilePath -Section "Default" -Key "extra_features" -Value "aaa,bbb,ccc"
#Set-IniFileValue -Path $configFilePath -Section "Default" -Key "extra_capabilities" -Value "aaa,bbb,ccc"
Set-IniFileValue -Path $configFilePath -Section "Default" -Key "custom_resources_path" -Value $customPkg
Set-IniFileValue -Path $configFilePath -Section "Default" -Key "custom_scripts_path" -Value $customScripts
Set-IniFileValue -Path $configFilePath -Section "vm" -Key "disk_size" -Value (80GB)
Set-IniFileValue -Path $configFilePath -Section "vm" -Key "cpu_count" -Value 4
Set-IniFileValue -Path $configFilePath -Section "vm" -Key "ram_size" -Value (8GB)
Set-IniFileValue -Path $configFilePath -Section "vm" -Key "external_switch" -Value "vSwitch"
#Set-IniFileValue -Path $configFilePath -Section "vm" -Key "vlan" -Value "1554"
Set-IniFileValue -Path $configFilePath -Section "vm" -Key "administrator_password" -Value "YourIn1tPwd.S8mple"
Set-IniFileValue -Path $configFilePath -Section "drivers" -Key "virtio_iso_path" -Value $virtIOISOPath
#Set-IniFileValue -Path $configFilePath -Section "drivers" -Key "drivers_path" -Value $extraDriversPath
Set-IniFileValue -Path $configFilePath -Section "updates" -Key "install_updates" -Value "False"
Set-IniFileValue -Path $configFilePath -Section "updates" -Key "purge_updates" -Value "False"
Set-IniFileValue -Path $configFilePath -Section "sysprep" -Key "disable_swap" -Value "False"
Set-IniFileValue -Path $configFilePath -Section "cloudbase_init" -Key "msi_path" -Value "c:\install\CloudbaseInitSetup_1_1_2_x64.msi"
Set-IniFileValue -Path $configFilePath -Section "cloudbase_init" -Key "cloudbase_init_config_path" -Value "C:\ImagePrep\Configs\WinOnPrem\cloudbase-init.conf"
Set-IniFileValue -Path $configFilePath -Section "cloudbase_init" -Key "cloudbase_init_unattended_config_path" -Value "C:\ImagePrep\Configs\WinOnPrem\cloudbase-init-unattend.conf"
Set-IniFileValue -Path $configFilePath -Section "custom" -Key "time_zone" -Value "W. Europe Standard Time"
Set-IniFileValue -Path $configFilePath -Section "custom" -Key "ntp_servers" -Value "pool.ntp.org"
Set-IniFileValue -Path $configFilePath -Section "custom" -Key "install_qemu_ga" -Value "True"


Write-Host "Starting Image generation with Config: $($configFilePath)."
# This scripts generates a raw image file that, after being started as an instance and
# after it shuts down, it can be used with Ironic or KVM hypervisor in OpenStack.
#Build Image with Hyper-V
New-WindowsOnlineImage -ConfigFilePath $configFilePath

Dismount-DiskImage -ImagePath $ImgPath
