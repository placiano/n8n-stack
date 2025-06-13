#!/bin/bash

# Script de backup para n8n-stack
# Realiza backup de bases de datos y volúmenes Docker

set -e

# Configuración
BACKUP_DIR="/mnt/d/Documentos/Ocio_DS/n8n-stack/backups"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
BACKUP_NAME="n8n_backup_${TIMESTAMP}"
BACKUP_PATH="${BACKUP_DIR}/${BACKUP_NAME}"
MAX_LOCAL_BACKUPS=7  # Mantener solo los últimos 7 backups locales

# Colores para output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
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

# Crear directorio de backups si no existe
mkdir -p "$BACKUP_DIR"
mkdir -p "$BACKUP_PATH"

log "Iniciando backup: ${BACKUP_NAME}"

# 1. Backup de bases de datos PostgreSQL
log "Realizando backup de bases de datos PostgreSQL..."

# Backup de la base de datos de n8n
if docker exec postgres-n8n pg_dump -U n8n_admin app_db > "${BACKUP_PATH}/n8n_database.sql" 2>/dev/null; then
    log "✓ Backup de base de datos n8n completado"
else
    error "✗ Error al hacer backup de base de datos n8n"
fi

# Backup de la base de datos de Evolution API
if docker exec postgres-n8n pg_dump -U n8n_admin evolution_db > "${BACKUP_PATH}/evolution_database.sql" 2>/dev/null; then
    log "✓ Backup de base de datos Evolution API completado"
else
    warning "✗ No se pudo hacer backup de evolution_db (puede que no exista aún)"
fi

# 2. Backup de volúmenes Docker
log "Realizando backup de volúmenes Docker..."

# Lista de volúmenes a respaldar
VOLUMES=(
    "n8n-stack_n8n_data:/backup/n8n_data"
    "n8n-stack_lab_evolution_instances:/backup/evolution_instances"
    "n8n-stack_redis_data:/backup/redis_data"
)

# Crear backup de cada volumen
for volume_mapping in "${VOLUMES[@]}"; do
    IFS=':' read -r volume_name backup_path <<< "$volume_mapping"
    volume_backup_name=$(echo $volume_name | sed 's/n8n-stack_//')
    
    log "Respaldando volumen: $volume_name"
    
    # Usar un contenedor temporal para acceder al volumen
    if docker run --rm \
        -v "$volume_name:/source:ro" \
        -v "$BACKUP_PATH:/backup" \
        alpine tar czf "/backup/${volume_backup_name}.tar.gz" -C /source . 2>/dev/null; then
        log "✓ Backup de $volume_backup_name completado"
    else
        warning "✗ Error al hacer backup de $volume_backup_name"
    fi
done

# 3. Backup de archivos de configuración
log "Respaldando archivos de configuración..."

# Lista de archivos a respaldar
CONFIG_FILES=(
    ".env"
    "docker-compose.yml"
    "ngrok.yml"
    "Dockerfile.n8n"
    "Dockerfile.evolution"
    "scripts/"
)

# Crear directorio para configs
mkdir -p "${BACKUP_PATH}/configs"

# Copiar archivos de configuración
for file in "${CONFIG_FILES[@]}"; do
    if [ -e "$file" ]; then
        cp -r "$file" "${BACKUP_PATH}/configs/" 2>/dev/null && \
        log "✓ Copiado: $file" || \
        warning "✗ No se pudo copiar: $file"
    fi
done

# 4. Crear archivo comprimido del backup completo
log "Comprimiendo backup..."
cd "$BACKUP_DIR"
if tar czf "${BACKUP_NAME}.tar.gz" "${BACKUP_NAME}"; then
    # Eliminar directorio temporal
    rm -rf "${BACKUP_PATH}"
    log "✓ Backup comprimido creado: ${BACKUP_NAME}.tar.gz"
    
    # Calcular tamaño del backup
    BACKUP_SIZE=$(du -h "${BACKUP_NAME}.tar.gz" | cut -f1)
    log "Tamaño del backup: $BACKUP_SIZE"
    
    # Calcular checksum SHA256
    log "Calculando checksum SHA256..."
    CHECKSUM=$(sha256sum "${BACKUP_NAME}.tar.gz" | cut -d' ' -f1)
    echo "$CHECKSUM" > "${BACKUP_NAME}.sha256"
    log "✓ Checksum SHA256: $CHECKSUM"
    log "✓ Archivo de checksum creado: ${BACKUP_NAME}.sha256"
else
    error "Error al comprimir el backup"
    exit 1
fi

# 5. Limpiar backups antiguos (mantener solo los últimos N)
log "Limpiando backups antiguos..."
cd "$BACKUP_DIR"
ls -t n8n_backup_*.tar.gz 2>/dev/null | tail -n +$((MAX_LOCAL_BACKUPS + 1)) | while read old_backup; do
    # Eliminar archivo de backup y su checksum
    rm "$old_backup"
    old_checksum="${old_backup%.tar.gz}.sha256"
    if [ -f "$old_checksum" ]; then
        rm "$old_checksum"
    fi
    log "✓ Eliminado backup antiguo: $old_backup"
done

# 6. Crear enlace simbólico al último backup
ln -sf "${BACKUP_NAME}.tar.gz" "latest_backup.tar.gz"

log "✅ Backup completado exitosamente: ${BACKUP_NAME}.tar.gz"
log "📁 Ubicación: ${BACKUP_DIR}/${BACKUP_NAME}.tar.gz"

# Retornar el nombre del archivo de backup para usar en otros scripts
echo "${BACKUP_NAME}.tar.gz"