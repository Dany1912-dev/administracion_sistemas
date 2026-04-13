#Requires -RunAsAdministrator

function Print-Ok   { param($msg) Write-Host "[OK]   $msg" -ForegroundColor Green  }
function Print-Info { param($msg) Write-Host "[INFO] $msg" -ForegroundColor Cyan   }
function Print-Warn { param($msg) Write-Host "[WARN] $msg" -ForegroundColor Yellow }
function Print-Err  { param($msg) Write-Host "[ERR]  $msg" -ForegroundColor Red    }

$rutaFunciones = "$PSScriptRoot\..\lib"

. "$rutaFunciones\T9_AD.ps1"
. "$rutaFunciones\T9_Delegacion.ps1"
. "$rutaFunciones\T9_Politicas.ps1"
. "$rutaFunciones\T9_MFA.ps1"

function Mostrar-Menu {
    do {
        Clear-Host
        Write-Host "========== Practica 09: Seguridad, Delegacion y MFA =========="
        Write-Host ""
        Write-Host "  [1] Inicializar entorno"
        Write-Host "  [2] Configurar Active Directory"
        Write-Host "  [3] Configurar Delegacion RBAC"
        Write-Host "  [4] Configurar Politicas y Auditoria"
        Write-Host "  [5] Configurar MFA"
        Write-Host "  [6] Salir"
        Write-Host ""

        $op = Read-Host "Selecciona una opcion"

        switch ($op) {
            "1" { Clear-Host; Inicializar-Entorno;   Read-Host "`nEnter para continuar" }
            "2" { Clear-Host; Configurar-AD;         Read-Host "`nEnter para continuar" }
            "3" { Clear-Host; Configurar-Delegacion; Read-Host "`nEnter para continuar" }
            "4" { Clear-Host; Configurar-Politicas;  Read-Host "`nEnter para continuar" }
            "5" { Clear-Host; Configurar-MFA;        Read-Host "`nEnter para continuar" }
            "6" { Clear-Host; Write-Host "Saliendo..."; return }
            default { Print-Warn "Opcion no valida."; Start-Sleep -Seconds 1 }
        }
    } while ($true)
}

Mostrar-Menu
