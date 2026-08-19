# NEORV32 (KyberLink 25K setup) synthesis - Windows Gowin EDA
# Run from repo root:  powershell -ExecutionPolicy Bypass -File hardware\rtl\neorv32\synth_25k.ps1
# VHDL sources in hardware/rtl/neorv32 are flattened to work library
# (library neorv32 -> work) for CLI synthesis; logic unchanged.
# Resources: <OUT>_syn_rsc.xml ; timing: <OUT>_syn.rpt.html

$ErrorActionPreference = 'Stop'
$GS  = 'C:\Gowin\Gowin_V1.9.11.03_Education_x64\IDE\bin\GowinSynthesis.exe'
$OUT = 'C:\Users\33918\AppData\Local\Temp\kyber_syn\nrv25k'
$LOG = 'logs\eth_tx\synth_nrv25k.log'

$files = (Get-ChildItem 'hardware\rtl\neorv32\*.vhd' | ForEach-Object { $_.FullName }) -join ' '
& $GS -i $files -top neorv32_setup_25k -pn 'GW5A-LV25UG324C2/I1' -looplimit 100000 -o $OUT *> $LOG
Write-Output "EXIT=$LASTEXITCODE"
