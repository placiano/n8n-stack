# Guía de Backup y Restauración - n8n Stack

## 📋 Índice
- [Resumen](#resumen)
- [Backup Local](#backup-local)
- [Backup en Google Drive](#backup-en-google-drive)
- [Restauración](#restauración)
- [Backups Automáticos](#backups-automáticos)
- [Verificación de Estado](#verificación-de-estado)

## 📌 Resumen

Este sistema de backup protege todos los datos críticos del stack n8n:
- ✅ Bases de datos PostgreSQL (n8n y Evolution API)
- ✅ Volúmenes Docker (workflows, configuraciones, instancias WhatsApp)
- ✅ Archivos de configuración (.env, docker-compose.yml, etc.)

### Componentes del Backup
1. **Backup Local**: Almacenamiento en el servidor
2. **Backup en Google Drive**: Copia de seguridad en la nube
3. **Backups Automáticos**: Programación con cron

## 💾 Backup Local

### Crear Backup Manual
```bash
./scripts/backup.sh
```

Este comando:
- Crea un backup completo con timestamp
- Guarda en `/backups/n8n_backup_YYYYMMDD_HHMMSS.tar.gz`
- Mantiene los últimos 7 backups locales
- Crea enlace simbólico `latest_backup.tar.gz`

### Contenido del Backup
- `n8n_database.sql`: Base de datos de n8n
- `evolution_database.sql`: Base de datos de Evolution API
- `n8n_data.tar.gz`: Workflows y configuraciones de n8n
- `evolution_instances.tar.gz`: Instancias de WhatsApp
- `redis_data.tar.gz`: Datos de Redis
- `configs/`: Archivos de configuración
- `n8n_backup_YYYYMMDD_HHMMSS.sha256`: Checksum SHA256 para verificación de integridad

## ☁️ Backup en Google Drive

### Prerequisitos
1. Instalar rclone:
   ```bash
   curl https://rclone.org/install.sh | sudo bash
   ```

2. Configurar Google Drive:
   ```bash
   rclone config
   ```
   - Crear remote llamado `gdrive`
   - Seguir el asistente para autenticar con Google

### Crear Backup y Subir a Google Drive
```bash
# Crear nuevo backup y subirlo
./scripts/backup-gdrive.sh

# Solo subir el último backup existente
./scripts/backup-gdrive.sh sync
```

### Características
- Mantiene 7 backups en Google Drive (1 semana)
- Sube tanto el backup como su checksum SHA256
- Verifica integridad comparando checksums local y remoto
- Elimina backups y checksums antiguos automáticamente

## 🔄 Restauración

### Desde Backup Local

```bash
# Restaurar el último backup
./scripts/restore.sh latest

# Restaurar backup específico
./scripts/restore.sh n8n_backup_20250113_120000.tar.gz

# Ver backups disponibles
ls -la backups/*.tar.gz
```

### Desde Google Drive

```bash
# Ver backups disponibles en Google Drive
./scripts/restore-gdrive.sh

# Restaurar el último backup
./scripts/restore-gdrive.sh latest

# Restaurar backup específico
./scripts/restore-gdrive.sh n8n_backup_20250113_120000.tar.gz
```

### Proceso de Restauración
1. **Verifica integridad del backup** (checksum SHA256)
2. **Detiene todos los servicios**
3. **Restaura archivos de configuración**
4. **Recrea bases de datos**
5. **Restaura volúmenes Docker**
6. **Reinicia todos los servicios**

⚠️ **ADVERTENCIA**: La restauración sobrescribe TODOS los datos actuales.

## 🕐 Backups Automáticos

### Configurar Backups Programados
```bash
./scripts/setup-cron-backup.sh
```

### Programación Predeterminada
- **Backup Local + Google Drive**: Diario a las 17:00 (5:00 PM)
  - Primero crea el backup local
  - Inmediatamente después lo sube a Google Drive
- **Limpieza de logs**: Mensual (día 1) a las 16:30 (4:30 PM)

### Ver Tareas Programadas
```bash
crontab -l
```

### Logs de Backups Automáticos
- Local: `logs/backup_local.log`
- Google Drive: `logs/backup_gdrive.log`

## 🔍 Verificación de Estado

### Verificar Estado de Backups
```bash
./scripts/check-backup-status.sh
```

Muestra:
- Último backup local (fecha, tamaño)
- Total de backups en Google Drive
- Últimas ejecuciones desde logs
- Tareas programadas activas

### Verificar Manualmente

```bash
# Backups locales
ls -lah backups/

# Backups en Google Drive
rclone lsf gdrive:n8n-stack-backups/

# Tamaño total en Google Drive
rclone size gdrive:n8n-stack-backups/
```

## 🛠️ Solución de Problemas

### Error: "rclone no está configurado"
```bash
# Instalar rclone
curl https://rclone.org/install.sh | sudo bash

# Configurar Google Drive
rclone config
# Seguir asistente para crear remote 'gdrive'
```

### Error: "No se puede conectar a PostgreSQL"
```bash
# Verificar que PostgreSQL esté corriendo
docker-compose ps postgres

# Reiniciar PostgreSQL
docker-compose restart postgres
```

### Backup Corrupto
```bash
# Verificar integridad
tar tzf backups/n8n_backup_YYYYMMDD_HHMMSS.tar.gz

# Si está corrupto, usar otro backup
ls -t backups/*.tar.gz | head -5
```

## 📊 Mejores Prácticas

1. **Realizar backups regulares** antes de cambios importantes
2. **Verificar backups** periódicamente restaurando en ambiente de prueba
3. **Mantener múltiples copias** (local + Google Drive)
4. **Documentar cambios** importantes entre backups
5. **Monitorear logs** de backups automáticos

## 🔐 Seguridad

- Los backups contienen datos sensibles (contraseñas, tokens)
- Google Drive debe tener autenticación fuerte
- Limitar acceso a directorio de backups
- Considerar encriptación adicional para datos muy sensibles

## 📝 Notas Adicionales

### Espacio en Disco
- Cada backup puede ocupar 50-500 MB según los datos
- Con 7 backups locales: ~3.5 GB máximo
- En Google Drive con 30 backups: ~15 GB máximo

### Tiempo de Ejecución
- Backup: 1-5 minutos
- Restauración: 5-10 minutos
- Depende del tamaño de datos y velocidad de red

### Compatibilidad
- Los backups son portables entre sistemas
- Requiere Docker y docker-compose
- Compatible con Linux, macOS, WSL2