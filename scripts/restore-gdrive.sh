#!/bin/bash

# Script para restaurar backups desde Google Drive
# Descarga un backup de Google Drive y luego ejecuta el proceso de restauración

set -e

# Configuración
BACKUP_DIR="/mnt/d/Documentos/Ocio_DS/n8n-stack/backups"
GDRIVE_FOLDER="n8n-stack-backups"
RCLONE_REMOTE="n8n-gdrive"

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
    exit 1
fi

# Si no se especifica archivo, mostrar lista de backups disponibles
if [ $# -eq 0 ]; then
    info "Uso: $0 <archivo_backup.tar.gz> o 'latest' para el último backup"
    echo ""
    info "Backups disponibles en Google Drive:"
    
    # Listar backups ordenados por fecha (más reciente primero)
    BACKUPS=$(rclone lsf "${RCLONE_REMOTE}:${GDRIVE_FOLDER}/" --files-only | grep "^n8n_backup_.*\.tar\.gz$" | sort -r)
    
    if [ -z "$BACKUPS" ]; then
        warning "No hay backups disponibles en Google Drive"
    else
        echo "$BACKUPS" | nl -w2 -s'. '
    fi
    
    exit 0
fi

BACKUP_FILE="$1"

# Si se especifica 'latest', obtener el último backup
if [ "$BACKUP_FILE" == "latest" ]; then
    log "Obteniendo el último backup de Google Drive..."
    BACKUP_FILE=$(rclone lsf "${RCLONE_REMOTE}:${GDRIVE_FOLDER}/" --files-only | grep "^n8n_backup_.*\.tar\.gz$" | sort -r | head -1)
    
    if [ -z "$BACKUP_FILE" ]; then
        error "No hay backups disponibles en Google Drive"
        exit 1
    fi
    
    info "Último backup encontrado: $BACKUP_FILE"
fi

# Verificar que el archivo existe en Google Drive
if ! rclone lsf "${RCLONE_REMOTE}:${GDRIVE_FOLDER}/${BACKUP_FILE}" &>/dev/null; then
    error "El archivo no existe en Google Drive: $BACKUP_FILE"
    exit 1
fi

# Crear directorio de backups si no existe
mkdir -p "$BACKUP_DIR"

# Descargar el backup
log "Descargando backup desde Google Drive: $BACKUP_FILE"

if rclone copy \
    "${RCLONE_REMOTE}:${GDRIVE_FOLDER}/${BACKUP_FILE}" \
    "$BACKUP_DIR/" \
    --progress \
    --stats-one-line; then
    log "✓ Backup descargado exitosamente"
else
    error "✗ Error al descargar backup desde Google Drive"
    exit 1
fi

# Descargar el archivo de checksum si existe
CHECKSUM_FILE="${BACKUP_FILE%.tar.gz}.sha256"
if rclone lsf "${RCLONE_REMOTE}:${GDRIVE_FOLDER}/${CHECKSUM_FILE}" >/dev/null 2>&1; then
    log "Descargando archivo de checksum..."
    if rclone copy \
        "${RCLONE_REMOTE}:${GDRIVE_FOLDER}/${CHECKSUM_FILE}" \
        "$BACKUP_DIR/" \
        --stats-one-line; then
        log "✓ Checksum descargado exitosamente"
    else
        warning "⚠️  No se pudo descargar el archivo de checksum"
    fi
fi

# Verificar la descarga
LOCAL_FILE="${BACKUP_DIR}/${BACKUP_FILE}"
if [ ! -f "$LOCAL_FILE" ]; then
    error "El archivo no se descargó correctamente"
    exit 1
fi

# Verificar integridad
log "Verificando integridad del archivo..."
if tar tzf "$LOCAL_FILE" &>/dev/null; then
    log "✓ Archivo verificado correctamente"
else
    error "✗ El archivo de backup está corrupto"
    exit 1
fi

# Ejecutar el proceso de restauración
log "Iniciando proceso de restauración..."
/mnt/d/Documentos/Ocio_DS/n8n-stack/scripts/restore.sh "$BACKUP_FILE"