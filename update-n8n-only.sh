#!/bin/bash
set -e

echo "==================================="
echo "   Actualizador de n8n (solo)"
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

# Paso 1: Detener solo n8n
print_status "Deteniendo n8n..."
docker-compose stop n8n || {
    print_error "Error al detener n8n"
    exit 1
}

# Paso 2: Guardar la imagen actual de n8n
print_status "Identificando imagen actual de n8n..."
if [ "$CURRENT_BRANCH" = "n8n_tunnel" ]; then
    OLD_N8N_IMAGE=$(docker images n8n-stack-n8n:latest -q 2>/dev/null || echo "")
else
    OLD_N8N_IMAGE=$(docker images docker.n8n.io/n8nio/n8n:latest -q 2>/dev/null || echo "")
fi

# Paso 3: Eliminar el contenedor de n8n
print_status "Eliminando contenedor de n8n..."
docker-compose rm -f n8n || {
    print_warning "No se pudo eliminar el contenedor (puede que ya no exista)"
}

# Paso 4: Construir/descargar nueva imagen
if [ "$CURRENT_BRANCH" = "n8n_tunnel" ]; then
    print_status "Construyendo imagen personalizada de n8n..."
    docker-compose build n8n || {
        print_error "Error al construir la imagen de n8n"
        exit 1
    }
else
    print_status "Descargando última versión de n8n..."
    docker-compose pull n8n || {
        print_error "Error al descargar la imagen de n8n"
        exit 1
    }
fi

# Paso 5: Iniciar n8n con la nueva imagen
print_status "Iniciando n8n con la imagen actualizada..."
docker-compose up -d n8n || {
    print_error "Error al iniciar n8n"
    exit 1
}

# Paso 6: Esperar a que n8n esté listo
print_status "Esperando a que n8n esté listo..."
echo -n "  "
until curl -s http://localhost:5679 >/dev/null 2>&1; do
    echo -n "."
    sleep 2
done
echo " ¡Listo!"

# Paso 7: Limpiar imagen antigua
if [ ! -z "$OLD_N8N_IMAGE" ]; then
    print_status "Limpiando imagen anterior de n8n..."
    
    # Obtener la nueva imagen
    if [ "$CURRENT_BRANCH" = "n8n_tunnel" ]; then
        NEW_N8N_IMAGE=$(docker images n8n-stack-n8n:latest -q 2>/dev/null || echo "")
    else
        NEW_N8N_IMAGE=$(docker images docker.n8n.io/n8nio/n8n:latest -q 2>/dev/null || echo "")
    fi
    
    # Solo eliminar si es diferente
    if [ "$OLD_N8N_IMAGE" != "$NEW_N8N_IMAGE" ] && [ ! -z "$NEW_N8N_IMAGE" ]; then
        docker rmi $OLD_N8N_IMAGE 2>/dev/null && {
            echo "  - Imagen anterior eliminada exitosamente"
        } || echo "  - No se pudo eliminar la imagen anterior (puede estar en uso)"
    else
        echo "  - No hay imagen anterior para eliminar"
    fi
fi

# Mostrar información final
echo ""
echo "==================================="
print_status "¡n8n actualizado exitosamente!"
echo "==================================="
echo ""

# Mostrar versión de n8n
echo -n "Versión de n8n: "
docker exec n8n-app n8n --version 2>/dev/null || echo "No disponible"

echo ""
echo "n8n está disponible en: http://localhost:5679"

if [ "$CURRENT_BRANCH" = "n8n_tunnel" ]; then
    echo -n "URL pública: "
    docker logs n8n-app 2>&1 | grep "Editor is now accessible via:" | tail -1 | awk '{print $NF}' || echo "Verificar en logs"
fi

echo ""
echo "Para ver los logs:"
echo "  docker-compose logs -f n8n"
echo ""