#!/bin/bash
set -e

echo "==================================="
echo "   Actualizador de n8n Stack"
echo "==================================="
echo ""

# Colores para la salida
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Función para imprimir con color
print_status() {
    echo -e "${GREEN}[✓]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[!]${NC} $1"
}

print_error() {
    echo -e "${RED}[✗]${NC} $1"
}

# Verificar si estamos en el directorio correcto
if [ ! -f "docker-compose.yml" ]; then
    print_error "Error: No se encontró docker-compose.yml"
    echo "Por favor, ejecuta este script desde el directorio del proyecto n8n-stack"
    exit 1
fi

# Detectar la rama actual
CURRENT_BRANCH=$(git branch --show-current)
echo "Rama actual: $CURRENT_BRANCH"
echo ""

# Paso 1: Hacer pull de los últimos cambios
print_status "Obteniendo últimos cambios del repositorio..."
git pull origin $CURRENT_BRANCH || {
    print_error "Error al hacer git pull"
    echo "Verifica tu conexión a internet y que no haya conflictos locales"
    exit 1
}

# Paso 2: Detener los contenedores
print_status "Deteniendo contenedores..."
docker-compose down || {
    print_error "Error al detener los contenedores"
    exit 1
}

# Paso 3: Guardar las imágenes actuales para poder eliminarlas después
print_status "Identificando imágenes actuales..."
if [ "$CURRENT_BRANCH" = "n8n_tunnel" ]; then
    # En la rama n8n_tunnel, n8n y evolution-api usan imágenes personalizadas
    OLD_N8N_IMAGE=$(docker images n8n-stack-n8n:latest -q 2>/dev/null || echo "")
    OLD_EVOLUTION_IMAGE=$(docker images n8n-stack-evolution-api:latest -q 2>/dev/null || echo "")
else
    # En la rama main, se usan las imágenes oficiales
    OLD_N8N_IMAGE=$(docker images docker.n8n.io/n8nio/n8n:latest -q 2>/dev/null || echo "")
    OLD_EVOLUTION_IMAGE=$(docker images atendai/evolution-api:latest -q 2>/dev/null || echo "")
fi

# Paso 4: Construir nuevas imágenes (si estamos en n8n_tunnel)
if [ "$CURRENT_BRANCH" = "n8n_tunnel" ]; then
    print_status "Construyendo imágenes personalizadas..."
    docker-compose build || {
        print_error "Error al construir las imágenes"
        exit 1
    }
fi

# Paso 5: Descargar/actualizar todas las imágenes
print_status "Descargando imágenes actualizadas..."
docker-compose pull || {
    print_warning "Algunas imágenes no se pudieron actualizar (esto es normal para imágenes personalizadas)"
}

# Paso 6: Iniciar los contenedores con las nuevas imágenes
print_status "Iniciando contenedores con imágenes actualizadas..."
docker-compose up -d || {
    print_error "Error al iniciar los contenedores"
    exit 1
}

# Paso 7: Esperar a que los servicios estén listos
print_status "Esperando a que los servicios estén listos..."
echo -n "  - PostgreSQL: "
until docker exec postgres-n8n pg_isready -U n8n_admin >/dev/null 2>&1; do
    echo -n "."
    sleep 2
done
echo " ¡Listo!"

echo -n "  - n8n: "
until curl -s http://localhost:5679 >/dev/null 2>&1; do
    echo -n "."
    sleep 2
done
echo " ¡Listo!"

echo -n "  - Evolution API: "
until curl -s http://localhost:8088 >/dev/null 2>&1; do
    echo -n "."
    sleep 2
done
echo " ¡Listo!"

# Paso 8: Limpiar imágenes antiguas
print_status "Limpiando imágenes antiguas..."
IMAGES_REMOVED=0

if [ ! -z "$OLD_N8N_IMAGE" ]; then
    # Verificar que la imagen antigua es diferente a la nueva
    if [ "$CURRENT_BRANCH" = "n8n_tunnel" ]; then
        NEW_N8N_IMAGE=$(docker images n8n-stack-n8n:latest -q 2>/dev/null || echo "")
    else
        NEW_N8N_IMAGE=$(docker images docker.n8n.io/n8nio/n8n:latest -q 2>/dev/null || echo "")
    fi
    
    if [ "$OLD_N8N_IMAGE" != "$NEW_N8N_IMAGE" ] && [ ! -z "$NEW_N8N_IMAGE" ]; then
        docker rmi $OLD_N8N_IMAGE 2>/dev/null && {
            echo "  - Imagen anterior de n8n eliminada"
            ((IMAGES_REMOVED++))
        } || echo "  - No se pudo eliminar la imagen anterior de n8n (puede estar en uso)"
    fi
fi

if [ ! -z "$OLD_EVOLUTION_IMAGE" ]; then
    # Verificar que la imagen antigua es diferente a la nueva
    if [ "$CURRENT_BRANCH" = "n8n_tunnel" ]; then
        NEW_EVOLUTION_IMAGE=$(docker images n8n-stack-evolution-api:latest -q 2>/dev/null || echo "")
    else
        NEW_EVOLUTION_IMAGE=$(docker images atendai/evolution-api:latest -q 2>/dev/null || echo "")
    fi
    
    if [ "$OLD_EVOLUTION_IMAGE" != "$NEW_EVOLUTION_IMAGE" ] && [ ! -z "$NEW_EVOLUTION_IMAGE" ]; then
        docker rmi $OLD_EVOLUTION_IMAGE 2>/dev/null && {
            echo "  - Imagen anterior de Evolution API eliminada"
            ((IMAGES_REMOVED++))
        } || echo "  - No se pudo eliminar la imagen anterior de Evolution API (puede estar en uso)"
    fi
fi

if [ $IMAGES_REMOVED -eq 0 ]; then
    echo "  - No había imágenes antiguas para eliminar"
fi

# Paso 9: Limpiar imágenes huérfanas
print_status "Limpiando imágenes huérfanas..."
DANGLING_IMAGES=$(docker images -f "dangling=true" -q)
if [ ! -z "$DANGLING_IMAGES" ]; then
    docker rmi $DANGLING_IMAGES 2>/dev/null && echo "  - Imágenes huérfanas eliminadas" || echo "  - No se pudieron eliminar algunas imágenes huérfanas"
else
    echo "  - No se encontraron imágenes huérfanas"
fi

# Mostrar estado final
echo ""
echo "==================================="
print_status "¡Actualización completada!"
echo "==================================="
echo ""
echo "Servicios disponibles:"
echo "  - n8n: http://localhost:5679"
echo "  - Evolution API: http://localhost:8088"
echo "  - Adminer: http://localhost:8082"
echo "  - ngrok Dashboard: http://localhost:4041"

if [ "$CURRENT_BRANCH" = "n8n_tunnel" ]; then
    echo ""
    echo "URLs públicas de ngrok:"
    echo -n "  - n8n: "
    docker logs n8n-app 2>&1 | grep "Editor is now accessible via:" | tail -1 | awk '{print $NF}' || echo "Verificar en logs"
    echo -n "  - Evolution API: "
    docker logs evolution-api-n8n 2>&1 | grep "SERVER_URL configurada:" | tail -1 | awk '{print $NF}' || echo "Verificar en logs"
fi

echo ""
echo "Para ver los logs de un servicio:"
echo "  docker-compose logs -f [servicio]"
echo ""