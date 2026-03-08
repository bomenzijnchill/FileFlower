// popup.js - UI logic voor de extensie popup

const APP_HEALTH_ENDPOINT = 'http://127.0.0.1:17890/health';
const APP_METADATA_ENDPOINT = 'http://127.0.0.1:17890/stock-metadata';

let currentMetadata = null;
let isConnected = false;

async function checkConnection() {
  const statusDot = document.getElementById('statusDot');
  const statusText = document.getElementById('statusText');
  
  try {
    const response = await fetch(APP_HEALTH_ENDPOINT, {
      method: 'GET',
      signal: AbortSignal.timeout(2000)
    });
    
    if (response.ok) {
      statusDot.className = 'status-dot connected';
      statusText.textContent = 'Verbonden met FileFlower';
      isConnected = true;
    } else {
      statusDot.className = 'status-dot disconnected';
      statusText.textContent = 'App niet bereikbaar';
      isConnected = false;
    }
  } catch (error) {
    statusDot.className = 'status-dot disconnected';
    statusText.textContent = 'FileFlower niet actief';
    isConnected = false;
  }
  
  updateProcessButton();
}

async function loadLatestMetadata() {
  const metadataContent = document.getElementById('metadataContent');
  
  // Get current tab
  const tabs = await chrome.tabs.query({ active: true, currentWindow: true });
  const currentTab = tabs[0];
  
  if (!currentTab) {
    metadataContent.innerHTML = '<span class="no-metadata">Geen actieve tab</span>';
    currentMetadata = null;
    updateProcessButton();
    return;
  }
  
  // Check if we're on a supported site
  const host = new URL(currentTab.url).host.toLowerCase();
  const isSupported = host.includes('artlist.io') || host.includes('epidemicsound.com');
  
  if (!isSupported) {
    metadataContent.innerHTML = '<span class="no-metadata">Niet op een ondersteunde site</span>';
    currentMetadata = null;
    updateProcessButton();
    return;
  }
  
  // Try to get metadata from the content script
  try {
    chrome.tabs.sendMessage(currentTab.id, { type: 'GET_METADATA' }, (response) => {
      if (chrome.runtime.lastError || !response?.metadata) {
        metadataContent.innerHTML = '<span class="no-metadata">Navigeer naar een track pagina</span>';
        currentMetadata = null;
        updateProcessButton();
        return;
      }
      
      const meta = response.metadata;
      currentMetadata = meta;
      let html = '';
      
      if (meta.title) {
        html += `<div class="metadata-item"><span class="metadata-label">Titel:</span> <span class="metadata-value">${escapeHtml(meta.title)}</span></div>`;
      }
      
      if (meta.artists?.length > 0) {
        html += `<div class="metadata-item"><span class="metadata-label">Artist:</span> <span class="metadata-value">${escapeHtml(meta.artists.join(', '))}</span></div>`;
      }
      
      if (meta.genres?.length > 0) {
        html += `<div class="metadata-item"><span class="metadata-label">Genre:</span> <span class="metadata-value">${escapeHtml(meta.genres.join(', '))}</span></div>`;
      }
      
      if (meta.moods?.length > 0) {
        html += `<div class="metadata-item"><span class="metadata-label">Mood:</span> <span class="metadata-value">${escapeHtml(meta.moods.join(', '))}</span></div>`;
      }
      
      if (meta.bpm) {
        html += `<div class="metadata-item"><span class="metadata-label">BPM:</span> <span class="metadata-value">${meta.bpm}</span></div>`;
      }
      
      metadataContent.innerHTML = html || '<span class="no-metadata">Geen metadata gevonden</span>';
      updateProcessButton();
    });
  } catch (error) {
    metadataContent.innerHTML = '<span class="no-metadata">Kan metadata niet ophalen</span>';
    currentMetadata = null;
    updateProcessButton();
  }
}

function updateProcessButton() {
  const processBtn = document.getElementById('processBtn');
  const hasValidMetadata = currentMetadata && (currentMetadata.title || currentMetadata.genres?.length > 0);
  
  processBtn.disabled = !isConnected || !hasValidMetadata;
  
  if (!isConnected) {
    processBtn.textContent = 'App niet verbonden';
  } else if (!hasValidMetadata) {
    processBtn.textContent = 'Geen metadata beschikbaar';
  } else {
    processBtn.textContent = 'Verwerk metadata';
  }
}

async function processMetadata() {
  const processBtn = document.getElementById('processBtn');
  
  if (!currentMetadata || !isConnected) return;
  
  processBtn.disabled = true;
  processBtn.textContent = 'Verzenden...';
  
  // Bouw payload
  const payload = {
    downloadId: null,
    downloadUrl: null,
    finalUrl: null,
    filename: null,
    fileSize: null,
    startTime: new Date().toISOString(),
    
    provider: currentMetadata.provider || 'unknown',
    pageUrl: currentMetadata.pageUrl || null,
    title: currentMetadata.title || null,
    artists: currentMetadata.artists || [],
    genres: currentMetadata.genres || [],
    moods: currentMetadata.moods || [],
    instruments: currentMetadata.instruments || [],
    videoThemes: currentMetadata.videoThemes || [],
    tags: currentMetadata.tags || [],
    bpm: currentMetadata.bpm || null,
    duration: currentMetadata.duration || null,
    album: currentMetadata.album || null,
    energy: currentMetadata.energy || null,
    
    hasRichMetadata: true,
    scrapedAt: currentMetadata.scrapedAt || null,
    sentAt: new Date().toISOString(),
    manualSend: true
  };
  
  try {
    const response = await fetch(APP_METADATA_ENDPOINT, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json'
      },
      body: JSON.stringify(payload)
    });
    
    if (response.ok) {
      processBtn.textContent = 'Verzonden!';
      processBtn.className = 'process-btn success';
      
      // Sluit popup na korte vertraging
      setTimeout(() => {
        window.close();
      }, 500);
    } else {
      processBtn.textContent = 'Fout bij verzenden';
      processBtn.className = 'process-btn error';
      
      setTimeout(() => {
        processBtn.className = 'process-btn';
        updateProcessButton();
      }, 2000);
    }
  } catch (error) {
    console.error('Error sending metadata:', error);
    processBtn.textContent = 'Verbinding mislukt';
    processBtn.className = 'process-btn error';
    
    setTimeout(() => {
      processBtn.className = 'process-btn';
      updateProcessButton();
    }, 2000);
  }
}

function escapeHtml(text) {
  const div = document.createElement('div');
  div.textContent = text;
  return div.innerHTML;
}

// Initialize
document.addEventListener('DOMContentLoaded', () => {
  checkConnection();
  loadLatestMetadata();
  
  // Process button click handler
  document.getElementById('processBtn').addEventListener('click', processMetadata);
});




