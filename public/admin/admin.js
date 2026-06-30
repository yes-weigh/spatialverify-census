const API_BASE = "/api/admin";
const TOKEN_KEY = "sv_admin_token";

let currentStatus = "PENDING";
let selectedPaymentId = null;

const loginView = document.getElementById("login-view");
const dashboardView = document.getElementById("dashboard-view");
const loginForm = document.getElementById("login-form");
const loginError = document.getElementById("login-error");
const statsEl = document.getElementById("stats");
const paymentsList = document.getElementById("payments-list");
const paymentDialog = document.getElementById("payment-dialog");
const paymentDetail = document.getElementById("payment-detail");

function token() {
  return sessionStorage.getItem(TOKEN_KEY);
}

function setToken(value) {
  if (value) sessionStorage.setItem(TOKEN_KEY, value);
  else sessionStorage.removeItem(TOKEN_KEY);
}

async function api(path, options = {}) {
  const headers = { "Content-Type": "application/json", ...(options.headers || {}) };
  const t = token();
  if (t) headers.Authorization = `Bearer ${t}`;

  const response = await fetch(`${API_BASE}${path}`, { ...options, headers });
  if (response.status === 401) {
    logout();
    throw new Error("Session expired");
  }
  const payload = await response.json().catch(() => ({}));
  if (!response.ok) {
    throw new Error(payload.error || `Request failed (${response.status})`);
  }
  return payload;
}

function logout() {
  setToken(null);
  dashboardView.classList.add("hidden");
  loginView.classList.remove("hidden");
}

function formatMoney(amount) {
  return `₹${Number(amount || 0).toLocaleString("en-IN")}`;
}

function formatDate(value) {
  if (!value) return "—";
  const date = value._seconds
    ? new Date(value._seconds * 1000)
    : new Date(value);
  return date.toLocaleString();
}

function renderStats(stats) {
  statsEl.innerHTML = `
    <div class="stat-card"><span class="muted">Pending</span><strong>${stats.pending}</strong></div>
    <div class="stat-card"><span class="muted">Approved</span><strong>${stats.approved}</strong></div>
    <div class="stat-card"><span class="muted">Rejected</span><strong>${stats.rejected}</strong></div>
    <div class="stat-card"><span class="muted">Users</span><strong>${stats.users}</strong></div>
    <div class="stat-card"><span class="muted">Revenue</span><strong>${formatMoney(stats.revenue)}</strong></div>
    <div class="stat-card"><span class="muted">Expired licenses</span><strong>${stats.expired}</strong></div>
  `;
}

function renderPayments(items) {
  if (!items.length) {
    paymentsList.innerHTML = `<p class="muted">No ${currentStatus.toLowerCase()} payments.</p>`;
    return;
  }

  paymentsList.innerHTML = items
    .map(
      (p) => `
      <article class="payment-card">
        <div>
          <h3>${p.email || p.uid}</h3>
          <p>${formatMoney(p.amount)} · ${p.creditsRequested} credits · ${p.reference || "—"}</p>
          <p>${formatDate(p.createdAt)} · ${p.upiTransactionId || "No txn ID"}</p>
        </div>
        <button class="btn ghost" data-id="${p.id}">View</button>
      </article>
    `,
    )
    .join("");

  paymentsList.querySelectorAll("button[data-id]").forEach((btn) => {
    btn.addEventListener("click", () => openPayment(btn.dataset.id));
  });
}

async function loadDashboard() {
  const [stats, payments] = await Promise.all([
    api("/stats"),
    api(`/payments?status=${currentStatus}`),
  ]);
  renderStats(stats);
  renderPayments(payments.items || []);
}

async function openPayment(id) {
  selectedPaymentId = id;
  const payment = await api(`/payments/${id}`);
  paymentDetail.innerHTML = `
    <div class="detail-grid">
      <div><span>User</span><strong>${payment.email || payment.uid}</strong></div>
      <div><span>Amount</span><strong>${formatMoney(payment.amount)}</strong></div>
      <div><span>Credits requested</span><strong>${payment.creditsRequested}</strong></div>
      <div><span>Reference</span><strong>${payment.reference || "—"}</strong></div>
      <div><span>UPI Txn ID</span><strong>${payment.upiTransactionId || "—"}</strong></div>
      <div><span>Status</span><strong>${payment.status}</strong></div>
      <div><span>App version</span><strong>${payment.appVersion || "—"}</strong></div>
    </div>
    ${
      payment.screenshotUrl
        ? `<img class="screenshot" src="${payment.screenshotUrl}" alt="Payment screenshot">`
        : "<p class='muted'>No screenshot uploaded.</p>"
    }
  `;
  document.getElementById("custom-credits").value = "";
  paymentDialog.showModal();
}

loginForm.addEventListener("submit", async (event) => {
  event.preventDefault();
  loginError.classList.add("hidden");
  try {
    const username = document.getElementById("username").value.trim();
    const password = document.getElementById("password").value;
    const result = await api("/login", {
      method: "POST",
      body: JSON.stringify({ username, password }),
    });
    setToken(result.token);
    loginView.classList.add("hidden");
    dashboardView.classList.remove("hidden");
    await loadDashboard();
  } catch (error) {
    loginError.textContent = error.message;
    loginError.classList.remove("hidden");
  }
});

document.getElementById("logout-btn").addEventListener("click", logout);
document.getElementById("close-dialog").addEventListener("click", () => paymentDialog.close());

document.querySelectorAll(".tab").forEach((tab) => {
  tab.addEventListener("click", async () => {
    document.querySelectorAll(".tab").forEach((t) => t.classList.remove("active"));
    tab.classList.add("active");
    currentStatus = tab.dataset.status;
    await loadDashboard();
  });
});

document.getElementById("approve-btn").addEventListener("click", async () => {
  if (!selectedPaymentId) return;
  const custom = document.getElementById("custom-credits").value;
  const body = custom ? { customCredits: Number(custom) } : {};
  await api(`/payments/${selectedPaymentId}/approve`, {
    method: "POST",
    body: JSON.stringify(body),
  });
  paymentDialog.close();
  await loadDashboard();
});

document.getElementById("reject-btn").addEventListener("click", async () => {
  if (!selectedPaymentId) return;
  const reason = prompt("Rejection reason (optional)") || "";
  await api(`/payments/${selectedPaymentId}/reject`, {
    method: "POST",
    body: JSON.stringify({ reason }),
  });
  paymentDialog.close();
  await loadDashboard();
});

if (token()) {
  loginView.classList.add("hidden");
  dashboardView.classList.remove("hidden");
  loadDashboard().catch(logout);
}
