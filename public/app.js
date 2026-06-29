const PROJECT_ID = "spatialverify-census";
const STORAGE_BUCKET = "spatialverify-census.firebasestorage.app";
const RELEASE_DOC =
  `https://firestore.googleapis.com/v1/projects/${PROJECT_ID}` +
  `/databases/(default)/documents/system/android_release`;

const statusEl = document.getElementById("release-status");
const downloadBtn = document.getElementById("download-btn");
const metaEl = document.getElementById("release-meta");
const notesEl = document.getElementById("release-notes");

function fieldString(fields, key) {
  return fields?.[key]?.stringValue ?? "";
}

function fieldInt(fields, key) {
  const value = fields?.[key]?.integerValue ?? fields?.[key]?.stringValue;
  const parsed = Number.parseInt(value ?? "", 10);
  return Number.isFinite(parsed) ? parsed : 0;
}

function fieldTimestamp(fields, key) {
  const raw = fields?.[key]?.timestampValue;
  if (!raw) return null;
  const date = new Date(raw);
  return Number.isNaN(date.getTime()) ? null : date;
}

function storageDownloadUrl(storagePath) {
  const encoded = encodeURIComponent(storagePath);
  return `https://firebasestorage.googleapis.com/v0/b/${STORAGE_BUCKET}/o/${encoded}?alt=media`;
}

function formatPublished(date) {
  if (!date) return "—";
  return new Intl.DateTimeFormat(undefined, {
    dateStyle: "medium",
    timeStyle: "short",
  }).format(date);
}

function showError(message) {
  statusEl.classList.add("error");
  statusEl.innerHTML = message;
}

async function loadLatestRelease() {
  try {
    const response = await fetch(RELEASE_DOC);
    if (response.status === 404) {
      showError("No Android release has been published yet.");
      return;
    }
    if (!response.ok) {
      throw new Error(`Release lookup failed (${response.status})`);
    }

    const payload = await response.json();
    const fields = payload.fields ?? {};
    const versionName = fieldString(fields, "versionName") || "Unknown";
    const buildNumber = fieldInt(fields, "buildNumber");
    const apkStoragePath = fieldString(fields, "apkStoragePath");
    const releaseNotes = fieldString(fields, "releaseNotes");
    const publishedAt = fieldTimestamp(fields, "publishedAt");

    if (!apkStoragePath) {
      showError("Release metadata is missing an APK path.");
      return;
    }

    const downloadUrl = storageDownloadUrl(apkStoragePath);
    const fileName = apkStoragePath.split("/").pop() || "spatialverify.apk";

    statusEl.classList.add("hidden");
    downloadBtn.classList.remove("hidden");
    downloadBtn.href = downloadUrl;
    downloadBtn.download = fileName;
    downloadBtn.textContent = `Download ${versionName} (${buildNumber})`;

    document.getElementById("meta-version").textContent = versionName;
    document.getElementById("meta-build").textContent = String(buildNumber);
    document.getElementById("meta-published").textContent = formatPublished(publishedAt);
    metaEl.classList.remove("hidden");

    if (releaseNotes.trim()) {
      notesEl.textContent = releaseNotes.trim();
      notesEl.classList.remove("hidden");
    }
  } catch (error) {
    console.error(error);
    showError("Could not load the latest release. Try again in a moment.");
  }
}

loadLatestRelease();
