import Foundation

enum HTMLExportError: LocalizedError {
    case missingResource(String)

    var errorDescription: String? {
        switch self {
        case .missingResource(let name): return "The bundled \(name) resource is missing."
        }
    }
}

enum HTMLExporter {
    static func write(snapshot: Repository.ExportSnapshot, to url: URL) throws {
        let html = try render(snapshot: snapshot, worldData: WorldData.json)
        try html.write(to: url, atomically: true, encoding: .utf8)
    }

    static func render(snapshot: Repository.ExportSnapshot, worldData: String) throws -> String {
        guard let d3URL = Bundle.module.url(forResource: "d3.v7.min", withExtension: "js") else {
            throw HTMLExportError.missingResource("D3.js")
        }
        guard let licenseURL = Bundle.module.url(forResource: "D3-LICENSE", withExtension: "txt") else {
            throw HTMLExportError.missingResource("D3.js license")
        }

        let d3 = try String(contentsOf: d3URL, encoding: .utf8)
        let license = try String(contentsOf: licenseURL, encoding: .utf8)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let snapshotJSON = try encoder.encode(snapshot)
        guard let snapshotText = String(data: snapshotJSON, encoding: .utf8) else {
            throw CocoaError(.fileReadInapplicableStringEncoding)
        }

        return #"""
        <!doctype html>
        <html lang="en">
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width, initial-scale=1">
          <title>DC &amp; DR Topology — Interactive Map</title>
          <script>
            (() => {
              const param = new URLSearchParams(window.location.search).get("scoutTheme");
              const theme =
                param || (window.matchMedia("(prefers-color-scheme: dark)").matches ? "dark" : "light");
              document.documentElement.setAttribute("data-theme", theme);
            })();
          </script>
          <style>
            :root {
              color-scheme: light;
              --cp-bg: #f7f4ef;
              --cp-bg-elevated: #fcfbf8;
              --cp-surface: #ffffff;
              --cp-surface-soft: #f5f5f5;
              --cp-border: #dedede;
              --cp-border-strong: #919191;
              --cp-text: #242424;
              --cp-text-muted: #5c5c5c;
              --cp-text-soft: #6f6f6f;
              --cp-accent: #b11f4b;
              --cp-accent-hover: #9a1a41;
              --cp-accent-soft: rgba(177, 31, 75, 0.08);
              --cp-accent-fg: #ffffff;
              --cp-success: #16a34a;
              --cp-danger: #dc2626;
              --cp-warning: #f59e0b;
              --cp-link: #0078d4;
              --cp-shadow: 0 18px 48px rgba(0, 0, 0, 0.12);
              --cp-overlay: rgba(255, 255, 255, 0.8);
              --cp-panel: rgba(255, 255, 255, 0.86);
              --cp-panel-strong: rgba(255, 255, 255, 0.96);
              --cp-sheen: rgba(255, 255, 255, 0.55);
              --cp-highlight: rgba(177, 31, 75, 0.12);
              --cp-map-ocean: #e4ecf4;
              --cp-map-land: #f8fafc;
              --cp-map-land-stroke: #c3cfdc;
              --cp-map-has-site: #bcd6ee;
              --cp-map-graticule: #d7e2ed;
              --cp-map-dc: #0f9e86;
              --cp-map-dr: #d9820b;
              --cp-map-both: #3a6fe0;
              --cp-map-link: #3a6fe0;
              --cp-map-warning: #c93a3a;
              --cp-map-unlinked: var(--cp-text-soft);
            }
            html[data-theme="dark"] {
              color-scheme: dark;
              --cp-bg: #3d3b3a;
              --cp-bg-elevated: #343231;
              --cp-surface: #292929;
              --cp-surface-soft: #2e2e2e;
              --cp-border: #474747;
              --cp-border-strong: #5f5f5f;
              --cp-text: #dedede;
              --cp-text-muted: #919191;
              --cp-text-soft: #b0b0b0;
              --cp-accent: #fd8ea1;
              --cp-accent-hover: #fb7b91;
              --cp-accent-soft: rgba(253, 142, 161, 0.14);
              --cp-accent-fg: #1a1a1a;
              --cp-success: #4ade80;
              --cp-danger: #f87171;
              --cp-warning: #fbbf24;
              --cp-link: #4da6ff;
              --cp-shadow: 0 18px 48px rgba(0, 0, 0, 0.32);
              --cp-overlay: rgba(41, 41, 41, 0.88);
              --cp-panel: rgba(41, 41, 41, 0.72);
              --cp-panel-strong: rgba(41, 41, 41, 0.96);
              --cp-sheen: rgba(255, 255, 255, 0.04);
              --cp-highlight: rgba(253, 142, 161, 0.12);
              --cp-map-ocean: #0c1117;
              --cp-map-land: #1a2431;
              --cp-map-land-stroke: #2a3748;
              --cp-map-has-site: #23415a;
              --cp-map-graticule: #141d28;
              --cp-map-dc: #2fd4b5;
              --cp-map-dr: #ffb347;
              --cp-map-both: #7aa7ff;
              --cp-map-link: #7aa7ff;
              --cp-map-warning: #ff7a7a;
              --cp-map-unlinked: var(--cp-text-soft);
            }
            * { box-sizing: border-box; }
            body {
              margin: 0;
              background: var(--cp-bg);
              color: var(--cp-text);
              font-family: "Segoe UI", Aptos, Calibri, -apple-system, BlinkMacSystemFont, sans-serif;
            }
            button, input { font: inherit; }
            button {
              color: var(--cp-text);
              background: var(--cp-surface);
              border: 1px solid var(--cp-border);
              border-radius: 0.625rem;
              padding: 0.5rem 0.75rem;
              cursor: pointer;
            }
            button:hover { border-color: var(--cp-accent); }
            button:focus-visible, input:focus-visible {
              outline: 2px solid var(--cp-accent);
              outline-offset: 2px;
            }
            .topbar {
              display: flex;
              align-items: center;
              justify-content: space-between;
              gap: 1rem;
              padding: 1.25rem 1.5rem;
              border-bottom: 1px solid var(--cp-border);
              background: var(--cp-bg-elevated);
            }
            h1, h2, h3, p { margin: 0; }
            h1 { font-size: 1.35rem; }
            h2 { font-size: 1rem; }
            h3 { font-size: 0.95rem; }
            .subtitle, .muted { color: var(--cp-text-muted); }
            .subtitle { margin-top: 0.25rem; font-size: 0.85rem; }
            .stats { display: flex; flex-wrap: wrap; gap: 0.5rem; justify-content: flex-end; }
            .stat {
              min-width: 7rem;
              padding: 0.55rem 0.75rem;
              border: 1px solid var(--cp-border);
              border-radius: 0.625rem;
              background: var(--cp-surface);
              text-align: center;
            }
            .stat strong { display: block; font-size: 1.05rem; }
            .stat span { color: var(--cp-text-muted); font-size: 0.72rem; }
            .stat small { display: block; margin-top: 0.12rem; color: var(--cp-text-soft); font-size: 0.65rem; }
            main {
              display: grid;
              grid-template-columns: minmax(0, 1fr) minmax(18rem, 23rem);
              gap: 1rem;
              padding: 1rem;
              align-items: start;
            }
            .card {
              min-width: 0;
              border: 1px solid var(--cp-border);
              border-radius: 16px;
              background: var(--cp-surface);
              box-shadow: var(--cp-shadow);
            }
            .map-card { overflow: hidden; }
            .card-heading, .map-controls, .card-body { padding: 0.9rem 1rem; }
            .card-heading {
              display: flex;
              align-items: center;
              justify-content: space-between;
              gap: 0.75rem;
              border-bottom: 1px solid var(--cp-border);
            }
            .map-stage { position: relative; }
            .map-controls {
              position: absolute;
              z-index: 1;
              left: 0.75rem;
              bottom: 0.75rem;
              display: flex;
              flex-direction: column;
              align-items: flex-start;
              gap: 0.45rem;
              padding: 0.65rem 0.75rem;
              border: 1px solid var(--cp-border);
              border-radius: 0.625rem;
              background: var(--cp-panel-strong);
              box-shadow: var(--cp-shadow);
            }
            .map-controls label { display: inline-flex; align-items: center; gap: 0.4rem; }
            input[type="checkbox"] { accent-color: var(--cp-accent); }
            .map-actions {
              position: absolute;
              z-index: 1;
              top: 0.75rem;
              right: 0.75rem;
              display: grid;
              gap: 0.35rem;
            }
            .map-actions button { min-width: 2.4rem; min-height: 2.4rem; padding: 0.35rem; font-size: 0.85rem; }
            .map-status {
              position: absolute;
              right: 0.75rem;
              bottom: 0.75rem;
              padding: 0.4rem 0.6rem;
              border: 1px solid var(--cp-border);
              border-radius: 0.625rem;
              background: var(--cp-panel-strong);
              color: var(--cp-text-muted);
              font-size: 0.72rem;
              pointer-events: none;
            }
            #map {
              display: block;
              width: 100%;
              height: auto;
              aspect-ratio: 1200 / 650;
              min-height: 25rem;
              background: var(--cp-map-ocean);
              cursor: grab;
              touch-action: none;
            }
            #map:active { cursor: grabbing; }
            .land {
              fill: var(--cp-map-land);
              stroke: var(--cp-map-land-stroke);
              stroke-width: 0.55;
              vector-effect: non-scaling-stroke;
            }
            .land.has-site { fill: var(--cp-map-has-site); }
            .graticule {
              fill: none;
              stroke: var(--cp-map-graticule);
              stroke-width: 0.55;
              vector-effect: non-scaling-stroke;
            }
            .replication-link {
              fill: none;
              stroke: var(--cp-map-link);
              stroke-width: 2;
              stroke-dasharray: 6 6;
              opacity: 1;
              cursor: pointer;
              vector-effect: non-scaling-stroke;
            }
            .replication-link:hover, .replication-link.selected {
              stroke-width: 3.2;
              opacity: 1;
            }
            .replication-link.dimmed { opacity: 0.12; }
            .route-arrow { fill: var(--cp-map-link); stroke: none; pointer-events: none; }
            .packet { fill: var(--cp-map-link); stroke: none; pointer-events: none; }
            .site-pulse {
              fill: none;
              stroke-width: 1.5;
              pointer-events: none;
            }
            .site-marker { stroke: var(--cp-surface); stroke-width: 1.6; cursor: pointer; }
            .site-marker.dc { fill: var(--cp-map-dc); }
            .site-marker.dr { fill: var(--cp-map-dr); }
            .site-marker.both { fill: var(--cp-map-both); }
            .site-marker.unlinked { fill: var(--cp-text-soft); }
            .site-marker.selected { stroke: var(--cp-text); stroke-width: 3; }
            .site-marker.dimmed { opacity: 0.12; }
            .self-ring {
              fill: none;
              stroke: var(--cp-map-warning);
              stroke-width: 1.6;
              stroke-dasharray: 3 3;
              vector-effect: non-scaling-stroke;
              cursor: pointer;
            }
            .self-ring.selected { stroke-width: 2.6; }
            .self-ring.dimmed { opacity: 0.12; }
            .legend { display: flex; flex-wrap: wrap; gap: 0.8rem; color: var(--cp-text-muted); font-size: 0.8rem; }
            .legend-item { display: inline-flex; align-items: center; gap: 0.35rem; }
            .swatch { width: 0.7rem; height: 0.7rem; border-radius: 50%; }
            .swatch.dc { background: var(--cp-map-dc); }
            .swatch.dr { background: var(--cp-map-dr); }
            .swatch.both { background: var(--cp-map-both); }
            .swatch.link { width: 1.1rem; height: 0; border-top: 2px dashed var(--cp-map-link); border-radius: 0; }
            .site-label {
              fill: var(--cp-text);
              stroke: var(--cp-map-ocean);
              stroke-width: 3px;
              stroke-linejoin: round;
              paint-order: stroke;
              font-size: 12px;
              font-weight: 600;
              pointer-events: none;
            }
            aside { display: grid; gap: 1rem; }
            .card-body { display: grid; gap: 0.75rem; }
            .card-body input[type="search"] {
              width: 100%;
              padding: 0.6rem 0.7rem;
              color: var(--cp-text);
              border: 1px solid var(--cp-border);
              border-radius: 0.625rem;
              background: var(--cp-bg-elevated);
            }
            .selection {
              min-height: 3rem;
              color: var(--cp-text-muted);
              font-size: 0.85rem;
              overflow-wrap: anywhere;
            }
            .selection h3 { color: var(--cp-text); margin-bottom: 0.45rem; }
            .detail-row { display: grid; grid-template-columns: 6.5rem minmax(0, 1fr); gap: 0.45rem; margin-top: 0.25rem; }
            .detail-row span:first-child { color: var(--cp-text-muted); }
            .scroll-list { display: grid; gap: 0.35rem; max-height: 18rem; overflow: auto; }
            .list-button {
              display: block;
              width: 100%;
              padding: 0.6rem;
              text-align: left;
            }
            .list-button.active { border-color: var(--cp-accent); background: var(--cp-accent-soft); }
            .list-button.related { border-color: var(--cp-border-strong); }
            .list-button small { display: block; margin-top: 0.2rem; color: var(--cp-text-muted); }
            .empty { color: var(--cp-text-muted); font-size: 0.85rem; }
            details { margin: 0 1rem 1rem; border-top: 1px solid var(--cp-border); padding-top: 0.75rem; }
            summary { cursor: pointer; color: var(--cp-text-muted); }
            pre {
              max-height: 24rem;
              overflow: auto;
              padding: 0.75rem;
              border: 1px solid var(--cp-border);
              border-radius: 0.625rem;
              background: var(--cp-bg-elevated);
              color: var(--cp-text-soft);
              font: 0.75rem Consolas, "Courier New", Courier, monospace;
            }
            footer { padding: 0 1rem 1rem; color: var(--cp-text-muted); font-size: 0.75rem; }
            footer details { margin: 0.5rem 0 0; }
            @media (max-width: 900px) {
              .topbar { align-items: flex-start; flex-direction: column; }
              .stats { justify-content: flex-start; }
              main { grid-template-columns: minmax(0, 1fr); }
              #map { min-height: 0; }
              .map-controls { left: 0.5rem; bottom: 0.5rem; }
              .map-actions { top: 0.5rem; right: 0.5rem; }
              .map-status { right: 0.5rem; bottom: 0.5rem; }
            }
          </style>
        </head>
        <body>
          <header class="topbar">
            <div>
              <h1>DC &amp; DR Topology</h1>
              <p class="subtitle" id="exported-at"></p>
            </div>
            <div class="stats" id="stats" aria-label="Database totals"></div>
          </header>
          <main>
            <section class="card map-card" aria-label="Interactive world map">
              <div class="card-heading">
                <h2>Global topology</h2>
                <div class="legend" aria-label="Map legend">
                  <span class="legend-item"><i class="swatch dc"></i>Data center</span>
                  <span class="legend-item"><i class="swatch dr"></i>DR site</span>
                  <span class="legend-item"><i class="swatch both"></i>Both roles</span>
                  <span class="legend-item"><i class="swatch link"></i>Replication</span>
                </div>
              </div>
              <div class="map-stage">
                <svg id="map" viewBox="0 0 1200 650" role="img" aria-label="World map with animated data center and disaster recovery links"></svg>
                <div class="map-actions" aria-label="Map navigation">
                  <button id="zoom-in" type="button" aria-label="Zoom in" title="Zoom in">+</button>
                  <button id="zoom-out" type="button" aria-label="Zoom out" title="Zoom out">-</button>
                  <button id="fit-sites" type="button" aria-label="Fit to sites" title="Fit to sites">Fit</button>
                  <button id="reset-map" type="button" aria-label="World view" title="World view">World</button>
                </div>
                <div class="map-controls" aria-label="Map filters">
                  <label><input id="show-dc" type="checkbox" checked><i class="swatch dc"></i>Data center</label>
                  <label><input id="show-dr" type="checkbox" checked><i class="swatch dr"></i>DR site</label>
                  <label><input id="animate-map" type="checkbox" checked>Animate</label>
                </div>
                <div class="map-status" id="map-count" aria-live="polite"></div>
              </div>
              <details>
                <summary>Embedded database snapshot (JSON)</summary>
                <pre id="raw-snapshot"></pre>
              </details>
            </section>
            <aside>
              <section class="card">
                <div class="card-heading"><h2>Replication links</h2><span class="muted" id="link-count"></span></div>
                <div class="card-body">
                  <input id="search" type="search" placeholder="Filter sites, cities, countries…" aria-label="Filter links and sites">
                  <div class="scroll-list" id="link-list"></div>
                </div>
              </section>
              <section class="card">
                <div class="card-heading"><h2>Selection</h2></div>
                <div class="card-body"><div class="selection" id="selection">Select a site or link on the map, or choose a link above.</div></div>
              </section>
              <section class="card">
                <div class="card-heading"><h2>Sites without coordinates</h2><span class="muted" id="unmapped-count"></span></div>
                <div class="card-body"><div class="scroll-list" id="unmapped-list"></div></div>
              </section>
            </aside>
          </main>
          <footer>
            Offline export. Natural Earth 1:50m map geometry and the complete database snapshot are embedded in this file.
            <details>
              <summary>D3.js v7.9.2 license</summary>
              <pre>\#(escapeHTML(license))</pre>
            </details>
          </footer>
          <script type="application/json" id="database-data">\#(safeJSON(snapshotText))</script>
          <script type="application/json" id="world-data">\#(safeJSON(worldData))</script>
          <script>
          \#(d3)
          </script>
          <script>
            (() => {
              const database = JSON.parse(document.getElementById("database-data").textContent);
              const rawWorld = JSON.parse(document.getElementById("world-data").textContent);
              const sitesByID = new Map(database.sites.map(site => [site.id, site]));
              const roles = new Map(database.sites.map(site => [site.id, { dc: false, dr: false }]));
              for (const link of database.links) {
                if (roles.has(link.dc_site_id)) roles.get(link.dc_site_id).dc = true;
                if (roles.has(link.dr_site_id)) roles.get(link.dr_site_id).dr = true;
              }

              const isMapped = site =>
                Number.isFinite(site.latitude) && Number.isFinite(site.longitude) &&
                site.latitude >= -90 && site.latitude <= 90 &&
                site.longitude >= -180 && site.longitude <= 180;
              const mappedSites = database.sites.filter(isMapped);
              const unmappedSites = database.sites.filter(site => !isMapped(site));
              const featureCollection = {
                type: "FeatureCollection",
                features: rawWorld.map(country => ({
                  type: "Feature",
                  properties: { name: country.n },
                  geometry: {
                    type: "MultiPolygon",
                    coordinates: country.p.map(polygon => polygon.map(ring => {
                      const coordinates = [];
                      for (let i = 0; i + 1 < ring.length; i += 2) coordinates.push([ring[i], ring[i + 1]]);
                      return coordinates;
                    }))
                  }
                }))
              };

              const width = 1200;
              const height = 650;
              const projection = d3.geoNaturalEarth1().fitExtent([[20, 18], [width - 20, height - 18]], featureCollection);
              const geoPath = d3.geoPath(projection);
              const svg = d3.select("#map");
              const root = svg.append("g");
              root.append("path").datum(d3.geoGraticule10()).attr("class", "graticule").attr("d", geoPath);
              const normalized = value => String(value || "").normalize("NFD")
                .replace(/[\u0300-\u036f]/g, "").trim().toLocaleLowerCase();
              const countryAliases = new Map([
                ["united states", "united states of america"], ["usa", "united states of america"],
                ["us", "united states of america"], ["u.s.", "united states of america"],
                ["u.s.a.", "united states of america"], ["america", "united states of america"],
                ["uk", "united kingdom"], ["great britain", "united kingdom"],
                ["england", "united kingdom"], ["scotland", "united kingdom"], ["wales", "united kingdom"],
                ["czech republic", "czechia"], ["holland", "netherlands"], ["the netherlands", "netherlands"],
                ["russian federation", "russia"], ["korea, republic of", "south korea"],
                ["republic of korea", "south korea"], ["korea", "south korea"],
                ["uae", "united arab emirates"], ["turkiye", "turkey"],
                ["democratic republic of the congo", "dem. rep. congo"], ["drc", "dem. rep. congo"],
                ["ivory coast", "cote d'ivoire"], ["bosnia and herzegovina", "bosnia and herz."],
                ["dominican republic", "dominican rep."], ["central african republic", "central african rep."],
                ["south sudan", "s. sudan"], ["equatorial guinea", "eq. guinea"],
                ["swaziland", "eswatini"], ["macedonia", "north macedonia"],
                ["vietnam", "vietnam"], ["viet nam", "vietnam"]
              ]);
              const sitesByCountry = new Set(database.sites.map(site =>
                countryAliases.get(normalized(site.country)) || normalized(site.country)
              ).filter(Boolean));
              root.append("g").selectAll("path")
                .data(featureCollection.features)
                .join("path")
                .attr("class", feature => {
                  const country = normalized(feature.properties.name);
                  const hasNamedSite = sitesByCountry.has(country);
                  const hasLocatedSite = mappedSites.some(site =>
                    d3.geoContains(feature, [site.longitude, site.latitude])
                  );
                  return `land${hasNamedSite || hasLocatedSite ? " has-site" : ""}`;
                })
                .attr("d", geoPath)
                .append("title")
                .text(feature => feature.properties.name);

              const linksLayer = root.append("g");
              const selfLayer = root.append("g");
              const pulsesLayer = root.append("g");
              const sitesLayer = root.append("g");
              const labelsLayer = root.append("g");
              const sitePosition = new Map(mappedSites.map(site => [site.id, projection([site.longitude, site.latitude])]));
              const positionsByCoordinate = new Map();
              for (const site of mappedSites) {
                const key = `${site.latitude},${site.longitude}`;
                const group = positionsByCoordinate.get(key) || [];
                group.push(site.id);
                positionsByCoordinate.set(key, group);
              }
              for (const ids of positionsByCoordinate.values()) {
                if (ids.length < 2) continue;
                ids.forEach((id, index) => {
                  const angle = -Math.PI / 2 + index * 2 * Math.PI / ids.length;
                  const point = sitePosition.get(id);
                  sitePosition.set(id, [point[0] + Math.cos(angle) * 5, point[1] + Math.sin(angle) * 5]);
                });
              }
              const routeRows = database.links.map((link, index) => ({
                link,
                source: sitesByID.get(link.dc_site_id),
                target: sitesByID.get(link.dr_site_id),
                index
              }));
              const routePoints = (row) => {
                const p0 = sitePosition.get(row.source.id);
                const p1 = sitePosition.get(row.target.id);
                const dx = p1[0] - p0[0];
                const dy = p1[1] - p0[1];
                return {
                  p0,
                  c: [(p0[0] + p1[0]) / 2 - dy * 0.22, (p0[1] + p1[1]) / 2 + dx * 0.22],
                  p1
                };
              };
              const routeArrowTransform = row => {
                const { p0, p1 } = routePoints(row);
                const midX = (p0[0] + p1[0]) / 2;
                const midY = (p0[1] + p1[1]) / 2;
                const angle = Math.atan2(p1[1] - p0[1], p1[0] - p0[0]) * 180 / Math.PI;
                return `translate(${midX},${midY}) rotate(${angle}) scale(${1 / currentScale})`;
              };

              let selected = null;
              let currentScale = 1;
              let animationFrame = null;
              let lastAnimationFrame = 0;
              const selection = document.getElementById("selection");
              const search = document.getElementById("search");
              const showDC = document.getElementById("show-dc");
              const showDR = document.getElementById("show-dr");
              const animateMap = document.getElementById("animate-map");

              function appendDetail(label, value) {
                const row = document.createElement("div");
                row.className = "detail-row";
                const key = document.createElement("span");
                key.textContent = label;
                const text = document.createElement("span");
                text.textContent = value == null || value === "" ? "—" : String(value);
                row.append(key, text);
                selection.append(row);
              }

              function showSite(site) {
                selected = { type: "site", id: site.id };
                selection.replaceChildren();
                const heading = document.createElement("h3");
                heading.textContent = site.name;
                selection.append(heading);
                appendDetail("Location", [site.city, site.country].filter(Boolean).join(", "));
                appendDetail("Role", roleName(site.id));
                appendDetail("Coordinates", isMapped(site) ? `${site.latitude}, ${site.longitude}` : "Not available");
                appendDetail("Geocoding", site.geo_status);
                appendDetail("Created", site.created_at);
                appendDetail("Updated", site.updated_at);
                updateMap();
                renderLists();
                if (sitePosition.has(site.id)) focusSites([site.id], 6);
              }

              function showLink(link) {
                selected = { type: "link", id: link.id };
                const source = sitesByID.get(link.dc_site_id);
                const target = sitesByID.get(link.dr_site_id);
                selection.replaceChildren();
                const heading = document.createElement("h3");
                heading.textContent = source && target ? `${source.name} → ${target.name}` : `Link ${link.id}`;
                selection.append(heading);
                appendDetail("Data center", source ? siteLocation(source) : link.dc_site_id);
                appendDetail("DR site", target ? siteLocation(target) : link.dr_site_id);
                appendDetail("Map", source && target && isMapped(source) && isMapped(target) ? "Plotted" : "Missing coordinates");
                appendDetail("Created", link.created_at);
                updateMap();
                renderLists();
                focusSites([link.dc_site_id, link.dr_site_id], 30);
              }

              function roleName(siteID) {
                const role = roles.get(siteID) || { dc: false, dr: false };
                if (role.dc && role.dr) return "Data center + DR";
                if (role.dc) return "Data center";
                if (role.dr) return "DR site";
                return "Unlinked";
              }

              function roleClass(siteID) {
                const role = roles.get(siteID) || { dc: false, dr: false };
                const dc = role.dc && showDC.checked;
                const dr = role.dr && showDR.checked;
                if (dc && dr) return "both";
                if (dc) return "dc";
                if (dr) return "dr";
                return "unlinked";
              }

              function siteLocation(site) {
                return [site.city, site.country].filter(Boolean).join(", ") || site.name;
              }

              function relatedItems() {
                if (!selected) return null;
                const siteIDs = new Set();
                const linkIDs = new Set();
                if (selected.type === "site") {
                  siteIDs.add(selected.id);
                  for (const link of database.links) {
                    if (link.dc_site_id === selected.id || link.dr_site_id === selected.id) {
                      linkIDs.add(link.id);
                      siteIDs.add(link.dc_site_id);
                      siteIDs.add(link.dr_site_id);
                    }
                  }
                } else {
                  const link = database.links.find(item => item.id === selected.id);
                  if (link) {
                    linkIDs.add(link.id);
                    siteIDs.add(link.dc_site_id);
                    siteIDs.add(link.dr_site_id);
                  }
                }
                return { siteIDs, linkIDs };
              }

              function visibleSite(site) {
                const role = roles.get(site.id) || { dc: false, dr: false };
                return (!role.dc && !role.dr) || (showDC.checked && role.dc) || (showDR.checked && role.dr);
              }

              function focusSites(ids, maxScale) {
                const points = ids.map(id => sitePosition.get(id)).filter(Boolean);
                if (!points.length) return;
                const x0 = d3.min(points, point => point[0]);
                const x1 = d3.max(points, point => point[0]);
                const y0 = d3.min(points, point => point[1]);
                const y1 = d3.max(points, point => point[1]);
                const span = Math.max((x1 - x0) / width, (y1 - y0) / height, 0.03);
                const scale = Math.max(1, Math.min(maxScale, 0.7 / span));
                const centerX = (x0 + x1) / 2;
                const centerY = (y0 + y1) / 2;
                const transform = d3.zoomIdentity
                  .translate(width / 2 - centerX * scale, height / 2 - centerY * scale)
                  .scale(scale);
                svg.transition().duration(650).ease(d3.easeCubicInOut).call(zoom.transform, transform);
              }

              function updateMap() {
                const visibleRoutes = showDC.checked && showDR.checked
                  ? routeRows.filter(row => row.source && row.target && isMapped(row.source) && isMapped(row.target))
                  : [];
                const related = relatedItems();
                const regularRoutes = visibleRoutes.filter(row => row.link.dc_site_id !== row.link.dr_site_id);
                const linkSelection = linksLayer.selectAll("g.replication-link")
                  .data(regularRoutes, row => row.link.id)
                  .join(
                    enter => {
                      const group = enter.append("g")
                        .attr("class", "replication-link")
                        .on("click", (event, row) => { event.stopPropagation(); showLink(row.link); });
                      group.append("path").attr("class", "route-path");
                      group.append("path").attr("class", "route-arrow").attr("d", "M5,0L-4,4L-4,-4Z");
                      group.append("title");
                      group.append("g").attr("class", "packets")
                        .selectAll("circle").data([0, 1, 2, 3]).join("circle").attr("class", "packet");
                      return group;
                    }
                  )
                  .attr("class", row => {
                    const isSelected = selected?.type === "link" && selected.id === row.link.id;
                    const dimmed = related && !related.linkIDs.has(row.link.id);
                    return `replication-link${isSelected ? " selected" : ""}${dimmed ? " dimmed" : ""}`;
                  });
                linkSelection.select("path.route-path").attr("d", row => {
                  const points = routePoints(row);
                  return `M${points.p0[0]},${points.p0[1]}Q${points.c[0]},${points.c[1]} ${points.p1[0]},${points.p1[1]}`;
                });
                linkSelection.select("path.route-arrow").attr("transform", routeArrowTransform);
                linkSelection.select("title").text(row =>
                  `${row.source.name} → ${row.target.name} · ${siteLocation(row.source)} → ${siteLocation(row.target)}`
                );

                const selfLinks = visibleRoutes.filter(row => row.link.dc_site_id === row.link.dr_site_id);
                const selfRings = selfLayer.selectAll("circle.self-ring")
                  .data(selfLinks, row => row.link.id)
                  .join(enter => {
                    const ring = enter.append("circle").attr("class", "self-ring");
                    ring.append("title");
                    return ring;
                  })
                  .attr("class", row => {
                    const isSelected = selected?.type === "link" && selected.id === row.link.id;
                    const dimmed = related && !related.linkIDs.has(row.link.id);
                    return `self-ring${isSelected ? " selected" : ""}${dimmed ? " dimmed" : ""}`;
                  })
                  .attr("cx", row => sitePosition.get(row.source.id)[0])
                  .attr("cy", row => sitePosition.get(row.source.id)[1])
                  .on("click", (event, row) => { event.stopPropagation(); showLink(row.link); });
                selfRings.select("title").text(row => `${row.source.name} local DR`);

                const visibleSites = mappedSites.filter(visibleSite);
                const visibleRelatedSites = visibleSites.filter(site => !related || related.siteIDs.has(site.id));
                const pulses = pulsesLayer.selectAll("circle.site-pulse")
                  .data(visibleRelatedSites, site => site.id)
                  .join("circle")
                  .attr("class", "site-pulse")
                  .attr("cx", site => sitePosition.get(site.id)[0])
                  .attr("cy", site => sitePosition.get(site.id)[1])
                  .attr("stroke", site => `var(--cp-map-${roleClass(site.id)})`);
                const markers = sitesLayer.selectAll("circle.site-marker")
                  .data(visibleSites, site => site.id)
                  .join(
                    enter => {
                      const marker = enter.append("circle")
                        .attr("class", "site-marker")
                        .on("click", (event, site) => { event.stopPropagation(); showSite(site); });
                      marker.append("title");
                      return marker;
                    }
                  )
                  .attr("r", 6 / currentScale)
                  .attr("class", site => {
                    const isSelected = selected?.type === "site" && selected.id === site.id;
                    const dimmed = related && !related.siteIDs.has(site.id);
                    return `site-marker ${roleClass(site.id)}${isSelected ? " selected" : ""}${dimmed ? " dimmed" : ""}`;
                  })
                  .attr("cx", site => sitePosition.get(site.id)[0])
                  .attr("cy", site => sitePosition.get(site.id)[1]);
                markers.select("title").text(site =>
                  `${site.name} · ${siteLocation(site)} · ${roleName(site.id)}`
                );
                renderLabels(related ? visibleRelatedSites : []);
                document.getElementById("map-count").textContent =
                  `${visibleSites.length} of ${mappedSites.length} mapped sites · ${visibleRoutes.length} plotted links`;
                updateAnimation();
              }

              function renderLabels(sites) {
                const ordered = [...sites].sort((a, b) => {
                  const aSelected = selected?.type === "site" && selected.id === a.id ? 1 : 0;
                  const bSelected = selected?.type === "site" && selected.id === b.id ? 1 : 0;
                  return bSelected - aSelected || a.name.localeCompare(b.name);
                });
                const labels = labelsLayer.selectAll("text.site-label")
                  .data(ordered, site => site.id)
                  .join("text")
                  .attr("class", "site-label")
                  .attr("x", site => sitePosition.get(site.id)[0] + 12 / currentScale)
                  .attr("y", site => sitePosition.get(site.id)[1])
                  .attr("font-size", 12 / currentScale)
                  .attr("stroke-width", 3 / currentScale)
                  .text(site => site.name);
                const placed = [];
                labels.each(function () {
                  const label = d3.select(this);
                  const bounds = this.getBBox();
                  const overlaps = placed.some(rect =>
                    bounds.x < rect.x + rect.width && bounds.x + bounds.width > rect.x &&
                    bounds.y < rect.y + rect.height && bounds.y + bounds.height > rect.y
                  );
                  if (overlaps) label.attr("display", "none");
                  else {
                    label.attr("display", null);
                    placed.push(bounds);
                  }
                });
              }

              function drawAnimation(time) {
                const isAnimating = animateMap.checked;
                const routeGroups = linksLayer.selectAll("g.replication-link");
                routeGroups.select("path.route-path")
                  .attr("stroke-dashoffset", isAnimating ? -time * 12 : 0);
                routeGroups.each(function (row) {
                  const packetGroup = d3.select(this).selectAll("circle.packet");
                  if (!isAnimating || this.classList.contains("dimmed")) {
                    packetGroup.attr("display", "none");
                    return;
                  }
                  const points = routePoints(row);
                  const phase = ((time / 3.2 + row.index * 0.37) % 1 + 1) % 1;
                  packetGroup.each(function (index) {
                    const progress = phase - index * 0.016;
                    const packet = d3.select(this);
                    if (progress < 0) {
                      packet.attr("display", "none");
                      return;
                    }
                    const inverse = 1 - progress;
                    const x = inverse * inverse * points.p0[0] +
                      2 * inverse * progress * points.c[0] + progress * progress * points.p1[0];
                    const y = inverse * inverse * points.p0[1] +
                      2 * inverse * progress * points.c[1] + progress * progress * points.p1[1];
                    packet.attr("display", null)
                      .attr("cx", x).attr("cy", y)
                    .attr("r", (3.4 - index * 0.65) / currentScale)
                      .attr("opacity", 1 - index * 0.25);
                  });
                });
                pulsesLayer.selectAll("circle.site-pulse")
                  .attr("display", isAnimating ? null : "none")
                  .each(function (site) {
                    const phase = ((time + site.id * 0.37) / 2.4) % 1;
                    d3.select(this)
                      .attr("r", 7 * (0.8 + 1.8 * phase) / currentScale)
                      .attr("opacity", 0.9 * (1 - phase));
                  });
                selfLayer.selectAll("circle.self-ring")
                  .attr("r", 13 / currentScale)
                  .attr("stroke-dashoffset", isAnimating ? time * 6 : 0);
              }

              function animationTick(timestamp) {
                if (!lastAnimationFrame || timestamp - lastAnimationFrame >= 25) {
                  drawAnimation(timestamp / 1000);
                  lastAnimationFrame = timestamp;
                }
                if (animateMap.checked && !document.hidden) {
                  animationFrame = requestAnimationFrame(animationTick);
                } else {
                  animationFrame = null;
                }
              }

              function updateAnimation() {
                if (animationFrame !== null) cancelAnimationFrame(animationFrame);
                animationFrame = null;
                lastAnimationFrame = 0;
                animationTick(performance.now());
              }

              function renderLists() {
                const query = normalized(search.value);
                const list = document.getElementById("link-list");
                list.replaceChildren();
                const related = relatedItems();
                const filteredLinks = database.links.filter(link => {
                  const source = sitesByID.get(link.dc_site_id);
                  const target = sitesByID.get(link.dr_site_id);
                  return !query || normalized([
                    source?.name, source?.city, source?.country,
                    target?.name, target?.city, target?.country
                  ].filter(Boolean).join(" ")).includes(query);
                });
                document.getElementById("link-count").textContent = `${filteredLinks.length} / ${database.links.length}`;
                if (filteredLinks.length === 0) list.append(emptyMessage("No matching links."));
                for (const link of filteredLinks) {
                  const source = sitesByID.get(link.dc_site_id);
                  const target = sitesByID.get(link.dr_site_id);
                  const button = document.createElement("button");
                  button.type = "button";
                  button.className = "list-button";
                  if (selected && selected.type === "link" && selected.id === link.id) button.classList.add("active");
                  if (related && related.linkIDs.has(link.id) && selected?.id !== link.id) button.classList.add("related");
                  button.addEventListener("click", () => showLink(link));
                  button.append(document.createTextNode(
                    `${source?.name ?? `Site ${link.dc_site_id}`} → ${link.dc_site_id === link.dr_site_id ? "itself" : target?.name ?? `Site ${link.dr_site_id}`}`
                  ));
                  const subline = document.createElement("small");
                  const plotted = source && target && isMapped(source) && isMapped(target);
                  subline.textContent = link.dc_site_id === link.dr_site_id
                    ? `${source ? siteLocation(source) : "Unknown"} · local DR`
                    : `${source ? siteLocation(source) : "Unknown"} → ${target ? siteLocation(target) : "Unknown"}${plotted ? "" : " · not plotted"}`;
                  button.append(subline);
                  list.append(button);
                }

                const unmappedList = document.getElementById("unmapped-list");
                const filteredSites = unmappedSites.filter(site =>
                  !query || normalized([site.name, site.city, site.country].join(" ")).includes(query)
                );
                unmappedList.replaceChildren();
                document.getElementById("unmapped-count").textContent = `${filteredSites.length} / ${unmappedSites.length}`;
                if (filteredSites.length === 0) unmappedList.append(emptyMessage("No sites without coordinates."));
                for (const site of filteredSites) {
                  const button = document.createElement("button");
                  button.type = "button";
                  button.className = "list-button";
                  if (selected && selected.type === "site" && selected.id === site.id) button.classList.add("active");
                  if (related && related.siteIDs.has(site.id) && selected?.id !== site.id) button.classList.add("related");
                  button.textContent = `${site.name} · ${siteLocation(site)} · ${site.geo_status}`;
                  button.addEventListener("click", () => showSite(site));
                  unmappedList.append(button);
                }
              }

              function emptyMessage(text) {
                const message = document.createElement("p");
                message.className = "empty";
                message.textContent = text;
                return message;
              }

              const countByRole = role => database.sites.filter(site => roles.get(site.id)?.[role]).length;
              const localLinks = database.links.filter(link => link.dc_site_id === link.dr_site_id).length;
              const realLinks = database.links.length - localLinks;
              const countries = new Set(database.sites.map(site => normalized(site.country)).filter(Boolean)).size;
              const cities = new Set(database.sites.map(site => normalized(site.city)).filter(Boolean)).size;
              const stats = [
                ["Data centers", countByRole("dc")],
                ["DR sites", countByRole("dr")],
                ["Replication links", realLinks, localLinks ? `+${localLinks} local` : ""],
                ["Countries", countries],
                ["Cities", cities]
              ];
              for (const [label, value, note] of stats) {
                const item = document.createElement("div");
                item.className = "stat";
                const number = document.createElement("strong");
                number.textContent = value.toLocaleString();
                const caption = document.createElement("span");
                caption.textContent = label;
                item.append(number, caption);
                if (note) {
                  const subline = document.createElement("small");
                  subline.textContent = note;
                  item.append(subline);
                }
                document.getElementById("stats").append(item);
              }
              document.getElementById("exported-at").textContent =
                `Offline snapshot · exported ${database.generated_at}`;
              document.getElementById("raw-snapshot").textContent = JSON.stringify(database, null, 2);

              const zoom = d3.zoom().scaleExtent([1, 80]).translateExtent([[0, 0], [width, height]]).on("zoom", event => {
                currentScale = event.transform.k;
                root.attr("transform", event.transform);
                sitesLayer.selectAll("circle.site-marker").attr("r", 6 / currentScale);
                linksLayer.selectAll("path.route-arrow").attr("transform", routeArrowTransform);
                labelsLayer.selectAll("text.site-label")
                  .attr("x", site => sitePosition.get(site.id)[0] + 12 / currentScale)
                  .attr("font-size", 12 / currentScale)
                  .attr("stroke-width", 3 / currentScale);
              });
              svg.call(zoom).on("dblclick.zoom", null);
              svg.on("click", () => {
                if (!selected) return;
                selected = null;
                selection.textContent = "Select a site or link on the map, or choose a link above.";
                updateMap();
                renderLists();
              });
              document.getElementById("zoom-in").addEventListener("click", () => {
                svg.transition().duration(250).call(zoom.scaleBy, 1.7);
              });
              document.getElementById("zoom-out").addEventListener("click", () => {
                svg.transition().duration(250).call(zoom.scaleBy, 1 / 1.7);
              });
              document.getElementById("fit-sites").addEventListener("click", () => {
                focusSites(mappedSites.map(site => site.id), 12);
              });
              document.getElementById("reset-map").addEventListener("click", () => {
                svg.transition().duration(650).ease(d3.easeCubicInOut).call(zoom.transform, d3.zoomIdentity);
              });
              showDC.addEventListener("change", updateMap);
              showDR.addEventListener("change", updateMap);
              animateMap.addEventListener("change", updateAnimation);
              search.addEventListener("input", renderLists);
              document.addEventListener("visibilitychange", updateAnimation);
              updateMap();
              renderLists();
            })();
          </script>
        </body>
        </html>
        """#
    }

    private static func safeJSON(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&", with: "\\u0026")
            .replacingOccurrences(of: "<", with: "\\u003c")
            .replacingOccurrences(of: ">", with: "\\u003e")
            .replacingOccurrences(of: "\u{2028}", with: "\\u2028")
            .replacingOccurrences(of: "\u{2029}", with: "\\u2029")
    }

    private static func escapeHTML(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
}
