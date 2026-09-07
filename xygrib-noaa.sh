#!/bin/bash
# --------------------------------------------------------------------------------------------------------------------------------------
# File: xygrib-noaash
# By Julio Alberto Lascano https://mastodon.social/@drcalambre
#________          _________        .__                ___.                  
#\______ \_______  \_   ___ \_____  |  | _____    _____\_ |_________   ____  
# |    |  \_  __ \ /    \  \/\__  \ |  | \__  \  /     \| __ \_  __ \_/ __ \ 
# |    `   \  | \/ \     \____/ __ \|  |__/ __ \|  Y Y  \ \_\ \  | \/\  ___/ 
#/_______  /__|     \______  (____  /____(____  /__|_|  /___  /__|    \___  >
#        \/                \/     \/          \/      \/    \/            \/ 
# --------------------------------------------------------------------------------------------------------------------------------------
# GFS NOAA NOMADS - v1.0.0 — 2026-09-07
# --------------------------------------------------------------------------------------------------------------------------------------
# Pronóstico de 72 horas para XyGrib
#
# Corrección: Mejora en el conteo de fallos y fallbacks
# ============================================================

set -u

# ------------------------------------------------------------
# CONFIGURACIÓN
# ------------------------------------------------------------

DATE=$(date -u +%Y%m%d)

# Ciclos GFS disponibles (en orden de preferencia)
CYCLES=("18" "12" "06" "00")

# Horizonte: 72 horas
MAX_FORECAST=72
STEP=3

# Región optimizada para Sudamérica
WEST="-90"
EAST="-30"
NORTH="15"
SOUTH="-60"

# Directorios
WORKDIR="/tmp/gfs-v10-${DATE}-$$"
XYGRIB_DIR="${HOME}/.xygrib/grib"
OUTPUT="${XYGRIB_DIR}/GFS_NOAA_${DATE}_72hs.grib2"

PAUSE=8
EXPECTED_FILES=25

# ------------------------------------------------------------
# FUNCIONES
# ------------------------------------------------------------

test_cycle() {
    local cycle=$1
    local test_url="https://nomads.ncep.noaa.gov/cgi-bin/filter_gfs_0p25.pl?file=gfs.t${cycle}z.pgrb2.0p25.f000&dir=%2Fgfs.${DATE}%2F${cycle}%2Fatmos&subregion=&leftlon=-90&rightlon=-30&toplat=15&bottomlat=-60"
    curl --output /dev/null --silent --head --fail "$test_url"
    return $?
}

find_best_cycle() {
    for cycle in "${CYCLES[@]}"; do
        echo "  Probando ciclo ${cycle}Z..." >&2
        if test_cycle "$cycle"; then
            echo "$cycle"
            return 0
        fi
    done
    echo ""
    return 1
}

download_with_fallback() {
    local forecast=$1
    local primary_cycle=$2
    local output_file=$3
    local url_base="https://nomads.ncep.noaa.gov/cgi-bin/filter_gfs_0p25.pl?file=gfs.t{cycle}z.pgrb2.0p25.f${forecast}&dir=%2Fgfs.${DATE}%2F{cycle}%2Fatmos&var_TMP=on&lev_2_m_above_ground=on&var_DPT=on&lev_2_m_above_ground=on&var_RH=on&lev_2_m_above_ground=on&var_TCDC=on&lev_entire_atmosphere=on&var_PRATE=on&lev_surface=on&var_CSNOW=on&lev_surface=on&var_UGRD=on&lev_10_m_above_ground=on&var_VGRD=on&lev_10_m_above_ground=on&var_GUST=on&lev_surface=on&var_CAPE=on&lev_surface=on&var_CFRZR=on&lev_surface=on&var_SNOD=on&lev_surface=on&var_WEASD=on&lev_surface=on&var_HGT=on&lev_925_mb=on&lev_850_mb=on&lev_700_mb=on&lev_600_mb=on&lev_500_mb=on&lev_400_mb=on&lev_300_mb=on&lev_250_mb=on&lev_200_mb=on&var_TMP=on&lev_925_mb=on&lev_850_mb=on&lev_700_mb=on&lev_600_mb=on&lev_500_mb=on&lev_400_mb=on&lev_300_mb=on&lev_250_mb=on&lev_200_mb=on&var_HGT=on&lev_0C_isotherm=on&var_RH=on&lev_0C_isotherm=on&var_PRES=on&lev_0C_isotherm=on&subregion=&leftlon=${WEST}&rightlon=${EAST}&toplat=${NORTH}&bottomlat=${SOUTH}"
    
    # Intentar con ciclo primario
    local url="${url_base//\{cycle\}/$primary_cycle}"
    if curl --fail --location --connect-timeout 30 --max-time 600 --retry 2 --retry-delay 5 --output "$output_file" "$url" 2>/dev/null; then
        echo "  ✅ ${primary_cycle}Z"
        return 0
    fi
    
    # Si falla, probar con otros ciclos
    for alt_cycle in "${CYCLES[@]}"; do
        if [ "$alt_cycle" != "$primary_cycle" ]; then
            local alt_url="${url_base//\{cycle\}/$alt_cycle}"
            if curl --fail --location --connect-timeout 30 --max-time 600 --retry 1 --output "$output_file" "$alt_url" 2>/dev/null; then
                echo "  ✅ ${alt_cycle}Z (fallback)"
                return 1  # Éxito con fallback
            fi
        fi
    done
    
    echo "  ❌ TODOS LOS CICLOS FALLARON"
    return 2  # Fallo total
}

# ------------------------------------------------------------
# PREPARACIÓN
# ------------------------------------------------------------

mkdir -p "${WORKDIR}"
mkdir -p "${XYGRIB_DIR}"

echo
echo "============================================================"
echo " GFS NOAA NOMADS - V10.1"
echo " 72-hour forecast for XyGrib"
echo "============================================================"
echo

echo "🔍 Detecting available GFS cycle..."
BEST_CYCLE=$(find_best_cycle)

if [ -z "$BEST_CYCLE" ]; then
    echo "❌ ERROR: No GFS cycle available for date ${DATE}."
    exit 1
fi

echo "✅ Using cycle: ${BEST_CYCLE}Z"
echo

echo "Date        : ${DATE}"
echo "Cycle       : ${BEST_CYCLE}Z"
echo "Horizon     : f000 → f${MAX_FORECAST}"
echo "Interval    : ${STEP} hours"
echo "Time steps  : ${EXPECTED_FILES}"
echo "Region      : ${WEST}°W to ${EAST}°W / ${SOUTH}°S to ${NORTH}°N"
echo "Output      : ${OUTPUT}"
echo "Temp dir    : ${WORKDIR}"
echo

# ------------------------------------------------------------
# DESCARGA
# ------------------------------------------------------------

echo "============================================================"
echo " DOWNLOADING"
echo "============================================================"
echo

SUCCESS=0
FAILED=0
FALLBACK_USED=0
TOTAL=0

for ((HOUR=0; HOUR<=MAX_FORECAST; HOUR+=STEP)); do
    FORECAST=$(printf "%03d" "${HOUR}")
    PART="${WORKDIR}/gfs_${FORECAST}.grib2"
    TOTAL=$((TOTAL + 1))
    
    printf "[%02d/%02d] F%s → " "$TOTAL" "$EXPECTED_FILES" "$FORECAST"
    
    download_with_fallback "$FORECAST" "$BEST_CYCLE" "$PART"
    STATUS=$?
    
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
    
    if [ "$HOUR" -lt "$MAX_FORECAST" ]; then
        sleep "$PAUSE"
    fi
done

# ------------------------------------------------------------
# RESULTADOS
# ------------------------------------------------------------

echo
echo "============================================================"
echo " RESULTS"
echo "============================================================"
echo
echo "✅ Successful       : ${SUCCESS}"
echo "🔄 Fallback used    : ${FALLBACK_USED}"
echo "❌ Failed           : ${FAILED}"
echo "📊 Total            : ${TOTAL}"
echo

if [ "$FAILED" -gt 5 ]; then
    echo "❌ ERROR: Too many failures (${FAILED}). Aborting."
    exit 1
fi

# ------------------------------------------------------------
# CONSTRUIR GRIB FINAL
# ------------------------------------------------------------

echo "Building final GRIB2..."
echo

rm -f "$OUTPUT"

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
# VALIDACIÓN
# ------------------------------------------------------------

if [ ! -s "$OUTPUT" ]; then
    echo "❌ ERROR: Final GRIB is empty."
    exit 1
fi

echo "✅ Final GRIB created:"
ls -lh "$OUTPUT"

if command -v file >/dev/null 2>&1; then
    if file "$OUTPUT" | grep -qi "grib"; then
        echo "✅ File validation: GRIB format confirmed."
    else
        echo "⚠️  Warning: File may not be a valid GRIB format."
    fi
fi

# ------------------------------------------------------------
# LIMPIEZA
# ------------------------------------------------------------

echo "🧹 Cleaning temporary files..."
rm -rf "$WORKDIR"
echo "✅ Temporary files removed."

echo
echo "============================================================"
echo " V10.1 COMPLETED"
echo "============================================================"
echo
echo "Final file:"
echo "  $OUTPUT"
echo
echo "You can now open it in XyGrib:"
echo "  File → Open GRIB..."
echo
echo "============================================================"
