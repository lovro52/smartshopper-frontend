<template>
  <div class="app">
    <header class="header">
      <h1>SmartShopper <span class="logo">🛒</span></h1>
    </header>

    <div class="layout">
      <!-- Lijevi panel -->
      <aside class="panel">
        <div class="card">
          <h3>Proizvodi</h3>
          <textarea
            v-model="inputProducts"
            rows="5"
            placeholder="mlijeko 2.8%\nčokolada"
          ></textarea>
        </div>

        <div class="card">
          <h3>Lokacija</h3>
          <div class="row">
            <input
              v-model="address"
              @keyup.enter="geocode"
              placeholder="Omladinska 18, Rovinj"
            />
            <button class="btn" :disabled="loadingGeo" @click="geocode">
              <span v-if="loadingGeo" class="spinner"></span>
              <span v-else>Geokodiraj</span>
            </button>
          </div>
          <div v-if="coords" class="coords">
            📍 {{ coords.lat.toFixed(4) }}, {{ coords.lon.toFixed(4) }}
          </div>
        </div>

        <div class="card">
          <h3>Opcije</h3>
          <div class="grid2">
            <div>
              <label class="lbl">Radius (m)</label>
              <input
                type="number"
                v-model.number="radius"
                min="500"
                step="100"
              />
            </div>
            <div>
              <label class="lbl">Sortiraj po</label>
              <select v-model="sortBy">
                <option value="distance">Udaljenost</option>
                <option value="price">Cijena</option>
                <option value="items">Broj pronađenih</option>
              </select>
            </div>
            <div>
              <label class="lbl">Min. pronađenih</label>
              <input type="number" v-model.number="minItems" min="0" />
            </div>
            <div class="toggles">
              <label
                ><input type="checkbox" v-model="useOSM" /> Koristi OSM</label
              >
              <label
                ><input type="checkbox" v-model="preferReal" /> Samo stvarni
                katalozi</label
              >
            </div>
          </div>
        </div>

        <div class="card actions">
          <button class="btn primary" :disabled="loadingRec" @click="recommend">
            <span v-if="loadingRec" class="spinner"></span>
            <span v-else>Preporuči trgovine</span>
          </button>
          <button class="btn" @click="fetchBrands">Popis brendova</button>
          <button
            v-if="useDynamo"
            class="btn ghost"
            :disabled="loadingIngest"
            @click="ingestAll"
          >
            <span v-if="loadingIngest" class="spinner"></span>
            <span v-else>Ingest ALL → Dynamo</span>
          </button>
        </div>
      </aside>

      <!-- Desno: mapa i rezultati -->
      <section class="right">
        <div id="map" ref="map" class="map"></div>

        <!-- Brandovi -->
        <section class="brands" v-if="brands.length">
          <h2>Brendovi (iz JSON/Dynamo):</h2>
          <div class="chips">
            <span class="chip" v-for="b in brands" :key="b">{{ b }}</span>
          </div>
        </section>

        <!-- Rezultati sa zasebnim scrollom -->
        <section class="results-board" v-if="recommendations.length">
          <div class="results-head">
            <h2>Preporuke ({{ recommendations.length }})</h2>
          </div>
          <div class="results-scroller">
            <div class="cards">
              <div
                class="card rec"
                v-for="(r, idx) in recommendations"
                :key="r.shop_name + r.distance_km"
                :id="'shop-' + idx"
                @click="focusMarker(idx)"
              >
                <div class="card-header">
                  <h3>{{ r.shop_name }}</h3>
                  <span class="brand">{{ r.brand }}</span>
                </div>
                <p>
                  Udaljenost: <strong>{{ r.distance_km }} km</strong>
                </p>
                <p>
                  Ukupno:
                  <strong>{{
                    r.total_price != null
                      ? r.total_price.toFixed(2) + " €"
                      : "—"
                  }}</strong>
                </p>
                <p>
                  Pronađeno: <strong>{{ r.items_found }}</strong>
                </p>
                <ul class="items">
                  <li v-for="m in r.matched" :key="m.name">
                    {{ m.name }} — {{ m.price.toFixed(2) }} €
                  </li>
                </ul>
              </div>
            </div>
          </div>
        </section>
      </section>
    </div>

    <!-- Toast -->
    <div v-if="toast.show" class="toast" :class="toast.kind">
      {{ toast.msg }}
    </div>

    <section v-if="error" class="error">⚠️ {{ error }}</section>
  </div>
</template>

<script>
import * as L from "leaflet";
import iconRetinaUrl from "leaflet/dist/images/marker-icon-2x.png";
import iconUrl from "leaflet/dist/images/marker-icon.png";
import shadowUrl from "leaflet/dist/images/marker-shadow.png";
L.Icon.Default.mergeOptions({ iconRetinaUrl, iconUrl, shadowUrl });

const API =
  (typeof import.meta !== "undefined" &&
    import.meta.env &&
    import.meta.env.VITE_API_BASE) ||
  (typeof process !== "undefined" &&
    process.env &&
    process.env.VUE_APP_API_BASE) ||
  "http://localhost:8000";

export default {
  name: "App",
  data() {
    return {
      inputProducts: "mlijeko 2.8%\nčokolada",
      address: "Omladinska 18, Rovinj",
      coords: null,
      radius: 3000,
      sortBy: "distance",
      minItems: 0,
      useOSM: true,
      preferReal: true,
      recommendations: [],
      brands: [],
      loadingGeo: false,
      loadingRec: false,
      loadingIngest: false,
      error: "",
      toast: { show: false, msg: "", kind: "info" },
      useDynamo: false,
      // mapa
      map: null,
      markersLayer: null,
      userMarker: null,
      markers: [],
    };
  },
  methods: {
    showToast(msg, kind = "info", ms = 2200) {
      this.toast = { show: true, msg, kind };
      setTimeout(() => (this.toast.show = false), ms);
    },
    parseProducts() {
      return (this.inputProducts || "")
        .split("\n")
        .map((s) => s.trim())
        .filter(Boolean)
        .map((name) => ({ name }));
    },
    ensureMap() {
      if (this.map) return;
      this.map = L.map(this.$refs.map, {
        zoomAnimation: false,
        markerZoomAnimation: false,
      }).setView([45.081, 13.64], 13);

      L.tileLayer("https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png", {
        maxZoom: 19,
        attribution: "&copy; OpenStreetMap contributors",
      }).addTo(this.map);

      this.markersLayer = L.layerGroup().addTo(this.map);
      this.map.whenReady(() => this.map.invalidateSize());
    },
    setUserLocation(lat, lon) {
      this.ensureMap();
      if (this.userMarker) this.userMarker.setLatLng([lat, lon]);
      else {
        this.userMarker = L.marker([lat, lon], { title: "Vi ste ovdje" }).addTo(
          this.map
        );
      }
      this.map.setView([lat, lon], 13, { animate: false });
    },
    renderShops(shops) {
      this.ensureMap();
      this.map.stop();
      this.markersLayer.clearLayers();
      this.markers = [];

      const bounds = L.latLngBounds([]);
      shops.forEach((s, idx) => {
        if (typeof s.lat !== "number" || typeof s.lon !== "number") return;
        const mk = L.marker([s.lat, s.lon])
          .bindPopup(
            `<b>${s.shop_name}</b><br/>${s.brand}<br/>${s.items_found} artikala<br/>` +
              (s.total_price != null
                ? `Ukupno: ${s.total_price.toFixed(2)} €`
                : "")
          )
          .addTo(this.markersLayer);
        mk.on("click", () => this.scrollToCard(idx));
        this.markers.push(mk);
        bounds.extend([s.lat, s.lon]);
      });

      if (bounds.isValid()) {
        setTimeout(
          () =>
            this.map.fitBounds(bounds, { padding: [20, 20], animate: false }),
          0
        );
      }
    },
    focusMarker(idx) {
      const mk = this.markers[idx];
      if (!mk) return;
      mk.openPopup();
      this.map.setView(mk.getLatLng(), this.map.getZoom(), { animate: false });
    },
    scrollToCard(idx) {
      const el = document.getElementById("shop-" + idx);
      if (!el) return;
      el.scrollIntoView({ behavior: "smooth", block: "center" });
      el.classList.add("hl");
      setTimeout(() => el.classList.remove("hl"), 800);
    },
    async geocode() {
      this.error = "";
      this.loadingGeo = true;
      try {
        const r = await fetch(
          `${API}/api/geo/geocode?address=${encodeURIComponent(this.address)}`
        );
        if (!r.ok) throw new Error(await r.text());
        const data = await r.json();
        this.coords = data;
        this.setUserLocation(data.lat, data.lon);
      } catch (e) {
        this.error = String(e);
        this.showToast("Greška pri geokodiranju", "error");
      } finally {
        this.loadingGeo = false;
      }
    },
    async recommend() {
      this.error = "";
      this.loadingRec = true;
      try {
        if (!this.coords) await this.geocode();
        const body = {
          products: this.parseProducts(),
          user_location: this.coords,
          radius_m: this.radius,
          sort_by: this.sortBy,
          min_items: this.minItems,
          use_osm: this.useOSM,
          prefer_real_catalog: this.preferReal,
        };
        const r = await fetch(`${API}/api/products/recommend`, {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify(body),
        });
        if (!r.ok) throw new Error(await r.text());
        this.recommendations = await r.json();
        this.renderShops(this.recommendations);
        this.showToast(
          `Pronađeno ${this.recommendations.length} trgovina`,
          "ok"
        );
      } catch (e) {
        this.error = String(e);
        this.showToast("Greška pri preporuci", "error");
      } finally {
        this.loadingRec = false;
      }
    },
    async fetchBrands() {
      this.error = "";
      try {
        const r = await fetch(`${API}/api/catalog/brands`);
        if (!r.ok) throw new Error(await r.text());
        this.brands = await r.json();
      } catch (e) {
        this.error = String(e);
        this.showToast("Greška pri dohvaćanju brendova", "error");
      }
    },
    async ingestAll() {
      this.error = "";
      this.loadingIngest = true;
      try {
        const r = await fetch(`${API}/api/catalog/ingest-all`, {
          method: "POST",
        });
        if (!r.ok) {
          const t = await r.text();
          console.warn("ingest-all:", t);
          this.showToast("Dynamo nije dostupan", "warn");
          return;
        }
        await this.fetchBrands();
        this.showToast("Ingest završen", "ok");
      } catch (e) {
        this.error = String(e);
        this.showToast("Greška pri ingestu", "error");
      } finally {
        this.loadingIngest = false;
      }
    },
    async fetchHealth() {
      try {
        const r = await fetch(`${API}/health`);
        const h = await r.json();
        this.useDynamo = !!h.use_dynamo;
      } catch (e) {
        this.useDynamo = false;
        if (
          typeof console !== "undefined" &&
          process.env.NODE_ENV !== "production"
        ) {
          console.debug("Health fetch failed:", e);
        }
      }
    },
  },
  async mounted() {
    this.ensureMap();
    await this.fetchHealth();
    await this.fetchBrands();
    await this.geocode();
  },
};
</script>

<style>
:root {
  --accent: #2563eb;
  --bg: #fff;
  --muted: #f5f7fb;
  --border: #e6e8ef;
  --text: #111827;
}
* {
  box-sizing: border-box;
}
body {
  margin: 0;
  background: var(--muted);
  color: var(--text);
}

/* centriran naslov */
.header {
  text-align: center;
  padding: 8px 0 12px;
}
.header h1 {
  margin: 0;
  font-weight: 800;
  letter-spacing: 0.2px;
}
.logo {
  font-size: 0.9em;
}

/* layout: lijevi panel odvojen + sticky */
.app {
  max-width: 1260px;
  margin: 0 auto 48px;
  padding: 0 16px;
}
.layout {
  display: grid;
  grid-template-columns: 380px 1fr;
  gap: 28px;
  align-items: start;
}
.panel {
  position: sticky;
  top: 12px;
  align-self: start;
}
.panel .card {
  margin-bottom: 14px;
}

/* kartice + odvajanja */
.card {
  background: var(--bg);
  border: 1px solid var(--border);
  border-radius: 18px;
  padding: 14px;
  box-shadow: 0 8px 16px rgba(17, 24, 39, 0.04);
}
.card h3 {
  margin: 0 0 8px;
  font-size: 15px;
}

.row {
  display: grid;
  grid-template-columns: 1fr auto;
  gap: 8px;
}
.grid2 {
  display: grid;
  grid-template-columns: 1fr 1fr;
  gap: 10px;
}
.lbl {
  display: block;
  font-size: 12px;
  color: #555;
  margin-bottom: 4px;
}

textarea,
input,
select {
  width: 100%;
  padding: 10px;
  border: 1px solid var(--border);
  border-radius: 10px;
  background: #fff;
}
.toggles {
  display: flex;
  gap: 10px;
  align-items: center;
  padding-top: 8px;
  flex-wrap: wrap;
}

/* gumbi */
.actions {
  display: flex;
  gap: 8px;
  flex-wrap: wrap;
}
.btn {
  padding: 10px 12px;
  border: 1px solid var(--border);
  background: #fff;
  border-radius: 10px;
  cursor: pointer;
}
.btn:hover {
  background: #fafafa;
}
.btn.primary {
  background: var(--accent);
  border-color: var(--accent);
  color: #fff;
}
.btn.primary:hover {
  filter: brightness(0.97);
}
.btn.ghost {
  background: transparent;
}

/* mapa */
.right {
  display: flex;
  flex-direction: column;
  gap: 16px;
}
.map {
  height: 520px;
  border: 1px solid var(--border);
  border-radius: 16px;
  background: #fff;
}

/* brandovi */
.brands .chips {
  display: flex;
  gap: 8px;
  flex-wrap: wrap;
}
.chip {
  padding: 6px 10px;
  border: 1px solid var(--border);
  border-radius: 999px;
  background: #fff;
}

/* rezultati — vlastiti scroller + razdvojene kartice trgovina */
.results-board {
  background: var(--bg);
  border: 1px solid var(--border);
  border-radius: 18px;
}
.results-head {
  padding: 12px 14px;
  border-bottom: 1px solid var(--border);
}
.results-scroller {
  max-height: clamp(280px, 46vh, 560px);
  overflow-y: auto;
  overscroll-behavior: contain;
  padding: 14px;
}
.cards {
  display: grid;
  grid-template-columns: repeat(auto-fill, minmax(260px, 1fr));
  gap: 16px;
}
.card.rec {
  border-radius: 14px;
  box-shadow: 0 6px 12px rgba(17, 24, 39, 0.05);
}
.card.rec .card-header {
  display: flex;
  justify-content: space-between;
  align-items: center;
}
.brand {
  background: rgba(37, 99, 235, 0.1);
  color: var(--accent);
  padding: 2px 8px;
  border-radius: 999px;
  font-size: 12px;
}
.items {
  margin: 8px 0 0;
  padding-left: 18px;
}
.coords {
  margin-top: 6px;
  color: #374151;
}
.hl {
  outline: 2px solid var(--accent);
  transition: outline 0.2s;
}

/* toast */
.toast {
  position: fixed;
  top: 14px;
  right: 14px;
  background: #111;
  color: #fff;
  padding: 10px 12px;
  border-radius: 10px;
  opacity: 0.95;
  z-index: 9999;
}
.toast.ok {
  background: #16a34a;
}
.toast.warn {
  background: #ca8a04;
}
.toast.error {
  background: #b00020;
}

/* responsive */
@media (max-width: 980px) {
  .layout {
    grid-template-columns: 1fr;
  }
  .map {
    height: 420px;
  }
}
.spinner {
  width: 14px;
  height: 14px;
  border: 2px solid #fff;
  border-right-color: transparent;
  border-radius: 50%;
  display: inline-block;
  vertical-align: -2px;
  animation: spin 0.7s linear infinite;
}
.btn:not(.primary) .spinner {
  border-color: #999;
  border-right-color: transparent;
}
@keyframes spin {
  to {
    transform: rotate(360deg);
  }
}
.error {
  margin-top: 12px;
  color: #b00020;
}
</style>
