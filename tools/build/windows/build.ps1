# --- LRR Windows build script ---

echo "🎌 Building up LRR Windows Package 🎌"
echo "Inferring version from package.json..."

$json = (Get-Content "package.json" -Raw) | ConvertFrom-Json
$version = $json.version
echo "Version is $version"
$env:LRR_VERSION_NUM=$version

# Use Docker image
Move-Item .\package\package.tar .\tools\build\windows\Karen\External\package.tar

# Use Karen master
cd .\tools\build\windows\Karen
echo (Resolve-Path .\).Path
nuget restore

# Build Karen and Setup 
msbuild /p:Configuration=Release

Get-FileHash .\Setup\bin\LANraragi.msi | Format-List