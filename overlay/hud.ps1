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
  [int]$IdleMs = 300000,
  [Parameter(Mandatory=$true)][string]$SlotFile,
  [Parameter(Mandatory=$true)][string]$TitleFile,
  [string]$Title = "BUREAU"
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase

# Read a file as UTF-8, tolerating concurrent writers. Defined FIRST because the
# script runs top-to-bottom and the title read below calls it. Windows PS 5.1's
# default reader uses the ANSI codepage, which mangles UTF-8 special characters.
function Read-Text($path) {
  try {
    $fs = [System.IO.File]::Open($path, 'Open', 'Read', 'ReadWrite')
    $sr = $null
    try {
      $sr = New-Object System.IO.StreamReader($fs, [System.Text.Encoding]::UTF8)
      return $sr.ReadToEnd()
    } finally { if ($sr) { $sr.Dispose() } else { $fs.Dispose() } }
  } catch { return $null }
}

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
  <!-- Margin gives the drop shadow transparent room so its blur isn't hard-
       clipped at the window's rectangular edge (the faint light corner artifact). -->
  <Border CornerRadius="12" Padding="12,7,12,8" Margin="12"
          BorderThickness="1">
    <Border.Background>
      <SolidColorBrush Color="#000000" Opacity="0.88"/>
    </Border.Background>
    <Border.BorderBrush>
      <SolidColorBrush Color="#5A6B8C" Opacity="0.30"/>
    </Border.BorderBrush>
    <Border.Effect>
      <DropShadowEffect BlurRadius="16" ShadowDepth="0" Opacity="0.5" Color="#000000"/>
    </Border.Effect>
    <StackPanel>
      <!-- header: status dot + label, and the Bureau title -->
      <Grid Margin="0,0,0,4">
        <StackPanel Orientation="Horizontal" HorizontalAlignment="Left">
          <Ellipse x:Name="Dot" Width="10" Height="10" VerticalAlignment="Center"/>
          <TextBlock x:Name="StatusText" Margin="8,0,0,0" VerticalAlignment="Center"
                     FontFamily="Segoe UI Semibold" FontSize="11" Foreground="#AEB9CF"/>
        </StackPanel>
        <!-- Title: a fixed-width clipped viewport. If the text fits it sits
             static (right-aligned); if it overflows it marquee-scrolls. -->
        <Canvas x:Name="TitleClip" Width="250" Height="16" HorizontalAlignment="Right"
                VerticalAlignment="Center" ClipToBounds="True">
          <TextBlock x:Name="TitleText" Canvas.Top="0" TextWrapping="NoWrap"
                     FontFamily="Segoe UI Semibold" FontSize="11" Foreground="#7C8BA8">
            <TextBlock.RenderTransform>
              <TranslateTransform x:Name="TitleShift" X="0"/>
            </TextBlock.RenderTransform>
          </TextBlock>
        </Canvas>
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
# Title comes from a file (avoids fragile command-line quoting for titles with
# quotes/spaces); fall back to the -Title param if the file isn't readable. Read
# via Read-Text so it's decoded UTF-8 (special chars render correctly).
$titleText = $Title
$tf = (Read-Text $TitleFile)
if ($tf) { $titleText = $tf.Trim() }
$titleTB   = $win.FindName('TitleText')
$titleClip = $win.FindName('TitleClip')
$titleShift = $win.FindName('TitleShift')
$titleTB.Text = $titleText.ToUpper()

# Marquee state: when the title is wider than its viewport, scroll it left-and-
# back with pauses at each end; otherwise sit static, right-aligned in the clip.
$script:mqW = 0.0            # measured text width (px)
$script:mqViewW = 250.0     # viewport width (matches Canvas Width above)
$script:mqX = 0.0           # current shift
$script:mqDir = -1          # -1 scrolling left, +1 scrolling right
$script:mqPause = 0         # ticks to hold at an end
function Measure-Title {
  $titleTB.Measure([Windows.Size]::new([double]::PositiveInfinity, [double]::PositiveInfinity))
  $script:mqW = $titleTB.DesiredSize.Width
  if ($script:mqW -le $script:mqViewW) {
    # fits — pin to the right edge, no scroll
    $script:mqX = $script:mqViewW - $script:mqW
    $titleShift.X = $script:mqX
  } else {
    $script:mqX = 0.0; $script:mqDir = -1; $script:mqPause = 40
    $titleShift.X = 0.0
  }
}
$lineTB = @($win.FindName('L0'), $win.FindName('L1'), $win.FindName('L2'))
# Start every row collapsed (zero height) so a freshly-opened card is not three
# empty rows tall; each row becomes Visible as a line fills it.
for ($i = 0; $i -lt $LINES; $i++) { $lineTB[$i].Opacity = $FADE[$i]; $lineTB[$i].Visibility = 'Collapsed' }

# --- geometry + entrance/exit animation ---------------------------------------
# The window slides in from just past the right edge while fading up, and reverses
# on hide. "Rest" is the settled position; "Off" is nudged right + transparent.
# Vertical position comes from the current slot; when the slot changes (another
# window closed and the stack re-packed) the window animates UP/DOWN to its new
# row, so the stack always stays gap-free.
$script:restLeft = 0.0
$script:offLeft  = 0.0
$script:marginTop = 0.0
$SLIDE = 46            # px of horizontal travel for the slide
$ROW_EST = 74         # fallback per-row height until a sibling publishes its real one
$STACK_GAP = -14      # overlap the transparent card margins so the visible gap is tight
$script:slot = 0       # current slot; kept in sync from $SlotFile
$script:targetTop = 0.0
$script:lastPubH = -1.0

# Each instance lives in its own dir; the overlay root is two levels up from the
# feed file. Siblings publish a "height" file we read to stack by ACTUAL height,
# so a card that grows (wrapped line) pushes the ones below it down instead of
# overlapping them.
$script:instDir  = Split-Path $Feed
$script:root     = Split-Path $script:instDir
$script:heightFile = Join-Path $script:instDir 'height'

# Publish this window's rendered height so siblings below can position under it.
function Publish-Height {
  $h = $win.ActualHeight
  if ($h -gt 0 -and [Math]::Abs($h - $script:lastPubH) -gt 0.5) {
    $script:lastPubH = $h
    # Format culture-invariant (always '.' decimal) so a comma-decimal locale
    # can't write "342,5" that the invariant parse below then misreads.
    try { [System.IO.File]::WriteAllText($script:heightFile, $h.ToString([System.Globalization.CultureInfo]::InvariantCulture)) } catch {}
  }
}

# Desired Top = margin + sum of (height + gap) for every live sibling in a lower
# slot. Uses each sibling's published height, falling back to an estimate until
# it appears. Recomputed each tick, so growth/shrink and re-packs both settle.
function Desired-Top {
  $acc = $script:marginTop
  try {
    foreach ($d in [System.IO.Directory]::GetDirectories($script:root)) {
      $sf = Join-Path $d 'slot'
      if (-not (Test-Path $sf)) { continue }
      $s = -1; $sv = (Read-Text $sf); if ($sv) { [int]::TryParse($sv.Trim(), [ref]$s) | Out-Null }
      if ($s -ge 0 -and $s -lt $script:slot) {
        $h = $ROW_EST; $hv = (Read-Text (Join-Path $d 'height'))
        if ($hv) { [double]::TryParse($hv.Trim(), [System.Globalization.NumberStyles]::Float, [System.Globalization.CultureInfo]::InvariantCulture, [ref]$h) | Out-Null }
        $acc += $h + $STACK_GAP
      }
    }
  } catch {}
  return $acc
}

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

# Animate the window vertically to a target Top (re-flow / height changes).
function Animate-ToTop($target) {
  $script:targetTop = $target
  $dur = [Windows.Duration]::new([TimeSpan]::FromMilliseconds(300))
  $ease = New-Object Windows.Media.Animation.CubicEase; $ease.EasingMode = 'EaseInOut'
  $aT = New-Object Windows.Media.Animation.DoubleAnimation($win.Top, $target, $dur)
  $aT.EasingFunction = $ease
  $win.BeginAnimation([Windows.Window]::TopProperty, $aT)
}

function Show-Overlay($onDone) { Animate-To $script:restLeft 1.0 380 $onDone }
function Hide-Overlay($onDone) { Animate-To $script:offLeft 0.0 300 $onDone }

$win.Add_SourceInitialized({
  $wa = [System.Windows.SystemParameters]::WorkArea
  # The 12px transparent Border margin is absorbed past the screen edge (via the
  # -$MARGIN offsets) so the visible card sits tight to the corner while the drop
  # shadow still has room to render un-clipped.
  $MARGIN = 12
  $script:restLeft  = $wa.Right - $win.Width - 10 + $MARGIN
  $script:offLeft   = $script:restLeft + $SLIDE
  $script:marginTop = $wa.Top + 10 - $MARGIN
  # initial slot from the file (default 0 if unreadable)
  $s0 = 0; $sv = (Read-Text $SlotFile); if ($null -ne $sv) { [int]::TryParse($sv.Trim(), [ref]$s0) | Out-Null }
  $script:slot = $s0
  Publish-Height
  $script:targetTop = (Desired-Top)
  $win.Top  = $script:targetTop
  # start off-screen-ish + transparent, then animate in
  $win.Left = $script:offLeft
  $win.Opacity = 0
  # make the window click-through (WS_EX_TRANSPARENT | WS_EX_LAYERED)
  $h = (New-Object System.Windows.Interop.WindowInteropHelper($win)).Handle
  $GWL_EXSTYLE = -20; $WS_EX_TRANSPARENT = 0x20; $WS_EX_LAYERED = 0x80000
  $ex = $U::GetWindowLong($h, $GWL_EXSTYLE)
  [void]$U::SetWindowLong($h, $GWL_EXSTYLE, $ex -bor $WS_EX_TRANSPARENT -bor $WS_EX_LAYERED)
  Measure-Title
  # (Show-Overlay below; $null completion is fine — Animate-To guards on it.)
  # Seed the idle clock so the window gets its full grace period from launch.
  try {
    $script:lastActivity = '{0}|{1}' -f `
      ([System.IO.File]::GetLastWriteTimeUtc($Feed).Ticks), `
      ([System.IO.File]::GetLastWriteTimeUtc($Status).Ticks)
  } catch { $script:lastActivity = '' }
  $script:idleTick = 0
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
$script:lastActivity = ''    # last-seen "feed mtime|status mtime" signature
$script:idleTick   = 0       # tick when activity last changed

# Auto-dismiss: once status has been 'done' for this many ms, the HUD fades out
# and closes on its own. Any status change back (e.g. the next improvement cycle
# sets 'working') cancels the countdown, so it never vanishes mid-run. Passed in
# as the -DoneMs param (0 disables auto-fade — the window stays until stopped).
$DONE_MS = $DoneMs

# Idle safety net: if NOTHING is written to this instance (no new feed line, no
# status change) for this long, fade out anyway. This is what catches a session
# that ended, crashed, or went quiet WITHOUT ever setting status=done — otherwise
# the window would float forever. Reset on any activity. -IdleMs 0 disables it.
$IDLE_MS = $IdleMs

# Colours per line kind (the "kind" is the text before the first TAB).
function Kind-Color($kind) {
  switch ($kind) {
    'decision' { return '#8FD6FF' }   # cool accent — a decision/conclusion
    'action'   { return '#FFC24B' }   # amber — needs you
    'status'   { return '#9AA7BE' }   # dim — plain status
    default    { return '#FFFFFF' }   # summary — bright
  }
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
      Show-Overlay({ $script:animating = $false })
    }
  }

  # ---- height-aware stacking: keep my slot current, publish my height, and
  #      sit exactly below the (variable-height) windows in lower slots. This is
  #      what prevents overlap when a card grows (a wrapped line) or the stack
  #      re-packs after a close.
  if ($script:tick % 6 -eq 0 -and $script:visState -eq 'shown' -and -not $script:closing) {
    $sv = (Read-Text $SlotFile)
    if ($null -ne $sv) { $ns = $script:slot; [int]::TryParse($sv.Trim(), [ref]$ns) | Out-Null; $script:slot = $ns }
    Publish-Height
    $want = (Desired-Top)
    if ([Math]::Abs($want - $script:targetTop) -gt 1.0) { Animate-ToTop $want }
  }

  # ---- title re-poll: a session can be renamed at runtime (overlay.sh start on
  #      a live instance rewrites the title file). Re-read on a slow tick and
  #      re-measure the marquee if it changed, so the header stays current.
  if ($script:tick % 25 -eq 0 -and -not $script:closing) {
    $tf = (Read-Text $TitleFile)
    if ($tf) {
      $newTitle = $tf.Trim().ToUpper()
      if ($newTitle -ne $titleTB.Text) { $titleTB.Text = $newTitle; Measure-Title }
    }
  }

  # ---- poll the feed + status every ~280ms --------------------------------
  if ($script:tick % 7 -eq 0) {
    $raw = Read-Text $Feed
    if ($null -ne $raw) {
      $all = @($raw -split "`r?`n" | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' })
      $take = @()
      if ($all.Count -gt 0) {
        $start = [Math]::Max(0, $all.Count - $LINES)
        $take = $all[$start..($all.Count - 1)]
      }
      # Render bottom-aligned: newest at the bottom row (lineTB[LINES-1], bright,
      # typewriter), older rows above it and dimmer. k=0 is the bottom/newest.
      # Empty rows are COLLAPSED (zero height, not just blank) so the card grows
      # 1 -> 2 -> 3 lines as content arrives, instead of showing a gap above the
      # first one or two prompts.
      for ($k = 0; $k -lt $LINES; $k++) {
        $tb  = $lineTB[$LINES - 1 - $k]        # k=0 => bottom row (newest)
        $idx = $take.Count - 1 - $k            # k=0 => newest entry
        if ($idx -ge 0) {
          $parts = $take[$idx] -split "`t", 2
          if ($parts.Count -eq 2) { $kind = $parts[0]; $txt = $parts[1] }
          else { $kind = 'summary'; $txt = $parts[0] }
          $tb.Visibility = 'Visible'
          if ($k -eq 0) {
            # newest line — remember kind/text; the typewriter below reveals it
            if ($txt -ne $script:lastNewest) { $script:lastNewest = $txt; $script:typed = 0; $script:kindLast = $kind }
          } else {
            $tb.Text = $txt
            $tb.Foreground = [Windows.Media.BrushConverter]::new().ConvertFromString((Kind-Color $kind))
          }
        } else {
          $tb.Text = ''
          $tb.Visibility = 'Collapsed'
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

  # ---- idle safety net: fade if nothing has been written for $IDLE_MS -------
  # Catches sessions that ended/crashed/went quiet without setting status=done,
  # which would otherwise leave the window floating forever. Activity = a change
  # in the feed OR status file mtime; any change resets the idle clock.
  if ($IDLE_MS -gt 0 -and -not $script:closing -and $script:tick % 12 -eq 0) {
    $sig = ''
    try {
      $sig = '{0}|{1}' -f `
        ([System.IO.File]::GetLastWriteTimeUtc($Feed).Ticks), `
        ([System.IO.File]::GetLastWriteTimeUtc($Status).Ticks)
    } catch { $sig = '' }
    if ($sig -ne $script:lastActivity) {
      $script:lastActivity = $sig
      $script:idleTick = $script:tick
    } elseif ((($script:tick - $script:idleTick) * 40) -ge $IDLE_MS) {
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

  # ---- title marquee: scroll only when the text overflows its viewport ------
  if ($script:mqW -gt $script:mqViewW) {
    if ($script:mqPause -gt 0) {
      $script:mqPause--
    } else {
      $minX = $script:mqViewW - $script:mqW   # fully-left extent (negative)
      $script:mqX += $script:mqDir * 0.8      # px/tick (~20px/s at 40ms)
      if ($script:mqX -le $minX) { $script:mqX = $minX; $script:mqDir = 1; $script:mqPause = 40 }
      elseif ($script:mqX -ge 0) { $script:mqX = 0.0; $script:mqDir = -1; $script:mqPause = 40 }
      $titleShift.X = $script:mqX
    }
  }
})

$script:pulseOn = $true
$timer.Start()
[void]$win.ShowDialog()
