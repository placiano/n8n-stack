#!/bin/sh
# Healthcheck para verificar que ngrok tiene túneles activos
curl -s http://localhost:4040/api/tunnels | grep -q "public_url" || exit 1