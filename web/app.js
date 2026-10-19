// Demo client for the Community Resource Reservation API.
// Plain JavaScript, no build step. All times are shown and entered in UTC to
// match the API.
(() => {
  "use strict";

  const API = window.APP_CONFIG.apiBaseUrl;
  const DEMO = { email: "demo@example.com", password: "demo-password-123" };

  const state = {
    token: localStorage.getItem("token"),
    user: JSON.parse(localStorage.getItem("user") || "null"),
    selected: null,
    resourcePage: 1,
    reservationPage: 1,
    registering: false,
  };

  const $ = (id) => document.getElementById(id);

  // ---- API client ---------------------------------------------------------

  class ApiError extends Error {
    constructor(status, body) {
      const error = body?.error || {};
      super(error.message || `Request failed (${status})`);
      this.status = status;
      this.code = error.code;
      this.details = error.details;
    }

    // Field errors arrive as { field: ["Full message", ...] }.
    get fullMessage() {
      const fieldMessages = Object.values(this.details || {}).flat();
      return fieldMessages.length ? fieldMessages.join(" ") : this.message;
    }
  }

  async function api(path, { method = "GET", body, auth = true } = {}) {
    const headers = { Accept: "application/json" };
    if (body) headers["Content-Type"] = "application/json";
    if (auth && state.token) headers.Authorization = `Bearer ${state.token}`;

    let response;
    try {
      response = await fetch(`${API}${path}`, { method, headers, body: body && JSON.stringify(body) });
    } catch {
      throw new ApiError(0, { error: { message: "Cannot reach the API. It may be waking up; try again in a moment." } });
    }

    const data = response.status === 204 ? null : await response.json().catch(() => null);
    if (response.status === 401 && state.token && auth) {
      logout("Your session expired. Please log in again.");
    }
    if (!response.ok) throw new ApiError(response.status, data);
    return data;
  }

  // ---- Helpers ------------------------------------------------------------

  function escapeHtml(value) {
    return String(value ?? "").replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[c]);
  }

  const timeFmt = new Intl.DateTimeFormat("en-US", { timeZone: "UTC", hour: "2-digit", minute: "2-digit", hour12: false });
  const dateFmt = new Intl.DateTimeFormat("en-US", { timeZone: "UTC", weekday: "short", month: "short", day: "numeric", year: "numeric" });

  const formatRange = (start, end) =>
    `${dateFmt.format(new Date(start))}, ${timeFmt.format(new Date(start))} to ${timeFmt.format(new Date(end))}`;

  const todayUtc = () => new Date().toISOString().slice(0, 10);
  const tomorrowUtc = () => new Date(Date.now() + 86_400_000).toISOString().slice(0, 10);

  let toastTimer;
  function toast(message, kind = "info") {
    const el = $("toast");
    el.textContent = message;
    el.className = `toast toast-${kind}`;
    el.hidden = false;
    clearTimeout(toastTimer);
    toastTimer = setTimeout(() => { el.hidden = true; }, 3500);
  }

  function showError(id, message) {
    const el = $(id);
    el.textContent = message || "";
    el.hidden = !message;
  }

  function renderPager(container, meta, onPage) {
    container.innerHTML = "";
    if (!meta || meta.total_pages <= 1) return;

    const button = (label, page) => {
      const b = document.createElement("button");
      b.type = "button";
      b.className = "btn btn-ghost";
      b.textContent = label;
      b.disabled = !page;
      b.addEventListener("click", () => onPage(page));
      return b;
    };
    const info = document.createElement("span");
    info.className = "muted";
    info.textContent = `Page ${meta.page} of ${meta.total_pages} · ${meta.total_count} total`;
    container.append(button("← Previous", meta.prev_page), info, button("Next →", meta.next_page));
  }

  // ---- Session ------------------------------------------------------------

  function saveSession({ token, user }) {
    state.token = token;
    state.user = user;
    localStorage.setItem("token", token);
    localStorage.setItem("user", JSON.stringify(user));
    renderSession();
  }

  function logout(message) {
    state.token = null;
    state.user = null;
    localStorage.removeItem("token");
    localStorage.removeItem("user");
    renderSession();
    if (message) toast(message, "error");
  }

  function renderSession() {
    const loggedIn = Boolean(state.token && state.user);
    $("session").hidden = !loggedIn;
    $("auth-card").hidden = loggedIn;
    $("reservations-card").hidden = !loggedIn;
    $("admin-card").hidden = !(loggedIn && state.user.role === "admin");
    $("booking-login-hint").hidden = loggedIn;

    if (loggedIn) {
      $("session-name").textContent = state.user.name;
      $("session-role").textContent = state.user.role;
      $("reservations-title").textContent = state.user.role === "admin" ? "All reservations" : "My reservations";
      loadReservations();
    }
    loadResources();
  }

  function setAuthMode(registering) {
    state.registering = registering;
    $("auth-title").textContent = registering ? "Create an account" : "Log in";
    $("auth-submit").textContent = registering ? "Sign up" : "Log in";
    $("auth-toggle").textContent = registering ? "Already have an account? Log in" : "New here? Create an account";
    $("name-field").hidden = !registering;
    showError("auth-error", "");
  }

  async function submitAuth(credentials) {
    showError("auth-error", "");
    try {
      const path = state.registering ? "/api/v1/auth/register" : "/api/v1/auth/login";
      saveSession(await api(path, { method: "POST", body: credentials, auth: false }));
      toast(`Welcome, ${state.user.name}!`, "success");
    } catch (error) {
      showError("auth-error", error.fullMessage);
    }
  }

  // ---- Resources ----------------------------------------------------------

  async function loadResources(page = state.resourcePage) {
    state.resourcePage = page;
    const filters = new FormData($("resource-filters"));
    const params = new URLSearchParams({ page, per_page: 6 });
    for (const [key, value] of filters) if (value) params.set(key, value);

    const list = $("resource-list");
    try {
      const { data, meta } = await api(`/api/v1/resources?${params}`);
      list.innerHTML = data.length
        ? data.map((r) => `
            <li>
              <button type="button" class="resource ${state.selected?.id === r.id ? "is-selected" : ""}" data-id="${r.id}">
                <span class="pill pill-${escapeHtml(r.category)}">${escapeHtml(r.category)}</span>
                <strong>${escapeHtml(r.name)}</strong>
                <span class="muted">${escapeHtml(r.location || "")}${r.capacity ? ` · up to ${r.capacity}` : ""}</span>
                ${r.active ? "" : '<span class="pill pill-muted">inactive</span>'}
              </button>
            </li>`).join("")
        : '<li class="muted">No resources match these filters.</li>';
      list._resources = Object.fromEntries(data.map((r) => [r.id, r]));
      renderPager($("resource-pager"), meta, loadResources);
    } catch (error) {
      list.innerHTML = `<li class="form-error">${escapeHtml(error.message)}</li>`;
    }
  }

  function selectResource(resource) {
    state.selected = resource;
    $("booking-card").hidden = false;
    $("selected-name").textContent = resource.name;
    $("selected-meta").textContent = [resource.category, resource.location, resource.capacity && `capacity ${resource.capacity}`]
      .filter(Boolean).join(" · ");
    $("selected-description").textContent = resource.description || "";
    if (!$("availability-date").value) $("availability-date").value = tomorrowUtc();
    showError("booking-error", "");
    loadAvailability();
    loadResources();
    $("booking-card").scrollIntoView({ behavior: "smooth", block: "nearest" });
  }

  async function loadAvailability() {
    if (!state.selected) return;
    const date = $("availability-date").value;
    const list = $("availability-list");
    try {
      const { data } = await api(`/api/v1/resources/${state.selected.id}/availability?date=${date}`, { auth: false });
      list.innerHTML = data.bookings.length
        ? data.bookings.map((b) => `<li class="slot">${timeFmt.format(new Date(b.starts_at))} to ${timeFmt.format(new Date(b.ends_at))}</li>`).join("")
        : '<li class="muted">Free all day.</li>';
    } catch (error) {
      list.innerHTML = `<li class="form-error">${escapeHtml(error.message)}</li>`;
    }
  }

  async function submitBooking(form) {
    showError("booking-error", "");
    if (!state.token) return showError("booking-error", "Log in to make a reservation.");

    const date = $("availability-date").value;
    const startsAt = new Date(`${date}T${form.start.value}:00Z`);
    const endsAt = new Date(startsAt.getTime() + Number(form.duration.value) * 60_000);

    try {
      await api("/api/v1/reservations", {
        method: "POST",
        body: { reservation: {
          resource_id: state.selected.id, starts_at: startsAt.toISOString(),
          ends_at: endsAt.toISOString(), notes: form.notes.value || null,
        } },
      });
      form.notes.value = "";
      toast("Reservation confirmed.", "success");
      loadAvailability();
      loadReservations(1);
    } catch (error) {
      const prefix = error.status === 409 ? "That slot is taken. " : "";
      showError("booking-error", prefix + error.fullMessage);
    }
  }

  // ---- Reservations -------------------------------------------------------

  async function loadReservations(page = state.reservationPage) {
    if (!state.token) return;
    state.reservationPage = page;
    const params = new URLSearchParams({ page, per_page: 8 });
    const status = $("reservation-status").value;
    if (status) params.set("status", status);

    const rows = $("reservation-rows");
    try {
      const { data, meta } = await api(`/api/v1/reservations?${params}`);
      const now = Date.now();
      rows.innerHTML = data.length
        ? data.map((r) => {
            const cancellable = r.status === "confirmed" && new Date(r.ends_at).getTime() > now;
            return `
              <tr>
                <td>${escapeHtml(r.resource.name)}</td>
                <td>${formatRange(r.starts_at, r.ends_at)}</td>
                <td>${escapeHtml(r.user.name)}</td>
                <td><span class="pill pill-${r.status}">${r.status}</span></td>
                <td>${escapeHtml(r.notes || "")}</td>
                <td>${cancellable ? `<button type="button" class="btn btn-ghost btn-danger" data-cancel="${r.id}">Cancel</button>` : ""}</td>
              </tr>`;
          }).join("")
        : '<tr><td colspan="6" class="muted">No reservations yet. Pick a resource above to book one.</td></tr>';
      renderPager($("reservation-pager"), meta, loadReservations);
    } catch (error) {
      rows.innerHTML = `<tr><td colspan="6" class="form-error">${escapeHtml(error.message)}</td></tr>`;
    }
  }

  async function cancelReservation(id) {
    try {
      await api(`/api/v1/reservations/${id}/cancel`, { method: "PATCH" });
      toast("Reservation cancelled.", "success");
      loadReservations();
      loadAvailability();
    } catch (error) {
      toast(error.fullMessage, "error");
    }
  }

  // ---- Admin --------------------------------------------------------------

  async function submitResource(form) {
    showError("resource-error", "");
    const body = Object.fromEntries(new FormData(form));
    body.capacity = body.capacity ? Number(body.capacity) : null;
    try {
      const { data } = await api("/api/v1/resources", { method: "POST", body: { resource: body } });
      form.reset();
      toast(`Created "${data.name}".`, "success");
      loadResources(1);
    } catch (error) {
      showError("resource-error", error.fullMessage);
    }
  }

  // ---- Health -------------------------------------------------------------

  async function checkHealth() {
    const pill = $("api-status");
    try {
      await api("/api/v1/health", { auth: false });
      pill.textContent = "API online";
      pill.className = "pill pill-confirmed";
    } catch {
      pill.textContent = "API waking up…";
      pill.className = "pill pill-cancelled";
      setTimeout(checkHealth, 5000); // free hosting tiers sleep when idle
    }
  }

  // ---- Wiring -------------------------------------------------------------

  function init() {
    $("api-url").textContent = API;
    $("availability-date").min = todayUtc();

    $("auth-form").addEventListener("submit", (event) => {
      event.preventDefault();
      const form = event.currentTarget;
      const credentials = { email: form.email.value, password: form.password.value };
      if (state.registering) credentials.name = form.name.value;
      submitAuth(credentials);
    });
    $("auth-toggle").addEventListener("click", () => setAuthMode(!state.registering));
    $("demo-login-btn").addEventListener("click", () => { setAuthMode(false); submitAuth(DEMO); });
    $("logout-btn").addEventListener("click", () => { logout(); toast("Logged out."); });

    let searchTimer;
    $("resource-filters").addEventListener("input", () => {
      clearTimeout(searchTimer);
      searchTimer = setTimeout(() => loadResources(1), 250);
    });
    $("resource-filters").addEventListener("submit", (event) => event.preventDefault());
    $("resource-list").addEventListener("click", (event) => {
      const button = event.target.closest("[data-id]");
      if (button) selectResource($("resource-list")._resources[button.dataset.id]);
    });

    $("availability-date").addEventListener("change", loadAvailability);
    $("booking-form").addEventListener("submit", (event) => { event.preventDefault(); submitBooking(event.currentTarget); });

    $("reservation-status").addEventListener("change", () => loadReservations(1));
    $("reservation-rows").addEventListener("click", (event) => {
      const button = event.target.closest("[data-cancel]");
      if (button && confirm("Cancel this reservation?")) cancelReservation(button.dataset.cancel);
    });

    $("resource-form").addEventListener("submit", (event) => { event.preventDefault(); submitResource(event.currentTarget); });

    checkHealth();
    renderSession();
  }

  init();
})();
