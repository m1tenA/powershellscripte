function Get-HelloMessage {
    param(
        [string]$Name = "Team"
    )
    "Hallo $Name, willkommen im PowerShell-Toolkit!"
}

Export-ModuleMember -Function Get-HelloMessage
