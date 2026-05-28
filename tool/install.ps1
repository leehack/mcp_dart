$ErrorActionPreference = "Stop"

$Repo = if ($env:MCP_DART_REPO) { $env:MCP_DART_REPO } else { "leehack/mcp_dart" }
$Version = if ($env:MCP_DART_VERSION) { $env:MCP_DART_VERSION } else { "latest" }
$InstallDir = if ($env:MCP_DART_INSTALL_DIR) {
  $env:MCP_DART_INSTALL_DIR
} else {
  Join-Path $HOME ".local\bin"
}

$Arch = [System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture.ToString().ToLowerInvariant()
switch ($Arch) {
  "x64" { $AssetArch = "x64" }
  "arm64" { $AssetArch = "arm64" }
  default { throw "Unsupported architecture: $Arch" }
}

if ($Version -eq "latest") {
  $Releases = Invoke-RestMethod "https://api.github.com/repos/$Repo/releases?per_page=50"
  $Release = $Releases | Where-Object {
    $_.tag_name -like "mcp_dart_cli-v*" -and -not $_.prerelease
  } | Select-Object -First 1
  if (-not $Release) {
    throw "Could not find a mcp_dart_cli GitHub release."
  }
  $Tag = $Release.tag_name
} elseif ($Version.StartsWith("mcp_dart_cli-v")) {
  $Tag = $Version
} else {
  $Tag = "mcp_dart_cli-v$Version"
}

$Asset = "mcp_dart-windows-$AssetArch.exe"
$Url = "https://github.com/$Repo/releases/download/$Tag/$Asset"
$SkillUrl = "https://github.com/$Repo/releases/download/$Tag/mcp-developer.SKILL.md"
$Tmp = Join-Path ([System.IO.Path]::GetTempPath()) "mcp_dart.exe"
$Target = Join-Path $InstallDir "mcp_dart.exe"
$ShareRoot = Join-Path (Split-Path $InstallDir -Parent) "share"
$SkillDir = Join-Path $ShareRoot "mcp_dart\skills\mcp-developer"
$SkillTarget = Join-Path $SkillDir "SKILL.md"

Write-Host "Downloading $Url"
Invoke-WebRequest -Uri $Url -OutFile $Tmp
New-Item -ItemType Directory -Force -Path $InstallDir | Out-Null
Move-Item -Force $Tmp $Target

Write-Host "Downloading $SkillUrl"
New-Item -ItemType Directory -Force -Path $SkillDir | Out-Null
Invoke-WebRequest -Uri $SkillUrl -OutFile $SkillTarget

Write-Host "Installed $Target"
Write-Host "Run: $Target --version"
