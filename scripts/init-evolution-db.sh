#!/bin/bash

# Script para inicializar la base de datos de Evolution API en la primera ejecución

set -e

echo "Inicializando base de datos de Evolution API..."

# Esperar a que PostgreSQL esté listo
echo "Esperando a que PostgreSQL esté listo..."
until docker exec postgres-n8n pg_isready -U n8n_admin; do
  echo "PostgreSQL no está listo aún..."
  sleep 2
done

echo "PostgreSQL está listo."

# Verificar si la base de datos evolution_db existe
DB_EXISTS=$(docker exec postgres-n8n psql -U n8n_admin -d postgres -tAc "SELECT 1 FROM pg_database WHERE datname='evolution_db'" || echo "")

if [ -z "$DB_EXISTS" ]; then
  echo "Creando base de datos evolution_db..."
  docker exec postgres-n8n psql -U n8n_admin -d postgres -c "CREATE DATABASE evolution_db;"
  echo "Base de datos evolution_db creada."
  
  # Marcar que necesitamos sincronizar el schema
  NEED_SCHEMA_SYNC=true
else
  echo "La base de datos evolution_db ya existe."
  
  # Verificar si hay tablas en la base de datos
  TABLE_COUNT=$(docker exec postgres-n8n psql -U n8n_admin -d evolution_db -tAc "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = 'public' AND table_type = 'BASE TABLE';" || echo "0")
  
  if [ "$TABLE_COUNT" -eq "0" ]; then
    echo "La base de datos está vacía, se necesita sincronizar el schema."
    NEED_SCHEMA_SYNC=true
  else
    echo "La base de datos ya tiene $TABLE_COUNT tabla(s)."
    NEED_SCHEMA_SYNC=false
  fi
fi

# Si necesitamos sincronizar el schema
if [ "$NEED_SCHEMA_SYNC" = true ]; then
  echo "Esperando a que Evolution API esté listo para sincronizar el schema..."
  
  # Esperar un poco para que el contenedor se inicie completamente
  sleep 10
  
  echo "Sincronizando schema de Prisma..."
  
  # Intentar sincronizar el schema hasta 3 veces
  RETRY_COUNT=0
  MAX_RETRIES=3
  
  while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
    if docker exec evolution-api-n8n npx prisma db push --schema=/evolution/prisma/postgresql-schema.prisma --skip-generate 2>/dev/null; then
      echo "Schema de Prisma sincronizado exitosamente."
      break
    else
      RETRY_COUNT=$((RETRY_COUNT + 1))
      if [ $RETRY_COUNT -lt $MAX_RETRIES ]; then
        echo "Error al sincronizar schema. Reintentando en 5 segundos... (Intento $RETRY_COUNT de $MAX_RETRIES)"
        sleep 5
      else
        echo "ERROR: No se pudo sincronizar el schema después de $MAX_RETRIES intentos."
        echo "Es posible que necesites ejecutar manualmente:"
        echo "docker exec evolution-api-n8n npx prisma db push --schema=/evolution/prisma/postgresql-schema.prisma"
      fi
    fi
  done
fi

echo "Inicialización de Evolution API completada."