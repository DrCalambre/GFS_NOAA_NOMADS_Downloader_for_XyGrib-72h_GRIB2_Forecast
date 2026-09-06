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
| **Region** | `-80°E` to `-50°E` / `-15°S` to `-58°S`<br>(Argentina, Chile, and surrounding waters) |
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
```

### Option 2 — Direct download

```bash
wget https://raw.githubusercontent.com/your-username/GFS_NOAA_NOMADS_Downloader_for_XyGrib-72h_GRIB2_Forecast/main/xygrib-noaa.sh
chmod +x xygrib-noaa.sh
```

### Option 3 — Manual copy

If you already have the script on your system, just make it executable:

```bash
chmod +x xygrib-noaa.sh
```

---

## ▶️ Usage

```bash
./xygrib-noaa.sh
```

### What it does

1. Downloads **25 filtered GRIB files** from NOAA NOMADS (`f000`, `f003`, ... `f072`).
2. Waits **8 seconds** between requests (respecting NOAA's recommendation).
3. Concatenates the files into a **single GRIB2**.
4. Saves it to `~/.xygrib/grib/GFS_NOAA_YYYYMMDD_12Z_72hs.grib2`.
5. Displays size and location information.

### Example output

```text
============================================================
 GFS NOAA NOMADS - V9
 72-hour forecast for XyGrib
============================================================

Date        : 20260906
Cycle       : 12Z
Horizon     : f000 → f072
Interval    : 3 hours
Time steps  : 25

...
OK → F000 (187K)
OK → F003 (192K)
...
Final file:
/home/user/.xygrib/grib/GFS_NOAA_20260906_12Z_72hs.grib2
```

---

## ⚙️ Advanced configuration

You can edit the script to adjust these parameters:

| Variable | Description | Default |
|---|---|---|
| `CYCLE` | GFS cycle (`00`, `06`, `12`, `18`) | `12` |
| `MAX_FORECAST` | Forecast horizon in hours | `72` |
| `STEP` | Interval in hours | `3` |
| `PAUSE` | Pause between downloads (seconds) | `8` |

---

## 🗺️ Adjusting the geographic area

The script downloads a GRIB2 file for a specific region. By default, it covers:

```
West:  -80°  →  East:  -50°
North: -15°  →  South: -58°
```

This area includes the southern cone of South America and surrounding waters.

### How to change the region

Edit the script and modify these variables:

```bash
WEST="-80"      # Longitude limit (west)
EAST="-50"      # Longitude limit (east)
NORTH="-15"     # Latitude limit (north)
SOUTH="-58"     # Latitude limit (south)
```

**Important:** Longitudes are negative for the Western Hemisphere. Latitudes are negative for the Southern Hemisphere.

---

### Examples

#### 1. Focus on Patagonia

```bash
WEST="-75"
EAST="-65"
NORTH="-40"
SOUTH="-56"
```

#### 2. Cover all of South America

```bash
WEST="-85"
EAST="-35"
NORTH="10"
SOUTH="-60"
```

#### 3. Focus on a specific coastal area

```bash
WEST="-72"
EAST="-62"
NORTH="-35"
SOUTH="-50"
```

---

### How to find the right coordinates

You can get coordinates from:

- **Google Maps** → Right-click → "What's here?"
- **OpenStreetMap** → Click on a location → shows coordinates
- **GPS tools** → Any tool that shows latitude/longitude

**Remember:**
- Longitude: West = negative, East = positive
- Latitude: South = negative, North = positive

---

### Verify the region

After downloading, you can check the actual region with:

```bash
cdo sinfo ~/.xygrib/grib/GFS_NOAA_*.grib2
```

Look for the `Grid coordinates` section:

```text
lon : 280 to 310 by 0.25 degrees_east
lat : -58 to -15 by 0.25 degrees_north
```

This confirms the longitude and latitude limits of your downloaded GRIB.

---

## 🧪 Validation

The script was tested on **XyGrib 1.2.6 / antiX Linux 26** with the following verified parameters:

| XyGrib Parameter | Value in Río Gallegos |
|---|---|
| Temperature (2 m) | 7.0 °C |
| Wind (10 m) | 251° / 32.1 km/h |
| Wind gusts | 39.4 km/h |
| CAPE | 0 J/kg |
| Relative humidity | 59 % |
| Dew point | -0.5 °C |
| Cloud cover | 4.3 % |
| Precipitation | 0.00 mm/h |
| Snow possible | 0 |
| Freezing rain | 0 |
| Snow depth | 0.0 cm |
| **0°C isotherm** | **1147 m** ✅ |

---

## 🗂️ File structure

### Temporary (during download)

```text
/tmp/gfs-v9-YYYYMMDD-12Z/
├── gfs_000.grib2
├── gfs_003.grib2
├── gfs_006.grib2
...
└── gfs_072.grib2
```

### Final (permanent)

```text
~/.xygrib/grib/
└── GFS_NOAA_YYYYMMDD_12Z_72hs.grib2
```

---

## ⚠️ Important notes

1. **Pause between requests:** NOAA recommends spacing requests to avoid overloading NOMADS. The script waits 8 seconds between each download.
2. **Download failures:** If any individual file fails, the script stops and shows which `fXXX` failed.
3. **Temporary files:** They are kept in `/tmp/gfs-v9-...` for debugging if needed.
4. **CDO compatibility:** If you run `cdo showname` and get `Unsupported file structure`, **don't worry** — XyGrib can still open the file. This happens with some GRIB structures that CDO can't interpret but XyGrib handles fine.

---

## 🔧 Requirements

- `curl` (installed by default on most systems)
- Bash 4.0+
- Internet access to reach `nomads.ncep.noaa.gov`

If `curl` is not installed:

```bash
# Debian/Ubuntu/MX Linux/antiX
sudo apt install curl

# Fedora
sudo dnf install curl

# Arch
sudo pacman -S curl
```

---

## 🐛 Troubleshooting

### Error: `curl: (22) The requested URL returned error: 500`

- Verify that the UTC date is correct (`date -u +%Y%m%d`).
- Check that the chosen cycle (`CYCLE`) is available on NOAA for that date.
- Try switching to another cycle (e.g., `00` or `06`).

### XyGrib doesn't show the 0°C isotherm

- Make sure the file was generated with **V9** or later (includes `lev_0C_isotherm`).
- Verify that the `HGT` variable at the `0C isotherm` level is included in the URL.

### The final file doesn't appear in XyGrib

- Confirm that the `~/.xygrib/grib` directory exists.
- XyGrib may need to be restarted to see new files in that folder.
- You can also open the file manually from **XyGrib → File → Open GRIB...**

---

## 🤝 Contributing

If you find an issue, have an improvement, or want to add support for other models (DWD ICON, etc.), please open an **issue** or **pull request**.

---

## 📄 License

**MIT** — free use, no warranty.

---

## 🌐 Useful links

- [NOAA NOMADS GRIB Filter](https://nomads.ncep.noaa.gov/gribfilter.php?ds=gfs_0p25)
- [XyGrib — GitHub](https://github.com/opengribs/XyGrib)
- [OpenGribs issue #326 — GRIB server down](https://github.com/opengribs/XyGrib/issues/326)
- [GFS 0.25° documentation](https://www.nco.ncep.noaa.gov/pmb/products/gfs/)

---

## 🧠 Credits

Developed from tests conducted with **XyGrib 1.2.6** on **antiX Linux 26**.

Thanks to the XyGrib community and NOAA/NCEP for keeping the data open.

---

**Fair winds!** 🌬️
