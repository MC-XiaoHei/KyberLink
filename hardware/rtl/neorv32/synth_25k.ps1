$ErrorActionPreference = 'Stop'
$GS  = 'C:\Gowin\Gowin_V1.9.11.03_Education_x64\IDE\bin\GowinSynthesis.exe'
$OUT = 'build\synth\nrv25k'
$LOG = 'logs\synth_nrv25k.log'

$files = (Get-ChildItem 'hardware\rtl\neorv32\*.vhd' | ForEach-Object { $_.FullName }) -join ' '
& $GS -i $files -top neorv32_setup_25k -pn 'GW5A-LV25MG121NC1/I0' -looplimit 100000 -o $OUT *> $LOG
Write-Output "EXIT=$LASTEXITCODE"
