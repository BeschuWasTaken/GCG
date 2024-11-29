# Import required module
Import-Module ActiveDirectory

# Set variables
$csvPath = "C:\Scripts\Input\AddADUsers.csv"
$domainController = "gcg-dc01"
$domain = "gcg.com"
$baseOU = "OU=Users,OU=gcg,DC=gcg,DC=com"

# Read CSV file
try {
    $users = Import-Csv -Path $csvPath -Delimiter "," -Encoding UTF8
}
catch {
    Write-Error "Error reading CSV file: $_"
    exit
}

# Function to replace Norwegian characters
function Replace-NorwegianChars {
    param (
        [string]$inputString
    )
    $outputString = $inputString -replace 'æ', 'e' `
                                    -replace 'ø', 'o' `
                                    -replace 'å', 'a'
    return $outputString
}

function Get-UniqueUsername {
    param (
        [Parameter(Mandatory)]
        [string]$GivenName,
        [Parameter(Mandatory)]
        [string]$Surname
    )

    # Get first 3 letters of given name and surname
    $givenPrefix = $GivenName.Substring(0, [Math]::Min(3, $GivenName.Length)).ToLower()
    $surnamePrefix = $Surname.Substring(0, [Math]::Min(3, $Surname.Length)).ToLower()
    
    # Initial username
    $baseUsername = "$givenPrefix$surnamePrefix"
    
    # Replace Norwegian characters in the username
    $baseUsername = Replace-NorwegianChars $baseUsername

    # Check if username exists
    if (-not (Get-ADUser -Filter "SamAccountName -eq '$baseUsername'" -ErrorAction SilentlyContinue)) {
        return $baseUsername
    }
    
    # If username exists, shift surname letters
    for ($i = 1; $i -lt $Surname.Length - 2; $i++) {
        $shiftedSurname = $Surname.Substring($i, [Math]::Min(3, $Surname.Length - $i)).ToLower()
        $newUsername = "$givenPrefix$shiftedSurname"
        
        $newUsername = Replace-NorwegianChars $newUsername

        if (-not (Get-ADUser -Filter "SamAccountName -eq '$newUsername'" -ErrorAction SilentlyContinue)) {
            return $newUsername
        }
    }
    
    throw "Unable to generate unique username for $($user.GivenName) $($user.Surname)"
}

function Get-UserManager {
    param (
        [Parameter(Mandatory)]
        [string]$Department,
        [Parameter(Mandatory)]
        [string]$Title
    )

    switch ($Department) {
        'Administration' {
            if ($Title -ne 'CEO') { return 'havmyr' }
        }
        'Sales' {
            if ($Title -eq 'Head of Sales') { return 'karsta' }
            return 'sonols'
        }
        'Development' {
            if ($Title -eq 'Lead Developer') { return 'mikcha' }
            return 'silped'
        }
        'Customer Support' {
            if ($Title -eq 'Lead Customer Support') { return 'havmyr' }
            return 'kjedah'
        }
        'Shipping' {
            if ($Title -eq 'Lead Shipping and Handling') { return 'havmyr' }
            return 'synjen'
        }
        'IT' {
            if ($Title -eq 'Lead IT') { return 'havmyr' }
            return 'henhen'
        }
        default {
            throw "Unknown department: $Department"
        }
    }
}

# Process each user
foreach ($user in $users) {
    try {
        # Create name in required format
        $name = if ([string]::IsNullOrWhiteSpace($user.MiddleName)) {
            "$($user.Surname), $($user.GivenName)"
        } else {
            "$($user.Surname), $($user.GivenName) $($user.MiddleName)"
        }
        $displayName = if ([string]::IsNullOrWhiteSpace($user.MiddleName)) {
            "$($user.GivenName) $($user.Surname)"
        } else {
            "$($user.GivenName) $($user.MiddleName) $($user.Surname)"
        }

        # Create initials, handling empty MiddleInitial
        $initials = if ([string]::IsNullOrWhiteSpace($user.MiddleName)) {
            "$($user.GivenName.Substring(0,1))$($user.Surname.Substring(0,1))"
        } else {
            "$($user.GivenName.Substring(0,1))$($user.MiddleName.Substring(0,1))$($user.Surname.Substring(0,1))"
        }

        # Create a username
        $SamAccountName = Get-UniqueUsername -GivenName $user.GivenName -Surname $user.Surname

        $title = if ([string]::IsNullOrWhiteSpace($user.Title)) {
            "$($user.Department) Consultant"
        } else {
            "$($user.Title)"
        }

        $group = "G_$($user.Department)"

        $manager = Get-UserManager -Department $user.Department -Title $title

        # Set user properties
        $userProps = @{
            'Name' = $name
            'DisplayName' = $displayName
            'GivenName' = $user.GivenName
            'Surname' = $user.Surname
            'Initials' = $initials
            'SamAccountName' = $SamAccountName
            'UserPrincipalName' = "$SamAccountName@$domain"
            'Title' = $title
            'Department' = $user.Department
            'Company' = "GPTClaudeGemini"
            'manager' = $manager
            'Office' = $user.Site
            'MobilePhone' = $user.Mobile
            'Enabled' = $false
            'ChangePasswordAtLogon' = $true
            'AccountPassword' = (ConvertTo-SecureString "Passord!234567" -AsPlainText -Force)
            'Path' = "OU=$($user.Department),$baseOU"
        }

        # Create new user
        New-ADUser @userProps -Server $domainController

        Write-Host "User $($SamAccountName) created successfully."
        
        # Add user to department group
        Add-ADGroupMember -Identity $group -Members $SamAccountName

        #Show what each of the values would be
        #Write-Host "User properties for $($user.SamAccountName):"
        #$userProps | Format-Table -AutoSize | Out-String | Write-Host
    }
    catch {
        Write-Error "Error creating user $($SamAccountName): $_"
        exit
    }
}

Write-Host "All users processed successfully."