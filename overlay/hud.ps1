# Bureau overlay — a glass, rounded, always-on-top teleprompter HUD.
#
# Renders the last few narration summary lines with a typewriter effect and a
# small status indicator (working / done / action-needed). Non-interactive and
# click-through, so it floats over your work and never steals the mouse.
#
# It is a pure VIEW: it reads two files written by the WSL side and never writes
# back. It exits by itself the moment the armed flag disappears, so the Bureau
# controls its whole lifecycle.
#
#   -Feed    path to overlay.feed   (lines: "kind<TAB>text", newest last)
#   -Status  path to overlay.status (one token: working|done|action|blocked)
#   -Flag    path to overlay.armed  (window self-closes when this is gone)
#   -Vis     path to overlay.vis    (shown|hidden — drives the slide in/out)
#   -DoneMs  auto-fade delay after status hits 'done' (0 disables)
#   -Slot    stack position (0 = top); windows tile down the right edge
#   -Title   descriptive window label (which Bureau session this is)
#
# All paths are WINDOWS paths (the caller converts via wslpath -w). Multi-session
# safety lives in the WSL scripts (per-instance files + slot assignment); this
# window just renders the files and sits at the slot it was given.

param(
  [Parameter(Mandatory=$true)][string]$Feed,
  [Parameter(Mandatory=$true)][string]$Status,
  [Parameter(Mandatory=$true)][string]$Flag,
  [Parameter(Mandatory=$true)][string]$Vis,
  [int]$DoneMs = 12000,
  [int]$Slot = 0,
  [string]$Title = "BUREAU"
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase

# --- click-through / layered window interop ------------------------------------
$sig = @'
[DllImport("user32.dll")] public static extern int GetWindowLong(IntPtr hwnd, int index);
[DllImport("user32.dll")] public static extern int SetWindowLong(IntPtr hwnd, int index, int newStyle);
'@
$U = Add-Type -MemberDefinition $sig -Name 'BureauU32' -Namespace 'Bureau' -PassThru

# --- how many lines the teleprompter shows ------------------------------------
$LINES = 3
# Opacity gradient oldest -> newest (teleprompter fade).
$FADE = @(0.40, 0.68, 1.00)

# --- XAML shell ---------------------------------------------------------------
# A rounded, semi-transparent "glass" card. Text blocks are pre-created and
# updated in place each tick (no visual-tree rebuilds). Newest line is at the
# bottom, brightest, and types out; older lines dim and scroll up.
[xml]$xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        WindowStyle="None" AllowsTransparency="True" Background="Transparent"
        Topmost="True" ShowInTaskbar="False" ResizeMode="NoResize"
        SizeToContent="Height" Width="380" Focusable="False" Opacity="0">
  <Border CornerRadius="13" Padding="13,9,13,10"
          BorderThickness="1">
    <Border.Background>
      <SolidColorBrush Color="#000000" Opacity="0.88"/>
    </Border.Background>
    <Border.BorderBrush>
      <SolidColorBrush Color="#5A6B8C" Opacity="0.30"/>
    </Border.BorderBrush>
    <Border.Effect>
      <DropShadowEffect BlurRadius="24" ShadowDepth="0" Opacity="0.55" Color="#000000"/>
    </Border.Effect>
    <StackPanel>
      <!-- header: status dot + label, and the Bureau title -->
      <Grid Margin="0,0,0,7">
        <StackPanel Orientation="Horizontal" HorizontalAlignment="Left">
          <Ellipse x:Name="Dot" Width="10" Height="10" VerticalAlignment="Center"/>
          <TextBlock x:Name="StatusText" Margin="8,0,0,0" VerticalAlignment="Center"
                     FontFamily="Segoe UI Semibold" FontSize="11" Foreground="#AEB9CF"/>
        </StackPanel>
        <TextBlock x:Name="TitleText" HorizontalAlignment="Right" VerticalAlignment="Center"
                   MaxWidth="250" TextTrimming="CharacterEllipsis" TextWrapping="NoWrap"
                   FontFamily="Segoe UI Semibold" FontSize="11" Foreground="#7C8BA8"/>
      </Grid>
      <TextBlock x:Name="L0" TextWrapping="Wrap" FontFamily="Segoe UI" FontSize="12" Foreground="#E6ECF7" Margin="0,0,0,0"/>
      <TextBlock x:Name="L1" TextWrapping="Wrap" FontFamily="Segoe UI" FontSize="12" Foreground="#E6ECF7" Margin="0,0,0,0"/>
      <TextBlock x:Name="L2" TextWrapping="Wrap" FontFamily="Segoe UI Semibold" FontSize="13" Foreground="#FFFFFF" Margin="0,0,0,0"/>
    </StackPanel>
  </Border>
</Window>
"@

$reader = New-Object System.Xml.XmlNodeReader $xaml
$win = [Windows.Markup.XamlReader]::Load($reader)

$dot    = $win.FindName('Dot')
$stext  = $win.FindName('StatusText')
# Uppercase the title for a calm HUD-label look; trimming handles overflow.
$win.FindName('TitleText').Text = $Title.ToUpper()
$lineTB = @($win.FindName('L0'), $win.FindName('L1'), $win.FindName('L2'))
for ($i = 0; $i -lt $LINES; $i++) { $lineTB[$i].Opacity = $FADE[$i] }

# --- geometry + entrance/exit animation ---------------------------------------
# The window slides in from just past the right edge while fading up, and reverses
# on hide. "Rest" is the settled position; "Off" is nudged right + transparent.
$script:restLeft = 0.0
$script:offLeft  = 0.0
$SLIDE = 46            # px of horizontal travel for the slide

# Animate Left + Opacity together. $onDone runs when the fade finishes (used to
# actually close the window after the exit animation).
function Animate-To($targetLeft, $targetOpacity, $ms, $onDone) {
  $dur = [Windows.Duration]::new([TimeSpan]::FromMilliseconds($ms))
  $ease = New-Object Windows.Media.Animation.CubicEase
  $ease.EasingMode = if ($targetOpacity -ge 1) { 'EaseOut' } else { 'EaseIn' }

  $aL = New-Object Windows.Media.Animation.DoubleAnimation($win.Left, $targetLeft, $dur)
  $aL.EasingFunction = $ease
  $aO = New-Object Windows.Media.Animation.DoubleAnimation($win.Opacity, $targetOpacity, $dur)
  $aO.EasingFunction = $ease
  if ($onDone) { $aO.Add_Completed($onDone) }

  # BeginAnimation on Left needs the property to not be animation-locked; using
  # the animations directly is fine because we only ever drive these two.
  $win.BeginAnimation([Windows.Window]::LeftProperty, $aL)
  $win.BeginAnimation([Windows.Window]::OpacityProperty, $aO)
}

function Show-Overlay { Animate-To $script:restLeft 1.0 380 $null }
function Hide-Overlay($onDone) { Animate-To $script:offLeft 0.0 300 $onDone }

$win.Add_SourceInitialized({
  $wa = [System.Windows.SystemParameters]::WorkArea
  $script:restLeft = $wa.Right - $win.Width - 24
  $script:offLeft  = $script:restLeft + $SLIDE
  # Stack down the right edge: each instance gets a slot; ~118px per row leaves a
  # gap for the typical 3-line card. Windows past the work area clamp to the top.
  $rowH = 118
  $top = $wa.Top + 24 + ($Slot * $rowH)
  if ($top -gt ($wa.Bottom - 90)) { $top = $wa.Top + 24 }
  $win.Top  = $top
  # start off-screen-ish + transparent, then animate in
  $win.Left = $script:offLeft
  $win.Opacity = 0
  # make the window click-through (WS_EX_TRANSPARENT | WS_EX_LAYERED)
  $h = (New-Object System.Windows.Interop.WindowInteropHelper($win)).Handle
  $GWL_EXSTYLE = -20; $WS_EX_TRANSPARENT = 0x20; $WS_EX_LAYERED = 0x80000
  $ex = $U::GetWindowLong($h, $GWL_EXSTYLE)
  [void]$U::SetWindowLong($h, $GWL_EXSTYLE, $ex -bor $WS_EX_TRANSPARENT -bor $WS_EX_LAYERED)
  Show-Overlay
})

# --- state --------------------------------------------------------------------
$script:lastNewest = ''      # full text of current newest line
$script:typed      = 0       # chars revealed of the newest line
$script:pulse      = 0.0     # status-dot pulse phase
$script:kindLast   = 'summary'
$script:closing    = $false  # exit animation in flight
$script:visState   = 'shown' # shown | hidden — driven by the control file
$script:animating  = $false  # a show/hide slide is in flight
$script:doneTick   = -1      # tick at which status first became 'done' (-1 = not done)

# Auto-dismiss: once status has been 'done' for this many ms, the HUD fades out
# and closes on its own. Any status change back (e.g. the next improvement cycle
# sets 'working') cancels the countdown, so it never vanishes mid-run. Passed in
# as the -DoneMs param (0 disables auto-fade — the window stays until stopped).
$DONE_MS = $DoneMs

# Colours per line kind (the "kind" is the text before the first TAB).
function Kind-Color($kind) {
  switch ($kind) {
    'decision' { return '#8FD6FF' }   # cool accent — a decision/conclusion
    'action'   { return '#FFC24B' }   # amber — needs you
    'status'   { return '#9AA7BE' }   # dim — plain status
    default    { return '#FFFFFF' }   # summary — bright
  }
}

function Read-Text($path) {
  try {
    $fs = [System.IO.File]::Open($path, 'Open', 'Read', 'ReadWrite')
    try {
      $sr = New-Object System.IO.StreamReader($fs)
      return $sr.ReadToEnd()
    } finally { $fs.Dispose() }
  } catch { return $null }
}

# --- one shared timer: fast tick drives typewriter + pulse; every Nth tick polls
$tick = 0
$timer = New-Object System.Windows.Threading.DispatcherTimer
$timer.Interval = [TimeSpan]::FromMilliseconds(40)
$timer.Add_Tick({
  $script:tick++

  # self-close when disarmed — play the exit animation, then close for real
  if (-not (Test-Path $Flag)) {
    if (-not $script:closing) {
      $script:closing = $true
      $timer.Stop()
      Hide-Overlay({ $win.Close() })
    }
    return
  }

  # ---- visibility control: slide out / back in without quitting -----------
  if ($script:tick % 5 -eq 0 -and -not $script:animating) {
    $want = (Read-Text $Vis)
    if ($null -ne $want) { $want = $want.Trim().ToLower() } else { $want = 'shown' }
    if ($want -eq 'hidden' -and $script:visState -eq 'shown') {
      $script:visState = 'hidden'; $script:animating = $true
      Hide-Overlay({ $script:animating = $false })
    } elseif ($want -eq 'shown' -and $script:visState -eq 'hidden') {
      $script:visState = 'shown'; $script:animating = $true
      Show-Overlay; $script:animating = $false
    }
  }

  # ---- poll the feed + status every ~280ms --------------------------------
  if ($script:tick % 7 -eq 0) {
    $raw = Read-Text $Feed
    if ($null -ne $raw) {
      $all = @($raw -split "`n" | Where-Object { $_.Trim() -ne '' })
      $take = @()
      if ($all.Count -gt 0) {
        $start = [Math]::Max(0, $all.Count - $LINES)
        $take = $all[$start..($all.Count - 1)]
      }
      # render lines bottom-aligned: newest -> L4
      for ($i = 0; $i -lt $LINES; $i++) {
        $slot = $LINES - 1 - $i               # 0 => L4 (newest)
        $idx  = $take.Count - 1 - $i
        if ($idx -ge 0) {
          $parts = $take[$idx] -split "`t", 2
          if ($parts.Count -eq 2) { $kind = $parts[0]; $txt = $parts[1] }
          else { $kind = 'summary'; $txt = $parts[0] }
          $tb = $lineTB[$LINES - 1 - $slot]
          if ($slot -eq 0) {
            # newest line — remember kind/text; typewriter handled below
            if ($txt -ne $script:lastNewest) { $script:lastNewest = $txt; $script:typed = 0; $script:kindLast = $kind }
          } else {
            $tb.Text = $txt
            $tb.Foreground = [Windows.Media.BrushConverter]::new().ConvertFromString((Kind-Color $kind))
          }
        } else {
          $lineTB[$LINES - 1 - $slot].Text = ''
        }
      }
    }

    $st = (Read-Text $Status)
    if ($null -ne $st) { $st = $st.Trim().ToLower() } else { $st = 'working' }
    switch ($st) {
      'done'    { $dot.Fill = [Windows.Media.BrushConverter]::new().ConvertFromString('#3ECF8E'); $stext.Text = 'DONE';          $script:pulseOn = $false }
      'action'  { $dot.Fill = [Windows.Media.BrushConverter]::new().ConvertFromString('#FFB020'); $stext.Text = 'ACTION NEEDED'; $script:pulseOn = $true }
      'blocked' { $dot.Fill = [Windows.Media.BrushConverter]::new().ConvertFromString('#FF5C5C'); $stext.Text = 'BLOCKED';       $script:pulseOn = $true }
      default   { $dot.Fill = [Windows.Media.BrushConverter]::new().ConvertFromString('#4C8DFF'); $stext.Text = 'WORKING';       $script:pulseOn = $false }
    }

    # Auto-dismiss countdown: start it when 'done' first appears; cancel on any
    # other status (a new cycle keeps the HUD up).
    if ($st -eq 'done') {
      if ($script:doneTick -lt 0) { $script:doneTick = $script:tick }
    } else {
      $script:doneTick = -1
    }
  }

  # ---- auto-fade after status has held 'done' for $DONE_MS -----------------
  if ($DONE_MS -gt 0 -and $script:doneTick -ge 0 -and -not $script:closing) {
    $elapsedMs = ($script:tick - $script:doneTick) * 40
    if ($elapsedMs -ge $DONE_MS) {
      $script:closing = $true
      $timer.Stop()
      Hide-Overlay({ $win.Close() })
      return
    }
  }

  # ---- typewriter on the newest line --------------------------------------
  $newestTB = $lineTB[$LINES - 1]
  $full = $script:lastNewest
  if ($script:typed -lt $full.Length) {
    $script:typed = [Math]::Min($full.Length, $script:typed + 2)
  }
  $shown = $full.Substring(0, $script:typed)
  if ($script:typed -lt $full.Length) { $shown += '▌' }     # blinking-ish caret
  $newestTB.Text = $shown
  $newestTB.Foreground = [Windows.Media.BrushConverter]::new().ConvertFromString((Kind-Color $script:kindLast))

  # ---- status-dot pulse ----------------------------------------------------
  if ($script:pulseOn) {
    $script:pulse += 0.14
    $dot.Opacity = 0.45 + 0.55 * (0.5 * (1 + [Math]::Sin($script:pulse)))
  } else {
    $dot.Opacity = 1.0
  }
})

$script:pulseOn = $true
$timer.Start()
[void]$win.ShowDialog()
