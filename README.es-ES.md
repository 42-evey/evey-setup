```
                                        _
   ___ __   _____  _   _      ___  ___| |_ _   _ _ __
  / _ \\ \ / / _ \| | | |    / __|/ _ \ __| | | | '_ \
 |  __/ \ V /  __/| |_| |    \__ \  __/ |_| |_| | |_) |
  \___|  \_/ \___| \__, |    |___/\___|\__|\__,_| .__/
                   |___/                         |_|
```

# Evey Setup

> **Apoya a Evey** — funciona 24/7 con modelos gratuitos, costos de hardware ~$69/mes: **[Donar](https://evey.cc/donate.html)** (BTC, ETH, SOL, XRP, DOGE)


Un script. Costo cero. Stack completo de agente de IA autónomo.

Despliega un stack completo de [hermes-agent](https://github.com/NousResearch/hermes-agent) con enrutamiento de modelos, inferencia por GPU y plugins comunitarios (29 de core/observabilidad/social/memoria/calidad/extra) en menos de 5 minutos.

---

## Inicio Rápido

Flujo nativo de hermes-agent (recomendado / predeterminado para todos los usuarios):

```bash
git clone https://github.com/42-evey/evey-setup.git
cd evey-setup
bash setup.sh
```

El instalador te guiará a través de las claves API, creará la estructura de directorios, escribirá todas las configuraciones y clonará hermes-agent. Luego, elige un nivel de servicio e inicia los contenedores.

O ejecuta las 4 fases a la vez: `bash install.sh`

No interactivo (para automatización / CI / usuarios de forks):

```bash
OPENROUTER_API_KEY=sk-or-... bash install.sh --yes --tier full --plugins all
# o por fase:
bash setup.sh --yes
TIER=full bash setup-services.sh --yes
PLUGINS=all bash install-plugins.sh --yes
bash configure.sh --yes
```
Los valores predeterminados de `--yes` seleccionan plugins compatibles con el entorno nativo (los específicos del host, como el bridge, se activan explícitamente vía `--plugins`).

Después de cualquier instalación, verifica la conexión:

```bash
bash verify.sh
```

(Sale con 0 en caso de PASS general; habilita la autonomía automáticamente para que el agente esté listo para uso nativo.)

### Avanzado: Deja que Claude Code lo haga (opcional)

Para usuarios que integran con Claude Code, consulta CLAUDE.md. El flujo nativo anterior es la ruta documentada y soportada para usuarios genéricos.

---

## Qué obtienes

| Servicio | Descripción | Puerto |
|-----------|-------------|--------|
| **hermes-agent** | Agente de IA autónomo de NousResearch | 8642 |
| **LiteLLM** | Proxy de modelos con enrutamiento, fallbacks y límites de presupuesto | 4000 |
| **Ollama** | Inferencia local por GPU (NVIDIA) | 11434 |
| **MQTT** | Pub/sub de eventos en tiempo real (Mosquitto) | 1883 |
| **SearXNG** | Motor de meta-búsqueda privado | 8888 |
| **Qdrant** | Base de datos vectorial para RAG/memoria | 6333 |
| **ntfy** | Notificaciones push | 2586 |
| **n8n** | Automatización de flujos de trabajo | 5678 |
| **Langfuse** | Seguimiento de costos de LLM y observabilidad | 3100 |
| **Uptime Kuma** | Monitoreo de servicios y alertas | 3001 |

Además, plugins comunitarios (29 enumerados en categorías instalables) para autonomía, memoria, validación de calidad, funciones sociales y más. Los componentes específicos del host (ej. bridge) se activan mediante tu elección de plugins.

---

## Prerrequisitos

- **Docker** >= 24.0 con Docker Compose v2
- **Git**
- **5GB+ de espacio libre en disco**
- **Clave API de OpenRouter** (funciona el nivel gratuito) -- consíguela en [openrouter.ai/keys](https://openrouter.ai/keys)
- **GPU NVIDIA** (opcional) -- Ollama recurre a la CPU si no se detecta GPU

---

## Arquitectura

```
 Usuario
  |
  |  Telegram / CLI / Discord
  v
+----------------------------------------------------------+
|                     hermes-agent                          |
|  (agente de IA autónomo -- metas, cron, plugins, habilidades) |
+------+----------+----------+----------+---------+--------+
       |          |          |          |         |
       v          v          v          v         v
  +---------+ +--------+ +-------+ +------+ +--------+
  | LiteLLM | | Ollama | | MQTT  | |SearX | | Qdrant |
  |  proxy  | |  GPU   | | evento | |  NG  | | vector |
  | :4000   | | :11434 | | :1883 | |:8888 | | :6333  |
  +---------+ +--------+ +-------+ +------+ +--------+
       |
       v
  +--------------------------------------------------+
  |            Proveedores de Modelos (via LiteLLM)  |
  |  OpenRouter (gratis)  |  Ollama (local)  |  + más  |
  +--------------------------------------------------+

  Servicios opcionales (nivel full):
  +---------+ +----------+ +-------------+
  |   n8n   | | Langfuse | | Uptime Kuma |
  | :5678   | |  :3100   | |    :3001    |
  +---------+ +----------+ +-------------+
  |  ntfy   |
  |  :2586  |
  +---------+
```

Todos los puertos se vinculan solo a `127.0.0.1` (no expuestos a la red).

---

## Niveles del Stack

Se proporcionan tres plantillas de docker-compose. Elige tu nivel al momento de la instalación.

### Base (3 servicios)
```
hermes-agent + LiteLLM + Ollama
```
Stack mínimo viable. Ideal para pruebas y comenzar.

### Services (7 servicios)
```
Base + MQTT + SearXNG + Qdrant + ntfy
```
Añade mensajería en tiempo real, búsqueda web, memoria vectorial y notificaciones push.

### Full (12+ servicios)
```
Services + n8n + Langfuse + Uptime Kuma + Backends de Postgres
```
Stack de producción completo con automatización de flujos, seguimiento de costos y monitoreo.

---

## Uso Paso a Paso

La configuración se divide en 4 fases. Cada fase es un script independiente que puede ejecutarse por separado.

### Fase 1: Cimientos

```bash
bash setup.sh
```

Verifica los prerrequisitos (Docker >= 24, Compose v2, git, 5GB disco), solicita claves API (OpenRouter, Telegram, Discord), genera secretos internos seguros, crea la estructura de directorios, clona hermes-agent y escribe todos los archivos de configuración.

### Fase 2: Despliegue de Servicios

```bash
bash setup-services.sh
```

Elige un nivel de stack (base/services/full), verifica disponibilidad de puertos, detecta la GPU, copia la plantilla de docker-compose correspondiente e inicia los contenedores. Espera a que los servicios estén saludables.

### Fase 3: Plugins

```bash
bash install-plugins.sh
```

Menú interactivo (o `--plugins all|core,extra...`) por categorías. Selecciona qué grupos de plugins instalar (core, observability, social, memory, quality, extra). Clona desde el repositorio de plugins y copia los seleccionados al directorio de datos del agente. (Los plugins específicos del host son opcionales mediante selección.)

### Fase 4: Configuración

```bash
bash configure.sh
```

Asistente interactivo para la selección del modelo cerebral, umbral de compresión, programación de tareas cron, emparejamiento con Telegram y preset de personalidad SOUL.md. Genera scripts de ayuda en `scripts/`.

### Verificación y Autonomía

```bash
bash verify.sh
```

Script de diagnóstico: imprime PASS/FAIL para servicios, configuraciones, clonación, alcanzabilidad de LiteLLM y plugins. En caso de PASS, habilita la autonomía automáticamente (metas + marcador) para que el hermes nativo no quede inactivo.

Se admiten equivalentes no interactivos en todos los scripts mediante `--yes`, `--tier`, `--plugins` y variables de entorno `OPENROUTER_API_KEY`, `TIER`, `PLUGINS`.

---

## Configuración

Después de la instalación, toda la configuración reside en tu directorio de instalación:

```
hermes-stack/
  .env                          # Claves API y secretos (gitignored)
  docker-compose.yml            # Definiciones de servicio para tu nivel
  config/
    litellm.yaml                # Enrutamiento de modelos, fallbacks, presupuesto
    mosquitto/mosquitto.conf    # Configuración del broker MQTT
    searxng/settings.yml        # Ajustes del motor de búsqueda
  data/
    hermes/                     # Datos del agente (plugins, habilidades, memorias, cron)
      config.yaml               # Configuración de comportamiento del agente
      SOUL.md                   # Personalidad del agente
    # claude-bridge/ (opcional, creado solo si se selecciona el plugin bridge para Claude Code)
  src/
    hermes-agent/               # Fuente del agente (clonado de NousResearch)
```

### Archivos de configuración clave

| Archivo | Qué editar |
|---------|-------------|
| `.env` | Claves API, tokens, zona horaria |
| `config/litellm.yaml` | Añadir/eliminar modelos, cambiar cadenas de fallback, establecer presupuesto |
| `data/hermes/config.yaml` | Comportamiento del agente: compresión, enrutamiento inteligente, aprobaciones, sets de herramientas |
| `data/hermes/SOUL.md` | Personalidad del agente y marco de decisiones |

### Modelos

La configuración predeterminada utiliza modelos totalmente gratuitos:

- **Brain**: MiMo-V2-Pro vía OpenRouter (gratis, 1M contexto)
- **Fallbacks**: Nemotron Ultra 253B, Llama 3.3 70B, Step Flash, Qwen Coder, Gemma 27B, Mistral Small, GLM-4.5 Air (todos gratis)
- **Local**: Ollama con hermes3:8b y qwen3.5:4b (descargarlos tras la instalación)

Costo diario: **$0**.

---

## Plugins

Instala los plugins de forma interactiva después de la configuración:

```bash
bash install-plugins.sh
```

### Categorías

| Categoría | Plugins | Descripción |
|-----------|---------|-------------|
| **Core** | bridge, goals, delegate-model, status, cost-guard | Capacidades esenciales del agente |
| **Observability** | telemetry, watchdog, mqtt | Monitoreo y alertas |
| **Social** | moltbook, proactive, news | Interacción con el usuario y contenido |
| **Memory** | memory-adaptive, consolidate, learner, habits | Gestión de memoria persistente |
| **Quality** | reflect, validate, council, email-guard | Validación y revisión de salida |
| **Extra** | autonomy, research, scheduler, digest, delegation-score, identity, session-guard, telegram-ux, sandbox, cache | Capacidades extendidas |

Todos los plugins provienen de [42-evey/hermes-plugins](https://github.com/42-evey/hermes-plugins).

---

## Comandos Comunes

```bash
# Gestión de servicios
docker compose up -d                    # iniciar todos los servicios
docker compose down                     # detener todos los servicios
docker compose restart hermes-agent     # reiniciar el agente tras cambios de config

# Logs
docker compose logs -f hermes-agent     # logs del agente
docker compose logs -f hermes-litellm   # logs del proxy de modelos

# Verificaciones de salud
curl http://localhost:4000/health/liveliness   # LiteLLM
curl http://localhost:8642/health              # API del Agente
docker compose ps                              # todos los servicios
bash verify.sh                                 # diagnóstico completo + auto autonomía en PASS

# Modelos
docker exec hermes-ollama ollama pull hermes3:8b    # descargar modelo local
docker exec hermes-ollama ollama list               # listar modelos locales
```

---

## Resolución de Problemas

### LiteLLM no inicia
- Verifica tu clave API de OpenRouter en `.env`
- Ejecuta `docker compose logs hermes-litellm` para más detalles
- Verifica la sintaxis de la config: `python3 -c "import yaml; yaml.safe_load(open('config/litellm.yaml'))"`

### Errores de GPU en Ollama
- Si no tienes GPU NVIDIA: elimina el bloque `deploy:` de `hermes-ollama` en `docker-compose.yml`
- Si tienes GPU pero falla: asegúrate de que [NVIDIA Container Toolkit](https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/install-guide.html) esté instalado
- Ollama también funciona en CPU, aunque más lento

### Conflictos de puertos
- El instalador verifica los puertos antes de iniciar. Si un puerto está en uso:
  ```bash
  ss -tlnp | grep :4000    # encontrar qué está usando el puerto
  ```
- Cambia el puerto del host en `docker-compose.yml` (ej., `"127.0.0.1:4001:4000"`)

### El agente no responde
- Verifica primero que LiteLLM esté saludable (el agente depende de él)
- Ejecuta `docker compose restart hermes-agent`
- Revisa `docker compose logs hermes-agent --tail 50`

### Los plugins no cargan
- Los plugins van en `data/hermes/plugins/`
- Reinicia el agente después de instalar: `docker compose restart hermes-agent`
- Revisa los archivos README de los plugins por cualquier cambio requerido en `config.yaml`

### Instalación existente
- Volver a ejecutar `setup.sh` en un directorio existente pedirá confirmación antes de sobrescribir
- Los archivos de configuración se reemplazan, pero los volúmenes de datos se conservan
- Haz una copia de seguridad de `.env` antes de re-ejecutar si lo habías personalizado

---

## Seguridad

Este stack está diseñado para **despliegue local único** en una sola máquina. No está destinado a ser expuesto a la internet pública.

### Aislamiento de red

Cada puerto de servicio se vincula a `127.0.0.1`, lo que significa que el tráfico nunca sale de tu máquina. Ningún servicio es accesible desde la red a menos que cambies explícitamente las vinculaciones de puertos en `docker-compose.yml`. Si necesitas acceso remoto, usa un túnel SSH o un proxy inverso con autenticación; no cambies `127.0.0.1` por `0.0.0.0`.

### Gestión de secretos

- Todas las claves API y contraseñas de servicios internos son generadas automáticamente por `setup.sh` usando `openssl rand` y escritas en `.env`
- `.env` se configura con `chmod 600` (solo lectura/escritura para el propietario) y está en el gitignore
- Ningún secreto aparece en ningún archivo excepto en `.env`; las plantillas de docker-compose referencian secretos vía sintaxis `${VAR}`
- La clave secreta de SearXNG se genera aleatoriamente al instalar (no está hardcodeada)
- No hay credenciales hardcodeadas en ninguna parte del código base

### Valores predeterminados de servicio

- MQTT permite acceso anónimo; esto es seguro porque el broker solo escucha en localhost. Si expones el puerto 1883, configura la autenticación primero.
- La redacción de PII (información personalmente identificable) y secretos está habilitada por defecto en la configuración del agente (`data/hermes/config.yaml`)
- LiteLLM impone un límite de presupuesto diario ($10 por defecto) para evitar costos excesivos de API
- Todos los contenedores de docker usan logs de tipo `json-file` con rotación de 10MB para evitar el agotamiento del disco

---

## Estructura del Proyecto

```
evey-setup/
  setup.sh                 # Fase 1: prerrequisitos, estructura, secretos, archivos de config
  setup-services.sh        # Fase 2: selección de nivel, docker-compose, inicio de contenedores
  install-plugins.sh       # Fase 3: instalador interactivo de plugins por categoría
  configure.sh             # Fase 4: modelo cerebral, compresión, cron, asistente de personalidad
  lib/
    common.sh              # Ayudantes compartidos (colores, logs, generación de claves, chequeo de puertos)
  templates/
    docker-compose.base.yml       # 3 servicios (agent + LiteLLM + Ollama)
    docker-compose.services.yml   # 7 servicios (+ MQTT, SearXNG, Qdrant, ntfy)
    docker-compose.full.yml       # 12+ servicios (+ n8n, Langfuse, Uptime Kuma)
    litellm.yaml                  # Configuración completa de enrutamiento (8 modelos gratis + 2 locales)
    config.yaml                   # Plantilla de configuración del agente
    soul.md                       # Plantilla de personalidad del agente
    .env.template                 # Referencia de variables de entorno
    .gitignore                    # Valores predeterminados de gitignore seguros
  README.md
  LICENSE
```

---

## Licencia

Licencia MIT. Consulta [LICENSE](LICENSE).

---

## Créditos

Construido por [Evey](https://evey.cc) — un agente de IA autónomo que funciona 24/7 en un stack auto-alojado.

Impulsado por [hermes-agent](https://github.com/NousResearch/hermes-agent) de Nous Research.```
