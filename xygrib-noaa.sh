#!/bin/bash
# --------------------------------------------------------------------------------------------------------------------------------------
# File: xygrib-noaa.sh
# By Julio Alberto Lascano https://mastodon.social/@drcalambre
#________          _________        .__                ___.                  
#\______ \_______  \_   ___ \_____  |  | _____    _____\_ |_________   ____  
# |    |  \_  __ \ /    \  \/\__  \ |  | \__  \  /     \| __ \_  __ \_/ __ \ 
# |    `   \  | \/ \     \____/ __ \|  |__/ __ \|  Y Y  \ \_\ \  | \/\  ___/ 
#/_______  /__|     \______  (____  /____(____  /__|_|  /___  /__|    \___  >
#        \/                \/     \/          \/      \/    \/            \/ 
# --------------------------------------------------------------------------------------------------------------------------------------
# GFS NOAA NOMADS - v1.0.2 — 2026-09-08
# --------------------------------------------------------------------------------------------------------------------------------------
# Descarga un pronóstico GFS de 0.25° directamente desde NOAA NOMADS
# y construye un archivo GRIB2 compatible con XyGrib.
#
# Características principales:
#   - Detección automática del ciclo GFS más reciente disponible (18Z → 12Z → 06Z → 00Z)
#   - Reintento con días anteriores si la fecha actual no tiene ciclos disponibles
#   - Fallback inteligente a ciclos alternativos si un archivo devuelve 404
#   - Soporte dinámico para cualquier horizonte entre 0 y 384 horas
#   - Adaptación automática de la resolución temporal (3h hasta 240h, 12h de 240h a 384h)
#   - Validación de límites del modelo GFS 0.25°
#   - Limpieza automática de archivos temporales
#   - Validación del formato GRIB final
#   - Salida de progreso clara y compacta
#   - [NUEVO] Descarga opcional de datos de olas (WW3) con detección inteligente de archivos disponibles
# ============================================================

set -u

# ------------------------------------------------------------
# CONFIGURACIÓN PRINCIPAL
# ------------------------------------------------------------

# Fecha UTC actual para la descarga
DATE=$(date -u +%Y%m%d)

# Ciclos GFS disponibles en orden de preferencia (el primero disponible será usado)
CYCLES=("18" "12" "06" "00")

# Número máximo de días hacia atrás que se buscarán si la fecha actual no tiene datos
# El modelo GFS mantiene disponible los datos de los últimos días, por lo que
# es seguro buscar hasta 3 días atrás.
MAX_DAYS_BACK=3

# ------------------------------------------------------------
# CONFIGURACIÓN DEL HORIZONTE DE PRONÓSTICO
# ------------------------------------------------------------

# Horizonte deseado en horas.
# El modelo GFS 0.25° tiene un límite máximo de 384 horas (16 días).
# Valores permitidos: 0 - 384
MAX_FORECAST=72  # 3 días (configurable)

# --- VALIDACIÓN DEL HORIZONTE ---
# El modelo GFS 0.25° no proporciona archivos más allá de 384 horas.
if [ "$MAX_FORECAST" -gt 384 ]; then
    echo "❌ ERROR: MAX_FORECAST cannot exceed 384 hours (GFS 0.25° limit)."
    echo "   Current value: ${MAX_FORECAST}h"
    echo "   Please set MAX_FORECAST to a value between 0 and 384."
    exit 1
fi

if [ "$MAX_FORECAST" -lt 0 ]; then
    echo "❌ ERROR: MAX_FORECAST cannot be negative."
    echo "   Current value: ${MAX_FORECAST}h"
    exit 1
fi

# --- CONFIGURACIÓN DINÁMICA DEL INTERVALO ---
# El modelo GFS 0.25° cambia su resolución temporal a partir de las 240 horas:
#   - De 0 a 240 horas: datos cada 3 horas
#   - De 240 a 384 horas: datos cada 12 horas
#
# Esta lógica ajusta automáticamente el intervalo (STEP) y calcula
# el número exacto de archivos que se descargarán.

if [ "$MAX_FORECAST" -le 240 ]; then
    # Caso 1: Horizonte dentro del rango de alta resolución (≤ 240h)
    # Se usa un intervalo fijo de 3 horas
    STEP=3
    EXPECTED_FILES=$((MAX_FORECAST / STEP + 1))
else
    # Caso 2: Horizonte en el rango de baja resolución (> 240h)
    # Se necesita un enfoque mixto: 3h hasta 240h, 12h de 240h a MAX_FORECAST
    
    # Paso 1: Calcular archivos en el tramo de 0-240h (cada 3h)
    # Fórmula: (240 / 3) + 1 = 81 archivos (f000 a f240)
    STEP_3H=3
    FILES_3H=$((240 / STEP_3H + 1))
    
    # Paso 2: Calcular archivos en el tramo de 240h a MAX_FORECAST (cada 12h)
    # Se excluye el archivo f240 (ya contado en FILES_3H) usando -240 en el numerador
    STEP_12H=12
    REMAINING_HOURS=$((MAX_FORECAST - 240))
    FILES_12H=$((REMAINING_HOURS / STEP_12H))
    
    # Paso 3: Sumar ambos tramos para obtener el total esperado
    EXPECTED_FILES=$((FILES_3H + FILES_12H))
    
    # Paso 4: Establecer STEP para el bucle principal (inicia en 3h)
    # El bucle cambiará dinámicamente a 12h cuando supere las 240h
    STEP=3
fi

# ------------------------------------------------------------
# CONFIGURACIÓN DE LA REGIÓN
# ------------------------------------------------------------

# Coordenadas geográficas para el recorte del GRIB.
# Por defecto cubre Sudamérica hasta el norte de Argentina.
# Los valores negativos indican Oeste (longitud) y Sur (latitud).
WEST="-90"    # Límite oeste (longitud) - Océano Pacífico
EAST="-30"    # Límite este (longitud) - Océano Atlántico
NORTH="-20"   # Límite norte (latitud) - Norte de Argentina
SOUTH="-60"   # Límite sur (latitud) - Cabo de Hornos

# ------------------------------------------------------------
# CONFIGURACIÓN DE OLAS (WW3)
# ------------------------------------------------------------

# Activar descarga de datos de olas (WW3)
#   true  = descargar también los datos de olas
#   false = solo descargar GFS (tiempo)
DOWNLOAD_WAVES=true

# ------------------------------------------------------------
# DIRECTORIOS
# ------------------------------------------------------------

# Directorio temporal para archivos intermedios (se limpia al finalizar)
# El sufijo $$ añade el PID del proceso para evitar colisiones
WORKDIR="/tmp/gfs-v1-${DATE}-$$"
WAVE_WORKDIR="/tmp/wave-v1-${DATE}-$$"

# Directorio de GRIB de XyGrib (donde se guarda el archivo final)
XYGRIB_DIR="${HOME}/.xygrib/grib"

# Archivo final: nombre que incluye la fecha y el horizonte descargado
# Se usará la fecha real de descarga (DATE) para identificar cuándo se generó
OUTPUT="${XYGRIB_DIR}/GFS_NOAA_${DATE}_${MAX_FORECAST}hs.grib2"
WAVE_OUTPUT="${XYGRIB_DIR}/WW3_NOAA_${DATE}_${MAX_FORECAST}hs.grib2"

# Pausa entre solicitudes (segundos) para no sobrecargar el servidor NOAA
# NOAA recomienda espaciar las solicitudes automatizadas
PAUSE=8

# ------------------------------------------------------------
# FUNCIONES
# ------------------------------------------------------------

# Función: test_cycle
# Descripción: Verifica si un ciclo GFS específico está disponible en NOAA
# Parámetros: $1 = ciclo (ej. "12"), $2 = fecha (ej. "20260908")
# Retorna: 0 si está disponible, 1 si no
test_cycle() {
    local cycle=$1
    local date=$2
    local test_url="https://nomads.ncep.noaa.gov/cgi-bin/filter_gfs_0p25.pl?file=gfs.t${cycle}z.pgrb2.0p25.f000&dir=%2Fgfs.${date}%2F${cycle}%2Fatmos&subregion=&leftlon=-90&rightlon=-30&toplat=15&bottomlat=-60"
    curl --output /dev/null --silent --head --fail "$test_url"
    return $?
}

# Función: find_best_cycle
# Descripción: Encuentra el primer ciclo disponible para una fecha específica
# Parámetros: $1 = fecha (ej. "20260908")
# Retorna: El ciclo disponible (ej. "12") o cadena vacía si ninguno funciona
find_best_cycle() {
    local date=$1
    for cycle in "${CYCLES[@]}"; do
        echo "  Probando ciclo ${cycle}Z..." >&2
        if test_cycle "$cycle" "$date"; then
            echo "$cycle"
            return 0
        fi
    done
    echo ""
    return 1
}

# Función: find_best_cycle_with_retry
# Descripción: Busca un ciclo disponible, primero en la fecha actual y luego
#              en días anteriores si es necesario.
# Retorna: Una cadena con el formato "CICLO:FECHA" (ej. "12:20260907")
#          o cadena vacía si no se encuentra ningún ciclo.
find_best_cycle_with_retry() {
    local current_date="${DATE}"
    local attempt=0
    
    while [ $attempt -lt $MAX_DAYS_BACK ]; do
        echo "  Probando fecha ${current_date}..." >&2
        local cycle=$(find_best_cycle "$current_date")
        if [ -n "$cycle" ]; then
            echo "${cycle}:${current_date}"
            return 0
        fi
        # Si no hay ciclos, probar con el día anterior
        current_date=$(date -u -d "${current_date} -1 day" +%Y%m%d)
        attempt=$((attempt + 1))
    done
    
    # Si llegamos aquí, no se encontró ningún ciclo en los días disponibles
    echo ""
    return 1
}

# Función: download_with_fallback
# Descripción: Descarga un archivo GFS para un forecast específico.
#              Primero intenta con el ciclo primario; si falla (ej. 404),
#              prueba con los ciclos alternativos en orden.
# Parámetros:
#   $1 = forecast (ej. "003")
#   $2 = ciclo primario (ej. "12")
#   $3 = fecha (ej. "20260907")
#   $4 = archivo de salida
# Retorna:
#   0 = éxito con ciclo primario
#   1 = éxito con ciclo alternativo (fallback)
#   2 = fallo total (ningún ciclo funcionó)
download_with_fallback() {
    local forecast=$1
    local primary_cycle=$2
    local date=$3
    local output_file=$4
    
    # Base de la URL con placeholders {cycle} y {date} que se reemplazarán dinámicamente
    local url_base="https://nomads.ncep.noaa.gov/cgi-bin/filter_gfs_0p25.pl?file=gfs.t{cycle}z.pgrb2.0p25.f${forecast}&dir=%2Fgfs.{date}%2F{cycle}%2Fatmos&var_TMP=on&lev_2_m_above_ground=on&var_DPT=on&lev_2_m_above_ground=on&var_RH=on&lev_2_m_above_ground=on&var_TCDC=on&lev_entire_atmosphere=on&var_PRATE=on&lev_surface=on&var_CSNOW=on&lev_surface=on&var_UGRD=on&lev_10_m_above_ground=on&var_VGRD=on&lev_10_m_above_ground=on&var_GUST=on&lev_surface=on&var_CAPE=on&lev_surface=on&var_CFRZR=on&lev_surface=on&var_SNOD=on&lev_surface=on&var_WEASD=on&lev_surface=on&var_HGT=on&lev_925_mb=on&lev_850_mb=on&lev_700_mb=on&lev_600_mb=on&lev_500_mb=on&lev_400_mb=on&lev_300_mb=on&lev_250_mb=on&lev_200_mb=on&var_TMP=on&lev_925_mb=on&lev_850_mb=on&lev_700_mb=on&lev_600_mb=on&lev_500_mb=on&lev_400_mb=on&lev_300_mb=on&lev_250_mb=on&lev_200_mb=on&var_HGT=on&lev_0C_isotherm=on&var_RH=on&lev_0C_isotherm=on&var_PRES=on&lev_0C_isotherm=on&subregion=&leftlon=${WEST}&rightlon=${EAST}&toplat=${NORTH}&bottomlat=${SOUTH}"
    
    # --- Intento 1: Ciclo primario ---
    local url="${url_base//\{cycle\}/$primary_cycle}"
    url="${url//\{date\}/$date}"
    if curl --fail --location --connect-timeout 30 --max-time 600 --retry 2 --retry-delay 5 --output "$output_file" "$url" 2>/dev/null; then
        echo "  ✅ ${primary_cycle}Z"
        return 0
    fi
    
    # --- Intento 2: Ciclos alternativos (fallback) ---
    for alt_cycle in "${CYCLES[@]}"; do
        if [ "$alt_cycle" != "$primary_cycle" ]; then
            local alt_url="${url_base//\{cycle\}/$alt_cycle}"
            alt_url="${alt_url//\{date\}/$date}"
            if curl --fail --location --connect-timeout 30 --max-time 600 --retry 1 --output "$output_file" "$alt_url" 2>/dev/null; then
                echo "  ✅ ${alt_cycle}Z (fallback)"
                return 1  # Éxito con fallback
            fi
        fi
    done
    
    # --- Fallo total ---
    echo "  ❌ TODOS LOS CICLOS FALLARON"
    return 2  # Fallo total
}

# Función: find_best_wave_cycle
# Descripción: Encuentra el primer ciclo disponible para WW3
# Parámetros: $1 = fecha (ej. "20260907")
# Retorna: El ciclo disponible (ej. "18") o cadena vacía si ninguno funciona
find_best_wave_cycle() {
    local date=$1
    for cycle in "${CYCLES[@]}"; do
        local test_url="https://nomads.ncep.noaa.gov/cgi-bin/filter_gfswave.pl?dir=%2Fgfs.${date}%2F${cycle}%2Fwave%2Fgridded&file=gfswave.t${cycle}z.global.0p25.f000.grib2&all_var=on&all_lev=on"
        if curl --output /dev/null --silent --head --fail "$test_url"; then
            echo "$cycle"
            return 0
        fi
    done
    echo ""
    return 1
}

# Función: find_best_wave_cycle_with_retry
# Descripción: Busca un ciclo disponible para WW3, primero en la fecha actual y luego
#              en días anteriores si es necesario.
# Retorna: Una cadena con el formato "CICLO:FECHA" (ej. "18:20260907")
#          o cadena vacía si no se encuentra ningún ciclo.
find_best_wave_cycle_with_retry() {
    local current_date="${DATE}"
    local attempt=0
    
    while [ $attempt -lt $MAX_DAYS_BACK ]; do
        local cycle=$(find_best_wave_cycle "$current_date")
        if [ -n "$cycle" ]; then
            echo "${cycle}:${current_date}"
            return 0
        fi
        current_date=$(date -u -d "${current_date} -1 day" +%Y%m%d)
        attempt=$((attempt + 1))
    done
    
    echo ""
    return 1
}

# Función: download_wave_data
# Descripción: Descarga datos de olas (WW3) para un forecast específico.
#              Usa la resolución global 0.25° con all_var=on y all_lev=on.
# Parámetros:
#   $1 = forecast (ej. "003")
#   $2 = ciclo (ej. "12")
#   $3 = fecha (ej. "20260907")
#   $4 = archivo de salida
# Retorna: 0 si éxito, 1 si fallo
download_wave_data() {
    local forecast=$1
    local cycle=$2
    local date=$3
    local output_file=$4
    
    # Estructura correcta para WW3 global 0.25° con all_var=on y all_lev=on
    local file="gfswave.t${cycle}z.global.0p25.f${forecast}.grib2"
    local url="https://nomads.ncep.noaa.gov/cgi-bin/filter_gfswave.pl?dir=%2Fgfs.${date}%2F${cycle}%2Fwave%2Fgridded&file=${file}&all_var=on&all_lev=on&subregion=&toplat=${NORTH}&leftlon=${WEST}&rightlon=${EAST}&bottomlat=${SOUTH}"
    
    if curl --fail --location --connect-timeout 30 --max-time 600 --retry 2 --retry-delay 5 --output "$output_file" "$url" 2>/dev/null; then
        return 0
    else
        return 1
    fi
}

# Función: check_wave_file_exists
# Descripción: Verifica si un archivo WW3 específico existe en el servidor
# Parámetros: $1 = forecast (ej. "003"), $2 = ciclo, $3 = fecha
# Retorna: 0 si existe, 1 si no
check_wave_file_exists() {
    local forecast=$1
    local cycle=$2
    local date=$3
    local file="gfswave.t${cycle}z.global.0p25.f${forecast}.grib2"
    local test_url="https://nomads.ncep.noaa.gov/cgi-bin/filter_gfswave.pl?dir=%2Fgfs.${date}%2F${cycle}%2Fwave%2Fgridded&file=${file}&all_var=on&all_lev=on&subregion=&toplat=${NORTH}&leftlon=${WEST}&rightlon=${EAST}&bottomlat=${SOUTH}"
    curl --output /dev/null --silent --head --fail "$test_url"
    return $?
}

# ------------------------------------------------------------
# PREPARACIÓN
# ------------------------------------------------------------

# Crear directorios necesarios
mkdir -p "${WORKDIR}"
mkdir -p "${XYGRIB_DIR}"
if [ "$DOWNLOAD_WAVES" = true ]; then
    mkdir -p "${WAVE_WORKDIR}"
fi

# Mostrar cabecera informativa
echo
echo "============================================================"
echo " GFS NOAA NOMADS - v1.0.2"
echo " ${MAX_FORECAST}-hour forecast for XyGrib"
if [ "$DOWNLOAD_WAVES" = true ]; then
    echo " + Wave data (WW3) with intelligent file detection"
fi
echo "============================================================"
echo

# Detectar el mejor ciclo disponible para GFS (con reintento en días anteriores)
echo "🔍 Detecting available GFS cycle..."
BEST_CYCLE_INFO=$(find_best_cycle_with_retry)

if [ -z "$BEST_CYCLE_INFO" ]; then
    echo "❌ ERROR: No GFS cycle available for date ${DATE} or previous ${MAX_DAYS_BACK} days."
    echo "   Please check your internet connection or try again later."
    echo "   Note: GFS cycles are usually available 3-4 hours after each cycle time."
    exit 1
fi

# Extraer el ciclo y la fecha del resultado
BEST_CYCLE="${BEST_CYCLE_INFO%:*}"
USED_DATE="${BEST_CYCLE_INFO#*:}"

if [ "$USED_DATE" != "$DATE" ]; then
    echo "ℹ️  NOTE: Using GFS data from ${USED_DATE} (current date ${DATE} has no cycles available yet)."
    echo "   This is normal when running the script early in the day (00:00-04:00 UTC)."
fi

echo "✅ Using GFS cycle: ${BEST_CYCLE}Z (date: ${USED_DATE})"
echo

# Mostrar configuración completa
echo "Date (current) : ${DATE}"
echo "Date (used)    : ${USED_DATE}"
echo "GFS Cycle      : ${BEST_CYCLE}Z"
echo "Horizon        : f000 → f${MAX_FORECAST}"
echo "Interval       : ${STEP} hours (dynamic if >240h)"
echo "Time steps     : ${EXPECTED_FILES}"
echo "Region         : ${WEST}°W to ${EAST}°W / ${SOUTH}°S to ${NORTH}°N"
echo "GFS output     : ${OUTPUT}"
if [ "$DOWNLOAD_WAVES" = true ]; then
    echo "Wave output    : ${WAVE_OUTPUT}"
fi
echo "Temp dir       : ${WORKDIR}"
echo

# ------------------------------------------------------------
# DESCARGA DE ARCHIVOS GFS
# ------------------------------------------------------------

echo "============================================================"
echo " DOWNLOADING GFS (weather)"
echo "============================================================"
echo

# Inicializar contadores
SUCCESS=0
FAILED=0
FALLBACK_USED=0
TOTAL=0

# Bucle principal de descarga
# El intervalo (STEP) puede cambiar dinámicamente si MAX_FORECAST > 240
for ((HOUR=0; HOUR<=MAX_FORECAST; HOUR+=STEP)); do
    
    # --- LÓGICA DE CAMBIO DE RESOLUCIÓN ---
    # Si superamos las 240h y aún estamos en STEP=3, cambiamos a STEP=12
    # Esto refleja la resolución real del modelo GFS 0.25°
    if [ "$HOUR" -ge 240 ] && [ "$STEP" -ne 12 ]; then
        STEP=12
        # Nota: No recalculamos EXPECTED_FILES aquí porque ya se calculó al inicio
    fi
    
    # Formatear el número de hora (ej. 003, 012, 168)
    FORECAST=$(printf "%03d" "${HOUR}")
    PART="${WORKDIR}/gfs_${FORECAST}.grib2"
    TOTAL=$((TOTAL + 1))
    
    # Mostrar progreso compacto
    printf "[%02d/%02d] F%s → " "$TOTAL" "$EXPECTED_FILES" "$FORECAST"
    
    # Intentar descargar el archivo con fallback
    download_with_fallback "$FORECAST" "$BEST_CYCLE" "$USED_DATE" "$PART"
    STATUS=$?
    
    # Procesar el resultado de la descarga
    if [ $STATUS -eq 0 ] || [ $STATUS -eq 1 ]; then
        SIZE=$(du -h "$PART" | cut -f1)
        
        if [ $STATUS -eq 0 ]; then
            echo " ✅ ${SIZE} [${BEST_CYCLE}Z]"
        else
            echo " ✅ ${SIZE} [fallback]"
            ((FALLBACK_USED++))
        fi
        ((SUCCESS++))
    else
        echo " ❌ FAILED"
        ((FAILED++))
    fi
    
    # Pausa entre solicitudes (excepto después del último archivo)
    if [ "$HOUR" -lt "$MAX_FORECAST" ]; then
        sleep "$PAUSE"
    fi
done

# ------------------------------------------------------------
# RESULTADOS DE LA DESCARGA GFS
# ------------------------------------------------------------

echo
echo "============================================================"
echo " GFS RESULTS"
echo "============================================================"
echo
echo "✅ Successful       : ${SUCCESS}"
echo "🔄 Fallback used    : ${FALLBACK_USED}"
echo "❌ Failed           : ${FAILED}"
echo "📊 Total            : ${TOTAL}"
echo

# Si hay demasiados fallos, abortar para no construir un GRIB incompleto
if [ "$FAILED" -gt 5 ]; then
    echo "❌ ERROR: Too many failures (${FAILED}). Aborting."
    echo "   This prevents creating an incomplete GRIB file."
    exit 1
fi

# ------------------------------------------------------------
# CONSTRUIR EL GRIB FINAL (GFS)
# ------------------------------------------------------------

echo "Building final GFS GRIB2..."
echo

# Eliminar archivo anterior si existe
rm -f "$OUTPUT"

# Concatenar todos los archivos parciales en orden cronológico
for ((HOUR=0; HOUR<=MAX_FORECAST; HOUR+=STEP)); do
    FORECAST=$(printf "%03d" "${HOUR}")
    PART="${WORKDIR}/gfs_${FORECAST}.grib2"
    if [ -f "$PART" ] && [ -s "$PART" ]; then
        cat "$PART" >> "$OUTPUT"
    else
        echo "⚠️  Warning: F${FORECAST} is missing. GRIB will have a gap."
    fi
done

# ------------------------------------------------------------
# VALIDACIÓN DEL GRIB FINAL (GFS)
# ------------------------------------------------------------

if [ ! -s "$OUTPUT" ]; then
    echo "❌ ERROR: Final GFS GRIB is empty."
    exit 1
fi

echo "✅ Final GFS GRIB created:"
ls -lh "$OUTPUT"

# Verificar que el archivo sea realmente un GRIB usando el comando 'file'
if command -v file >/dev/null 2>&1; then
    if file "$OUTPUT" | grep -qi "grib"; then
        echo "✅ File validation: GRIB format confirmed."
    else
        echo "⚠️  Warning: File may not be a valid GRIB format."
        echo "   Please check the file manually."
    fi
fi

# ------------------------------------------------------------
# DESCARGA DE DATOS DE OLAS (WW3) - CON DETECCIÓN INTELIGENTE
# ------------------------------------------------------------

if [ "$DOWNLOAD_WAVES" = true ]; then
    echo
    echo "============================================================"
    echo " DOWNLOADING WAVE DATA (WW3)"
    echo "============================================================"
    echo

    # Detectar el mejor ciclo para WW3 (independiente de GFS)
    echo "🔍 Detecting available WW3 cycle..."
    WAVE_CYCLE_INFO=$(find_best_wave_cycle_with_retry)

    if [ -z "$WAVE_CYCLE_INFO" ]; then
        echo "⚠️  WARNING: No WW3 cycle available for date ${DATE} or previous ${MAX_DAYS_BACK} days."
        echo "   Skipping wave data download."
    else
        WAVE_CYCLE="${WAVE_CYCLE_INFO%:*}"
        WAVE_DATE="${WAVE_CYCLE_INFO#*:}"

        if [ "$WAVE_DATE" != "$DATE" ]; then
            echo "ℹ️  NOTE: Using WW3 data from ${WAVE_DATE} (current date ${DATE} has no cycles available yet)."
        fi

        echo "✅ Using WW3 cycle: ${WAVE_CYCLE}Z (date: ${WAVE_DATE})"
        echo

        WAVE_SUCCESS=0
        WAVE_FAILED=0
        WAVE_TOTAL=0
        
        # Bucle inteligente: probar archivos hasta que uno falle o se alcance MAX_FORECAST
        HOUR=0
        while [ "$HOUR" -le "$MAX_FORECAST" ]; do
            # Formatear el número de hora (ej. 003, 012, 168)
            FORECAST=$(printf "%03d" "${HOUR}")
            WAVE_PART="${WAVE_WORKDIR}/wave_${FORECAST}.grib2"
            
            # Verificar si el archivo existe antes de descargar
            if check_wave_file_exists "$FORECAST" "$WAVE_CYCLE" "$WAVE_DATE"; then
                # El archivo existe, descargarlo
                WAVE_TOTAL=$((WAVE_TOTAL + 1))
                printf "[%02d] WAVE F%s → " "$WAVE_TOTAL" "$FORECAST"
                
                if download_wave_data "$FORECAST" "$WAVE_CYCLE" "$WAVE_DATE" "$WAVE_PART"; then
                    SIZE=$(du -h "$WAVE_PART" | cut -f1)
                    echo " ✅ ${SIZE}"
                    ((WAVE_SUCCESS++))
                else
                    echo " ❌ FAILED (download error)"
                    ((WAVE_FAILED++))
                    break
                fi
            else
                # El archivo no existe, salir del bucle
                if [ "$WAVE_TOTAL" -eq 0 ]; then
                    echo "⚠️  No wave files found for cycle ${WAVE_CYCLE}Z (date: ${WAVE_DATE})."
                else
                    echo "ℹ️  No more wave files available beyond F${FORECAST}."
                    echo "   Total wave files downloaded: ${WAVE_SUCCESS}"
                fi
                break
            fi
            
            # Avanzar al siguiente paso
            HOUR=$((HOUR + STEP))
            
            # Pausa entre solicitudes
            sleep "$PAUSE"
        done

        # ------------------------------------------------------------
        # RESULTADOS DE LA DESCARGA WW3
        # ------------------------------------------------------------
        echo
        echo "============================================================"
        echo " WAVE RESULTS"
        echo "============================================================"
        echo
        echo "✅ Successful : ${WAVE_SUCCESS}"
        echo "❌ Failed    : ${WAVE_FAILED}"
        echo "📊 Total     : ${WAVE_TOTAL}"
        echo

        # ------------------------------------------------------------
        # CONSTRUIR EL GRIB FINAL (WW3)
        # ------------------------------------------------------------
        if [ "$WAVE_SUCCESS" -gt 0 ]; then
            echo "Building final Wave GRIB2..."
            echo

            rm -f "$WAVE_OUTPUT"

            # Reconstruir la lista de archivos descargados
            for ((HOUR=0; HOUR<=MAX_FORECAST; HOUR+=STEP)); do
                FORECAST=$(printf "%03d" "${HOUR}")
                WAVE_PART="${WAVE_WORKDIR}/wave_${FORECAST}.grib2"
                if [ -f "$WAVE_PART" ] && [ -s "$WAVE_PART" ]; then
                    cat "$WAVE_PART" >> "$WAVE_OUTPUT"
                fi
            done

            if [ -s "$WAVE_OUTPUT" ]; then
                echo "✅ Final Wave GRIB created:"
                ls -lh "$WAVE_OUTPUT"

                if command -v file >/dev/null 2>&1; then
                    if file "$WAVE_OUTPUT" | grep -qi "grib"; then
                        echo "✅ File validation: GRIB format confirmed."
                    else
                        echo "⚠️  Warning: File may not be a valid GRIB format."
                    fi
                fi
            else
                echo "❌ ERROR: Final Wave GRIB is empty."
            fi
        else
            echo "❌ No wave data was successfully downloaded."
        fi
    fi
fi

# ------------------------------------------------------------
# LIMPIEZA DE ARCHIVOS TEMPORALES
# ------------------------------------------------------------

echo "🧹 Cleaning temporary files..."
rm -rf "$WORKDIR"
if [ "$DOWNLOAD_WAVES" = true ]; then
    rm -rf "$WAVE_WORKDIR"
fi
echo "✅ Temporary files removed."

# ------------------------------------------------------------
# FINALIZACIÓN
# ------------------------------------------------------------

echo
echo "============================================================"
echo " v1.0.2 COMPLETED"
echo "============================================================"
echo
echo "GFS file:"
echo "  $OUTPUT"
if [ "$DOWNLOAD_WAVES" = true ] && [ -s "$WAVE_OUTPUT" ]; then
    echo
    echo "Wave file (WW3):"
    echo "  $WAVE_OUTPUT"
fi
echo
echo "You can now open them in XyGrib:"
echo "  File → Open GRIB..."
echo
echo "============================================================"
