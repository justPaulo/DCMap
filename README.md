# DC & DR Topology (macOS, SwiftUI + SQLite)

Native macOS version of the HTML map: a world map of data centers and disaster-recovery sites with
animated replication links, backed by a local SQLite database that you manage inside the app.

**Requires:** macOS 14 (Sonoma) or later, Swift 5.9+ and the macOS SDK (available through Command Line Tools). There are no external Swift package dependencies; D3.js is vendored with its license for offline HTML export.

## Run it

* **Terminal:** `swift run -c release`
* **Double-clickable app:** `./build_app.sh`, then `open build/DCMap.app` (includes a custom globe icon)

## First use

1. `⌘O` (or toolbar *Import*) and pick `Samples/DC-Locations.xlsx` or your own `.xlsx` / `.csv`.
2. Choose *Merge* or *Replace*, keep “Look up coordinates online” ticked, press *Import*.
3. Coordinates are fetched one city at a time (≈1 per second) and the map fills in live.

Spreadsheet layout (first sheet, header row optional):

| A | B | C | D | E | F | G–J (optional) |
|---|---|---|---|---|---|---|
| DataCenter Name | Country | City | DR site | Country | City | DC lat, DC lon, DR lat, DR lon |

Columns G–J are used as-is (no lookup) when present. *Export* writes the same layout including coordinates, so an
export can be re-imported later without any online lookup.

## What's in the app

* **Map** – Natural Earth world map (Natural Earth 1:50m, embedded, works offline), countries with sites tinted,
  animated DC → DR links with direction arrows and travelling packets, pulsing site markers, dashed ring for a site that
  is its own DR, collision-free labels, hover tooltips, click to select (dims everything unrelated and zooms in),
  scroll-wheel / pinch / drag zoom and pan, *Data center* and *DR site* tick boxes, *Animate* toggle, KPI tiles,
  searchable link list, selection details and data notes. Light and dark mode follow the system.
* **Sites** – table with add / edit / delete, per-site online lookup, status badge (Online, Manual, Pending, Not found).
* **Links** – table with add / edit / delete of data center → DR relationships.
* **Export Map** – creates a single offline HTML file that follows the app's KPI/map/sidebar layout and keeps the map animations: moving replication packets, pulsing sites, animated self-DR rings, role filters, selection focus, and zoom/pan controls. The exported map can load local `.xlsx` and `.csv` files (merging their rows into the current view) and toggle its light/dark theme.
* **Menu** – Import, Export CSV, Export Interactive Map as HTML, Look Up Missing Coordinates (⌘L), Show Database in Finder, Delete All Data.

The HTML map includes the database IDs, coordinates, geocoding status, and timestamps, including sites without coordinates. D3, SheetJS, Natural Earth geometry, and the complete database snapshot are embedded, so the file and its spreadsheet loader work offline. Files loaded into the exported map are kept in memory and do not modify the app's database.

Same filtering rules as the HTML version: unticking *DR site* hides the links (a link needs both ends) and the sites
turn teal because they now only count as data centers.

## Database

`~/Library/Application Support/DCMap/dcmap.sqlite` (WAL mode, foreign keys on). Inspect it with `sqlite3` any time.

```sql
sites(id, name, country, city, latitude, longitude, geo_status, created_at, updated_at)
      -- unique on (name, city), case-insensitive; geo_status: pending | ok | manual | failed
links(id, dc_site_id → sites, dr_site_id → sites, created_at)
      -- unique pair; deleting a site cascades to its links
```

## Geocoding

Primary: OpenStreetMap Nominatim (structured `city` + `country`, then free-text). Fallback: Open-Meteo geocoding
(only accepted if the country matches). No API keys. Requests are throttled to Nominatim's 1/second policy, each city is
looked up once and shared by every site in it, and the app stops after three consecutive network failures. Sites
whose coordinates you typed by hand are never overwritten by the bulk lookup.

## Notes / limits

* Sites that share exactly the same coordinates (e.g. *Frankfurt* and *Frankfurt DR*) are drawn a few pixels apart; zoom in to separate them.
* `.xlsx` is read through the `unzip` tool that ships with macOS; `.xls` (legacy binary) is not supported — save as `.xlsx` or `.csv`.
* The app is not sandboxed (needed for the simple file dialogs and outbound network when run unsigned).
