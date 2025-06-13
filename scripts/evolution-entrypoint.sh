#!/bin/bash

# Script de entrada combinado para Evolution API

set -e

# Primero ejecutar la actualización de URL de ngrok
source /update-evolution-url.sh

# En segundo plano, ejecutar la inicialización de la base de datos después de un delay
(
  sleep 15  # Dar tiempo para que Evolution API se inicie
  
  # Verificar si necesitamos inicializar la base de datos
  DB_EXISTS=$(PGPASSWORD="$POSTGRES_PASSWORD" psql -h postgres-n8n -U "$POSTGRES_USER" -d postgres -tAc "SELECT 1 FROM pg_database WHERE datname='evolution_db'" 2>/dev/null || echo "")
  
  if [ -z "$DB_EXISTS" ]; then
    echo "[DB Init] La base de datos evolution_db no existe. Esperando a que Evolution API falle para crearla..."
    
    # Esperar a que Evolution API falle por la base de datos faltante
    sleep 10
    
    echo "[DB Init] Creando base de datos evolution_db..."
    PGPASSWORD="$POSTGRES_PASSWORD" psql -h postgres-n8n -U "$POSTGRES_USER" -d postgres -c "CREATE DATABASE evolution_db;" 2>/dev/null || true
    
    echo "[DB Init] Base de datos creada. El contenedor se reiniciará automáticamente."
  else
    # Verificar si hay tablas
    TABLE_COUNT=$(PGPASSWORD="$POSTGRES_PASSWORD" psql -h postgres-n8n -U "$POSTGRES_USER" -d evolution_db -tAc "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = 'public' AND table_type = 'BASE TABLE';" 2>/dev/null || echo "0")
    
    if [ "$TABLE_COUNT" -eq "0" ]; then
      echo "[DB Init] La base de datos está vacía. Esperando para sincronizar el schema..."
      sleep 20
      
      echo "[DB Init] Sincronizando schema de Prisma..."
      npx prisma db push --schema=/evolution/prisma/postgresql-schema.prisma --skip-generate 2>/dev/null || true
      
      echo "[DB Init] Schema sincronizado. El contenedor se reiniciará automáticamente."
    fi
  fi
) &

# El proceso principal continúa normalmente
exec "$@"