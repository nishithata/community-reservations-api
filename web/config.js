// Where the demo UI finds the Rails API.
//
// Order of precedence:
//   1. ?api=https://... in the page URL (remembered in localStorage)
//   2. http://localhost:3000 when the UI itself is served from localhost
//   3. DEFAULT_API_BASE_URL below (set this to your Render URL before deploying)
const DEFAULT_API_BASE_URL = "https://community-reservations-api.onrender.com";

window.APP_CONFIG = (() => {
  const fromQuery = new URLSearchParams(window.location.search).get("api");
  if (fromQuery) localStorage.setItem("apiBaseUrl", fromQuery);

  const isLocal = ["localhost", "127.0.0.1"].includes(window.location.hostname);
  const apiBaseUrl =
    fromQuery || localStorage.getItem("apiBaseUrl") || (isLocal ? "http://localhost:3000" : DEFAULT_API_BASE_URL);

  return { apiBaseUrl: apiBaseUrl.replace(/\/+$/, "") };
})();
