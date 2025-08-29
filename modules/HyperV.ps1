<#
.SYNOPSIS
Interaktives PowerShell-Menü (Advanced Function) für häufige Aufgaben bei der Verwaltung von Hyper-V Umgebungen — Host- und VM-Inventar + Wartungsaufgaben

.BESCHREIBUNG
Dieses Skript liefert umfangreiche Informationen über den Hyper-V Host (Hardware, Netzwerk, OS) und die darauf laufenden VMs. Zusätzlich sind Wartungsfunktionen
enthalten, z. B. das Auflisten alter Snapshots (Checkpoints) und eine sichere Löschfunktion mit -WhatIf.

.VORAUSSETZUNGEN
- Auf dem System muss das Hyper-V PowerShell-Modul installiert sein.
- Script als Administrator ausführen.
- Für einige Gast-Infos (IP-Adressen) müssen Integrationsdienste / Guest Services aktiv sein.

.NOTES
- Zum selbstschutz sind zerstörende Aktionen per default auf -WhatIf gesetzt bzw. es ist eine zusätzliche expliziete Bestätigung nötig.
#>

#region Hilfsfunktionen
function Test-IsAdministrator {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $p = New-Object Security.Principal.WindowsPrincipal($id)
    return $p.IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)
}

function Ensure-ModuleAvailable {
    param([string]$Name)
    if (Get-Module -ListAvailable -Name $Name) {
        Import-Module $Name -ErrorAction Stop
        return $true
    }
    else {
        Write-Warning "Modul $Name nicht gefunden. Manche Funktionen sind dann nicht verfügbar."
        return $false
    }
}
#endregion

#region Host-Informationen
function Get-HostHardwareInfo {
    <# Liefert CPU, RAM, physische Speichermedien und Basisdaten der Host-Hardware #>
    Write-Host "== Host: Hardwareübersicht ==" -ForegroundColor Cyan

    $cs = Get-CimInstance -ClassName Win32_ComputerSystem
    $os = Get-CimInstance -ClassName Win32_OperatingSystem
    $procs = Get-CimInstance -ClassName Win32_Processor | Select-Object Name,NumberOfCores,NumberOfLogicalProcessors,MaxClockSpeed
    $memModules = Get-CimInstance -ClassName Win32_PhysicalMemory | Select-Object Manufacturer,Capacity,Speed,DeviceLocator

    $disks = @()
    if (Get-Command Get-PhysicalDisk -ErrorAction SilentlyContinue) {
        $disks = Get-PhysicalDisk | Select-Object FriendlyName,MediaType,Size,HealthStatus
    }
    else {
        # Fallback
        $disks = Get-CimInstance -ClassName Win32_DiskDrive | Select-Object Model,InterfaceType,Size
    }

    [PSCustomObject]@{
        ComputerName = $env:COMPUTERNAME
        Manufacturer = $cs.Manufacturer
        Model = $cs.Model
        TotalPhysicalMemoryGB = [Math]::Round($cs.TotalPhysicalMemory/1GB,2)
        OS = $os.Caption
        OSVersion = $os.Version
        Processors = $procs
        MemoryModules = $memModules
        PhysicalDisks = $disks
        LastBoot = $os.LastBootUpTime
    }
}

function Get-HostNetworkInfo {
    Write-Host "== Host: Netzwerkübersicht ==" -ForegroundColor Cyan
    if (Get-Command Get-NetAdapter -ErrorAction SilentlyContinue) {
        $adapters = Get-NetAdapter | Select-Object Name,Status,LinkSpeed,MacAddress
        $ipcfg = Get-NetIPConfiguration | Select-Object InterfaceAlias,IPv4Address,IPv6Address,DnsServers
        [PSCustomObject]@{Adapters=$adapters; IPConfig=$ipcfg}
    }
    else {
        Write-Warning 'NetTCPIP-Modul nicht verfügbar. Verwende CIM-Fallback.'
        $nic = Get-CimInstance Win32_NetworkAdapter | Select-Object Name,MACAddress,NetEnabled
        $ips = Get-CimInstance Win32_NetworkAdapterConfiguration | Where-Object {$_.IPAddress} | Select-Object Description,IPAddress
        [PSCustomObject]@{Adapters=$nic; IPConfig=$ips}
    }
}

function Get-HostOSInfo {
    Write-Host "== Host: Betriebssystem & Patch-Status ==" -ForegroundColor Cyan
    $os = Get-CimInstance -ClassName Win32_OperatingSystem | Select-Object Caption,Version,BuildNumber,OSArchitecture,LastBootUpTime
    $hotfix = Get-HotFix | Select-Object HotFixID,InstalledOn,Description
    [PSCustomObject]@{OS=$os; Hotfixes=$hotfix}
}
#endregion

#region VM-Informationen
function Get-VMInventory {
    <# Liefert eine Zusammenfassung aller VMs mit relevanten Eigenschaften #>
    Ensure-ModuleAvailable -Name Hyper-V | Out-Null
    Write-Host "== VM-Inventar ==" -ForegroundColor Cyan

    $vms = Get-VM | Sort-Object State,Name
    $list = foreach ($vm in $vms) {
        $net = Get-VMNetworkAdapter -VMName $vm.Name -ErrorAction SilentlyContinue | Select-Object Name,MacAddress,Status,@{n='IPAddresses';e={($_.IPAddresses -join ', ')}},SwitchName
        $disks = Get-VMHardDiskDrive -VMName $vm.Name -ErrorAction SilentlyContinue | Select-Object Path,ControllerType,ControllerNumber,ControllerLocation
        $snapshots = Get-VMSnapshot -VMName $vm.Name -ErrorAction SilentlyContinue | Select-Object Name,CreationTime
        $integration = Get-VMIntegrationService -VMName $vm.Name | Select-Object Name,Enabled,PrimaryStatusDescription

        [PSCustomObject]@{
            Name = $vm.Name
            State = $vm.State
            CPUUsagePercent = $vm.CPUUsage
            ProcessorCount = $vm.ProcessorCount
            MemoryAssignedMB = $vm.MemoryAssigned/1MB
            MemoryStartupMB = $vm.MemoryStartup/1MB
            DynamicMemory = $vm.DynamicMemoryEnabled
            Generation = $vm.Generation
            Uptime = $vm.Uptime
            Path = $vm.Path
            Version = $vm.Version
            NetworkAdapters = $net
            Disks = $disks
            Snapshots = $snapshots
            IntegrationServices = $integration
        }
    }
    return $list
}

function Get-VMDetails {
    param([Parameter(Mandatory=$true)][string]$VMName)
    Ensure-ModuleAvailable -Name Hyper-V | Out-Null
    if (-not (Get-VM -Name $VMName -ErrorAction SilentlyContinue)) {
        Write-Error "VM '$VMName' nicht gefunden."
        return
    }

    $vm = Get-VM -Name $VMName
    $net = Get-VMNetworkAdapter -VMName $VMName -ErrorAction SilentlyContinue | Select-Object Name,MacAddress,Status,VMName,@{n='IPAddresses';e={($_.IPAddresses -join ', ')}},SwitchName
    $disks = Get-VMHardDiskDrive -VMName $VMName -ErrorAction SilentlyContinue | Select-Object Path,ControllerType,ControllerNumber,ControllerLocation
    $snapshots = Get-VMSnapshot -VMName $VMName -ErrorAction SilentlyContinue | Select-Object Name,CreationTime,@{n='AgeDays';e={[math]::Round((Get-Date - $_.CreationTime).TotalDays,1)}}
    $integration = Get-VMIntegrationService -VMName $VMName | Select-Object Name,Enabled,PrimaryStatusDescription
    $replication = Get-VMReplication -VMName $VMName -ErrorAction SilentlyContinue

    [PSCustomObject]@{
        VM = $vm
        NetworkAdapters = $net
        Disks = $disks
        Snapshots = $snapshots
        IntegrationServices = $integration
        Replication = $replication
    }
}
#endregion

#region Wartung / Checks
function Find-OldSnapshots {
    param(
        [int]$OlderThanDays = 30
    )
    Ensure-ModuleAvailable -Name Hyper-V | Out-Null
    Write-Host "Suche Snapshots älter als $OlderThanDays Tage..." -ForegroundColor Yellow
    $threshold = (Get-Date).AddDays(-$OlderThanDays)
    $old = Get-VMSnapshot -ErrorAction SilentlyContinue | Where-Object {$_.CreationTime -lt $threshold} | Select-Object VMName,Name,CreationTime,@{n='AgeDays';e={[math]::Round((Get-Date - $_.CreationTime).TotalDays,1)}}
    return $old
}

function Remove-OldSnapshots {
    param(
        [int]$OlderThanDays = 60,
        [switch]$Force,
        [switch]$WhatIf
    )
    Ensure-ModuleAvailable -Name Hyper-V | Out-Null
    $old = Find-OldSnapshots -OlderThanDays $OlderThanDays
    if (-not $old) { Write-Host "Keine alten Snapshots gefunden."; return }

    Write-Host "Gefundene alte Snapshots:" -ForegroundColor Cyan
    $old | Format-Table -AutoSize

    if ($WhatIf) { Write-Host "Modus: WhatIf - keine Löschaktionen werden ausgeführt." -ForegroundColor Yellow }

    foreach ($s in $old) {
        $vm = $s.VMName; $name = $s.Name
        $msg = "Lösche Snapshot '$name' von VM '$vm' (Alter: $($s.AgeDays) Tage)"
        if ($WhatIf) {
            Write-Host "WHATIF: $msg" -ForegroundColor Magenta
        }
        else {
            if ($Force) {
                Remove-VMSnapshot -VMName $vm -Name $name -ErrorAction SilentlyContinue -Confirm:$false
                Write-Host "$msg - erledigt." -ForegroundColor Green
            }
            else {
                $confirm = Read-Host "$msg - bestätigen mit Y" -ErrorAction SilentlyContinue
                if ($confirm -eq 'Y') { Remove-VMSnapshot -VMName $vm -Name $name -ErrorAction SilentlyContinue; Write-Host "Gelöscht" -ForegroundColor Green }
                else { Write-Host "Übersprungen" -ForegroundColor Yellow }
            }
        }
    }
}

function Check-VMIntegrationServices {
    Write-Host "== Integration Services Check ==" -ForegroundColor Cyan
    $vms = Get-VM
    foreach ($vm in $vms) {
        $ints = Get-VMIntegrationService -VMName $vm.Name
        $bad = $ints | Where-Object {$_.PrimaryStatusDescription -ne 'OK' -and $_.Enabled -eq $true}
        if ($bad) {
            [PSCustomObject]@{VM=$vm.Name; Issues=$bad}
        }
    }
}
#endregion

#region Aktionen: Start/Stop/Restart/Export
function Start-VM-Safe {
    param([Parameter(Mandatory=$true)][string]$VMName)
    if ((Get-VM -Name $VMName).State -eq 'Running') { Write-Host "VM $VMName läuft bereits."; return }
    Start-VM -Name $VMName
    Write-Host "Start-Befehl an $VMName gesendet." -ForegroundColor Green
}

function Stop-VM-Safe {
    param([Parameter(Mandatory=$true)][string]$VMName, [switch]$Force)
    if ((Get-VM -Name $VMName).State -ne 'Running') { Write-Host "VM $VMName ist nicht laufend."; return }
    if ($Force) { Stop-VM -Name $VMName -Force -Confirm:$false } else { Stop-VM -Name $VMName }
    Write-Host "Stopp-Befehl an $VMName gesendet." -ForegroundColor Yellow
}

function Restart-VM-Safe {
    param([Parameter(Mandatory=$true)][string]$VMName)
    Restart-VM -Name $VMName
    Write-Host "Restart-Befehl an $VMName gesendet." -ForegroundColor Cyan
}

function Export-Inventory {
    param([string]$Path = "HyperV-Inventory_$(Get-Date -Format yyyyMMdd_HHmmss).json")
    $hostHw = Get-HostHardwareInfo
    $hostNet = Get-HostNetworkInfo
    $hostOS = Get-HostOSInfo
    $vms = Get-VMInventory
    $report = [PSCustomObject]@{HostHardware=$hostHw; HostNetwork=$hostNet; HostOS=$hostOS; VMs=$vms}
    $report | ConvertTo-Json -Depth 6 | Out-File -FilePath $Path -Encoding UTF8
    Write-Host "Inventar exportiert nach: $Path" -ForegroundColor Green
}
#endregion

#region Interaktives Menü
function Show-Menu {
    Clear-Host
    Write-Host "=== Hyper-V Management Tool ===" -ForegroundColor DarkCyan
    Write-Host "1) Host-Hardware anzeigen"
    Write-Host "2) Host-Netzwerk anzeigen"
    Write-Host "3) Host OS & Patches anzeigen"
    Write-Host "4) Alle VMs zusammenfassen (Kurzübersicht)"
    Write-Host "5) Detailinformationen zu einer VM"
    Write-Host "6) Snapshots älter X Tage finden"
    Write-Host "7) Alte Snapshots löschen (mit Bestätigung)"
    Write-Host "8) Integration Services prüfen"
    Write-Host "9) VM starten / stoppen / restart"
    Write-Host "10) Inventar exportieren (JSON)"
    Write-Host "0) Beenden"
}

# Hauptprogramm
if (-not (Test-IsAdministrator)) { Write-Error "Dieses Skript muss als Administrator ausgeführt werden."; return }
Ensure-ModuleAvailable -Name Hyper-V | Out-Null

do {
    Show-Menu
    $choice = Read-Host 'Auswahl'
    switch ($choice) {
        '1' { Get-HostHardwareInfo | Format-List; Read-Host 'Enter zum Weiter'}
        '2' { Get-HostNetworkInfo | Format-List; Read-Host 'Enter zum Weiter'}
        '3' { Get-HostOSInfo | Format-List; Read-Host 'Enter zum Weiter'}
        '4' { $v = Get-VMInventory; $v | Select-Object Name,State,ProcessorCount,MemoryAssignedMB,Uptime | Format-Table -AutoSize; Read-Host 'Enter zum Weiter' }
        '5' { $vmn = Read-Host 'VM-Name'; Get-VMDetails -VMName $vmn | Format-List *; Read-Host 'Enter zum Weiter' }
        '6' { $days = Read-Host 'Älter als wie viele Tage? (z.B. 30)'; Find-OldSnapshots -OlderThanDays ([int]$days) | Format-Table -AutoSize; Read-Host 'Enter zum Weiter' }
        '7' { $days = Read-Host 'Löschen: Snapshots älter als wie viele Tage? (z.B. 60)'; $what = Read-Host 'WhatIf only? (Y/N)'; if ($what -eq 'Y') { Remove-OldSnapshots -OlderThanDays ([int]$days) -WhatIf } else { Remove-OldSnapshots -OlderThanDays ([int]$days) } Read-Host 'Enter zum Weiter' }
        '8' { Check-VMIntegrationServices | Format-Table -AutoSize; Read-Host 'Enter zum Weiter' }
        '9' {
            $action = Read-Host 'start/stop/restart'
            $vmn = Read-Host 'VM-Name'
            switch ($action) {
                'start' { Start-VM-Safe -VMName $vmn }
                'stop' { $f = Read-Host 'Force? (Y/N)'; if ($f -eq 'Y') { Stop-VM-Safe -VMName $vmn -Force } else { Stop-VM-Safe -VMName $vmn } }
                'restart' { Restart-VM-Safe -VMName $vmn }
                default { Write-Host 'Ungültige Aktion' -ForegroundColor Red }
            }
            Read-Host 'Enter zum Weiter'
        }
        '10' { $path = Read-Host 'Pfad für Export-Datei (oder leer für default)'; if ($path) { Export-Inventory -Path $path } else { Export-Inventory }; Read-Host 'Enter zum Weiter' }
        '0' { Write-Host 'Beenden...' -ForegroundColor Cyan }
        default { Write-Host 'Ungültige Auswahl' -ForegroundColor Red }
    }
} while ($choice -ne '0')
#endregion
