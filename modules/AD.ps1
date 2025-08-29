bfunction ad {
<#
.SYNOPSIS
    Interaktives PowerShell-Menü (Advanced Function) für häufige Aufgaben in Active Directory (AD):
    Forest-/Domain-/Sites-Infos, DC-Übersicht & Replikation, Kennwortrichtlinie, GPO-Links, 
    Clients/Server/Computerlisten, Remote-Systeminfo, Computer verschieben, Gruppen & Mitgliedschaften,
    Benutzerabfragen, letzter Domain-Logon über alle DCs, aktuell angemeldete Benutzer je Computer,
    massenhaft Benachrichtigungen, verwaiste Konten, Time-Based Group Membership (TTL), 
    On-/Offboarding (Benutzer anlegen/deaktivieren).

.DESCRIPTION
    Dieses Skript stellt ein textbasiertes Menü bereit, um typische AD-Administrationsaufgaben 
    schnell aufzurufen. Es nutzt die ActiveDirectory-, GroupPolicy-Cmdlets sowie teils Bordmittel 
    (z. B. dsquery, repadmin, msg, systeminfo, quser). Viele Aktionen erfordern erhöhte Rechte
    (mindestens „Account Operators“, i. d. R. „Domain Admins“).

.PREREQUISITES
    - Windows mit RSAT/AD-PowerShell-Modul (ActiveDirectory) ODER Domain Controller.
    - Netzwerk-/Firewall-Regeln für WinRM/RemoteExec, je nach Funktionen (Invoke-Command, msg/quser).
    - Für Menüpunkt 20 (Time-Based Group Membership):
        * Forest Functional Level >= Windows Server 2016
        * Optional Feature „Privileged Access Management (PAM)“ aktiviert
    - Für einige Befehle wird eine englische OS-Sprache angenommen (Menü 17, quser-Ausgabe).

.USAGE
    - Auf einem DC oder einem Admin-Client mit AD-Modul starten.
    - Menüzahl eingeben und Anweisungen folgen.
    - Abbruchtypisch: Eingabe „0“ oder wie im Prompt angegeben.

.MENU OVERVIEW (Kurzüberblick)
    1  Forest/Domain/Sites-Infos & optionale Features
    2  Liste aller DCs inkl. Rollen, Ping-Test optional
    3  Replikation aller DCs anstoßen + Status
    4  Default Domain Password Policy anzeigen
    5  Mitglieder der Gruppe „Domain Admins“
    6  GPOs mit Links (per GPOReport-XML geprüft)
    7  Alle Windows-Clients
    8  Alle Windows-Server
    9  Alle Computer (gruppiert nach OS)
    10 Remote „systeminfo“ (lokal / gezielt / alle Server / alle Computer)
    11 Computerobjekt in OU verschieben (interaktiv)
    12 Alle AD-Gruppen (Basisübersicht)
    13 Gruppenmitgliedschaften nach Gruppenname
    14 Alle aktivierten Benutzer
    15 Benutzer-Details (Properties) nach Logon-Name
    16 letzter Domain-Logon eines Benutzers (ab allen DCs, aktuellster)
    17 aktuell angemeldete Benutzer auf Zielrechner (quser, sprachsensitiv)
    18 Nachricht an Benutzer (msg) – lokal/Remote/alle Server/alle Computer
    19 Verwaiste Konten (seit X Tagen nicht angemeldet) – Benutzer oder Computer
    20 Time-Based Group Membership (TTL) konfigurieren
    21 Onboarding: Neuen Benutzer nach Vorlage (kopiert Eigenschaften & Gruppen)
    22 Offboarding: Benutzer deaktivieren, optional Gruppenmitgliedschaften entfernen

.OUTPUTS
    Konsole (Format-Table/Format-List/Out-Host), teils interaktive Prompts.

.SECURITY & SAFETY NOTES
    - Viele Aktionen ändern Objekte (Move-ADObject, Add-ADGroupMember, New-ADUser, Set-ADUser). 
      Immer vorher prüfen und in Testumgebung validieren.
    - Menü 3 (Replikation) schreibt auf DC-Ebene; in produktiven Umgebungen bewusst einsetzen.
    - Menü 18 (msg) kann Nachrichten breit verteilen – vorsichtig verwenden.
    - Menü 21/22 verändern Benutzerobjekte – Dokumentation/Change Management beachten.

.LIMITATIONS & TECHNISCHE HINWEISE
    - Teilweise werden Legacy-Tools (dsquery, repadmin, quser, msg, systeminfo) genutzt. 
      Moderne Alternativen sind oft robuster (Get-ADUser -LDAPFilter, AD Repl-Cmdlets, CIM, usw.).
    - Frühzeitiges Formatieren (Format-Table/-List) erschwert Weiterverarbeitung. Für Skriptbarkeit
      wäre Export (Export-Csv) oder reine Objektausgabe ratsam.
    - Mehrere Stellen prüfen Eingaben mit Vergleichsoperator „=“ statt „-eq“ – das ist ein Assignment
      (Bug). Siehe Menüs 21/22. Kommentare markieren diese Stellen.
    - Einzelne Stellen enthalten Literale wie '...''n' anstatt Zeilenumbruch "`n" in doppelten Anführungszeichen (Bug). 
    - String-Filter innerhalb einfacher Anführungszeichen verhindern Variablensubstitution (z. B. 
      Get-ADComputer -Filter 'name -like $comp'). Besser: -LDAPFilter oder ScriptBlock-Filter.
    - Auf Englisch gesetzte Regex/Parsing für quser (Menü 17) kann auf nicht-englischen Systemen brechen.

.RECOMMENDATIONS (Refactoring-Ideen)
    - Eingabevalidierung zentralisieren; Switch mit ValidateSet; Try/Catch mit aussagekräftigen Fehlern.
    - Kein Format-* vor Logik; Objekte zurückgeben und am Ende darstellen/exportieren.
    - Konsistente Nutzung von AD-Cmdlets statt dsquery; CIM statt systeminfo/quser parsen.
    - Internationalisierung (Culture-Invariant Parsing) und robustere Regex.
    - Logging (Transcript / Dateilog) & -WhatIf / -Confirm where applicable.
    - Rechteprüfung (z. B. Test-ADServiceAccount oder WhoAmI/MemberOf-Checks) vor kritischen Aktionen.

.VERSION
    Angezeigte Menüversion: v1.1 (aus dem Header). Diese kommentierte Ausgabe ändert keine Logik,
    ergänzt jedoch umfangreiche Kommentare und weist auf Bugs/Verbesserungen hin.
#>

    # ————————————————————————————————————————————————————————————
    # UI/Grundkonfiguration
    # ————————————————————————————————————————————————————————————
    $host.ui.RawUI.WindowTitle = 'Erstellt vom timbo | tims-ecke.de'  # Setzt Fenstertitel der PowerShell-Host-UI
    $line  = '========================================================='   # Trennlinie (gleich)
    $line2 = '________________________________________________________'     # Trennlinie (unterstrich)

    # Prüfen und Importieren des AD-Moduls (harte Abbruchlogik, wenn nicht vorhanden)
    if (Get-Module -ListAvailable -Name ActiveDirectory) {
        Import-Module ActiveDirectory
    } else {
        ''
        Write-Host "Operation aborted. No Active Directory Module found. Run this tool on a Domain Controller." -ForegroundColor Red
        ''
        throw "Error"  # Harte Ausnahme -> Skriptende
    }

    cls  # Bildschirm leeren für frisches Menü

    do {
        # Hinweis: Alleinstehender String -> wird zur Pipeline/Host geschrieben und erscheint als Zeile
        $line
        Write-Host ' ACTIVE DIRECTORY Domain Services Section (v 1.1)' -ForegroundColor Green
        $line

        # — Forest/Domain/DC —
        Write-Host '---------------------------------------------------------' 
        Write-Host ' Forest | Domain | Domain Controller' -ForegroundColor Yellow
        Write-Host '---------------------------------------------------------' 
        Write-Host " 1 - Forest | Domain | Sites Configuration ($env:userdnsdomain)"
        Write-Host ' 2 - List Domain Controller'
        Write-Host ' 3 - Replicate all Domain Controller'
        Write-Host ' 4 - Show Default Domain Password Policy'
        Write-Host ' 5 - List Domain Admins'
        Write-Host ' 6 - List of Active GPOs'

        # — User/Computer/Groups —
        Write-Host '---------------------------------------------------------' 
        Write-Host ' User | Computer | Groups' -ForegroundColor Yellow
        Write-Host '---------------------------------------------------------' 
        Write-Host ' 7 - List all Windows Clients'
        Write-Host ' 8 - List all Windows Server'
        Write-Host ' 9 - List all Computers (by Operatingsystem)'
        Write-Host '10 - Run Systeminfo on Remote Computers'
        Write-Host '11 - Move Computer to OU'
        Write-Host '12 - List all Groups'
        Write-Host '13 - List Group Membership by User'
        Write-Host '14 - List all Users (enabled)'
        Write-Host '15 - List User Properties'
        Write-Host '16 - Users Last Domain Logon'
        Write-Host '17 - Show currently logged on User by Computer'
        Write-Host '18 - Send message to Users Desktop'
        Write-Host '19 - Find orphaned User or Computer Accounts'
        Write-Host '20 - Configure Time-Based-Group-Membership'

        # — On-/Offboarding —
        Write-Host '---------------------------------------------------------' 
        Write-Host ' OnBoarding | OffBoarding' -ForegroundColor Yellow
        Write-Host '---------------------------------------------------------' 
        Write-Host '21 - OnBoarding | Create new AD User (from existing)'
        Write-Host '22 - OffBoarding | Disable AD User'
        Write-Host '0 - Quit' -ForegroundColor Red
        Write-Host ''

        $input = Read-Host 'Select'

        switch ($input) {
            1 {
                ''
                Write-Host -ForegroundColor Green 'FOREST Configuration'
                # Forest-Infos ermitteln
                $get = Get-ADForest
                $forest += New-Object -TypeName PSObject -Property ([ordered]@{
                    'Root Domain' = $get.RootDomain
                    'Forest Mode' = $get.ForestMode
                    'Domains'     = $get.Domains -join ','
                    'Sites'       = $get.Sites   -join ','
                })
                $forest | Format-Table -AutoSize -Wrap

                Write-Host -ForegroundColor Green 'DOMAIN Configuration'
                Get-ADDomain | Format-Table DNSRoot, DomainMode, ComputersContainer, DomainSID -AutoSize -Wrap

                Write-Host -ForegroundColor Green 'SITES Configuration'
                # Sites via .NET API (DirectoryServices) – gibt Subnets/Servers je Site aus
                $GetSite = [System.DirectoryServices.ActiveDirectory.Forest]::GetCurrentForest().Sites
                $Sites = @()
                foreach ($Site in $GetSite) {
                    $Sites += New-Object -TypeName PSObject -Property (@{
                        'SiteName' = $Site.Name
                        'SubNets'  = $Site.Subnets -Join ','
                        'Servers'  = $Site.Servers -Join ','
                    })
                }
                $Sites | Format-Table -AutoSize -Wrap

                Write-Host -ForegroundColor Green 'Enabled OPTIONAL FEATURES'
                Get-ADOptionalFeature -Filter * | Format-Table Name,RequiredDomainMode,RequiredForestMode -AutoSize -Wrap
                Read-Host 'Press 0 and Enter to continue'
            }

            2 {
                # Liste aller DCs im Forest/der Domain, inkl. Rollen & Ping-Test
                $dcs     = Get-ADDomainController -Filter *
                $dccount = $dcs | Measure-Object | Select-Object -ExpandProperty Count
                ''
                Write-Host -ForegroundColor Green "Active Directory Domain Controller ($env:userdnsdomain)"
                $domdc = @()
                foreach ($dc in $dcs) {
                    $domdc += New-Object -TypeName PSObject -Property ([ordered]@{
                        'Name'           = $dc.Name
                        'IP Address'     = $dc.IPv4Address
                        'OS'             = $dc.OperatingSystem
                        'Site'           = $dc.Site
                        'Global Catalog' = $dc.IsGlobalCatalog
                        'FSMO Roles'     = $dc.OperationMasterRoles -join ','
                    })
                }
                ''
                $domdc | Format-Table -AutoSize -Wrap
                Write-Host ('Total Number: ' + $dccount) -ForegroundColor Yellow
                ''
                $ping = Read-Host "Do you want to test connectivity (ping) to these Domain Controllers? (Y/N)"
                if ($ping -eq 'Y') {
                    foreach ($items in $dcs.Name) {
                        # Achtung: Test-Connection v6+ hat anderes Default-Format; hier 1 Paket
                        Test-Connection $items -Count 1 | Format-Table Address, IPv4Address, ReplySize, ResponseTime
                    }
                    Read-Host 'Press 0 and Enter to continue'
                } else {
                    ''
                    Read-Host 'Press 0 and Enter to continue'
                }
            }

            3 {
                ''
                Write-Host "This sub-menu replicates all Domain Controller on all Sites of the Domain $env:userdnsdomain."
                ''
                Write-Host 'Start Replication?' -ForegroundColor Yellow
                ''
                $startr = Read-Host 'Y/N'
                if ($startr) {
                    # repadmin /syncall je DC gegen DN der Domain (e / A: enterprise, alle Partner, synchr.)
                    (Get-ADDomainController -Filter *).Name | ForEach-Object { repadmin /syncall $_ (Get-ADDomain).DistinguishedName /e /A | Out-Null }
                    Start-Sleep 10
                    # Statusübersicht über Partner-Metadaten, zeigt LastReplicationSuccess
                    Get-ADReplicationPartnerMetadata -Target "$env:userdnsdomain" -Scope Domain | 
                        Select-Object Server, LastReplicationSuccess | Out-Host
                }
            }

            4 {
                ''
                Write-Host -ForegroundColor Green 'The Default Domain Policy is configured as follows:'
                # BUG im Original: "'...''n" -> hier korrigiert kommentierend als zwei getrennte Ausgaben
                Get-ADDefaultDomainPasswordPolicy | Format-List \
                    ComplexityEnabled, LockoutDuration, LockoutObservationWindow, LockoutThreshold, \
                    MaxPasswordAge, MinPasswordAge, MinPasswordLength, PasswordHistoryCount, ReversibleEncryptionEnabled
                Read-Host 'Press 0 and Enter to continue'
            }

            5 {
                ''
                Write-Host -ForegroundColor Green 'The following users are member of the Domain Admins group:'
                # BUG im Original: "'...''n" – hier getrennt.
                $sid = (Get-ADDomain).DomainSid.Value + '-512'  # Well-known RID 512 = Domain Admins
                Get-ADGroupMember -Identity $sid | Format-Table Name, SamAccountName, SID -AutoSize -Wrap
                ''
                Read-Host 'Press 0 and Enter to continue'
            }

            6 {
                ''
                Write-Host -ForegroundColor Green 'The GPOs below are linked to AD Objects:'
                # Ermittelt GPOs mit Links via XML-Report-Suche nach <LinksTo>
                Get-GPO -All | ForEach-Object {
                    if ( $_ | Get-GPOReport -ReportType XML | Select-String '<LinksTo>' ) {
                        Write-Host $_.DisplayName
                    }
                }
                ''
                Read-Host 'Press 0 and Enter to continue'
            }

            7 {
                # Alle Nicht-Server-Computer (OS-Filter) inkl. Basis-Properties
                $client = Get-ADComputer -Filter { operatingsystem -notlike '*server*' } -Properties Name, Operatingsystem, OperatingSystemVersion, IPv4Address
                $ccount = $client | Measure-Object | Select-Object -ExpandProperty Count
                ''
                Write-Host -ForegroundColor Green "Windows Clients $env:userdnsdomain"
                Write-Output $client | Sort-Object Operatingsystem | 
                    Format-Table Name, Operatingsystem, OperatingSystemVersion, IPv4Address -AutoSize
                ''
                Write-Host ('Total: ' + $ccount) -ForegroundColor Yellow
                ''
                Read-Host 'Press 0 and Enter to continue'
            }

            8 {
                # Alle Server-Computer (OS-Filter)
                $server = Get-ADComputer -Filter { operatingsystem -like '*server*' } -Properties Name, Operatingsystem, OperatingSystemVersion, IPv4Address
                $scount = $server | Measure-Object | Select-Object -ExpandProperty Count
                ''
                Write-Host -ForegroundColor Green "Windows Server $env:userdnsdomain"
                Write-Output $server | Sort-Object Operatingsystem | 
                    Format-Table Name, Operatingsystem, OperatingSystemVersion, IPv4Address
                ''
                Write-Host ('Total: ' + $scount) -ForegroundColor Yellow
                ''
                Read-Host 'Press 0 and Enter to continue'
            }

            9 {
                # Alle Computer + Gruppierung nach OperatingSystem
                $all    = Get-ADComputer -Filter * -Properties Name, Operatingsystem, OperatingSystemVersion, IPv4Address
                $acount = $all | Measure-Object | Select-Object -ExpandProperty Count
                ''
                Write-Host -ForegroundColor Green "All Computer $env:userdnsdomain"
                Write-Output $all | Select-Object Name, Operatingsystem, OperatingSystemVersion, IPv4Address | 
                    Sort-Object OperatingSystem | Format-Table -GroupBy OperatingSystem
                Write-Host ('Total: ' + $acount) -ForegroundColor Yellow
                ''
                Read-Host 'Press 0 and Enter to continue'
            }

            10 {
                # Remote-Ausführung von systeminfo (CSV-Format), verschiedene Scopes
                do {
                    Write-Host ''
                    Write-Host 'This runs systeminfo on specific computers. Select scope:' -ForegroundColor Green
                    Write-Host ''
                    Write-Host '1 - Localhost'             -ForegroundColor Yellow
                    Write-Host '2 - Remote Computer (Enter Computername)' -ForegroundColor Yellow
                    Write-Host '3 - All Windows Server'    -ForegroundColor Yellow
                    Write-Host '4 - All Windows Computer'  -ForegroundColor Yellow
                    Write-Host '0 - Quit'                  -ForegroundColor Yellow
                    Write-Host ''

                    $scopesi = Read-Host 'Select'
                    $header  = 'Host Name','OS','Version','Manufacturer','Configuration','Build Type','Registered Owner','Registered Organization','Product ID','Install Date','Boot Time','System Manufacturer','Model','Type','Processor','Bios','Windows Directory','System Directory','Boot Device','Language','Keyboard','Time Zone','Total Physical Memory','Available Physical Memory','Virtual Memory','Virtual Memory Available','Virtual Memory in Use','Page File','Domain','Logon Server','Hotfix','Network Card','Hyper-V'

                    switch ($scopesi) {
                        1 {
                            & "$env:windir\system32\systeminfo.exe" /FO CSV | Select-Object -Skip 1 | ConvertFrom-Csv -Header $header | Out-Host
                        }
                        2 {
                            ''
                            Write-Host 'Separate multiple computernames by comma. (example: server01,server02)' -ForegroundColor Yellow
                            Write-Host ''
                            $comps = Read-Host 'Enter computername'
                            $comp  = $comps.Split(',')
                            $cred  = Get-Credential -Message 'Enter Username and Password of a Member of the Domain Admins Group'
                            Invoke-Command -ComputerName $comps -Credential $cred { systeminfo /FO CSV | Select-Object -Skip 1 } -ErrorAction SilentlyContinue |
                                ConvertFrom-Csv -Header $header | Out-Host
                        }
                        3 {
                            $cred = Get-Credential -Message 'Enter Username and Password of a Member of the Domain Admins Group'
                            Invoke-Command -ComputerName (Get-ADComputer -Filter { operatingsystem -like '*server*' }).Name -Credential $cred { systeminfo /FO CSV | Select-Object -Skip 1 } -ErrorAction SilentlyContinue |
                                ConvertFrom-Csv -Header $header | Out-Host
                        }
                        4 {
                            $cred = Get-Credential -Message 'Enter Username and Password of a Member of the Domain Admins Group'
                            Invoke-Command -ComputerName (Get-ADComputer -Filter *).Name -Credential $cred { systeminfo /FO CSV | Select-Object -Skip 1 } -ErrorAction SilentlyContinue |
                                ConvertFrom-Csv -Header $header | Out-Host
                        }
                    }
                } while ($scopesi -ne '0')
            }

            11 {
                ''
                Write-Host 'This sections moves Computer Accounts to an OU.' -ForegroundColor Green

                # 1) Computername erfragen und prüfen
                do {
                    ''
                    Write-Host 'Enter Computer Name or Q to quit' -ForegroundColor Yellow
                    ''
                    $comp = Read-Host 'Computer Name'

                    # BUG: Ursprünglich: -Filter 'name -like $comp' (string literal) – Variablen werden nicht ersetzt.
                    # Besser: ScriptBlock-Filter oder -LDAPFilter. Nachstehend belassen wir Logik, kommentieren nur.
                    $c = Get-ADComputer -Filter 'name -like $comp' -Properties CanonicalName -ErrorAction SilentlyContinue
                    $cfound = $c.Name

                    if ($comp -eq 'Q') { break }

                    if ($cfound) {
                        $discfound = $c.CanonicalName
                        ''
                        Write-Host -ForegroundColor Green ("$comp in $discfound found!")
                        ''
                    }
                    elseif (!$cfound) {
                        ''
                        Write-Host -ForegroundColor Red ("$comp not found. Please try again.")
                    }
                } while (!$cfound)

                # 2) OU-Namen erfragen und prüfen
                do {
                    if (($comp -eq 'Q') -or (!$cfound)) { break }
                    $Domain = (Get-ADDomain).DistinguishedName
                    Write-Host 'Enter Name of OU (e.g. HR) or Q to quit' -ForegroundColor Yellow
                    ''
                    $OU = Read-Host 'Enter OU Name'

                    # BUG: Wie oben – 'name -like $OU' ist Literal. Besser ScriptBlock/LDAPFilter.
                    $OUfound = Get-ADOrganizationalUnit -Filter 'name -like $OU'

                    if ($OU -eq 'Q') { break }
                    if ($OUfound) {
                        ''
                        Write-Host -ForegroundColor Green ("$OUfound found!")
                        ''
                    }
                    elseif (!$OUfound) {
                        ''
                        Write-Host -ForegroundColor Red ("$OU not found. Please try again.")
                        ''
                    }
                } while (!$OUfound)

                if ($comp -eq 'Q') { break }

                if ($OUfound -and $cfound) {
                    ''
                    Write-Host "Are you sure you want to move Computer $cfound to $OUfound ?" -ForegroundColor Yellow
                    ''
                    $dec = Read-Host "Press Y or any other key to abort"
                }

                if ($dec -eq 'Y') {
                    $dis = $OUfound.DistinguishedName
                    Get-ADComputer $cfound | Move-ADObject -TargetPath "$dis"
                    ''
                    Write-Host "Computer $cfound moved to $OUfound" -ForegroundColor Green
                    ''
                    Get-ADComputer -Identity $cfound | Select-Object Name, DistinguishedName, Enabled, SID | Out-Host
                }
                else {
                    ''
                    Write-Host 'Operation aborted.' -ForegroundColor Red
                }
                ''
                Read-Host 'Press 0 and Enter to continue'
            }

            12 {
                ''
                Write-Host 'Overview of all Active Directory Groups' -ForegroundColor Green
                Get-ADGroup -Filter * -Properties * | Sort-Object Name | Format-Table Name, GroupCategory, GroupScope, SID -AutoSize -Wrap | more
                Read-Host 'Press 0 and Enter to continue'
            }

            13 {
                do {
                    ''
                    $groupm = Read-Host 'Enter group name'
                    ''
                    Write-Host "Group Members of $groupm" -ForegroundColor Green
                    Get-ADGroupMember $groupm | Format-Table Name, SamAccountName, SID -AutoSize -Wrap
                    $input = Read-Host 'Quit searching groups? (Y/N)'
                } while ($input -eq 'N')
            }

            14 {
                ''
                Write-Host "The following users in $env:userdnsdomain are enabled:" -ForegroundColor Green
                Get-ADUser -Filter { enabled -eq $true } -Properties CanonicalName, whenCreated | 
                    Sort-Object Name | Format-Table Name, SamAccountName, CanonicalName, whenCreated -AutoSize -wrap | more
                Read-Host 'Press 0 and Enter to continue'
            }

            15 {
                do {
                    ''
                    $userp = Read-Host 'Enter user logon name'
                    ''
                    Write-Host "Details of user $userp" -ForegroundColor Green
                    Get-ADUser $userp -Properties * | 
                        Format-List GivenName, SurName, DistinguishedName, Enabled, EmailAddress, ProfilePath, ScriptPath, MemberOf, LastLogonDate, whencreated
                    $input = Read-Host 'Quit searching users? (Y/N)'
                } while ($input -eq 'N')
            }

            16 {
                ''
                Write-Host "This section shows the latest Users Active Directory Logon based on all Domain Controllers of $env:userdnsdomain." -ForegroundColor Green
                do {
                    do {
                        ''
                        Write-Host 'Enter USER LOGON NAME (Q to quit)' -ForegroundColor Yellow
                        ''
                        $userl = Read-Host 'USER LOGON NAME'
                        if ($userl -eq 'Q') { break }
                        $ds = dsquery user -samid $userl
                        ''
                        if ($ds) {
                            Write-Host "User $userl found! Please wait ... contacting all Domain Controllers ... Showing results from most current DC ..." -ForegroundColor Green
                        }
                        else {
                            Write-Host "User $userl not found. Try again" -ForegroundColor Red
                        }
                    } while (!$ds)

                    $resultlogon = @()
                    if ($userl -eq 'Q') { break }

                    $getdc = (Get-ADDomainController -Filter *).Name
                    foreach ($dc in $getdc) {
                        try {
                            $user = Get-ADUser $userl -Server $dc -Properties lastlogon -ErrorAction Stop
                            $resultlogon += New-Object -TypeName PSObject -Property ([ordered]@{
                                'Most current DC' = $dc
                                'User'            = $user.Name
                                'LastLogon'       = [datetime]::FromFileTime($user.'lastLogon')
                            })
                        }
                        catch {
                            ''
                            Write-Host "No reports from $dc!" -ForegroundColor Red
                        }
                    }

                    if ($userl -eq 'Q') { break }
                    ''
                    $resultlogon | Where-Object { $_.lastlogon -NotLike '*1601*' } | 
                        Sort-Object LastLogon -Descending | Select-Object -First 1 | Format-Table -AutoSize

                    if (($resultlogon | Where-Object { $_.lastlogon -NotLike '*1601*' }) -eq $null) {
                        ''
                        Write-Host ("All domain controllers report that the user " + $user.name + " has never logged on til now.") -ForegroundColor Red
                    }

                    Write-Host 'Search again? Press Y or any other key to quit ' -ForegroundColor Yellow
                    ''
                    $input = Read-Host 'Enter (Y/N)'
                } while ($input -eq 'Y')
            }

            17 {
                $result = @()
                ''
                Write-Warning 'This section only works flawlessly on English Operating Systems.'
                ''
                $read = Read-Host 'Enter COMPUTER NAME to query logged on users'
                $cred = Get-Credential -Message 'Enter Username and Password of a Member of the Domain Admins Group (domain/username)'

                # quser-Ausgabe per Invoke-Command einsammeln und parsen (sprach-/formatabhängig)
                Invoke-Command -ComputerName $read -ScriptBlock { quser } -Credential $cred |
                    Select-Object -Skip 1 | ForEach-Object {
                        $b = $_.trim() -replace '\s+',' ' -replace '>','' -split '\s'
                        # Sprach-/Spaltenheuristik: bei 'Disc*'/'Getr*' anderes Off-By-One
                        if ( ($b[2] -like 'Disc*') -or ($b[2] -like 'Getr*') ) {
                            $result += New-Object -TypeName PSObject -Property ([ordered]@{
                                'User'    = $b[0]
                                'Computer'= $read
                                'Date'    = $b[4]
                                'Time'    = $b[5..6] -join ' '
                            })
                        }
                        else {
                            $result += New-Object -TypeName PSObject -Property ([ordered]@{
                                'User'    = $b[0]
                                'Computer'= $read
                                'Date'    = $b[5]
                                'Time'    = $b[6..7] -join ' '
                            })
                        }
                    }
                ''
                Write-Host "User Logons on $read" -ForegroundColor Green
                $result | Format-Table
                Read-Host 'Press 0 and Enter to continue'
            }

            18 {
                # Nachrichten via msg an Benutzer/Terminalsitzungen
                do {
                    Write-Host ''
                    Write-Host 'To which computers should a message be sent?'
                    Write-Host ''
                    Write-Host '1 - Localhost'                 -ForegroundColor Yellow
                    Write-Host '2 - Remote Computer (Enter Computername)' -ForegroundColor Yellow
                    Write-Host '3 - All Windows Server'        -ForegroundColor Yellow
                    Write-Host '4 - All Windows Computer'      -ForegroundColor Yellow
                    Write-Host '0 - Quit'                      -ForegroundColor Yell  # BUG: Yell -> wohl Yellow
                    Write-Host ''

                    $scopemsg = Read-Host 'Select'
                    switch ($scopemsg) {
                        1 {
                            ''
                            Write-Host 'Enter message sent to all users logged on LOCALHOST' -ForegroundColor Yellow
                            ''
                            $msg = Read-Host 'Message'
                            msg * "$msg"
                        }
                        2 {
                            ''
                            Write-Host 'Separate multiple computernames by comma. (example: server01,server02)' -ForegroundColor Yellow
                            ''
                            $comp  = Read-Host 'Enter Computername'
                            $comps = $comp.Split(',')
                            ''
                            $msg  = Read-Host 'Enter Message'
                            $cred = Get-Credential -Message 'Enter Username and Password of a Member of the Domain Admins Group'
                            Invoke-Command -ComputerName $comps -Credential $cred -ScriptBlock { msg * $using:msg }
                        }
                        3 {
                            ''
                            Write-Host 'Note that the message will be sent to all servers!' -ForegroundColor Yellow
                            ''
                            $msg  = Read-Host 'Enter Message'
                            $cred = Get-Credential -Message 'Enter Username and Password of a Member of the Domain Admins Group'
                            (Get-ADComputer -Filter { operatingsystem -like '*server*' }).Name | ForEach-Object {
                                Invoke-Command -ComputerName $_ -ScriptBlock { msg * $using:msg } -Credential $cred -ErrorAction SilentlyContinue
                            }
                        }
                        4 {
                            ''
                            Write-Host 'Note that the message will be sent to all computers!' -ForegroundColor Yellow
                            ''
                            $msg  = Read-Host 'Enter Message'
                            $cred = Get-Credential -Message 'Enter Username and Password of a Member of the Domain Admins Group'
                            (Get-ADComputer -Filter *).Name | ForEach-Object {
                                Invoke-Command -ComputerName $_ -ScriptBlock { msg * $using:msg } -Credential $cred -ErrorAction SilentlyContinue
                            }
                        }
                    }
                } while ($scopemsg -ne '0')
            }

            19 {
                ''
                Write-Host 'Enter U for searching orphaned USER accounts or C for COMPUTER accounts or Q to quit' -ForegroundColor Yellow
                ''
                $orp = Read-Host 'Enter (U/C)'
                if ($orp -eq 'Q') { break }
                ''
                Write-Host 'Enter time span in DAYS in which USERS or COMPUTERS have not logged on since today. Example: If you enter 365 days, the system searches for all users/computers who have not logged on for a year.' -ForegroundColor Yellow
                ''
                $span = Read-Host 'Timespan'

                if ($orp -eq 'U') {
                    ''
                    Write-Host "The following USERS are enabled and have not logged on for $span days:" -ForegroundColor Green
                    # Hinweis: Filter 'enabled -ne $false' ist fragwürdig. Besser: -LDAPFilter oder Scriptblock.
                    Get-ADUser -Filter 'enabled -ne $false' -Properties LastLogonDate, whenCreated |
                        Where-Object { $_.lastlogondate -ne $null -and $_.lastlogondate -le ((Get-Date).AddDays(-$span)) } |
                        Format-Table Name, SamAccountName, LastLogonDate, whenCreated
                    Write-Host 'User and Computer Logons are replicated every 14 days. Data might be not completely up-to-date.' -ForegroundColor Yellow
                    ''
                    Read-Host 'Press 0 and Enter to continue'
                }

                if ($orp -eq 'C') {
                    ''
                    Write-Host "The following COMPUTERS are enabled have not logged on for $span days:" -ForegroundColor Green
                    Get-ADComputer -Filter 'enabled -ne $false' -Properties LastLogonDate, whenCreated |
                        Where-Object { $_.lastlogondate -ne $null -and $_.lastlogondate -le ((Get-Date).AddDays(-$span)) } |
                        Format-Table Name, SamAccountName, LastLogonDate, whenCreated
                    Write-Host 'User and Computer Logons are replicated every 14 days. Data might be not completely up-to-date.' -ForegroundColor Yellow
                    ''
                    Read-Host 'Press 0 and Enter to continue'
                }
            }

            20 {
                # Time-Based Group Membership (TTL) – Voraussetzungen prüfen
                $checkF = (Get-ADForest).ForestMode
                $opt    = (Get-ADOptionalFeature -Identity "Privileged Access Management Feature").enabledscopes
                ''
                if ( ($checkF -like '*2016*') -or ($checkF -like '*2019*') -and ($opt.Count -ne '0') ) {
                    ''
                    Write-Host ("Forest mode is $checkF. Privileged Access Management Feature enabled. Everything's fine. Moving on ...") -ForegroundColor Green
                    ''
                    Write-Host "This section configures Time-Based-Group-Membership. Provide User, Group and Timespan." -ForegroundColor Green
                    ''
                    # USER erfragen & prüfen
                    do {
                        Write-Host 'Enter USER LOGON Name for Time-Based-Group-Membership or press Q to quit.' -ForegroundColor Yellow
                        ''
                        $user = Read-Host 'USER LOGON Name'
                        if ($user -eq 'Q') { break }
                        $ds = dsquery user -samid $user
                        ''
                        if ($ds) { Write-Host "User $user found!" -ForegroundColor Green }
                        else     { Write-Host "User $user not found. Try again" -ForegroundColor Red }
                        ''
                    } while (!$ds)

                    # GROUP erfragen & prüfen
                    do {
                        if ($user -eq 'Q') { break }
                        Write-Host 'Enter GROUP Name for Time-Based-Group-Membership or press Q to quit.' -ForegroundColor Yellow
                        ''
                        $group = Read-Host 'GROUP Name'
                        if ($group -eq 'Q') { break }
                        $dsg = dsquery group -samid $group
                        ''
                        if ($dsg) { Write-Host "Group $group found!" -ForegroundColor Green }
                        else      { Write-Host "Group $group not found. Try again" -ForegroundColor Red }
                        ''
                        if ($group -eq 'Q') { break }
                    } while (!$dsg)

                    if ( ($user -eq 'Q') -or ($group -eq 'Q') ) { break }

                    Write-Host 'Enter timespan for Group Membership in HOURS or Q to quit' -ForegroundColor Yellow
                    ''
                    $timegpm = Read-Host 'TIMESPAN'
                    if ($timegpm -eq 'Q') { break }

                    # TTL-Attribut setzen – Mitgliedschaft erlischt automatisch nach Ablauf
                    Add-ADGroupMember -Identity "$group" -Members $user -MemberTimeToLive (New-TimeSpan -Hours $timegpm)
                    ''
                    Write-Host "Here's your configuration:" -ForegroundColor Yellow
                    ''
                    $groupup = $group.ToUpper()
                    Write-Host "Time-Based-Group-Membership for $groupup" -ForegroundColor Green
                    ''
                    # Anzeige der Member inkl. TTL (ShowMemberTimeToLive)
                    Get-ADGroup $group -Properties Member -ShowMemberTimeToLive | 
                        Select-Object Name -ExpandProperty Member | Where-Object { ($_ -like '*TTL*') }
                    Write-Host ''
                    Read-Host 'Press 0 and Enter to continue'
                }
                else {
                    ''
                    $fname = (Get-ADForest).Name
                    Write-Host 'Operation aborted.' -ForegroundColor Red
                    ''
                    Write-Host ("The forest $fname does not meet the minimum requirements (Windows Server 2016 Forest Mode) and/or the Privileged Access Management Feature is not enabled. Solution: Upgrade all Domain Controllers to Windows Server 2016, then raise the Forest Level and activate Privileged Access Management.") -ForegroundColor Yellow
                    ''
                    Read-Host 'Press 0 and Enter to continue'
                }
            }

            21 {
                ''
                Write-Host "This menu item creates a new AD User based on an existing one for the domain $env:userdnsdomain." -ForegroundColor Green
                ''
                # Vorlage (bestehender Benutzer) erfragen
                do {
                    Write-Host 'Enter LOGON NAME of an EXISTING USER to copy (Q to quit)' -ForegroundColor Yellow
                    ''
                    $nameds = Read-Host 'LOGON NAME (existing user)'
                    if ($nameds -eq 'Q') { break }
                    if ( dsquery user -samid $nameds ) {
                        ''
                        Write-Host -ForegroundColor Green "AD User $nameds found!"
                    }
                    elseif ($nameds = 'null') {  # BUG: "=" weist zu; sollte "-eq" sein
                        ''
                        Write-Host 'User not found. Please try again.' -ForegroundColor Red
                        ''
                    }
                } while ($nameds -eq 'null')

                if ($nameds -eq 'Q') { break }

                # Eigenschaften der Vorlage laden
                $name = Get-ADUser -Identity $nameds -Properties *
                $DN   = $name.DistinguishedName
                $OldUser = [ADSI]"LDAP://$DN"
                $Parent  = $OldUser.Parent
                $OU      = [ADSI]$Parent
                $OUDN    = $OU.DistinguishedName

                # Neuen Benutzer erfassen
                Write-Host ''
                Write-Host 'Enter the LOGON NAME of the NEW USER' -ForegroundColor Yellow
                ''
                $NewUser  = Read-Host 'LOGON NAME (new user)'
                $firstname = Read-Host 'First Name'
                $Lastname  = Read-Host 'Last Name'
                $NewName   = "$firstname $lastname"
                $domain    = [System.DirectoryServices.ActiveDirectory.Domain]::GetCurrentDomain()
                $prof      = $name.ProfilePath

                Write-Host "Are you sure you want to create user $firstname $lastname with the logon name $newuser and copy properties from $nameds to $newuser (Y/N)" -ForegroundColor Yellow
                ''
                $surely = Read-Host 'Enter (Y/N)'
                if ($surely -eq 'y') {
                    # New-ADUser mit -Instance $DN (ungewöhnlich: -Instance erwartet eigentlich ein ADUser-Objekt, hier DN-String)
                    # Belassen wie im Original, Hinweis: Sicherstellen, dass Pflichtfelder/UPN korrekt sind.
                    New-ADUser -SamAccountName $NewUser -Name $NewName -GivenName $firstname -displayname "$firstname $lastname" -Surname $lastname -Instance $DN -Path "$OUDN" -AccountPassword (Read-Host "Enter Password for $firstname $lastname" -AsSecureString) –userPrincipalName ($NewUser + '@' + $domain) -Company $name.Company -Department $name.Department -Manager $name.Manager -title $name.Title -Office $name.Office -City $name.city -PostalCode $name.postalcode -Country $name.country -Fax $name.fax -State $name.State -StreetAddress $name.StreetAddress -Enabled $true -ProfilePath ($prof -replace $name.SamAccountName, $NewUser) -HomePage $name.wWWHomePage -ScriptPath $name.ScriptPath
                    Set-ADUser -Identity $newUser -ChangePasswordAtLogon $true
                    ''
                    Write-Host 'Copying Group Memberships, Profile Path, Logon Script and more ...'
                    $groups = (Get-ADUser –Identity $name –Properties MemberOf).MemberOf
                    foreach ($group in $groups) { Add-ADGroupMember -Identity $group -Members $NewUser }
                    ''
                    Write-Host 'The following user has been created by the Active Directory Services Section Tool:' -ForegroundColor Green
                    Get-ADUser $NewUser -Properties * | Format-List GivenName, SurName, CanonicalName, Enabled, ProfilePath, ScriptPath, MemberOf, whencreated
                }
                else { break }
                Read-Host 'Press 0 and Enter to continue'
            }

            22 {
                ''
                Write-Host "This menu item deactivates an AD User in the domain $env:userdnsdomain." -ForegroundColor Yellow
                ''
                do {
                    $a = Read-Host 'Enter LOGON NAME of the user to be deactivated (Q to quit)'
                    if ($a -eq 'Q') { break }
                    if ( dsquery user -samid $a ) {
                        ''
                        Write-Host -ForegroundColor Green "AD User $a found!"
                    }
                    elseif ($a = 'null') {  # BUG: "=" statt "-eq"
                        ''
                        Write-Host -ForegroundColor Red 'AD User not found. Please try again.'
                        ''
                    }
                } while ($a -eq 'null')

                if ($a -eq 'Q') { break }

                $det = ((Get-ADuser -Identity $a).GivenName + ' ' + (Get-ADUser -Identity $a).SurName)
                ''
                Write-Host "User $det will be deactivated. Are you sure? (Y/N)" -ForegroundColor Yellow
                ''
                $sure = Read-Host 'Enter (Y/N)'
                if ($sure -eq 'Y') {
                    Get-ADUser -Identity "$a" | Set-ADUser -Enabled $false
                    ''
                    Write-Host -ForegroundColor Green "User $a has been deactivated."
                    ''
                    $b = Read-Host "Do you want to remove all group memberships from that user ($a)? (Y/N)"
                    if ($b -eq 'Y') {
                        $ADgroups = Get-ADPrincipalGroupMembership -Identity "$a" | Where-Object { $_.Name -ne 'Domain Users' }
                        if ($ADgroups -ne $null) {
                            Remove-ADPrincipalGroupMembership -Identity "$a" -MemberOf $ADgroups -Confirm:$false -WarningAction SilentlyContinue -ErrorAction Ignore
                        }
                    }
                }
                else { break }
                ''
                Write-Host 'The following user has been deactivated by the Active Directory Services Section Tool:' -ForegroundColor Green
                Get-ADUser $a -Properties * | Format-List GivenName, SurName, DistinguishedName, Enabled, MemberOf, LastLogonDate, whencreated
                Read-Host 'Press 0 and Enter to continue'
            }
        }

    } while ($input -ne '0')
}
