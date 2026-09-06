#!/bin/bash

# ============================================================
# GFS NOAA NOMADS - V9
# Pronóstico de 72 horas para XyGrib
#
# Base: V8 / V7 VALIDADA
#
# Descarga:
#   f000 ... f072
#   cada 3 horas
#
# Total:
#   25 archivos
#
# Resultado:
#   un único GRIB2 con 72 horas de pronóstico
#
# El archivo final se guarda directamente en:
#   ~/.xygrib/grib
#
# Esto permite que XyGrib lo encuentre automáticamente
# y que las tareas de limpieza existentes de XyGrib
# puedan gestionar los archivos antiguos.
# ============================================================

set -u

# ------------------------------------------------------------
# CONFIGURACIÓN
# ------------------------------------------------------------

DATE=$(date -u +%Y%m%d)

# Ciclo GFS
CYCLE="12"

# Horizonte: 72 horas
MAX_FORECAST=72

# Intervalo temporal
STEP=3

# Región
WEST="-80"
EAST="-50"
NORTH="-15"
SOUTH="-58"

# ------------------------------------------------------------
# DIRECTORIOS
# ------------------------------------------------------------

# Archivos temporales de trabajo
WORKDIR="/tmp/gfs-v9-${DATE}-${CYCLE}z"

# Directorio oficial de GRIB de XyGrib
XYGRIB_DIR="${HOME}/.xygrib/grib"

# Archivo final
OUTPUT="${XYGRIB_DIR}/GFS_NOAA_${DATE}_${CYCLE}Z_72hs.grib2"

# Pausa entre solicitudes
PAUSE=8

# Cantidad esperada de archivos
EXPECTED_FILES=25

# ------------------------------------------------------------
# PREPARACIÓN
# ------------------------------------------------------------

mkdir -p "${WORKDIR}"
mkdir -p "${XYGRIB_DIR}"

echo
echo "============================================================"
echo " GFS NOAA NOMADS - V9"
echo " Pronóstico de 72 horas para XyGrib"
echo "============================================================"
echo
echo "Fecha       : ${DATE}"
echo "Ciclo       : ${CYCLE}Z"
echo "Horizonte   : f000 → f${MAX_FORECAST}"
echo "Intervalo   : ${STEP} horas"
echo "Tiempos     : ${EXPECTED_FILES}"
echo
echo "Región:"
echo "  Oeste     : ${WEST}"
echo "  Este      : ${EAST}"
echo "  Norte     : ${NORTH}"
echo "  Sur       : ${SOUTH}"
echo
echo "Directorio XyGrib:"
echo "  ${XYGRIB_DIR}"
echo
echo "Salida:"
echo "  ${OUTPUT}"
echo
echo "Directorio temporal:"
echo "  ${WORKDIR}"
echo
echo "============================================================"
echo

# ------------------------------------------------------------
# DESCARGA DE CADA TIEMPO
# ------------------------------------------------------------

for ((HOUR=0; HOUR<=MAX_FORECAST; HOUR+=STEP)); do

    FORECAST=$(printf "%03d" "${HOUR}")

    FILE="gfs.t${CYCLE}z.pgrb2.0p25.f${FORECAST}"

    PART="${WORKDIR}/gfs_${FORECAST}.grib2"

    echo
    echo "------------------------------------------------------------"
    echo "Pronóstico: F${FORECAST}"
    echo "Archivo   : ${FILE}"
    echo "------------------------------------------------------------"

    curl --fail --location \
         --connect-timeout 30 \
         --max-time 600 \
         --retry 2 \
         --retry-delay 5 \
         --output "${PART}" \
         "https://nomads.ncep.noaa.gov/cgi-bin/filter_gfs_0p25.pl?file=${FILE}&dir=%2Fgfs.${DATE}%2F${CYCLE}%2Fatmos&var_TMP=on&lev_2_m_above_ground=on&var_DPT=on&lev_2_m_above_ground=on&var_RH=on&lev_2_m_above_ground=on&var_TCDC=on&lev_entire_atmosphere=on&var_PRATE=on&lev_surface=on&var_CSNOW=on&lev_surface=on&var_UGRD=on&lev_10_m_above_ground=on&var_VGRD=on&lev_10_m_above_ground=on&var_GUST=on&lev_surface=on&var_CAPE=on&lev_surface=on&var_CFRZR=on&lev_surface=on&var_SNOD=on&lev_surface=on&var_WEASD=on&lev_surface=on&var_HGT=on&lev_925_mb=on&lev_850_mb=on&lev_700_mb=on&lev_600_mb=on&lev_500_mb=on&lev_400_mb=on&lev_300_mb=on&lev_250_mb=on&lev_200_mb=on&var_TMP=on&lev_925_mb=on&lev_850_mb=on&lev_700_mb=on&lev_600_mb=on&lev_500_mb=on&lev_400_mb=on&lev_300_mb=on&lev_250_mb=on&lev_200_mb=on&var_HGT=on&lev_0C_isotherm=on&var_RH=on&lev_0C_isotherm=on&var_PRES=on&lev_0C_isotherm=on&subregion=&leftlon=${WEST}&rightlon=${EAST}&toplat=${NORTH}&bottomlat=${SOUTH}"

    STATUS=$?

    if [ ${STATUS} -ne 0 ]; then
        echo
        echo "============================================================"
        echo " ERROR"
        echo " No se pudo descargar F${FORECAST}."
        echo "============================================================"
        echo
        echo "Los archivos descargados quedan en:"
        echo "${WORKDIR}"
        echo
        exit ${STATUS}
    fi

    if [ ! -s "${PART}" ]; then
        echo
        echo "ERROR: F${FORECAST} produjo un archivo vacío."
        exit 1
    fi

    SIZE=$(du -h "${PART}" | cut -f1)

    echo "OK → F${FORECAST} (${SIZE})"

    # No esperar después del último archivo
    if [ ${HOUR} -lt ${MAX_FORECAST} ]; then
        echo "Esperando ${PAUSE} segundos..."
        sleep "${PAUSE}"
    fi

done

# ------------------------------------------------------------
# COMPROBAR CANTIDAD DE ARCHIVOS
# ------------------------------------------------------------

COUNT=$(find "${WORKDIR}" -maxdepth 1 -name 'gfs_*.grib2' | wc -l)

echo
echo "============================================================"
echo " Descarga terminada"
echo "============================================================"
echo
echo "Archivos obtenidos: ${COUNT}"
echo "Esperados         : ${EXPECTED_FILES}"
echo

if [ "${COUNT}" -ne "${EXPECTED_FILES}" ]; then
    echo "ERROR: No se obtuvieron los ${EXPECTED_FILES} tiempos esperados."
    exit 1
fi

# ------------------------------------------------------------
# CONSTRUIR GRIB2 FINAL
# ------------------------------------------------------------

echo "Construyendo GRIB2 de 72 horas..."
echo

rm -f "${OUTPUT}"

for ((HOUR=0; HOUR<=MAX_FORECAST; HOUR+=STEP)); do

    FORECAST=$(printf "%03d" "${HOUR}")

    PART="${WORKDIR}/gfs_${FORECAST}.grib2"

    cat "${PART}" >> "${OUTPUT}"

done

# ------------------------------------------------------------
# COMPROBACIÓN FINAL
# ------------------------------------------------------------

if [ ! -s "${OUTPUT}" ]; then
    echo
    echo "ERROR: No se pudo crear el GRIB2 final."
    exit 1
fi

echo
echo "============================================================"
echo " V9 TERMINADA"
echo "============================================================"
echo
echo "Archivo final:"
echo "${OUTPUT}"
echo
ls -lh "${OUTPUT}"

echo
echo "Tamaño total de las partes:"
du -ch "${WORKDIR}"/*.grib2 | tail -1

echo
echo "============================================================"
echo " PRUEBAS"
echo "============================================================"
echo
echo "El archivo final ya está dentro del directorio"
echo "oficial de GRIB de XyGrib:"
echo
echo "  ${XYGRIB_DIR}"
echo
echo "Archivo:"
echo
echo "  ${OUTPUT}"
echo
echo
echo "Los archivos temporales permanecen en:"
echo
echo "  ${WORKDIR}"
echo
echo "============================================================"
