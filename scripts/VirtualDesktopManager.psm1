# Virtual Desktop Manager Module
# Wraps the VirtualDesktop PowerShell module from PSGallery
# Install: Install-Module VirtualDesktop -Scope CurrentUser

#Requires -Modules VirtualDesktop

<#
.SYNOPSIS
    Creates a new virtual desktop and returns it.

.PARAMETER Name
    Optional name for the virtual desktop.

.OUTPUTS
    The newly created virtual desktop object.
#>
function New-WorktreeDesktop {
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$Name
    )

    try {
        # If a name was provided, check if a desktop with that name already exists
        if ($Name) {
            $desktopCount = Get-DesktopCount
            for ($i = 0; $i -lt $desktopCount; $i++) {
                $existing = Get-Desktop -Index $i
                if ($existing.Name -eq $Name) {
                    Write-Host "Virtual desktop already exists: $Name (index $i)"
                    return $existing
                }
            }
        }

        $desktop = New-Desktop

        if ($Name) {
            Set-DesktopName -Desktop $desktop -Name $Name
            Write-Host "Created new virtual desktop: $Name"
        } else {
            Write-Host "Created new virtual desktop: $($desktop.Name)"
        }

        return $desktop
    } catch {
        Write-Error "Failed to create virtual desktop: $_"
        return $null
    }
}

<#
.SYNOPSIS
    Closes all windows on a virtual desktop identified by task number, then removes the desktop.
    Finds the desktop by name prefix matching (convention: desktop name starts with task number).

.PARAMETER TaskNumber
    The task number used to find the virtual desktop by name prefix.

.PARAMETER CloseTimeoutSeconds
    Maximum seconds to wait for windows to close. Defaults to 30.

.OUTPUTS
    Boolean - True if desktop was found and removed, False if not found or failed.
#>
function Close-AllWindowsOnDesktop {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [int]$TaskNumber,

        [Parameter()]
        [int]$CloseTimeoutSeconds = 30
    )

    # Add Win32 type for enumerating all visible windows
    Add-Type @"
    using System;
    using System.Runtime.InteropServices;
    using System.Text;
    using System.Collections.Generic;

    public class Win32Window {
        [DllImport("user32.dll")]
        public static extern bool PostMessage(IntPtr hWnd, uint Msg, IntPtr wParam, IntPtr lParam);

        [DllImport("user32.dll")]
        [return: MarshalAs(UnmanagedType.Bool)]
        public static extern bool IsWindowVisible(IntPtr hWnd);

        [DllImport("user32.dll", CharSet = CharSet.Unicode)]
        public static extern int GetWindowText(IntPtr hWnd, StringBuilder text, int count);

        [DllImport("user32.dll")]
        public static extern int GetWindowTextLength(IntPtr hWnd);

        public delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);

        [DllImport("user32.dll")]
        public static extern bool EnumWindows(EnumWindowsProc lpEnumFunc, IntPtr lParam);

        public const uint WM_CLOSE = 0x0010;

        public static List<IntPtr> GetAllVisibleWindows() {
            var result = new List<IntPtr>();
            EnumWindows((hWnd, _) => {
                if (!IsWindowVisible(hWnd)) return true;
                int length = GetWindowTextLength(hWnd);
                if (length == 0) return true;
                result.Add(hWnd);
                return true;
            }, IntPtr.Zero);
            return result;
        }

        public static string GetTitle(IntPtr hWnd) {
            int length = GetWindowTextLength(hWnd);
            if (length == 0) return "";
            var sb = new StringBuilder(length + 1);
            GetWindowText(hWnd, sb, sb.Capacity);
            return sb.ToString();
        }
    }
"@ -ErrorAction SilentlyContinue

    # Find the virtual desktop by name prefix
    $targetDesktop = $null
    $desktopName = $null
    $desktopCount = Get-DesktopCount
    for ($i = 0; $i -lt $desktopCount; $i++) {
        $d = Get-Desktop -Index $i
        $name = Get-DesktopName -Desktop $d
        if ($name -like "$TaskNumber*") {
            $targetDesktop = $d
            $desktopName = $name
            Write-Host "Found virtual desktop: '$name' at index $i"
            break
        }
    }

    if (-not $targetDesktop) {
        Write-Host "No virtual desktop found for task $TaskNumber. Skipping desktop cleanup."
        return $false
    }

    # Enumerate all visible windows and find those on the target desktop
    $allWindows = [Win32Window]::GetAllVisibleWindows()
    $windowsOnDesktop = @()
    foreach ($hwnd in $allWindows) {
        try {
            if (Test-Window -Desktop $targetDesktop -Hwnd $hwnd -ErrorAction SilentlyContinue) {
                $windowsOnDesktop += $hwnd
            }
        } catch {
            # Some window handles don't support HasWindow — skip silently
        }
    }
    Write-Host "Found $($windowsOnDesktop.Count) window(s) on desktop '$desktopName'"

    # Send WM_CLOSE to each window on the desktop
    foreach ($hwnd in $windowsOnDesktop) {
        $title = [Win32Window]::GetTitle($hwnd)
        Write-Host "  Closing: '$title' (HWND $hwnd)"
        [Win32Window]::PostMessage($hwnd, [Win32Window]::WM_CLOSE, [IntPtr]::Zero, [IntPtr]::Zero) | Out-Null
    }

    # Wait for windows to close
    if ($windowsOnDesktop.Count -gt 0) {
        Write-Host "Waiting for windows to close..."
        $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
        while ($stopwatch.Elapsed.TotalSeconds -lt $CloseTimeoutSeconds) {
            Start-Sleep -Seconds 1
            $stillOpen = $windowsOnDesktop | Where-Object { [Win32Window]::IsWindowVisible($_) }
            if ($stillOpen.Count -eq 0) {
                Write-Host "All windows closed."
                break
            }
        }
        if ($stopwatch.Elapsed.TotalSeconds -ge $CloseTimeoutSeconds) {
            Write-Warning "Some windows did not close within $CloseTimeoutSeconds seconds. Proceeding anyway."
        }
    }

    # Remove the virtual desktop (remaining windows move to adjacent desktop)
    Start-Sleep -Seconds 1
    Remove-Desktop -Desktop $targetDesktop
    Write-Host "Removed virtual desktop: $desktopName"
    return $true
}

<#
.SYNOPSIS
    Removes a virtual desktop, moving any windows to the adjacent desktop.

.PARAMETER Desktop
    The virtual desktop object to remove.

.OUTPUTS
    Boolean - True if successful, False otherwise.
#>
function Remove-WorktreeDesktop {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $Desktop
    )

    try {
        Remove-Desktop -Desktop $Desktop
        Write-Host "Removed virtual desktop: $($Desktop.Name)"
        return $true
    } catch {
        Write-Error "Failed to remove virtual desktop: $_"
        return $false
    }
}

<#
.SYNOPSIS
    Switches to the specified virtual desktop.

.PARAMETER Desktop
    The virtual desktop object to switch to.
#>
function Switch-WorktreeDesktop {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $Desktop
    )

    try {
        Switch-Desktop -Desktop $Desktop
        Write-Host "Switched to desktop: $($Desktop.Name)"
    } catch {
        Write-Error "Failed to switch desktop: $_"
    }
}

# Export module functions
Export-ModuleMember -Function @(
    'New-WorktreeDesktop',
    'Remove-WorktreeDesktop',
    'Switch-WorktreeDesktop',
    'Close-AllWindowsOnDesktop'
)
