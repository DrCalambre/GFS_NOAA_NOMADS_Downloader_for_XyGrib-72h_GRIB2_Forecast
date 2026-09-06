# GFS NOAA NOMADS Downloader for XyGrib — 72h GRIB2 Forecast

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Bash](https://img.shields.io/badge/Bash-4.0+-green.svg)](https://www.gnu.org/software/bash/)

> **Direct download from NOAA/NOMADS of a 72-hour GRIB2 forecast, ready for XyGrib.**  
> Eliminates dependency on the OpenGribs intermediary server.

---

## 📌 Background

Since **September 2026**, the OpenGribs server that generates and serves GRIB datasets for XyGrib has been down ([issue #326](https://github.com/opengribs/XyGrib/issues/326)).

This script **downloads directly from the official source (NOAA NOMADS)** and builds a **72-hour GRIB2** that XyGrib can open without intermediaries.

✅ **No OpenGribs dependency**  
✅ **No GUI required**  
✅ **Only `curl` and Bash**  
✅ **72-hour forecast, every 3 hours**  
✅ **Includes 0°C isotherm** (validated in Río Gallegos)

---

## 🚀 Features

| Feature | Detail |
|---|---|
| **Model** | GFS 0.25° (NOAA/NCEP) |
| **Cycle** | 12 UTC (configurable) |
| **Horizon** | 0 – 72 hours |
| **Interval** | 3 hours (25 time steps) |
| **Region** | `-80°E` to `-50°E` / `-15°S` to `-58°S`<br>(Argentina, Chile, Falkland Islands, and surrounding waters) |
| **Variables** | Temperature, wind, gusts, pressure, humidity, cloud cover, precipitation, snow, CAPE, **0°C isotherm**, freezing rain, etc. |
| **Output** | Single GRIB2 in `~/.xygrib/grib/GFS_NOAA_YYYYMMDD_12Z_72hs.grib2` |
| **Temporaries** | Kept in `/tmp/gfs-v9-...` for debugging if needed |

---

## 📦 Installation

### Option 1 — Clone the repository

```bash
cd ~/bin  # or any directory in your PATH
git clone https://github.com/your-username/GFS_NOAA_NOMADS_Downloader_for_XyGrib-72h_GRIB2_Forecast
cd GFS_NOAA_NOMADS_Downloader_for_XyGrib-72h_GRIB2_Forecast
chmod +x xygrib-noaa.sh
