#!/bin/bash

# Script para verificar el estado de los backups

SCRIPTS_DIR="/mnt/d/Documentos/Ocio_DS/n8n-stack/scripts"
BACKUP_DIR="/mnt/d/Documentos/Ocio_DS/n8n-stack/backups"
LOG_DIR="/mnt/d/Documentos/Ocio_DS/n8n-stack/logs"

echo "=== Estado de Backups de n8n-stack ==="
echo

# Último backup local
echo "📁 Backups Locales:"
if [ -d "$BACKUP_DIR" ]; then
    LATEST_LOCAL=$(ls -t "$BACKUP_DIR"/n8n_backup_*.tar.gz 2>/dev/null | head -1)
    if [ -n "$LATEST_LOCAL" ]; then
        echo "   Último: $(basename "$LATEST_LOCAL")"
        echo "   Fecha: $(stat -c "%y" "$LATEST_LOCAL" | cut -d' ' -f1,2)"
        echo "   Tamaño: $(du -h "$LATEST_LOCAL" | cut -f1)"
        echo "   Total backups: $(ls "$BACKUP_DIR"/n8n_backup_*.tar.gz 2>/dev/null | wc -l)"
        
        # Verificar si existe checksum
        CHECKSUM_FILE="${LATEST_LOCAL%.tar.gz}.sha256"
        if [ -f "$CHECKSUM_FILE" ]; then
            echo "   Checksum: ✓ Disponible"
            # Verificar integridad
            CURRENT_CHECKSUM=$(sha256sum "$LATEST_LOCAL" | cut -d' ' -f1)
            EXPECTED_CHECKSUM=$(cat "$CHECKSUM_FILE")
            if [ "$CURRENT_CHECKSUM" = "$EXPECTED_CHECKSUM" ]; then
                echo "   Integridad: ✓ Verificada"
            else
                echo "   Integridad: ❌ Corrupto"
            fi
        else
            echo "   Checksum: ⚠️  No disponible"
        fi
    else
        echo "   ❌ No hay backups locales"
    fi
else
    echo "   ❌ Directorio de backups no existe"
fi

echo

# Estado de Google Drive
echo "☁️  Google Drive:"
if command -v rclone &> /dev/null; then
    if rclone listremotes | grep -q "^n8n-gdrive:$"; then
        GDRIVE_COUNT=$(rclone lsf "n8n-gdrive:n8n-stack-backups/" --files-only 2>/dev/null | grep "^n8n_backup_.*\.tar\.gz$" | wc -l)
        echo "   Total backups: $GDRIVE_COUNT"
        
        LATEST_GDRIVE=$(rclone lsf "n8n-gdrive:n8n-stack-backups/" --files-only 2>/dev/null | grep "^n8n_backup_.*\.tar\.gz$" | sort -r | head -1)
        if [ -n "$LATEST_GDRIVE" ]; then
            echo "   Último: $LATEST_GDRIVE"
        fi
    else
        echo "   ❌ rclone no está configurado con Google Drive"
    fi
else
    echo "   ❌ rclone no está instalado"
fi

echo

# Últimas ejecuciones desde logs
echo "📋 Últimas Ejecuciones:"
if [ -d "$LOG_DIR" ]; then
    for log in backup_local.log backup_gdrive.log; do
        if [ -f "$LOG_DIR/$log" ]; then
            echo "   $log:"
            tail -n 3 "$LOG_DIR/$log" 2>/dev/null | sed 's/^/      /'
        fi
    done
else
    echo "   No hay logs disponibles"
fi

echo
echo "🔧 Tareas Programadas:"
crontab -l 2>/dev/null | grep -E "(backup\.sh|backup-gdrive\.sh)" | sed 's/^/   /'
