#!/bin/bash
set -e

echo "Esperando a que ngrok esté listo..."
until curl -s http://ngrok:4040/api/tunnels > /dev/null 2>&1; do
    echo "Ngrok aún no está listo, esperando 2 segundos..."
    sleep 2
done

echo "Esperando a que el túnel evolution-api esté disponible..."
until curl -s http://ngrok:4040/api/tunnels | grep -q '"name":"evolution-api"'; do
    echo "Túnel evolution-api aún no está listo, esperando 2 segundos..."
    sleep 2
done

echo "Ngrok está listo, obteniendo URL del túnel de evolution-api..."

# Obtener específicamente la URL del túnel llamado "evolution-api"
TUNNELS_JSON=$(curl -s http://ngrok:4040/api/tunnels)
echo "Túneles disponibles:"
echo "$TUNNELS_JSON" | grep -o '"name":"[^"]*"' | grep -o '"[^"]*"$'

# Buscar específicamente el túnel de evolution-api usando jq
NGROK_URL=$(echo "$TUNNELS_JSON" | jq -r '.tunnels[] | select(.name=="evolution-api") | .public_url')

if [ -z "$NGROK_URL" ]; then
    echo "Error: No se pudo obtener la URL del túnel evolution-api"
    echo "JSON completo de túneles:"
    echo "$TUNNELS_JSON"
    exit 1
fi

echo "URL de ngrok para evolution-api obtenida: $NGROK_URL"

# Actualizar la variable de entorno
export SERVER_URL="${NGROK_URL}"
echo "SERVER_URL configurada: $SERVER_URL"

# Iniciar Evolution API con el comando original
cd /evolution
exec npm run start:prod