#!/bin/bash

# Script para configurar backups automáticos con cron
# Configura backups diarios locales y semanales a Google Drive

set -e

# Configuración
SCRIPTS_DIR="/mnt/d/Documentos/Ocio_DS/n8n-stack/scripts"
CRON_LOG_DIR="/mnt/d/Documentos/Ocio_DS/n8n-stack/logs"

# Colores para output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Función para imprimir mensajes
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

# Crear directorio para logs si no existe
mkdir -p "$CRON_LOG_DIR"

# Función para agregar entrada a crontab
add_cron_job() {
    local schedule="$1"
    local command="$2"
    local comment="$3"
    
    # Verificar si la tarea ya existe
    if crontab -l 2>/dev/null | grep -q "$command"; then
        info "La tarea ya existe: $comment"
        return
    fi
    
    # Agregar la tarea
    (crontab -l 2>/dev/null || true; echo "# $comment"; echo "$schedule $command") | crontab -
    log "✓ Tarea agregada: $comment"
}

log "Configurando backups automáticos..."

# 1. Backup local y Google Drive diario a las 17:00 (5:00 PM)
# Primero hace backup local, luego lo sube a Google Drive
add_cron_job \
    "0 17 * * *" \
    "${SCRIPTS_DIR}/backup.sh >> ${CRON_LOG_DIR}/backup_local.log 2>&1 && ${SCRIPTS_DIR}/backup-gdrive.sh sync >> ${CRON_LOG_DIR}/backup_gdrive.log 2>&1" \
    "Backup diario local y Google Drive de n8n-stack"

# 2. Limpieza de logs mensual (día 1 de cada mes a las 16:30)
add_cron_job \
    "30 16 1 * *" \
    "find ${CRON_LOG_DIR} -name '*.log' -mtime +30 -delete" \
    "Limpieza mensual de logs antiguos"

# Mostrar el crontab actual
info "Configuración actual de crontab:"
crontab -l | grep -E "(n8n-stack|Backup)" || echo "No hay tareas de backup configuradas"

# Crear script wrapper para verificación manual
cat > "${SCRIPTS_DIR}/check-backup-status.sh" << 'EOF'
#!/bin/bash

# Script para verificar el estado de los backups

SCRIPTS_DIR="/mnt/d/Documentos/Ocio_DS/n8n-stack/scripts"
BACKUP_DIR="/mnt/d/Documentos/Ocio_DS/n8n-stack/backups"
LOG_DIR="/mnt/d/Documentos/Ocio_DS/n8n-stack/logs"

echo "=== Estado de Backups de n8n-stack ==="
echo

# Último backup local
echo "📁 Backups Locales:"
if [ -d "$BACKUP_DIR" ]; then
    LATEST_LOCAL=$(ls -t "$BACKUP_DIR"/n8n_backup_*.tar.gz 2>/dev/null | head -1)
    if [ -n "$LATEST_LOCAL" ]; then
        echo "   Último: $(basename "$LATEST_LOCAL")"
        echo "   Fecha: $(stat -c "%y" "$LATEST_LOCAL" | cut -d' ' -f1,2)"
        echo "   Tamaño: $(du -h "$LATEST_LOCAL" | cut -f1)"
        echo "   Total backups: $(ls "$BACKUP_DIR"/n8n_backup_*.tar.gz 2>/dev/null | wc -l)"
    else
        echo "   ❌ No hay backups locales"
    fi
else
    echo "   ❌ Directorio de backups no existe"
fi

echo

# Estado de Google Drive
echo "☁️  Google Drive:"
if command -v rclone &> /dev/null; then
    if rclone listremotes | grep -q "^gdrive:$"; then
        GDRIVE_COUNT=$(rclone lsf "gdrive:n8n-stack-backups/" --files-only 2>/dev/null | grep "^n8n_backup_.*\.tar\.gz$" | wc -l)
        GDRIVE_SIZE=$(rclone size "gdrive:n8n-stack-backups/" --json 2>/dev/null | jq -r '.human' || echo "N/A")
        echo "   Total backups: $GDRIVE_COUNT"
        echo "   Espacio usado: $GDRIVE_SIZE"
        
        LATEST_GDRIVE=$(rclone lsf "gdrive:n8n-stack-backups/" --files-only 2>/dev/null | grep "^n8n_backup_.*\.tar\.gz$" | sort -r | head -1)
        if [ -n "$LATEST_GDRIVE" ]; then
            echo "   Último: $LATEST_GDRIVE"
        fi
    else
        echo "   ❌ rclone no está configurado con Google Drive"
    fi
else
    echo "   ❌ rclone no está instalado"
fi

echo

# Últimas ejecuciones desde logs
echo "📋 Últimas Ejecuciones:"
if [ -d "$LOG_DIR" ]; then
    for log in backup_local.log backup_gdrive.log; do
        if [ -f "$LOG_DIR/$log" ]; then
            echo "   $log:"
            tail -n 3 "$LOG_DIR/$log" 2>/dev/null | sed 's/^/      /'
        fi
    done
else
    echo "   No hay logs disponibles"
fi

echo
echo "🔧 Tareas Programadas:"
crontab -l 2>/dev/null | grep -E "(backup\.sh|backup-gdrive\.sh)" | sed 's/^/   /'
EOF

chmod +x "${SCRIPTS_DIR}/check-backup-status.sh"

# Información final
log "✅ Configuración de backups automáticos completada"
echo
info "📌 Resumen de configuración:"
info "   • Backup local + Google Drive: Diario a las 17:00 (5:00 PM)"
info "   • Retención: 7 backups locales y 7 en Google Drive"
info "   • Limpieza de logs: Mensual (día 1) a las 16:30 (4:30 PM)"
echo
info "🔍 Para verificar el estado de los backups:"
info "   ${SCRIPTS_DIR}/check-backup-status.sh"
echo
info "📝 Los logs se guardan en:"
info "   ${CRON_LOG_DIR}/backup_local.log"
info "   ${CRON_LOG_DIR}/backup_gdrive.log"