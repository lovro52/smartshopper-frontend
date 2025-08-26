<template>
  <div class="layout">
    <!-- HEADER + INPUT BOX -->
    <div class="card input-card">
      <h1>SmartShopper 🛒</h1>

      <div class="grid-2">
        <!-- Proizvodi -->
        <div>
          <label class="lbl">Proizvodi</label>
          <textarea
            v-model="input"
            class="txt"
            placeholder="Unesi proizvode, jedan po red (npr. 'mlijeko 1l 2.8%')"
            rows="6"
          />
          <p class="hint">Primjeri: “mlijeko 1l 2.8%”, “jaja 10 kom”, “kruh”</p>
        </div>

        <!-- Adresa -->
        <div>
          <label class="lbl">Adresa</label>
          <input
            v-model="userAddress"
            class="txt"
            type="text"
            placeholder="npr. Omladinska ulica 18, Rovinj"
          />
          <div class="hint">
            Upisuj <b>ulica i broj, grad</b>. Primjeri:
            <span class="pill">Ilica 34, Zagreb</span>
            <span class="pill">Ulica Hrvatske Mornarice 1, Split</span>
          </div>

          <div class="controls-row">
            <label class="inline">
              Sortiraj:
              <select v-model="sortBy">
                <option value="distance">po udaljenosti</option>
                <option value="price">po cijeni</option>
                <option value="items">po broju artikala</option>
              </select>
            </label>

            <label class="inline">
              Radius:
              <select v-model.number="radiusM">
                <option :value="1500">1.5 km</option>
                <option :value="3000">3 km</option>
                <option :value="5000">5 km</option>
                <option :value="10000">10 km</option>
              </select>
            </label>
          </div>

          <div class="buttons">
            <button
              @click="getLocationFromAddress"
              title="Pretvori adresu u lokaciju"
            >
              📍 Lokacija
            </button>
            <button class="primary" @click="fetchRecommendation">
              🔎 Pretraži
            </button>
            <button class="secondary" @click="refreshCatalogs">
              🔄 Osvježi kataloge
            </button>
          </div>

          <p v-if="userLocation" class="muted">
            Lokacija: {{ userLocation.lat.toFixed(4) }},
            {{ userLocation.lon.toFixed(4) }}
          </p>
        </div>
      </div>

      <p v-if="notice" class="notice">ℹ️ {{ notice }}</p>
      <p v-if="error" class="error">⚠️ {{ error }}</p>
    </div>

    <!-- MAIN CONTENT: results (scrollable) + map -->
    <div class="content">
      <div class="card results-panel">
        <div v-if="isLoading" class="loading">⏳ Učitavanje...</div>

        <template v-else>
          <h2>Rezultati:</h2>
          <p v-if="hiddenCount > 0" class="muted sm">
            (Sakriveno {{ hiddenCount }} trgovina bez pronađenih artikala)
          </p>

          <div v-if="displayedRecommendations.length === 0" class="empty">
            Unesi proizvode i adresu, pa klikni <b>Pretraži</b>.
          </div>

          <div
            v-for="shop in displayedRecommendations"
            :key="shop.shop_name + '-' + shop.lat + '-' + shop.lon"
            class="shop-card"
          >
            <div class="shop-header">
              <h3>{{ shop.shop_name }}</h3>
              <span class="chip">{{ shop.distance_km.toFixed(2) }} km</span>
            </div>

            <div class="shop-stats">
              <div class="stat">
                <span class="label">Ukupna cijena</span>
                <span class="value">{{ euro(shop.total_price) }}</span>
              </div>
              <div class="stat">
                <span class="label">Artikli</span>
                <span class="value">{{ shop.items_found }}</span>
              </div>
            </div>

            <details class="matched">
              <summary>Detalji artikala</summary>
              <ul>
                <li v-for="item in shop.matched_products" :key="item.name">
                  ✔ {{ item.name }} — {{ euro(item.price) }}
                  <span
                    class="tag"
                    :class="item.source === 'dummy' ? 'tag-gray' : 'tag-green'"
                  >
                    {{ item.source === "dummy" ? "dummy" : "katalog" }}
                  </span>
                </li>
              </ul>
            </details>
          </div>
        </template>
      </div>

      <div class="card map-panel">
        <div id="map"></div>
      </div>
    </div>
  </div>
</template>

<script>
import axios from "axios";
import L from "leaflet";
import "leaflet/dist/leaflet.css";

const API = "http://localhost:8000";

export default {
  data() {
    return {
      input: "",
      userAddress: "",
      userLocation: null,

      sortBy: "distance",
      radiusM: 3000,

      recommendations: [],
      error: "",
      notice: "",
      isLoading: false,

      map: null,
      markers: [],
    };
  },
  computed: {
    displayedRecommendations() {
      return (this.recommendations || []).filter(
        (r) => (r.items_found || 0) > 0
      );
    },
    hiddenCount() {
      return (
        (this.recommendations || []).length -
        this.displayedRecommendations.length
      );
    },
  },
  mounted() {
    this.$nextTick(() => this.initMap());
  },
  methods: {
    euro(x) {
      return `${(x ?? 0).toFixed(2)} €`;
    },
    initMap() {
      const el = document.getElementById("map");
      if (!el) return;

      this.map = L.map(el).setView([45.1, 13.6], 12);

      L.tileLayer("https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png", {
        attribution: "&copy; OpenStreetMap contributors",
      }).addTo(this.map);

      delete L.Icon.Default.prototype._getIconUrl;
      L.Icon.Default.mergeOptions({
        iconRetinaUrl: "/leaflet/marker-icon-2x.png",
        iconUrl: "/leaflet/marker-icon.png",
        shadowUrl: "/leaflet/marker-shadow.png",
      });
    },
    addMarkers(recommendations) {
      if (!this.map) return;
      this.markers.forEach((m) => this.map.removeLayer(m));
      this.markers = [];

      (recommendations || [])
        .filter((r) => (r.items_found || 0) > 0)
        .forEach((shop) => {
          const marker = L.marker([shop.lat, shop.lon]).addTo(this.map);
          marker.bindPopup(`
            <b>${shop.shop_name}</b><br/>
            Ukupno: ${this.euro(shop.total_price)}<br/>
            Artikli: ${shop.items_found}<br/>
            <ul style="margin:6px 0 0; padding-left:18px; max-height:140px; overflow:auto;">
              ${shop.matched_products
                .map(
                  (p) =>
                    `<li>${p.name} — ${this.euro(
                      p.price
                    )} <span style="border:1px solid #d1d5db;border-radius:8px;padding:1px 6px;margin-left:6px;font-size:12px;background:${
                      p.source === "dummy" ? "#f3f4f6" : "#ecfdf5"
                    }">${
                      p.source === "dummy" ? "dummy" : "katalog"
                    }</span></li>`
                )
                .join("")}
            </ul>
          `);
          this.markers.push(marker);
        });

      if (this.userLocation) {
        const userMarker = L.circleMarker(
          [this.userLocation.lat, this.userLocation.lon],
          {
            radius: 8,
            fillColor: "#0ea5e9",
            color: "#fff",
            weight: 1,
            opacity: 1,
            fillOpacity: 0.85,
          }
        ).addTo(this.map);
        userMarker.bindPopup("🧍 Tvoja lokacija");
        this.markers.push(userMarker);
        this.map.setView([this.userLocation.lat, this.userLocation.lon], 13);
      }
    },
    async refreshCatalogs() {
      this.error = "";
      this.notice = "";
      try {
        const res = await axios.post(`${API}/api/catalog/ingest/all`);
        const ok = Object.entries(res.data)
          .filter(([, v]) => v.ok)
          .map(([b, v]) => `${b}: ${v.count}`)
          .join(", ");
        const fail = Object.entries(res.data)
          .filter(([, v]) => !v.ok)
          .map(([b, v]) => `${b}: ${v.error}`)
          .join(" | ");
        this.notice =
          `Osvježeno — ${ok || "nema podataka"}` +
          (fail ? ` | Greške: ${fail}` : "");
      } catch (e) {
        console.error(e);
        this.error = "Neuspjelo osvježavanje kataloga.";
      }
    },
    async fetchRecommendation() {
      this.error = "";
      this.notice = "";
      this.isLoading = true;
      this.recommendations = [];

      const products = this.input
        .split("\n")
        .map((p) => p.trim())
        .filter((p) => p.length > 0)
        .map((name) => ({ name }));

      if (!products.length) {
        this.error = "Unesi barem jedan proizvod.";
        this.isLoading = false;
        return;
      }
      if (!this.userLocation) {
        this.error =
          "Unesi adresu (npr. 'Omladinska ulica 18, Rovinj') i klikni Lokacija.";
        this.isLoading = false;
        return;
      }

      try {
        const url =
          `${API}/api/products/recommend` +
          `?sort_by=${encodeURIComponent(this.sortBy)}` +
          `&prefer_real_catalog=true&use_osm=true&radius_m=${this.radiusM}&min_items=1`;

        const { data } = await axios.post(url, {
          products,
          user_location: this.userLocation,
        });

        this.recommendations = Array.isArray(data) ? data : [];
        this.addMarkers(this.recommendations);

        if (this.displayedRecommendations.length === 0) {
          this.notice = "Nema pogodaka u radijusu za unesene proizvode.";
        }
      } catch (err) {
        console.error(err);
        this.error = "Greška prilikom dohvaćanja rezultata.";
      } finally {
        this.isLoading = false;
      }
    },
    async getLocationFromAddress() {
      this.error = "";
      this.notice = "";
      if (!this.userAddress.trim()) {
        this.error = "Unesi adresu (npr. 'Omladinska ulica 18, Rovinj').";
        return;
      }

      try {
        const { data } = await axios.get(`${API}/api/geo/geocode`, {
          params: { address: this.userAddress },
        });

        if (
          data &&
          typeof data.lat === "number" &&
          typeof data.lon === "number"
        ) {
          this.userLocation = { lat: data.lat, lon: data.lon };
          if (this.map) this.map.setView([data.lat, data.lon], 13);
          this.notice = "Lokacija postavljena.";
        } else {
          this.error =
            "Nije pronađena lokacija za ovu adresu. Pokušaj: 'Ulica i broj, Grad'.";
          this.userLocation = null;
        }
      } catch (err) {
        console.error("Greška kod lokacije:", err);
        this.error = "Greška pri dohvaćanju lokacije.";
        this.userLocation = null;
      }
    },
  },
};
</script>

<style>
:root {
  --bg: #f5f7fb;
  --card: #ffffff;
  --muted: #6b7280;
  --accent: #22c55e;
  --accent-2: #0ea5e9;
  --border: #e5e7eb;
  --shadow: 0 2px 10px rgba(0, 0, 0, 0.06);
}

* {
  box-sizing: border-box;
}
body {
  background: var(--bg);
}

.layout {
  max-width: 1200px;
  margin: 24px auto;
  padding: 0 16px;
}

.card {
  background: var(--card);
  border: 1px solid var(--border);
  border-radius: 14px;
  box-shadow: var(--shadow);
}
.input-card {
  padding: 16px;
}

.grid-2 {
  display: grid;
  grid-template-columns: 1fr 1fr;
  gap: 16px;
}

.lbl {
  display: block;
  font-weight: 600;
  margin-bottom: 6px;
}
.txt {
  width: 100%;
  padding: 10px 12px;
  border: 1px solid var(--border);
  border-radius: 10px;
  outline: none;
  background: #fff;
}

.hint {
  color: var(--muted);
  margin-top: 6px;
}
.hint .pill {
  display: inline-block;
  margin: 4px 6px 0 0;
  padding: 2px 8px;
  background: #eef2ff;
  border: 1px solid #e5e7eb;
  border-radius: 999px;
  font-size: 12px;
}

.controls-row {
  display: flex;
  gap: 12px;
  align-items: center;
  margin-top: 10px;
}
.inline select {
  margin-left: 6px;
}

.buttons {
  display: flex;
  gap: 8px;
  margin-top: 10px;
}
button {
  padding: 10px 14px;
  font-weight: 600;
  background: #e5e7eb;
  color: #111827;
  border: 1px solid var(--border);
  border-radius: 10px;
  cursor: pointer;
}
button.primary {
  background: var(--accent);
  color: white;
  border: none;
}
button.secondary {
  background: var(--accent-2);
  color: white;
  border: none;
}
button:hover {
  filter: brightness(0.97);
}

.muted {
  color: var(--muted);
  margin-top: 6px;
}
.muted.sm {
  font-size: 12px;
}
.notice {
  color: #0d9488;
  margin-top: 6px;
}
.error {
  color: #dc2626;
  margin-top: 6px;
}

.content {
  display: grid;
  grid-template-columns: 1fr 1fr;
  gap: 18px;
  margin-top: 18px;
}

/* scrollable results */
.results-panel {
  padding: 14px;
  max-height: 72vh;
  overflow: auto;
}

#map {
  width: 100%;
  height: 72vh;
  border-radius: 12px;
}

.map-panel {
  padding: 8px;
}

.shop-card {
  background: #fff;
  border: 1px solid var(--border);
  margin: 12px 0;
  padding: 14px;
  border-radius: 12px;
}

.shop-header {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 8px;
}

.chip {
  background: #eef6ee;
  color: #176b2a;
  padding: 4px 8px;
  border-radius: 999px;
  font-size: 12px;
  border: 1px solid #cfe7cf;
}

.shop-stats {
  display: grid;
  grid-template-columns: repeat(2, minmax(120px, 1fr));
  gap: 12px;
  margin-top: 8px;
}

.stat {
  background: #f9fafb;
  border: 1px solid var(--border);
  border-radius: 10px;
  padding: 10px;
}
.stat .label {
  display: block;
  color: var(--muted);
  font-size: 12px;
  margin-bottom: 4px;
}
.stat .value {
  font-weight: 700;
}

.matched {
  margin-top: 10px;
}

.tag {
  margin-left: 8px;
  border: 1px solid var(--border);
  border-radius: 8px;
  padding: 1px 6px;
  font-size: 12px;
}
.tag-green {
  background: #ecfdf5;
  color: #065f46;
  border-color: #a7f3d0;
}
.tag-gray {
  background: #f3f4f6;
  color: #374151;
  border-color: #d1d5db;
}

.loading,
.empty {
  padding: 16px;
  font-weight: bold;
}

@media (max-width: 980px) {
  .grid-2 {
    grid-template-columns: 1fr;
  }
  .content {
    grid-template-columns: 1fr;
  }
  #map {
    height: 56vh;
  }
}
</style>
