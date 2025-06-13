#!/bin/bash

# Script de restauración para n8n-stack
# Restaura bases de datos y volúmenes desde un backup

set -e

# Configuración
BACKUP_DIR="/mnt/d/Documentos/Ocio_DS/n8n-stack/backups"

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

# Verificar si se proporcionó un archivo de backup
if [ $# -eq 0 ]; then
    info "Uso: $0 <archivo_backup.tar.gz> o 'latest' para el último backup"
    echo ""
    info "Backups disponibles:"
    ls -la "$BACKUP_DIR"/*.tar.gz 2>/dev/null || echo "No hay backups disponibles"
    exit 1
fi

BACKUP_FILE="$1"

# Si se especifica 'latest', usar el último backup
if [ "$BACKUP_FILE" == "latest" ]; then
    BACKUP_FILE="$BACKUP_DIR/latest_backup.tar.gz"
elif [[ ! "$BACKUP_FILE" =~ ^/ ]]; then
    # Si no es una ruta absoluta, buscar en el directorio de backups
    BACKUP_FILE="$BACKUP_DIR/$BACKUP_FILE"
fi

# Verificar que el archivo existe
if [ ! -f "$BACKUP_FILE" ]; then
    error "El archivo de backup no existe: $BACKUP_FILE"
    exit 1
fi

# Verificar integridad del backup si existe el checksum
CHECKSUM_FILE="${BACKUP_FILE%.tar.gz}.sha256"
if [ -f "$CHECKSUM_FILE" ]; then
    log "Verificando integridad del backup..."
    
    # Calcular checksum del archivo
    CURRENT_CHECKSUM=$(sha256sum "$BACKUP_FILE" | cut -d' ' -f1)
    EXPECTED_CHECKSUM=$(cat "$CHECKSUM_FILE")
    
    if [ "$CURRENT_CHECKSUM" = "$EXPECTED_CHECKSUM" ]; then
        log "✓ Verificación de integridad exitosa"
    else
        error "✗ El archivo de backup está corrupto (checksum no coincide)"
        error "Esperado: $EXPECTED_CHECKSUM"
        error "Actual:   $CURRENT_CHECKSUM"
        exit 1
    fi
else
    warning "⚠️  No se encontró archivo de checksum. Continuando sin verificación de integridad."
fi

log "Iniciando restauración desde: $BACKUP_FILE"

# Solicitar confirmación
warning "⚠️  ADVERTENCIA: Esta operación sobrescribirá todos los datos actuales."
read -p "¿Estás seguro de que quieres continuar? (yes/no): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    log "Restauración cancelada."
    exit 0
fi

# Crear directorio temporal para extraer el backup
TEMP_DIR=$(mktemp -d)
log "Extrayendo backup en directorio temporal..."

cd "$TEMP_DIR"
tar xzf "$BACKUP_FILE"

# Obtener el nombre del directorio extraído
BACKUP_NAME=$(ls -d n8n_backup_* | head -1)
cd "$BACKUP_NAME"

# 1. Detener todos los servicios
log "Deteniendo servicios..."
cd /mnt/d/Documentos/Ocio_DS/n8n-stack
docker-compose down

# 2. Restaurar archivos de configuración
if [ -d "${TEMP_DIR}/${BACKUP_NAME}/configs" ]; then
    log "Restaurando archivos de configuración..."
    
    # Hacer backup de los archivos actuales
    mkdir -p "configs_backup_before_restore"
    cp .env docker-compose.yml ngrok.yml "configs_backup_before_restore/" 2>/dev/null || true
    
    # Restaurar configs
    cp -r "${TEMP_DIR}/${BACKUP_NAME}/configs/"* . 2>/dev/null && \
    log "✓ Archivos de configuración restaurados" || \
    warning "✗ Algunos archivos de configuración no se pudieron restaurar"
fi

# 3. Iniciar solo PostgreSQL para restaurar las bases de datos
log "Iniciando PostgreSQL..."
docker-compose up -d postgres
sleep 10  # Esperar a que PostgreSQL esté listo

# Esperar a que PostgreSQL esté completamente listo
until docker exec postgres-n8n pg_isready -U n8n_admin; do
    log "Esperando a que PostgreSQL esté listo..."
    sleep 2
done

# 4. Restaurar bases de datos
log "Restaurando bases de datos..."

# Restaurar base de datos de n8n
if [ -f "${TEMP_DIR}/${BACKUP_NAME}/n8n_database.sql" ]; then
    log "Restaurando base de datos n8n..."
    
    # Recrear la base de datos
    docker exec postgres-n8n psql -U n8n_admin -d postgres -c "DROP DATABASE IF EXISTS app_db;" || true
    docker exec postgres-n8n psql -U n8n_admin -d postgres -c "CREATE DATABASE app_db;"
    
    # Restaurar el backup
    if docker exec -i postgres-n8n psql -U n8n_admin -d app_db < "${TEMP_DIR}/${BACKUP_NAME}/n8n_database.sql"; then
        log "✓ Base de datos n8n restaurada"
    else
        error "✗ Error al restaurar base de datos n8n"
    fi
fi

# Restaurar base de datos de Evolution API
if [ -f "${TEMP_DIR}/${BACKUP_NAME}/evolution_database.sql" ]; then
    log "Restaurando base de datos Evolution API..."
    
    # Recrear la base de datos
    docker exec postgres-n8n psql -U n8n_admin -d postgres -c "DROP DATABASE IF EXISTS evolution_db;" || true
    docker exec postgres-n8n psql -U n8n_admin -d postgres -c "CREATE DATABASE evolution_db;"
    
    # Restaurar el backup
    if docker exec -i postgres-n8n psql -U n8n_admin -d evolution_db < "${TEMP_DIR}/${BACKUP_NAME}/evolution_database.sql"; then
        log "✓ Base de datos Evolution API restaurada"
    else
        warning "✗ Error al restaurar base de datos Evolution API"
    fi
fi

# 5. Detener servicios nuevamente para restaurar volúmenes
log "Deteniendo servicios para restaurar volúmenes..."
docker-compose down

# 6. Restaurar volúmenes Docker
log "Restaurando volúmenes Docker..."

# Lista de volúmenes a restaurar
VOLUMES=(
    "n8n_data:n8n-stack_n8n_data"
    "evolution_instances:n8n-stack_lab_evolution_instances"
    "redis_data:n8n-stack_redis_data"
)

for volume_mapping in "${VOLUMES[@]}"; do
    IFS=':' read -r backup_name volume_name <<< "$volume_mapping"
    
    if [ -f "${TEMP_DIR}/${BACKUP_NAME}/${backup_name}.tar.gz" ]; then
        log "Restaurando volumen: $volume_name"
        
        # Eliminar volumen existente
        docker volume rm "$volume_name" 2>/dev/null || true
        
        # Crear nuevo volumen
        docker volume create "$volume_name"
        
        # Restaurar datos
        if docker run --rm \
            -v "$volume_name:/restore" \
            -v "${TEMP_DIR}/${BACKUP_NAME}:/backup:ro" \
            alpine tar xzf "/backup/${backup_name}.tar.gz" -C /restore; then
            log "✓ Volumen $volume_name restaurado"
        else
            warning "✗ Error al restaurar volumen $volume_name"
        fi
    fi
done

# 7. Limpiar directorio temporal
log "Limpiando archivos temporales..."
rm -rf "$TEMP_DIR"

# 8. Iniciar todos los servicios
log "Iniciando todos los servicios..."
docker-compose up -d

# 9. Verificar el estado de los servicios
sleep 10
log "Verificando estado de los servicios..."
docker-compose ps

log "✅ Restauración completada exitosamente"
info "Los servicios están reiniciándose. Puede tomar unos minutos hasta que todo esté completamente operativo."