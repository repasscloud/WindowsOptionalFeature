[System.Array]$ExecFiles = Get-ChildItem -Path .\ -Recurse -Filter "*.ps1" -File | Select-Object -ExpandProperty FullName

foreach ($File in $ExecFiles)
{
    . $File
}
