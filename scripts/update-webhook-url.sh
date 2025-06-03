#!/bin/bash
set -e

echo "Esperando a que ngrok esté listo..."
until curl -s http://ngrok:4040/api/tunnels > /dev/null 2>&1; do
    echo "Ngrok aún no está listo, esperando 2 segundos..."
    sleep 2
done

echo "Ngrok está listo, obteniendo URL del túnel de n8n..."

# Obtener específicamente la URL del túnel llamado "n8n"
TUNNELS_JSON=$(curl -s http://ngrok:4040/api/tunnels)
echo "Túneles disponibles:"
echo "$TUNNELS_JSON" | grep -o '"name":"[^"]*"' | grep -o '"[^"]*"$'

# Buscar específicamente el túnel de n8n usando jq
NGROK_URL=$(echo "$TUNNELS_JSON" | jq -r '.tunnels[] | select(.name=="n8n") | .public_url')

if [ -z "$NGROK_URL" ]; then
    echo "Error: No se pudo obtener la URL del túnel n8n"
    echo "JSON completo de túneles:"
    echo "$TUNNELS_JSON"
    exit 1
fi

echo "URL de ngrok para n8n obtenida: $NGROK_URL"

# Actualizar la variable de entorno
export WEBHOOK_URL="${NGROK_URL}/"
echo "WEBHOOK_URL configurada: $WEBHOOK_URL"

# Iniciar n8n con la URL configurada
exec n8n