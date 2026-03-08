// background.js - Service Worker voor FileFlower Chrome Extension
// Ontvangt metadata van content scripts en koppelt aan downloads

// Mac app endpoint (moet matchen met JobServer port)
const APP_ENDPOINT = 'http://127.0.0.1:17890/stock-metadata';

// Cache voor metadata per tab
const metadataCache = new Map();

// ============================================================================
// SEND TO MAC APP - Direct versturen naar Mac app
// ============================================================================

async function sendToMacApp(metadata, downloadInfo = null) {
  const payload = {
    // Download info (optioneel)
    downloadId: downloadInfo?.id || null,
    downloadUrl: downloadInfo?.url || metadata?.downloadUrl || null,
    finalUrl: downloadInfo?.finalUrl || metadata?.finalUrl || null,
    filename: downloadInfo?.filename || metadata?.filename || null,
    fileSize: downloadInfo?.fileSize || null,
    startTime: downloadInfo?.startTime || null,
    
    // Metadata van content script
    provider: metadata?.provider || (downloadInfo ? detectProviderFromUrl(downloadInfo.url) : 'unknown'),
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
    
    // Meta info - gebruik Boolean() om zeker te zijn dat het een boolean is
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
      
      // DIRECT naar Mac app sturen - niet wachten op download event
      // Dit is belangrijk voor Arc Browser en andere Chromium forks
      // waar chrome.downloads.onCreated niet altijd werkt
      sendToMacApp(enrichedMetadata).then(result => {
        console.log('[FileFlower] Immediate send result:', result.success ? 'success' : 'failed');
      });
      
      sendResponse({ ok: true, cached: true, sentToApp: true });
    } else {
      sendResponse({ ok: false, error: 'No metadata provided' });
    }
    
    return true; // Keep message channel open for async response
  }
});

// ============================================================================
// DOWNLOAD DETECTION - Koppel downloads aan metadata (backup voor normale Chrome)
// ============================================================================

chrome.downloads.onCreated.addListener(async (downloadItem) => {
  console.log('[FileFlower] Download started:', downloadItem);
  
  // Check of dit een audio file is
  const filename = downloadItem.filename || downloadItem.finalUrl || '';
  const isAudioFile = /\.(wav|mp3|aiff|aac|m4a|flac|ogg)(\?|$)/i.test(filename) ||
                      /\.(wav|mp3|aiff|aac|m4a|flac|ogg)(\?|$)/i.test(downloadItem.url);
  
  if (!isAudioFile) {
    console.log('[FileFlower] Not an audio file, skipping');
    return;
  }
  
  // Zoek matching metadata
  let metadata = null;
  
  // Probeer eerst de metadata van de actieve tab
  const tabs = await chrome.tabs.query({ active: true, currentWindow: true });
  const activeTabId = tabs[0]?.id;
  
  if (activeTabId && metadataCache.has(activeTabId)) {
    metadata = metadataCache.get(activeTabId);
    console.log('[FileFlower] Found metadata from active tab:', metadata);
  }
  
  // Fallback: zoek recente metadata (binnen 30 seconden)
  if (!metadata) {
    const now = Date.now();
    for (const [tabId, cached] of metadataCache.entries()) {
      if (now - cached.receivedAt < 30000) {
        metadata = cached;
        console.log('[FileFlower] Found recent metadata from tab', tabId);
        break;
      }
    }
  }
  
  // Stuur naar Mac app met download info (dit stuurt meer complete data)
  // Metadata werd al eerder gestuurd, maar nu hebben we ook download URL/filename
  const result = await sendToMacApp(metadata, downloadItem);
  
  // Clear used metadata als succesvol
  if (result.success && metadata?.tabId) {
    metadataCache.delete(metadata.tabId);
  }
});

// ============================================================================
// HELPER FUNCTIONS
// ============================================================================

function detectProviderFromUrl(url) {
  if (!url) return 'unknown';
  
  const lower = url.toLowerCase();
  
  // Artlist
  if (lower.includes('artlist.io') || lower.includes('cms-artifacts.artlist')) return 'artlist';
  
  // Epidemic Sound
  if (lower.includes('epidemicsound.com') || lower.includes('audiocdn.epidemicsound')) return 'epidemic';
  
  // AudioJungle (Envato)
  if (lower.includes('audiojungle.net') || lower.includes('envato.com') || lower.includes('audiojungle')) return 'audiojungle';
  
  // Motion Array
  if (lower.includes('motionarray.com')) return 'motionarray';
  
  // PremiumBeat
  if (lower.includes('premiumbeat.com')) return 'premiumbeat';
  
  // Pond5
  if (lower.includes('pond5.com')) return 'pond5';
  
  // Storyblocks
  if (lower.includes('storyblocks.com') || lower.includes('audioblocks.com')) return 'storyblocks';
  
  // Shutterstock
  if (lower.includes('shutterstock.com')) return 'shutterstock';
  
  // Soundstripe
  if (lower.includes('soundstripe.com')) return 'soundstripe';
  
  // Uppbeat
  if (lower.includes('uppbeat.io')) return 'uppbeat';
  
  // BMG Production Music
  if (lower.includes('bmgproductionmusic.com') || lower.includes('bmgpm.com')) return 'bmg';
  
  // Universal Production Music
  if (lower.includes('universalproductionmusic.com') || lower.includes('upm.com')) return 'universal';
  
  // Musicbed
  if (lower.includes('musicbed.com')) return 'musicbed';
  
  // Adobe Stock
  if (lower.includes('stock.adobe.com') || lower.includes('adobe.com/stock')) return 'adobestock';
  
  // Freesound
  if (lower.includes('freesound.org')) return 'freesound';
  
  // YouTube Audio Library
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

console.log('[FileFlower] Background service worker loaded');
console.log('[FileFlower] Will send metadata to:', APP_ENDPOINT);




