param(
  [switch]$SelfTest
)

Set-StrictMode -Version 2.0

$ErrorActionPreference = "Stop"
$script:AppRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$script:AssetRoot = Join-Path $script:AppRoot "assets\fixture-icons"
$script:LondonTimeZone = [System.TimeZoneInfo]::FindSystemTimeZoneById("GMT Standard Time")
$script:Fixtures = @()
$script:WarningText = "Loading fixtures..."
$script:FetchJob = $null
$script:StackPanel = $null
$script:StatusText = $null

function Get-Prop {
  param($Object, [string]$Name)
  if ($null -eq $Object) { return $null }
  $property = $Object.PSObject.Properties[$Name]
  if ($null -eq $property) { return $null }
  return $property.Value
}

function Get-UtcDate {
  param([string]$Value)
  return [System.DateTimeOffset]::Parse(
    $Value,
    [System.Globalization.CultureInfo]::InvariantCulture,
    [System.Globalization.DateTimeStyles]::AssumeUniversal
  ).UtcDateTime
}

function Convert-ToLondonTime {
  param([datetime]$UtcDate)
  $utc = [datetime]::SpecifyKind($UtcDate, [System.DateTimeKind]::Utc)
  return [System.TimeZoneInfo]::ConvertTimeFromUtc($utc, $script:LondonTimeZone)
}

function Get-DisplayDateKey {
  param([datetime]$UtcDate)
  $local = Convert-ToLondonTime $UtcDate
  $displayDate = $local.Date
  if ($local.TimeOfDay -le ([timespan]::FromHours(6))) {
    $displayDate = $displayDate.AddDays(-1)
  }
  return $displayDate.ToString("yyyy-MM-dd", [System.Globalization.CultureInfo]::InvariantCulture)
}

function Get-CurrentDisplayDateKey {
  param([datetime]$Now)
  return Get-DisplayDateKey ([datetime]::SpecifyKind($Now.ToUniversalTime(), [System.DateTimeKind]::Utc))
}

function Format-Countdown {
  param([datetime]$KickoffUtc, [datetime]$Now)
  $totalMinutes = [math]::Max(0, [int][math]::Round(($KickoffUtc - $Now.ToUniversalTime()).TotalMinutes))

  if ($totalMinutes -le 60) {
    return "in ${totalMinutes}min"
  }

  $roundedMinutes = [int]([math]::Round($totalMinutes / 15) * 15)
  $hours = [int][math]::Floor($roundedMinutes / 60)
  $minutes = $roundedMinutes % 60

  if ($minutes -eq 0) {
    return "in ${hours}hrs"
  }

  return "in ${hours}hrs ${minutes}min"
}

function Should-ShowCountdown {
  param($Fixture, [datetime]$Now)
  return ($Fixture.KickoffUtc -gt $Now.ToUniversalTime()) -and
    ($Fixture.DisplayDate -eq (Get-CurrentDisplayDateKey $Now))
}

function Get-OrdinalSuffix {
  param([int]$Day)
  if ($Day -ge 11 -and $Day -le 13) { return "th" }

  switch ($Day % 10) {
    1 { return "st" }
    2 { return "nd" }
    3 { return "rd" }
    default { return "th" }
  }
}

function Format-DateHeader {
  param([string]$DisplayDate, [string]$CurrentDisplayDate)
  if ($DisplayDate -eq $CurrentDisplayDate) { return $null }

  $date = [datetime]::ParseExact($DisplayDate, "yyyy-MM-dd", [System.Globalization.CultureInfo]::InvariantCulture)
  $tomorrow = [datetime]::ParseExact($CurrentDisplayDate, "yyyy-MM-dd", [System.Globalization.CultureInfo]::InvariantCulture).AddDays(1)
  if ($date -eq $tomorrow) { return "tomorrow" }

  $weekday = $date.ToString("ddd", [System.Globalization.CultureInfo]::GetCultureInfo("en-GB")).ToUpperInvariant()
  return "$weekday $($date.Day)$(Get-OrdinalSuffix $date.Day)"
}

function Normalize-Team {
  param($Team)
  $name = Get-Prop $Team "name"
  $tla = Get-Prop $Team "tla"

  if ([string]::IsNullOrWhiteSpace($tla)) {
    $tla = "TBD"
  } else {
    $tla = $tla.Trim().ToUpperInvariant()
    if ($tla -eq "GERM") { $tla = "GER" }
    if ($tla.Length -gt 3) { $tla = $tla.Substring(0, 3) }
  }

  if ([string]::IsNullOrWhiteSpace($name)) {
    $name = $tla
  }

  return [pscustomobject]@{
    Name = [string]$name
    Tla = [string]$tla
  }
}

function Convert-MatchesToFixtures {
  param($Matches, [datetime]$Now)

  $validStatuses = @("SCHEDULED", "TIMED")
  $items = New-Object System.Collections.Generic.List[object]

  foreach ($match in @($Matches)) {
    $utcDate = Get-Prop $match "utcDate"
    $status = Get-Prop $match "status"
    if ([string]::IsNullOrWhiteSpace($utcDate)) { continue }
    if ($validStatuses -notcontains $status) { continue }

    $kickoffUtc = Get-UtcDate $utcDate
    if ($kickoffUtc -le $Now.ToUniversalTime()) { continue }

    $items.Add([pscustomobject]@{
      Id = Get-Prop $match "id"
      KickoffUtc = $kickoffUtc
      Status = $status
      Stage = Get-Prop $match "stage"
      Group = Get-Prop $match "group"
      Matchday = Get-Prop $match "matchday"
      HomeTeam = Normalize-Team (Get-Prop $match "homeTeam")
      AwayTeam = Normalize-Team (Get-Prop $match "awayTeam")
      Venue = Get-Prop $match "venue"
      DisplayDate = Get-DisplayDateKey $kickoffUtc
    })
  }

  return @($items | Sort-Object KickoffUtc)
}

function Assert-FixtureLogic {
  $now = Get-UtcDate "2026-06-23T16:00:00Z"
  if ((Format-Countdown (Get-UtcDate "2026-06-23T20:26:00Z") $now) -ne "in 4hrs 30min") { throw "Countdown rounding failed" }
  if ((Format-Countdown (Get-UtcDate "2026-06-23T20:20:00Z") $now) -ne "in 4hrs 15min") { throw "Countdown rounding down failed" }
  if ((Format-Countdown (Get-UtcDate "2026-06-23T16:42:00Z") $now) -ne "in 42min") { throw "Sub-hour countdown failed" }
  if ((Format-Countdown (Get-UtcDate "2026-06-23T17:00:00Z") $now) -ne "in 60min") { throw "Exactly-60 countdown failed" }
  if ((Get-DisplayDateKey (Get-UtcDate "2026-06-24T04:30:00Z")) -ne "2026-06-23") { throw "Display cutoff failed" }
  if ((Normalize-Team ([pscustomobject]@{ name = "Germany"; tla = "GERM" })).Tla -ne "GER") { throw "GER normalisation failed" }
}

if ($SelfTest) {
  Assert-FixtureLogic
  Write-Host "Self-test passed."
  exit 0
}

Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase
Add-Type @"
using System;
using System.Runtime.InteropServices;

public static class DwmTitleBar {
  [DllImport("dwmapi.dll")]
  public static extern int DwmSetWindowAttribute(IntPtr hwnd, int attr, ref int attrValue, int attrSize);
}
"@

function Enable-DarkTitleBar {
  param([System.Windows.Window]$Window)

  $helper = New-Object System.Windows.Interop.WindowInteropHelper($Window)
  $enabled = 1

  # Windows 10 20H1+ uses 20; older Windows 10 builds used 19.
  [void][DwmTitleBar]::DwmSetWindowAttribute($helper.Handle, 20, [ref]$enabled, 4)
  [void][DwmTitleBar]::DwmSetWindowAttribute($helper.Handle, 19, [ref]$enabled, 4)
}

function New-Brush {
  param([string]$Hex)
  return New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.ColorConverter]::ConvertFromString($Hex))
}

function New-BitmapImage {
  param([string]$Path)
  $image = New-Object System.Windows.Media.Imaging.BitmapImage
  $image.BeginInit()
  $image.CacheOption = [System.Windows.Media.Imaging.BitmapCacheOption]::OnLoad
  $image.UriSource = New-Object System.Uri($Path, [System.UriKind]::Absolute)
  $image.EndInit()
  $image.Freeze()
  return $image
}

function Add-Child {
  param($Parent, $Child)
  [void]$Parent.Children.Add($Child)
}

function New-TeamTile {
  param($Team)
  $asset = Join-Path $script:AssetRoot "$($Team.Tla).png"

  if (Test-Path -LiteralPath $asset) {
    $image = New-Object System.Windows.Controls.Image
    $image.Width = 96
    $image.Height = 36
    $image.Stretch = [System.Windows.Media.Stretch]::None
    $image.Source = New-BitmapImage ((Resolve-Path -LiteralPath $asset).Path)
    $image.ToolTip = $Team.Name
    return $image
  }

  $border = New-Object System.Windows.Controls.Border
  $border.Width = 96
  $border.Height = 36
  $border.BorderBrush = New-Brush "#2a3139"
  $border.BorderThickness = 1
  $border.Background = New-Brush "#171c22"
  $border.ToolTip = $Team.Name

  $text = New-Object System.Windows.Controls.TextBlock
  $text.Text = if ([string]::IsNullOrWhiteSpace($Team.Tla)) { "TBD" } else { $Team.Tla }
  $text.Foreground = New-Brush "#d7dde7"
  $text.FontSize = 18
  $text.FontWeight = [System.Windows.FontWeights]::Bold
  $text.HorizontalAlignment = "Center"
  $text.VerticalAlignment = "Center"
  $border.Child = $text
  return $border
}

function New-VsTile {
  $path = Join-Path $script:AssetRoot "VS.png"
  $image = New-Object System.Windows.Controls.Image
  $image.Width = 42
  $image.Height = 36
  $image.Stretch = [System.Windows.Media.Stretch]::None
  $image.Source = New-BitmapImage ((Resolve-Path -LiteralPath $path).Path)
  return $image
}

function New-CountdownBlock {
  param([string]$Text)
  $block = New-Object System.Windows.Controls.TextBlock
  $block.Width = 157
  $block.Margin = New-Object System.Windows.Thickness(0, 8, 0, 0)
  $block.TextAlignment = "Center"

  foreach ($token in [regex]::Split($Text, "(\d+)")) {
    if ([string]::IsNullOrEmpty($token)) { continue }
    $run = New-Object System.Windows.Documents.Run($token)
    if ($token -match "^\d+$") {
      $run.Foreground = New-Brush "#b9c1cd"
      $run.FontSize = 20
      $run.FontWeight = [System.Windows.FontWeights]::SemiBold
    } else {
      $run.Foreground = New-Brush "#858d9a"
      $run.FontSize = 13
      $run.FontWeight = [System.Windows.FontWeights]::Medium
    }
    [void]$block.Inlines.Add($run)
  }

  return $block
}

function New-FixtureRow {
  param($Fixture, [datetime]$Now)
  $row = New-Object System.Windows.Controls.StackPanel
  $row.Width = 238
  $row.HorizontalAlignment = "Center"
  $row.Margin = New-Object System.Windows.Thickness(0, 0, 0, 34)

  $strip = New-Object System.Windows.Controls.Grid
  $strip.Width = 238
  $strip.Height = 36
  foreach ($width in @(96, 2, 42, 2, 96)) {
    $column = New-Object System.Windows.Controls.ColumnDefinition
    $column.Width = New-Object System.Windows.GridLength($width)
    $strip.ColumnDefinitions.Add($column)
  }

  $homeTile = New-TeamTile $Fixture.HomeTeam
  $vs = New-VsTile
  $away = New-TeamTile $Fixture.AwayTeam
  [System.Windows.Controls.Grid]::SetColumn($homeTile, 0)
  [System.Windows.Controls.Grid]::SetColumn($vs, 2)
  [System.Windows.Controls.Grid]::SetColumn($away, 4)
  Add-Child $strip $homeTile
  Add-Child $strip $vs
  Add-Child $strip $away
  Add-Child $row $strip

  if (Should-ShowCountdown $Fixture $Now) {
    Add-Child $row (New-CountdownBlock (Format-Countdown $Fixture.KickoffUtc $Now))
  }

  return $row
}

function New-DayHeader {
  param([string]$Label)
  $grid = New-Object System.Windows.Controls.Grid
  $grid.Width = 218
  $grid.Height = 14
  $grid.Margin = New-Object System.Windows.Thickness(0, 16, 0, 13)

  foreach ($width in @("*", "Auto", "*")) {
    $column = New-Object System.Windows.Controls.ColumnDefinition
    $column.Width = New-Object System.Windows.GridLength(1, [System.Windows.GridUnitType]::Star)
    if ($width -eq "Auto") { $column.Width = [System.Windows.GridLength]::Auto }
    $grid.ColumnDefinitions.Add($column)
  }

  foreach ($columnIndex in @(0, 2)) {
    $line = New-Object System.Windows.Controls.Border
    $line.Height = 1
    $line.Background = New-Brush "#252c34"
    $line.VerticalAlignment = "Center"
    [System.Windows.Controls.Grid]::SetColumn($line, $columnIndex)
    Add-Child $grid $line
  }

  $text = New-Object System.Windows.Controls.TextBlock
  $text.Text = $Label
  $text.Foreground = New-Brush "#636b76"
  $text.FontSize = 12
  $text.Margin = New-Object System.Windows.Thickness(12, 0, 12, 0)
  $text.VerticalAlignment = "Center"
  [System.Windows.Controls.Grid]::SetColumn($text, 1)
  Add-Child $grid $text
  return $grid
}

function Update-View {
  if ($null -eq $script:StackPanel) { return }

  $script:StackPanel.Children.Clear()
  $now = Get-Date
  $currentDisplayDate = Get-CurrentDisplayDateKey $now

  if ($script:Fixtures.Count -eq 0) {
    $message = New-Object System.Windows.Controls.TextBlock
    $message.Width = 238
    $message.Margin = New-Object System.Windows.Thickness(0, 44, 0, 0)
    $message.Text = if ([string]::IsNullOrWhiteSpace($script:WarningText)) { "No upcoming fixtures found." } else { $script:WarningText }
    $message.Foreground = New-Brush "#9ba4b1"
    $message.FontSize = 13
    $message.TextAlignment = "Center"
    $message.TextWrapping = "Wrap"
    Add-Child $script:StackPanel $message
  } else {
    $groups = $script:Fixtures | Group-Object DisplayDate | Sort-Object Name
    $isFirstGroup = $true

    foreach ($group in $groups) {
      if (-not $isFirstGroup) {
        $spacer = New-Object System.Windows.Controls.Border
        $spacer.Height = 5
        Add-Child $script:StackPanel $spacer
      }

      $label = Format-DateHeader $group.Name $currentDisplayDate
      if ($null -ne $label) {
        Add-Child $script:StackPanel (New-DayHeader $label)
      }

      foreach ($fixture in @($group.Group | Sort-Object KickoffUtc)) {
        Add-Child $script:StackPanel (New-FixtureRow $fixture $now)
      }

      $isFirstGroup = $false
    }
  }

  if ($null -ne $script:StatusText) {
    $script:StatusText.Text = if ([string]::IsNullOrWhiteSpace($script:WarningText)) { "resize for more" } else { $script:WarningText }
  }
}

function Start-FixtureFetch {
  if ($null -ne $script:FetchJob -and $script:FetchJob.State -eq "Running") { return }

  $token = [Environment]::GetEnvironmentVariable("FOOTBALL_DATA_API_KEY")
  if ([string]::IsNullOrWhiteSpace($token)) {
    $script:WarningText = "Set FOOTBALL_DATA_API_KEY to load fixtures."
    Update-View
    return
  }

  $today = (Get-Date).ToString("yyyy-MM-dd", [System.Globalization.CultureInfo]::InvariantCulture)
  $uri = "https://api.football-data.org/v4/competitions/WC/matches?season=2026&dateFrom=$today&dateTo=2026-07-20"
  $script:StatusText.Text = "refreshing"

  $script:FetchJob = Start-Job -ScriptBlock {
    param([string]$Uri, [string]$Token)
    try {
      $request = [System.Net.HttpWebRequest]::Create($Uri)
      $request.Method = "GET"
      $request.Timeout = 20000
      $request.Headers.Add("X-Auth-Token", $Token)
      $response = $request.GetResponse()
      $reader = New-Object System.IO.StreamReader($response.GetResponseStream())
      $body = $reader.ReadToEnd()
      $reader.Close()
      $response.Close()
      [pscustomobject]@{ Ok = $true; Status = 200; Body = $body; Message = "" }
    } catch {
      $status = 0
      if ($_.Exception.Response -and $_.Exception.Response.StatusCode) {
        $status = [int]$_.Exception.Response.StatusCode
      }
      [pscustomobject]@{ Ok = $false; Status = $status; Body = ""; Message = $_.Exception.Message }
    }
  } -ArgumentList $uri, $token
}

function Complete-FixtureFetch {
  if ($null -eq $script:FetchJob) { return }
  if ($script:FetchJob.State -eq "Running") { return }

  $result = Receive-Job $script:FetchJob
  Remove-Job $script:FetchJob
  $script:FetchJob = $null

  if ($null -eq $result) {
    $script:WarningText = "Could not refresh fixtures; showing the last successful list."
    Update-View
    return
  }

  if ($result.Ok) {
    $data = $result.Body | ConvertFrom-Json
    $script:Fixtures = Convert-MatchesToFixtures (Get-Prop $data "matches") (Get-Date)
    $script:WarningText = $null
  } elseif ($result.Status -eq 429) {
    $script:WarningText = "Rate limit reached; retrying later."
  } else {
    $script:WarningText = "Could not refresh fixtures; showing the last successful list."
  }

  Update-View
}

$window = New-Object System.Windows.Window
$window.Title = "fixtures"
$window.Width = 316
$window.Height = 420
$window.MinWidth = 316
$window.MaxWidth = 316
$window.MinHeight = 270
$window.Background = New-Brush "#11151a"
$window.Foreground = New-Brush "#7f8896"
$window.FontFamily = New-Object System.Windows.Media.FontFamily("Segoe UI")
$window.WindowStartupLocation = "CenterScreen"
$window.ResizeMode = "CanResize"
$window.Add_SourceInitialized({ Enable-DarkTitleBar $window })

$root = New-Object System.Windows.Controls.Grid
$root.Background = New-Brush "#11151a"
$rowContent = New-Object System.Windows.Controls.RowDefinition
$rowContent.Height = New-Object System.Windows.GridLength(1, [System.Windows.GridUnitType]::Star)
$rowStatus = New-Object System.Windows.Controls.RowDefinition
$rowStatus.Height = New-Object System.Windows.GridLength(24)
$root.RowDefinitions.Add($rowContent)
$root.RowDefinitions.Add($rowStatus)

$scroll = New-Object System.Windows.Controls.ScrollViewer
$scroll.VerticalScrollBarVisibility = "Hidden"
$scroll.HorizontalScrollBarVisibility = "Disabled"
$scroll.Margin = New-Object System.Windows.Thickness(0, 20, 0, 0)
$script:StackPanel = New-Object System.Windows.Controls.StackPanel
$script:StackPanel.HorizontalAlignment = "Center"
$script:StackPanel.Margin = New-Object System.Windows.Thickness(0, 0, 0, 12)
$scroll.Content = $script:StackPanel
[System.Windows.Controls.Grid]::SetRow($scroll, 0)
$root.Children.Add($scroll) | Out-Null

$script:StatusText = New-Object System.Windows.Controls.TextBlock
$script:StatusText.Text = "resize for more"
$script:StatusText.Foreground = New-Brush "#4e5661"
$script:StatusText.FontSize = 12
$script:StatusText.HorizontalAlignment = "Center"
$script:StatusText.VerticalAlignment = "Center"
[System.Windows.Controls.Grid]::SetRow($script:StatusText, 1)
$root.Children.Add($script:StatusText) | Out-Null

$window.Content = $root

$countdownTimer = New-Object System.Windows.Threading.DispatcherTimer
$countdownTimer.Interval = [timespan]::FromSeconds(30)
$countdownTimer.Add_Tick({ Update-View })
$countdownTimer.Start()

$refreshTimer = New-Object System.Windows.Threading.DispatcherTimer
$refreshTimer.Interval = [timespan]::FromMinutes(15)
$refreshTimer.Add_Tick({ Start-FixtureFetch })
$refreshTimer.Start()

$jobPollTimer = New-Object System.Windows.Threading.DispatcherTimer
$jobPollTimer.Interval = [timespan]::FromSeconds(1)
$jobPollTimer.Add_Tick({ Complete-FixtureFetch })
$jobPollTimer.Start()

$window.Add_MouseRightButtonUp({ Start-FixtureFetch })
$window.Add_Closed({
  if ($null -ne $script:FetchJob) {
    Stop-Job $script:FetchJob -ErrorAction SilentlyContinue
    Remove-Job $script:FetchJob -ErrorAction SilentlyContinue
  }
})

Update-View
Start-FixtureFetch

$app = New-Object System.Windows.Application
[void]$app.Run($window)
