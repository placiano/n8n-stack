# n8n Stack Completo

Stack Docker completo para ejecutar n8n con PostgreSQL, Evolution API, Redis y ngrok preconfigurados.

## 🚀 Características

- **n8n**: Plataforma de automatización de flujos de trabajo
- **PostgreSQL con pgvector**: Base de datos principal con soporte para vectores
- **Evolution API**: API de WhatsApp integrada
- **Redis**: Sistema de caché para Evolution API
- **ngrok**: Túneles seguros para exponer servicios localmente
- **Adminer**: Interfaz web para gestión de base de datos

## 📋 Requisitos previos

- Docker y Docker Compose instalados
- Cuenta de ngrok (para el authtoken)
- Mínimo 4GB de RAM disponible

## 🛠️ Instalación

### 1. Clonar el repositorio

```bash
git clone https://github.com/placiano/n8n-stack.git
cd n8n-stack
```

### 2. Configurar variables de entorno

Copiar el archivo de ejemplo y configurar las contraseñas:

```bash
cp .env.example .env
```

Editar el archivo `.env` y configurar:

- **POSTGRES_PASSWORD**: Contraseña segura para PostgreSQL
- **N8N_BASIC_AUTH_PASSWORD**: Contraseña para acceder a n8n
- **AUTHENTICATION_API_KEY**: Clave API para Evolution API
- **REDIS_PASSWORD**: Contraseña para Redis

### 3. Configurar ngrok

En el archivo `.env`, configurar tu authtoken de ngrok:

```env
NGROK_AUTHTOKEN=tu_authtoken_de_ngrok
```

Puedes obtener tu authtoken en: https://dashboard.ngrok.com/get-started/your-authtoken

### 4. Iniciar los servicios

```bash
docker-compose up -d
```

## 🌐 Acceso a los servicios

Una vez iniciados los contenedores:

- **n8n**: http://localhost:5679
  - Usuario: configurado en `N8N_BASIC_AUTH_USER`
  - Contraseña: configurada en `N8N_BASIC_AUTH_PASSWORD`

- **Evolution API**: http://localhost:8088
  - API Key: configurada en `AUTHENTICATION_API_KEY`

- **Adminer**: http://localhost:8082
  - Sistema: PostgreSQL
  - Servidor: postgres
  - Usuario: configurado en `POSTGRES_USER`
  - Contraseña: configurada en `POSTGRES_PASSWORD`
  - Base de datos: configurada en `POSTGRES_DB`

- **ngrok Dashboard**: http://localhost:4041

## 🔧 Configuración adicional

### Timezone

Por defecto está configurado para `Europe/Madrid`. Para cambiar la zona horaria, editar en `.env`:

```env
GENERIC_TIMEZONE=America/New_York
```

### Puertos

Si necesitas cambiar los puertos expuestos, modifica el `docker-compose.yml`:

- n8n: 5679
- PostgreSQL: 5433
- Evolution API: 8088
- Adminer: 8082
- ngrok web: 4041
- Redis: 6381

### URLs públicas con ngrok

Una vez iniciado ngrok, puedes ver las URLs públicas en:
- Dashboard web: http://localhost:4041
- O ejecutar: `docker logs ngrok-n8n`

## 🌐 Rama n8n_tunnel - Configuración automática de URLs públicas

Esta rama incluye una configuración especial que permite a n8n y Evolution API detectar automáticamente sus URLs públicas de ngrok.

### Características de la rama n8n_tunnel:

1. **Detección automática de URLs**: Los servicios detectan automáticamente sus URLs públicas de ngrok al iniciar
2. **Configuración de webhooks**: n8n configura automáticamente la URL correcta para webhooks
3. **URLs separadas**: Cada servicio obtiene su propia URL de ngrok:
   - n8n: obtiene la URL del túnel llamado "n8n"
   - Evolution API: obtiene la URL del túnel llamado "evolution-api"

### Cómo funciona:

1. **Scripts personalizados**: Se incluyen scripts que esperan a que ngrok esté listo
2. **Dockerfiles personalizados**: Las imágenes de n8n y Evolution API se construyen con los scripts integrados
3. **Parseo de JSON**: Se usa `jq` para obtener las URLs correctas de cada túnel

### Archivos añadidos en esta rama:

- `Dockerfile.n8n`: Imagen personalizada de n8n con script de detección
- `Dockerfile.evolution`: Imagen personalizada de Evolution API con script de detección
- `scripts/update-webhook-url.sh`: Script para n8n
- `scripts/update-evolution-url.sh`: Script para Evolution API
- `scripts/ngrok-healthcheck.sh`: Healthcheck para ngrok

### Uso de la rama n8n_tunnel:

```bash
# Cambiar a la rama con túneles automáticos
git checkout n8n_tunnel

# Construir las imágenes personalizadas
docker-compose build

# Iniciar los servicios
docker-compose up -d
```

### Verificar las URLs asignadas:

```bash
# Ver URL de n8n
docker logs n8n-app | grep "URL"

# Ver URL de Evolution API
docker logs evolution-api-n8n | grep "URL"

# Ver todas las URLs de ngrok
curl -s http://localhost:4041/api/tunnels | jq
```

### Reiniciar servicios tras cambio de URL:

Si ngrok se reinicia y cambian las URLs:

```bash
# Solo reiniciar n8n y Evolution API
docker-compose restart n8n evolution-api
```

Los servicios detectarán automáticamente las nuevas URLs.

## 📊 Gestión de datos

### Backup de PostgreSQL

```bash
docker exec postgres-n8n pg_dump -U n8n_admin app_db > backup.sql
```

### Restaurar backup

```bash
docker exec -i postgres-n8n psql -U n8n_admin app_db < backup.sql
```

### Volúmenes Docker

Los datos persisten en los siguientes volúmenes:
- `n8n_data`: Datos y configuración de n8n
- `postgres_data`: Base de datos PostgreSQL
- `lab_evolution_instances`: Instancias de WhatsApp
- `redis_data`: Datos de caché Redis

## 🐛 Solución de problemas

### Ver logs de un servicio

```bash
docker-compose logs -f [servicio]
# Ejemplo: docker-compose logs -f n8n
```

### Reiniciar un servicio

```bash
docker-compose restart [servicio]
```

### Detener todo

```bash
docker-compose down
```

### Detener y eliminar volúmenes (⚠️ CUIDADO: borra todos los datos)

```bash
docker-compose down -v
```

## 🔒 Seguridad

⚠️ **IMPORTANTE**: 

1. Nunca subas el archivo `.env` a un repositorio público
2. Usa contraseñas seguras y únicas para cada servicio
3. En producción, considera usar secretos de Docker en lugar de archivos .env
4. Configura un firewall para limitar el acceso a los puertos expuestos

## 📝 Licencia

Este proyecto está bajo la licencia MIT. Ver el archivo [LICENSE](LICENSE) para más detalles.

## 🤝 Contribuciones

Las contribuciones son bienvenidas. Por favor:

1. Fork el proyecto
2. Crea tu feature branch (`git checkout -b feature/AmazingFeature`)
3. Commit tus cambios (`git commit -m 'Add some AmazingFeature'`)
4. Push a la branch (`git push origin feature/AmazingFeature`)
5. Abre un Pull Request

## 📞 Soporte

Si encuentras algún problema o tienes sugerencias, por favor abre un [issue](https://github.com/placiano/n8n-stack/issues).