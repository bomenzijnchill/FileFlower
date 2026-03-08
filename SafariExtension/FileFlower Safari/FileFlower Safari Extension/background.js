// background.js - Service Worker voor FileFlower Safari Extension
// Ontvangt metadata van content scripts en stuurt naar Mac app

// Mac app endpoint (moet matchen met JobServer port)
const APP_ENDPOINT = 'http://127.0.0.1:17890/stock-metadata';

// Cache voor metadata per tab
const metadataCache = new Map();

// ============================================================================
// SEND TO MAC APP - Direct versturen naar Mac app
// ============================================================================

async function sendToMacApp(metadata) {
  const payload = {
    // Download info (niet beschikbaar in Safari - downloads API niet ondersteund)
    downloadId: null,
    downloadUrl: metadata?.downloadUrl || null,
    finalUrl: metadata?.finalUrl || null,
    filename: metadata?.filename || null,
    fileSize: null,
    startTime: null,

    // Metadata van content script
    provider: metadata?.provider || 'unknown',
    pageUrl: metadata?.pageUrl || null,
    title: metadata?.title || null,
    artists: metadata?.artists || [],
    genres: metadata?.genres || [],
    moods: metadata?.moods || [],
    instruments: metadata?.instruments || [],
    videoThemes: metadata?.videoThemes || [],
    tags: metadata?.tags || [],
    keywords: metadata?.keywords || [],
    bpm: metadata?.bpm || null,
    tempo: metadata?.tempo || null,
    duration: metadata?.duration || null,
    album: metadata?.album || null,
    energy: metadata?.energy || null,

    // Meta info
    hasRichMetadata: Boolean(metadata && (metadata.title || (metadata.genres && metadata.genres.length > 0) || (metadata.moods && metadata.moods.length > 0))),
    scrapedAt: metadata?.scrapedAt || null,
    sentAt: new Date().toISOString()
  };

  console.log('[FileFlower] Sending payload to Mac app:', payload);

  try {
    const response = await fetch(APP_ENDPOINT, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json'
      },
      body: JSON.stringify(payload)
    });

    if (response.ok) {
      const result = await response.json();
      console.log('[FileFlower] Mac app response:', result);
      return { success: true, result };
    } else {
      const errorText = await response.text();
      console.error('[FileFlower] Mac app error:', response.status, errorText);
      return { success: false, error: errorText };
    }
  } catch (error) {
    console.error('[FileFlower] Failed to send to Mac app:', error.message);
    // App is waarschijnlijk niet actief - dit is OK
    return { success: false, error: error.message };
  }
}

// ============================================================================
// MESSAGE HANDLING - Ontvang metadata van content scripts
// ============================================================================

chrome.runtime.onMessage.addListener((message, sender, sendResponse) => {
  if (message.type === 'TRACK_METADATA') {
    const tabId = sender.tab?.id;

    if (message.metadata) {
      // Sla metadata op met tabId als key
      const enrichedMetadata = {
        ...message.metadata,
        tabId,
        receivedAt: Date.now()
      };
      metadataCache.set(tabId, enrichedMetadata);

      console.log('[FileFlower] Received metadata from tab', tabId, message.metadata);

      // Direct naar Mac app sturen
      sendToMacApp(enrichedMetadata).then(result => {
        console.log('[FileFlower] Send result:', result.success ? 'success' : 'failed');
      });

      sendResponse({ ok: true, cached: true, sentToApp: true });
    } else {
      sendResponse({ ok: false, error: 'No metadata provided' });
    }

    return true; // Keep message channel open for async response
  }
});

// ============================================================================
// HELPER FUNCTIONS
// ============================================================================

function detectProviderFromUrl(url) {
  if (!url) return 'unknown';

  const lower = url.toLowerCase();

  if (lower.includes('artlist.io') || lower.includes('cms-artifacts.artlist')) return 'artlist';
  if (lower.includes('epidemicsound.com') || lower.includes('audiocdn.epidemicsound')) return 'epidemic';
  if (lower.includes('audiojungle.net') || lower.includes('envato.com') || lower.includes('audiojungle')) return 'audiojungle';
  if (lower.includes('motionarray.com')) return 'motionarray';
  if (lower.includes('premiumbeat.com')) return 'premiumbeat';
  if (lower.includes('pond5.com')) return 'pond5';
  if (lower.includes('storyblocks.com') || lower.includes('audioblocks.com')) return 'storyblocks';
  if (lower.includes('shutterstock.com')) return 'shutterstock';
  if (lower.includes('soundstripe.com')) return 'soundstripe';
  if (lower.includes('uppbeat.io')) return 'uppbeat';
  if (lower.includes('bmgproductionmusic.com') || lower.includes('bmgpm.com')) return 'bmg';
  if (lower.includes('universalproductionmusic.com') || lower.includes('upm.com')) return 'universal';
  if (lower.includes('musicbed.com')) return 'musicbed';
  if (lower.includes('stock.adobe.com') || lower.includes('adobe.com/stock')) return 'adobestock';
  if (lower.includes('freesound.org')) return 'freesound';
  if (lower.includes('youtube.com/audiolibrary') || lower.includes('studio.youtube.com')) return 'youtube';

  return 'unknown';
}

// ============================================================================
// CLEANUP - Verwijder oude cache entries
// ============================================================================

setInterval(() => {
  const now = Date.now();
  const maxAge = 5 * 60 * 1000; // 5 minuten

  for (const [tabId, cached] of metadataCache.entries()) {
    if (now - cached.receivedAt > maxAge) {
      metadataCache.delete(tabId);
      console.log('[FileFlower] Cleaned up old metadata for tab', tabId);
    }
  }
}, 60000); // Check elke minuut

// ============================================================================
// INITIALIZATION
// ============================================================================

console.log('[FileFlower] Safari background service worker loaded');
console.log('[FileFlower] Will send metadata to:', APP_ENDPOINT);
