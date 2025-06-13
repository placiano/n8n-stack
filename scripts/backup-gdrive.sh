#!/bin/bash

# Script para sincronizar backups con Google Drive usando rclone
# Requiere que rclone esté configurado con un remote llamado "gdrive"

set -e

# Configuración
BACKUP_DIR="/mnt/d/Documentos/Ocio_DS/n8n-stack/backups"
GDRIVE_FOLDER="n8n-stack-backups"  # Carpeta en Google Drive
RCLONE_REMOTE="n8n-gdrive"  # Nombre del remote de rclone
MAX_GDRIVE_BACKUPS=7  # Mantener 7 backups en Google Drive (1 semana)

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

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

# Verificar si rclone está instalado
if ! command -v rclone &> /dev/null; then
    error "rclone no está instalado. Por favor, instala rclone primero."
    info "Puedes instalarlo con: curl https://rclone.org/install.sh | sudo bash"
    exit 1
fi

# Verificar si el remote de Google Drive está configurado
if ! rclone listremotes | grep -q "^${RCLONE_REMOTE}:$"; then
    error "Remote '${RCLONE_REMOTE}' no está configurado en rclone."
    info "Configura rclone con: rclone config"
    info "Crea un remote llamado '${RCLONE_REMOTE}' para Google Drive"
    exit 1
fi

# Función para realizar backup local primero
perform_backup() {
    log "Ejecutando backup local..."
    # Ejecutar backup.sh directamente
    /mnt/d/Documentos/Ocio_DS/n8n-stack/scripts/backup.sh > /dev/null
    
    # Obtener el último backup creado
    BACKUP_FILE=$(ls -t /mnt/d/Documentos/Ocio_DS/n8n-stack/backups/n8n_backup_*.tar.gz 2>/dev/null | head -1)
    
    if [ -z "$BACKUP_FILE" ]; then
        error "Error: No se encontró ningún backup"
        exit 1
    fi
    
    # Extraer solo el nombre del archivo
    echo "$(basename "$BACKUP_FILE")"
}

# Si se pasa 'sync' como parámetro, solo sincronizar el último backup
if [ "$1" == "sync" ]; then
    log "Modo sincronización: subiendo último backup a Google Drive..."
    
    # Obtener el último backup
    LATEST_BACKUP=$(ls -t "$BACKUP_DIR"/n8n_backup_*.tar.gz 2>/dev/null | head -1)
    
    if [ -z "$LATEST_BACKUP" ]; then
        error "No hay backups disponibles para sincronizar"
        exit 1
    fi
    
    BACKUP_FILE=$(basename "$LATEST_BACKUP")
else
    # Realizar nuevo backup
    BACKUP_FILE=$(perform_backup)
fi

# Subir backup a Google Drive
log "Subiendo backup a Google Drive: $BACKUP_FILE"

# Crear carpeta en Google Drive si no existe
rclone mkdir "${RCLONE_REMOTE}:${GDRIVE_FOLDER}" 2>/dev/null || true

# Subir el archivo de backup
if rclone copy \
    "${BACKUP_DIR}/${BACKUP_FILE}" \
    "${RCLONE_REMOTE}:${GDRIVE_FOLDER}/" \
    --progress \
    --stats-one-line; then
    log "✓ Backup subido exitosamente a Google Drive"
else
    error "✗ Error al subir backup a Google Drive"
    exit 1
fi

# Subir el archivo de checksum
CHECKSUM_FILE="${BACKUP_FILE%.tar.gz}.sha256"
if [ -f "${BACKUP_DIR}/${CHECKSUM_FILE}" ]; then
    log "Subiendo archivo de checksum..."
    if rclone copy \
        "${BACKUP_DIR}/${CHECKSUM_FILE}" \
        "${RCLONE_REMOTE}:${GDRIVE_FOLDER}/" \
        --stats-one-line; then
        log "✓ Checksum subido exitosamente a Google Drive"
    else
        warning "⚠️  No se pudo subir el archivo de checksum"
    fi
fi

# Verificar que el archivo existe en Google Drive
if rclone lsf "${RCLONE_REMOTE}:${GDRIVE_FOLDER}/${BACKUP_FILE}" >/dev/null 2>&1; then
    log "✓ Verificación exitosa: el archivo existe en Google Drive"
    
    # Verificar checksum si existe
    if [ -f "${BACKUP_DIR}/${CHECKSUM_FILE}" ]; then
        log "Verificando integridad del archivo en Google Drive..."
        
        # Descargar checksum de Google Drive
        TEMP_CHECKSUM=$(mktemp)
        if rclone cat "${RCLONE_REMOTE}:${GDRIVE_FOLDER}/${CHECKSUM_FILE}" > "$TEMP_CHECKSUM" 2>/dev/null; then
            REMOTE_CHECKSUM=$(cat "$TEMP_CHECKSUM")
            LOCAL_CHECKSUM=$(cat "${BACKUP_DIR}/${CHECKSUM_FILE}")
            
            if [ "$REMOTE_CHECKSUM" = "$LOCAL_CHECKSUM" ]; then
                log "✓ Verificación de integridad exitosa: checksums coinciden"
            else
                warning "⚠️  Los checksums no coinciden (posible corrupción)"
            fi
        else
            warning "⚠️  No se pudo verificar el checksum remoto"
        fi
        rm -f "$TEMP_CHECKSUM"
    fi
else
    warning "⚠️  No se pudo verificar la subida del archivo"
fi

# Limpiar backups antiguos en Google Drive
log "Verificando backups antiguos en Google Drive..."

# Listar todos los backups y ordenarlos por fecha
GDRIVE_BACKUPS=$(rclone lsf "${RCLONE_REMOTE}:${GDRIVE_FOLDER}/" --files-only | grep "^n8n_backup_.*\.tar\.gz$" | sort -r)
BACKUP_COUNT=$(echo "$GDRIVE_BACKUPS" | wc -l)

if [ $BACKUP_COUNT -gt $MAX_GDRIVE_BACKUPS ]; then
    log "Encontrados $BACKUP_COUNT backups. Eliminando los más antiguos (manteniendo $MAX_GDRIVE_BACKUPS)..."
    
    # Obtener lista de archivos a eliminar
    TO_DELETE=$(echo "$GDRIVE_BACKUPS" | tail -n +$((MAX_GDRIVE_BACKUPS + 1)))
    
    for old_backup in $TO_DELETE; do
        # Eliminar backup
        if rclone delete "${RCLONE_REMOTE}:${GDRIVE_FOLDER}/${old_backup}"; then
            log "✓ Eliminado de Google Drive: $old_backup"
        else
            warning "✗ No se pudo eliminar: $old_backup"
        fi
        
        # Eliminar checksum asociado
        old_checksum="${old_backup%.tar.gz}.sha256"
        if rclone lsf "${RCLONE_REMOTE}:${GDRIVE_FOLDER}/${old_checksum}" >/dev/null 2>&1; then
            if rclone delete "${RCLONE_REMOTE}:${GDRIVE_FOLDER}/${old_checksum}"; then
                log "✓ Eliminado checksum de Google Drive: $old_checksum"
            else
                warning "✗ No se pudo eliminar checksum: $old_checksum"
            fi
        fi
    done
fi

# Mostrar resumen de backups en Google Drive
log "Resumen de backups en Google Drive:"
BACKUP_COUNT=$(rclone lsf "${RCLONE_REMOTE}:${GDRIVE_FOLDER}/" --files-only | grep "^n8n_backup_.*\.tar\.gz$" | wc -l)
info "Total de backups: $BACKUP_COUNT"

log "✅ Sincronización con Google Drive completada"