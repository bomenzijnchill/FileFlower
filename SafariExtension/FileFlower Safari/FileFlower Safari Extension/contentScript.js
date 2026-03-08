// contentScript.js - DOM scraper voor stock muziek websites
// Scrapt metadata van tracks en stuurt het naar de background service worker

let lastMetadata = null;
let isInitialized = false;

// ============================================================================
// URL FILTER PARSER - Haal genre/mood/theme uit URL parameters
// ============================================================================

/**
 * Parse de Artlist URL voor actieve filters
 * URL formaat: ?includedIds=57,123,456 of ?includedIds=57
 */
function parseArtlistUrlFilters() {
  const url = new URL(window.location.href);
  const includedIds = url.searchParams.get('includedIds');
  
  if (!includedIds) {
    return { genres: [], moods: [], themes: [], instruments: [] };
  }
  
  const ids = includedIds.split(',').map(id => parseInt(id.trim(), 10)).filter(id => !isNaN(id));
  console.log('[FileFlower] URL filter IDs:', ids);
  
  // We kunnen de IDs niet direct mappen, maar we kunnen kijken naar
  // de actieve filter chips/tags in de UI
  return { filterIds: ids };
}

/**
 * Haal de actieve filter namen uit de DOM
 * Artlist toont de actieve filters vaak als chips/tags bovenaan
 */
function getActiveFiltersFromDOM() {
  const genres = [];
  const moods = [];
  const themes = [];
  const instruments = [];
  
  // Zoek naar actieve filter elementen
  // Dit zijn vaak chips/tags met een "selected" of "active" state
  const filterSelectors = [
    // Actieve filter chips
    '[class*="filter"][class*="active"]',
    '[class*="chip"][class*="selected"]',
    '[class*="tag"][class*="active"]',
    '[class*="selected"][class*="filter"]',
    // Filter sidebar items die geselecteerd zijn
    '[aria-selected="true"]',
    '[data-selected="true"]',
    // Breadcrumb-achtige filter indicators
    '[class*="breadcrumb"] a',
    '[class*="active-filter"]',
    // Remove/clear buttons bij actieve filters (de tekst ernaast is de filter naam)
    '[class*="remove"][class*="filter"]',
    'button[aria-label*="remove"]'
  ];
  
  for (const selector of filterSelectors) {
    const elements = document.querySelectorAll(selector);
    elements.forEach(el => {
      // Zoek de filter naam - kan in het element zelf zijn of in een sibling
      let filterName = el.innerText?.trim();
      
      // Als het een remove button is, zoek de naam in de parent
      if (!filterName || filterName.length < 2 || filterName.toLowerCase().includes('remove')) {
        const parent = el.closest('[class*="filter"], [class*="chip"], [class*="tag"]');
        if (parent) {
          filterName = parent.innerText?.replace(/[×✕✖]/g, '').trim();
        }
      }
      
      if (!filterName || filterName.length < 2 || filterName.length > 50) return;
      
      // Categoriseer de filter (basis heuristiek)
      const lowerName = filterName.toLowerCase();
      
      // Check parent/ancestor classes voor categorie hint
      const ancestors = [];
      let node = el;
      for (let i = 0; i < 5 && node; i++) {
        ancestors.push(node.className?.toLowerCase() || '');
        node = node.parentElement;
      }
      const ancestorClasses = ancestors.join(' ');
      
      if (ancestorClasses.includes('genre') || ancestorClasses.includes('style')) {
        if (!genres.includes(filterName)) genres.push(filterName);
      } else if (ancestorClasses.includes('mood') || ancestorClasses.includes('vibe')) {
        if (!moods.includes(filterName)) moods.push(filterName);
      } else if (ancestorClasses.includes('theme') || ancestorClasses.includes('video')) {
        if (!themes.includes(filterName)) themes.push(filterName);
      } else if (ancestorClasses.includes('instrument')) {
        if (!instruments.includes(filterName)) instruments.push(filterName);
      }
    });
  }
  
  console.log('[FileFlower] Active filters from DOM - Genres:', genres, 'Moods:', moods, 'Themes:', themes);
  
  return { genres, moods, themes, instruments };
}

/**
 * Zoek filter namen in de pagina die overeenkomen met de URL
 * Door te kijken naar welke filters "aan" staan in de sidebar/header
 */
function getFiltersFromSidebar() {
  const genres = [];
  const moods = [];
  const themes = [];
  const instruments = [];
  
  // Artlist heeft vaak een sidebar met filter categorieën
  // Zoek naar secties met headings en geselecteerde items
  
  // Methode 1: Zoek naar filter secties met selected/checked items
  const filterSections = document.querySelectorAll('[class*="filter"], [class*="sidebar"], [class*="facet"]');
  
  filterSections.forEach(section => {
    const heading = section.querySelector('h2, h3, h4, [class*="title"], [class*="heading"]');
    const headingText = heading?.innerText?.toLowerCase() || '';
    
    // Vind geselecteerde items in deze sectie
    const selectedItems = section.querySelectorAll('[class*="selected"], [class*="active"], [class*="checked"], input:checked + label, [aria-checked="true"]');
    
    selectedItems.forEach(item => {
      const name = item.innerText?.trim() || item.getAttribute('aria-label')?.trim();
      if (!name || name.length < 2 || name.length > 50) return;
      
      if (headingText.includes('genre') || headingText.includes('style')) {
        if (!genres.includes(name)) genres.push(name);
      } else if (headingText.includes('mood') || headingText.includes('vibe') || headingText.includes('feel')) {
        if (!moods.includes(name)) moods.push(name);
      } else if (headingText.includes('theme') || headingText.includes('video')) {
        if (!themes.includes(name)) themes.push(name);
      } else if (headingText.includes('instrument')) {
        if (!instruments.includes(name)) instruments.push(name);
      }
    });
  });
  
  // Methode 2: Zoek naar "Applied Filters" of "Active Filters" sectie
  const appliedFilters = document.querySelector('[class*="applied"], [class*="active-filters"], [class*="current-filters"]');
  if (appliedFilters) {
    const filterChips = appliedFilters.querySelectorAll('a, button, span, [class*="chip"], [class*="tag"]');
    filterChips.forEach(chip => {
      const name = chip.innerText?.replace(/[×✕✖]/g, '').trim();
      if (name && name.length > 1 && name.length < 50) {
        // Zonder categorie info, voeg toe als genre (meest waarschijnlijk)
        if (!genres.includes(name) && !moods.includes(name)) {
          genres.push(name);
        }
      }
    });
  }
  
  return { genres, moods, themes, instruments };
}

/**
 * Artlist-specifieke filter detectie
 * Gebaseerd op Artlist's DOM structuur:
 * - data-testid="StickySearchContainer" - hoofdcontainer
 * - data-testid="TopFiltersNext" - filter sectie
 * - class="parent-cetegories-bar" - categorie bar (let op: typo in hun code)
 * - class="hidden self-stretch lg:mx-0 lg:flex" - actieve filters container
 */
function getArtlistActiveFilters() {
  const genres = [];
  const moods = [];
  const themes = [];
  const instruments = [];
  
  console.log('[FileFlower] Scanning Artlist filters...');
  
  // ========================================================================
  // METHODE 1: Zoek in de TopFiltersNext / StickySearchContainer
  // ========================================================================
  const filterContainers = document.querySelectorAll(
    '[data-testid="TopFiltersNext"], ' +
    '[data-testid="StickySearchContainer"], ' +
    '[class*="parent-cetegories"], ' +  // Let op: typo in Artlist code
    '[class*="parent-categories"], ' +
    '.hidden.self-stretch.lg\\:flex, ' +
    '[class*="self-stretch"][class*="lg:flex"]'
  );
  
  console.log('[FileFlower] Found filter containers:', filterContainers.length);
  
  filterContainers.forEach(container => {
    // Zoek naar alle klikbare filter elementen
    const filterElements = container.querySelectorAll('a, button, [role="button"], [class*="chip"], [class*="pill"], [class*="tag"], [class*="filter"]');
    
    filterElements.forEach(el => {
      // Check of dit element "actief" of "geselecteerd" lijkt
      const className = el.className?.toLowerCase() || '';
      const ariaSelected = el.getAttribute('aria-selected');
      const ariaPressed = el.getAttribute('aria-pressed');
      const dataActive = el.getAttribute('data-active');
      const text = el.innerText?.replace(/[×✕✖]/g, '').trim();
      
      // Check voor actieve/geselecteerde state
      const isActive = 
        className.includes('active') ||
        className.includes('selected') ||
        className.includes('current') ||
        className.includes('accent') ||  // Artlist gebruikt vaak accent kleuren voor actief
        className.includes('bg-accent') ||
        className.includes('text-accent') ||
        ariaSelected === 'true' ||
        ariaPressed === 'true' ||
        dataActive === 'true';
      
      if (isActive && text && text.length > 1 && text.length < 50) {
        console.log('[FileFlower] Found active filter:', text, 'class:', className.substring(0, 100));
        
        // Categoriseer op basis van context
        const href = el.getAttribute('href') || '';
        const parentText = el.closest('[class*="section"], [class*="group"], div')?.className?.toLowerCase() || '';
        
        if (href.includes('/genre') || parentText.includes('genre') || className.includes('genre')) {
          if (!genres.includes(text)) genres.push(text);
        } else if (href.includes('/mood') || parentText.includes('mood') || className.includes('mood')) {
          if (!moods.includes(text)) moods.push(text);
        } else if (href.includes('/theme') || parentText.includes('theme') || className.includes('theme')) {
          if (!themes.includes(text)) themes.push(text);
        } else if (href.includes('/instrument') || parentText.includes('instrument') || className.includes('instrument')) {
          if (!instruments.includes(text)) instruments.push(text);
        } else {
          // Onbekende categorie - voeg toe aan genres als default
          if (!genres.includes(text) && !moods.includes(text)) {
            genres.push(text);
          }
        }
      }
    });
  });
  
  // ========================================================================
  // METHODE 2: Zoek naar elementen met "close" of "remove" buttons (actieve filters)
  // ========================================================================
  const elementsWithClose = document.querySelectorAll('[class*="pill"], [class*="chip"], [class*="badge"]');
  elementsWithClose.forEach(el => {
    const hasClose = el.querySelector('svg, [class*="close"], [class*="remove"], [aria-label*="remove"]');
    if (hasClose) {
      const text = el.innerText?.replace(/[×✕✖]/g, '').trim();
      if (text && text.length > 1 && text.length < 50 && !genres.includes(text) && !moods.includes(text)) {
        console.log('[FileFlower] Found filter with close button:', text);
        genres.push(text);
      }
    }
  });
  
  // ========================================================================
  // METHODE 3: Zoek specifiek naar de categorie headings en hun geselecteerde items
  // ========================================================================
  const categoryHeadings = ['Genre', 'Mood', 'Video Theme', 'Instrument', 'Vocal'];
  
  categoryHeadings.forEach(category => {
    // Zoek de heading
    const headingEl = Array.from(document.querySelectorAll('h2, h3, h4, span, div'))
      .find(el => el.innerText?.trim().toLowerCase() === category.toLowerCase());
    
    if (headingEl) {
      // Zoek de parent sectie
      const section = headingEl.closest('[class*="section"], [class*="group"], [class*="accordion"], div[class*="mb-"], div[class*="mt-"]');
      if (section) {
        // Zoek naar geselecteerde/actieve items in deze sectie
        const activeItems = section.querySelectorAll('[class*="active"], [class*="selected"], [aria-selected="true"], [aria-pressed="true"]');
        activeItems.forEach(item => {
          const text = item.innerText?.trim();
          if (text && text.length > 1 && text.length < 50 && text !== category) {
            console.log(`[FileFlower] Found ${category}:`, text);
            
            switch (category.toLowerCase()) {
              case 'genre':
                if (!genres.includes(text)) genres.push(text);
                break;
              case 'mood':
                if (!moods.includes(text)) moods.push(text);
                break;
              case 'video theme':
                if (!themes.includes(text)) themes.push(text);
                break;
              case 'instrument':
              case 'vocal':
                if (!instruments.includes(text)) instruments.push(text);
                break;
            }
          }
        });
      }
    }
  });
  
  console.log('[FileFlower] Artlist filters detected - Genres:', genres, 'Moods:', moods, 'Themes:', themes, 'Instruments:', instruments);
  
  return { genres, moods, themes, instruments };
}

/**
 * Combineer alle filter bronnen
 */
function getAllActiveFilters() {
  const domFilters = getActiveFiltersFromDOM();
  const sidebarFilters = getFiltersFromSidebar();
  const artlistFilters = getArtlistActiveFilters();
  
  return {
    genres: [...new Set([...domFilters.genres, ...sidebarFilters.genres, ...artlistFilters.genres])],
    moods: [...new Set([...domFilters.moods, ...sidebarFilters.moods, ...artlistFilters.moods])],
    themes: [...new Set([...domFilters.themes, ...sidebarFilters.themes, ...artlistFilters.themes])],
    instruments: [...new Set([...domFilters.instruments, ...sidebarFilters.instruments, ...artlistFilters.instruments])]
  };
}

// ============================================================================
// ARTLIST SCRAPER - ZOEKRESULTATEN PAGINA
// ============================================================================

/**
 * Scrape metadata van een specifieke track card/row element
 * Dit wordt aangeroepen wanneer de gebruiker op een download knop klikt
 */
function scrapeArtlistTrackFromElement(trackElement) {
  try {
    console.log('[FileFlower] Scraping specific track element...');
    
    // Zoek de parent container die alle track info bevat
    // Artlist gebruikt vaak een row/card structuur
    let container = trackElement;
    
    // Loop omhoog tot we een track container vinden
    for (let i = 0; i < 10 && container; i++) {
      const tag = container.tagName?.toLowerCase();
      const className = container.className?.toLowerCase() || '';
      const role = container.getAttribute('role')?.toLowerCase() || '';
      
      // Check of dit een track container is
      if (className.includes('track') || 
          className.includes('song') || 
          className.includes('row') ||
          className.includes('card') ||
          className.includes('item') ||
          role === 'row' ||
          role === 'listitem' ||
          container.getAttribute('data-testid')?.includes('track')) {
        console.log('[FileFlower] Found track container:', className || tag);
        break;
      }
      container = container.parentElement;
    }
    
    if (!container) {
      console.log('[FileFlower] Could not find track container, using clicked element');
      container = trackElement;
    }
    
    // ========================================================================
    // TITEL - zoek binnen de container
    // ========================================================================
    let title = null;
    
    // Zoek titel elementen
    const titleSelectors = [
      '[class*="title"]',
      '[class*="name"]',
      '[data-testid*="title"]',
      '[data-testid*="name"]',
      'h1', 'h2', 'h3', 'h4',
      'a[href*="/song/"]',
      'a[href*="/royalty-free-music/song/"]'
    ];
    
    for (const selector of titleSelectors) {
      const el = container.querySelector(selector);
      if (el) {
        const text = el.innerText?.trim();
        // Filter out non-title text
        if (text && text.length > 0 && text.length < 100 && 
            !text.toLowerCase().includes('download') &&
            !text.toLowerCase().includes('play') &&
            !text.match(/^\d+:\d+$/)) { // Not duration
          title = text;
          console.log('[FileFlower] Title found:', title, 'from', selector);
          break;
        }
      }
    }
    
    // ========================================================================
    // ARTIST - zoek binnen de container
    // ========================================================================
    const artists = [];
    
    // Zoek artist links
    const artistLinks = container.querySelectorAll('a[href*="/artist"]');
    artistLinks.forEach(link => {
      const name = link.innerText?.trim();
      if (name && name.length < 100 && !artists.includes(name)) {
        artists.push(name);
      }
    });
    
    // Fallback: zoek "by" tekst binnen container
    if (artists.length === 0) {
      const containerText = container.innerText;
      const byMatch = containerText.match(/(?:by|Song by)\s+([^\n\r•|]+)/i);
      if (byMatch && byMatch[1]) {
        const names = byMatch[1].split(/[,&]/).map(s => s.trim()).filter(s => s && s.length < 50);
        artists.push(...names);
      }
    }
    
    console.log('[FileFlower] Artists:', artists);
    
    // ========================================================================
    // GENRES, MOODS - zoek binnen container of nearby
    // ========================================================================
    const genres = [];
    const moods = [];
    
    // Zoek genre/mood tags binnen container
    const tagElements = container.querySelectorAll('[class*="genre"], [class*="mood"], [class*="tag"], [class*="chip"], a[href*="/genre/"], a[href*="/mood/"]');
    tagElements.forEach(el => {
      const text = el.innerText?.trim();
      const href = el.getAttribute('href') || '';
      const className = (el.className || '').toLowerCase();
      
      if (!text || text.length > 50) return;
      
      if (href.includes('/genre/') || className.includes('genre')) {
        if (!genres.includes(text)) genres.push(text);
      } else if (href.includes('/mood/') || className.includes('mood')) {
        if (!moods.includes(text)) moods.push(text);
      }
    });
    
    // ========================================================================
    // FALLBACK: Als geen genres/moods gevonden, gebruik URL/pagina filters
    // ========================================================================
    if (genres.length === 0 || moods.length === 0) {
      const pageFilters = getAllActiveFilters();
      
      if (genres.length === 0 && pageFilters.genres.length > 0) {
        genres.push(...pageFilters.genres);
        console.log('[FileFlower] Using page filters for genres:', pageFilters.genres);
      }
      if (moods.length === 0 && pageFilters.moods.length > 0) {
        moods.push(...pageFilters.moods);
        console.log('[FileFlower] Using page filters for moods:', pageFilters.moods);
      }
    }
    
    console.log('[FileFlower] Genres:', genres);
    console.log('[FileFlower] Moods:', moods);
    
    // ========================================================================
    // BPM & DURATION - zoek binnen container
    // ========================================================================
    const containerText = container.innerText;
    
    let bpm = null;
    const bpmMatch = containerText.match(/(\d{2,3})\s*BPM/i);
    if (bpmMatch) {
      bpm = parseInt(bpmMatch[1], 10);
    }
    
    let duration = null;
    const durationMatch = containerText.match(/(\d{1,2}):(\d{2})/);
    if (durationMatch) {
      duration = parseInt(durationMatch[1], 10) * 60 + parseInt(durationMatch[2], 10);
    }
    
    // ========================================================================
    // PAGE URL - probeer specifieke track URL te vinden
    // ========================================================================
    let pageUrl = window.location.href;
    const trackLink = container.querySelector('a[href*="/song/"], a[href*="/royalty-free-music/song/"]');
    if (trackLink) {
      const href = trackLink.getAttribute('href');
      if (href.startsWith('/')) {
        pageUrl = window.location.origin + href;
      } else if (href.startsWith('http')) {
        pageUrl = href;
      }
    }
    
    // Haal themes en instruments uit page filters als beschikbaar
    const pageFilters = getAllActiveFilters();
    
    const result = {
      provider: 'artlist',
      pageUrl,
      title,
      artists: [...new Set(artists)],
      genres: [...new Set(genres)],
      moods: [...new Set(moods)],
      instruments: [...new Set(pageFilters.instruments)],
      videoThemes: [...new Set(pageFilters.themes)],
      bpm,
      duration,
      album: null,
      scrapedAt: new Date().toISOString()
    };
    
    console.log('[FileFlower] Track scrape result:', result);
    return result;
    
  } catch (error) {
    console.error('[FileFlower] Error scraping track element:', error);
    return null;
  }
}

/**
 * Scrape de hele Artlist pagina (voor single track pagina's)
 */
function scrapeArtlist() {
  try {
    console.log('[FileFlower] Scraping Artlist page...');
    
    // ========================================================================
    // TITEL - Artlist gebruikt verschillende layouts
    // ========================================================================
    let title = null;
    
    // Methode 1: h1 element
    const h1 = document.querySelector('h1');
    if (h1) {
      title = h1.innerText?.trim();
      console.log('[FileFlower] Title from h1:', title);
    }
    
    // Methode 2: data-testid of aria-label
    if (!title) {
      const titleEl = document.querySelector('[data-testid*="title"], [aria-label*="song"], [class*="SongTitle"], [class*="song-title"], [class*="trackTitle"]');
      if (titleEl) {
        title = titleEl.innerText?.trim();
        console.log('[FileFlower] Title from data-testid/class:', title);
      }
    }
    
    // Methode 3: Open Graph meta tag
    if (!title) {
      const ogTitle = document.querySelector('meta[property="og:title"]');
      if (ogTitle) {
        title = ogTitle.getAttribute('content')?.split('|')[0]?.trim();
        console.log('[FileFlower] Title from og:title:', title);
      }
    }
    
    // Methode 4: document.title
    if (!title) {
      const docTitle = document.title;
      if (docTitle && !docTitle.includes('Artlist')) {
        title = docTitle.split('|')[0].split('-')[0].trim();
        console.log('[FileFlower] Title from document.title:', title);
      }
    }
    
    // ========================================================================
    // ARTISTS
    // ========================================================================
    const artists = [];
    
    // Methode 1: Artist links
    const artistLinks = document.querySelectorAll('a[href*="/artist/"], a[href*="/artists/"]');
    artistLinks.forEach(link => {
      const name = link.innerText?.trim();
      if (name && name.length < 100 && !artists.includes(name)) {
        artists.push(name);
      }
    });
    
    // Methode 2: "Song by" of "by" tekst
    if (artists.length === 0) {
      // Zoek in de hele pagina tekst
      const pageText = document.body.innerText;
      const byMatch = pageText.match(/(?:Song by|by|Artist[:\s]+)\s*([^\n\r|•]+)/i);
      if (byMatch && byMatch[1]) {
        const artistNames = byMatch[1]
          .split(/[,&]|feat\.?|ft\.?/i)
          .map(s => s.trim())
          .filter(s => s && s.length < 50);
        artists.push(...artistNames);
      }
    }
    
    console.log('[FileFlower] Artists found:', artists);
    
    // ========================================================================
    // GENRES, MOODS, INSTRUMENTS, THEMES
    // ========================================================================
    const genres = [];
    const moods = [];
    const instruments = [];
    const videoThemes = [];
    
    // Methode 1: Zoek naar labeled secties
    // Artlist heeft vaak een layout met labels zoals "Genre", "Mood", etc.
    const allText = document.body.innerText;
    
    // Genre sectie
    const genreMatch = allText.match(/Genre[:\s]*([^\n]+)/i);
    if (genreMatch) {
      const genreItems = genreMatch[1].split(/[,•|]/).map(s => s.trim()).filter(s => s && s.length < 30);
      genres.push(...genreItems);
    }
    
    // Mood sectie
    const moodMatch = allText.match(/Mood[:\s]*([^\n]+)/i);
    if (moodMatch) {
      const moodItems = moodMatch[1].split(/[,•|]/).map(s => s.trim()).filter(s => s && s.length < 30);
      moods.push(...moodItems);
    }
    
    // Methode 2: Zoek naar tag/chip elementen
    const tagContainers = document.querySelectorAll('[class*="tag"], [class*="chip"], [class*="pill"], [class*="badge"], [class*="genre"], [class*="mood"]');
    tagContainers.forEach(container => {
      const text = container.innerText?.trim();
      if (!text || text.length > 50) return;
      
      const className = container.className?.toLowerCase() || '';
      const parentClass = container.parentElement?.className?.toLowerCase() || '';
      const grandparentClass = container.parentElement?.parentElement?.className?.toLowerCase() || '';
      const allClasses = className + ' ' + parentClass + ' ' + grandparentClass;
      
      if (allClasses.includes('genre')) {
        if (!genres.includes(text)) genres.push(text);
      } else if (allClasses.includes('mood')) {
        if (!moods.includes(text)) moods.push(text);
      } else if (allClasses.includes('instrument')) {
        if (!instruments.includes(text)) instruments.push(text);
      } else if (allClasses.includes('theme')) {
        if (!videoThemes.includes(text)) videoThemes.push(text);
      }
    });
    
    // Methode 3: Links naar genre/mood pagina's
    const categoryLinks = document.querySelectorAll('a[href*="/genre/"], a[href*="/mood/"], a[href*="/instrument/"], a[href*="/theme/"]');
    categoryLinks.forEach(link => {
      const href = link.getAttribute('href') || '';
      const text = link.innerText?.trim();
      if (!text || text.length > 50) return;
      
      if (href.includes('/genre/') && !genres.includes(text)) {
        genres.push(text);
      } else if (href.includes('/mood/') && !moods.includes(text)) {
        moods.push(text);
      } else if (href.includes('/instrument/') && !instruments.includes(text)) {
        instruments.push(text);
      } else if (href.includes('/theme/') && !videoThemes.includes(text)) {
        videoThemes.push(text);
      }
    });
    
    console.log('[FileFlower] Genres:', genres);
    console.log('[FileFlower] Moods:', moods);
    
    // ========================================================================
    // BPM
    // ========================================================================
    let bpm = null;
    const bpmMatch = allText.match(/(\d{2,3})\s*BPM/i);
    if (bpmMatch) {
      bpm = parseInt(bpmMatch[1], 10);
      console.log('[FileFlower] BPM:', bpm);
    }
    
    // ========================================================================
    // DURATION
    // ========================================================================
    let duration = null;
    const durationMatch = allText.match(/(\d{1,2}):(\d{2})(?:\s|$)/);
    if (durationMatch) {
      duration = parseInt(durationMatch[1], 10) * 60 + parseInt(durationMatch[2], 10);
      console.log('[FileFlower] Duration:', duration, 'seconds');
    }
    
    // ========================================================================
    // ALBUM
    // ========================================================================
    const albumLink = document.querySelector('a[href*="/album/"]');
    const album = albumLink?.innerText?.trim() || null;
    
    const result = {
      provider: 'artlist',
      pageUrl: window.location.href,
      title,
      artists: [...new Set(artists)],
      genres: [...new Set(genres)],
      moods: [...new Set(moods)],
      instruments: [...new Set(instruments)],
      videoThemes: [...new Set(videoThemes)],
      bpm,
      duration,
      album,
      scrapedAt: new Date().toISOString()
    };
    
    console.log('[FileFlower] Artlist scrape result:', result);
    return result;
    
  } catch (error) {
    console.error('[FileFlower] Error scraping Artlist:', error);
    return null;
  }
}

// ============================================================================
// EPIDEMIC SOUND URL PARSER
// ============================================================================

/**
 * Parse Epidemic Sound URL voor genres en moods
 * URL voorbeelden:
 * - /music/genres/pop/ → genre = "Pop"
 * - /music/genres/pop/?genres=indie-pop → genres = ["Pop", "Indie Pop"]
 * - /music/moods/happy/ → mood = "Happy"
 * - /music/moods/happy/?moods=uplifting → moods = ["Happy", "Uplifting"]
 * - ?genres=indie-pop,electronic&moods=happy,uplifting
 */
function parseEpidemicUrlFilters() {
  const url = new URL(window.location.href);
  const pathname = url.pathname;
  const searchParams = url.searchParams;
  
  const genres = [];
  const moods = [];
  
  // Parse pathname: /music/genres/pop/ of /music/moods/happy/
  const genrePathMatch = pathname.match(/\/music\/genres\/([^\/]+)/i);
  if (genrePathMatch) {
    const genre = formatFilterName(genrePathMatch[1]);
    if (genre && !genres.includes(genre)) {
      genres.push(genre);
    }
  }
  
  const moodPathMatch = pathname.match(/\/music\/moods\/([^\/]+)/i);
  if (moodPathMatch) {
    const mood = formatFilterName(moodPathMatch[1]);
    if (mood && !moods.includes(mood)) {
      moods.push(mood);
    }
  }
  
  // Parse query parameters: ?genres=indie-pop,electronic&moods=happy
  const genresParam = searchParams.get('genres');
  if (genresParam) {
    genresParam.split(',').forEach(g => {
      const genre = formatFilterName(g.trim());
      if (genre && !genres.includes(genre)) {
        genres.push(genre);
      }
    });
  }
  
  const moodsParam = searchParams.get('moods');
  if (moodsParam) {
    moodsParam.split(',').forEach(m => {
      const mood = formatFilterName(m.trim());
      if (mood && !moods.includes(mood)) {
        moods.push(mood);
      }
    });
  }
  
  console.log('[FileFlower] Epidemic URL filters - Genres:', genres, 'Moods:', moods);
  
  return { genres, moods };
}

/**
 * Format filter naam: "indie-pop" → "Indie Pop"
 */
function formatFilterName(slug) {
  if (!slug) return null;
  
  return slug
    .split('-')
    .map(word => word.charAt(0).toUpperCase() + word.slice(1).toLowerCase())
    .join(' ');
}

// ============================================================================
// EPIDEMIC SOUND SCRAPER
// ============================================================================

/**
 * Scrape metadata van een specifieke track element op Epidemic Sound
 */
function scrapeEpidemicTrackFromElement(trackElement) {
  try {
    console.log('[FileFlower] Scraping specific Epidemic track element...');
    
    // Haal URL filters op - deze zijn de meest betrouwbare bron
    const urlFilters = parseEpidemicUrlFilters();
    
    // Zoek de parent track container
    let container = trackElement;
    
    for (let i = 0; i < 15 && container; i++) {
      const className = container.className?.toLowerCase() || '';
      const role = container.getAttribute('role')?.toLowerCase() || '';
      const testId = container.getAttribute('data-testid')?.toLowerCase() || '';
      const tagName = container.tagName?.toLowerCase() || '';
      
      // Epidemic gebruikt vaak <li> of elementen met specifieke test IDs
      if (className.includes('track') || 
          className.includes('song') || 
          className.includes('row') ||
          className.includes('card') ||
          className.includes('result') ||
          role === 'row' ||
          role === 'listitem' ||
          tagName === 'li' ||
          testId.includes('track') ||
          testId.includes('result')) {
        console.log('[FileFlower] Found Epidemic track container:', className.substring(0, 80) || tagName);
        break;
      }
      container = container.parentElement;
    }
    
    if (!container) {
      container = trackElement;
    }
    
    // ========================================================================
    // TITEL - zoek in container
    // ========================================================================
    let title = null;
    const titleSelectors = [
      '[data-testid*="title"]',
      '[data-testid*="name"]', 
      '[class*="title"]',
      '[class*="name"]',
      'a[href*="/track/"]',
      'h1', 'h2', 'h3', 'h4'
    ];
    
    for (const selector of titleSelectors) {
      const el = container.querySelector(selector);
      if (el) {
        const text = el.innerText?.trim();
        if (text && text.length > 0 && text.length < 100 && 
            !text.toLowerCase().includes('download') &&
            !text.match(/^\d+:\d+$/) &&  // niet duration
            !text.match(/^\d+\s*BPM$/i)) {  // niet BPM
          title = text;
          console.log('[FileFlower] Epidemic title found:', title);
          break;
        }
      }
    }
    
    // ========================================================================
    // ARTIST - zoek in container
    // ========================================================================
    const artists = [];
    const artistLinks = container.querySelectorAll('a[href*="/artists/"], a[href*="/artist/"]');
    artistLinks.forEach(link => {
      const name = link.innerText?.trim();
      if (name && name.length < 100 && !artists.includes(name)) {
        artists.push(name);
      }
    });
    
    console.log('[FileFlower] Epidemic artists:', artists);
    
    // ========================================================================
    // GENRES & MOODS - uit container + URL filters
    // ========================================================================
    const genres = [...urlFilters.genres];  // Start met URL filters
    const moods = [...urlFilters.moods];
    
    // Voeg genres/moods uit de track container toe
    const tagLinks = container.querySelectorAll('a[href*="/genre"], a[href*="/mood"], a[href*="/genres/"], a[href*="/moods/"]');
    tagLinks.forEach(link => {
      const href = link.getAttribute('href') || '';
      const text = link.innerText?.trim();
      if (!text || text.length > 50) return;
      
      if (href.includes('/genre')) {
        if (!genres.includes(text)) genres.push(text);
      } else if (href.includes('/mood')) {
        if (!moods.includes(text)) moods.push(text);
      }
    });
    
    console.log('[FileFlower] Epidemic genres (incl URL):', genres);
    console.log('[FileFlower] Epidemic moods (incl URL):', moods);
    
    // ========================================================================
    // BPM & DURATION - uit container tekst
    // ========================================================================
    const containerText = container.innerText;
    
    let bpm = null;
    const bpmMatch = containerText.match(/(\d{2,3})\s*BPM/i);
    if (bpmMatch) {
      bpm = parseInt(bpmMatch[1], 10);
      console.log('[FileFlower] Epidemic BPM:', bpm);
    }
    
    let duration = null;
    const durationMatch = containerText.match(/(\d{1,2}):(\d{2})/);
    if (durationMatch) {
      duration = parseInt(durationMatch[1], 10) * 60 + parseInt(durationMatch[2], 10);
    }
    
    // ========================================================================
    // PAGE URL - specifieke track URL
    // ========================================================================
    let pageUrl = window.location.href;
    const trackLink = container.querySelector('a[href*="/track/"]');
    if (trackLink) {
      const href = trackLink.getAttribute('href');
      if (href.startsWith('/')) {
        pageUrl = window.location.origin + href;
      } else if (href.startsWith('http')) {
        pageUrl = href;
      }
    }
    
    const result = {
      provider: 'epidemic',
      pageUrl,
      title,
      artists: [...new Set(artists)],
      genres: [...new Set(genres)],
      moods: [...new Set(moods)],
      tags: [],
      bpm,
      duration,
      energy: null,
      scrapedAt: new Date().toISOString()
    };
    
    console.log('[FileFlower] Epidemic track scrape result:', result);
    return result;
    
  } catch (error) {
    console.error('[FileFlower] Error scraping Epidemic track:', error);
    return null;
  }
}

/**
 * Scrape de hele Epidemic Sound pagina
 */
function scrapeEpidemic() {
  try {
    console.log('[FileFlower] Scraping Epidemic Sound page...');
    
    // ========================================================================
    // URL FILTERS - meest betrouwbare bron!
    // ========================================================================
    const urlFilters = parseEpidemicUrlFilters();
    
    const allText = document.body.innerText;
    
    // ========================================================================
    // TITEL
    // ========================================================================
    let title = null;
    
    // Methode 1: h1 element
    const h1 = document.querySelector('h1');
    if (h1) {
      title = h1.innerText?.trim();
      console.log('[FileFlower] Title from h1:', title);
    }
    
    // Methode 2: data-testid
    if (!title) {
      const titleEl = document.querySelector('[data-testid*="track-title"], [data-testid*="song-title"], [class*="TrackTitle"], [class*="track-title"]');
      if (titleEl) {
        title = titleEl.innerText?.trim();
        console.log('[FileFlower] Title from data-testid:', title);
      }
    }
    
    // Methode 3: og:title
    if (!title) {
      const ogTitle = document.querySelector('meta[property="og:title"]');
      if (ogTitle) {
        title = ogTitle.getAttribute('content')?.split('|')[0]?.split('-')[0]?.trim();
        console.log('[FileFlower] Title from og:title:', title);
      }
    }
    
    // ========================================================================
    // ARTISTS
    // ========================================================================
    const artists = [];
    
    // Methode 1: Artist links
    const artistLinks = document.querySelectorAll('a[href*="/artists/"], a[href*="/artist/"]');
    artistLinks.forEach(link => {
      const name = link.innerText?.trim();
      if (name && name.length < 100 && !artists.includes(name)) {
        artists.push(name);
      }
    });
    
    console.log('[FileFlower] Artists:', artists);
    
    // ========================================================================
    // GENRES & MOODS - start met URL filters, dan DOM
    // ========================================================================
    const genres = [...urlFilters.genres];
    const moods = [...urlFilters.moods];
    const tags = [];
    
    // Voeg genres/moods uit DOM links toe
    const categoryLinks = document.querySelectorAll('a[href*="/music/genres/"], a[href*="/music/moods/"], a[href*="/genre/"], a[href*="/mood/"]');
    categoryLinks.forEach(link => {
      const href = link.getAttribute('href') || '';
      const text = link.innerText?.trim();
      if (!text || text.length > 50) return;
      
      if (href.includes('/genre')) {
        if (!genres.includes(text)) genres.push(text);
      } else if (href.includes('/mood')) {
        if (!moods.includes(text)) moods.push(text);
      }
    });
    
    console.log('[FileFlower] Genres (incl URL):', genres);
    console.log('[FileFlower] Moods (incl URL):', moods);
    
    // ========================================================================
    // BPM
    // ========================================================================
    let bpm = null;
    const bpmMatch = allText.match(/(\d{2,3})\s*BPM/i);
    if (bpmMatch) {
      bpm = parseInt(bpmMatch[1], 10);
      console.log('[FileFlower] BPM:', bpm);
    }
    
    // ========================================================================
    // DURATION
    // ========================================================================
    let duration = null;
    const durationMatch = allText.match(/(\d{1,2}):(\d{2})(?:\s|$)/);
    if (durationMatch) {
      duration = parseInt(durationMatch[1], 10) * 60 + parseInt(durationMatch[2], 10);
    }
    
    // ========================================================================
    // ENERGY
    // ========================================================================
    let energy = null;
    const energyMatch = allText.match(/Energy[:\s]*([^\n,]+)/i);
    if (energyMatch) {
      energy = energyMatch[1].trim();
    }
    
    const result = {
      provider: 'epidemic',
      pageUrl: window.location.href,
      title,
      artists: [...new Set(artists)],
      genres: [...new Set(genres)],
      moods: [...new Set(moods)],
      tags: [...new Set(tags)],
      bpm,
      duration,
      energy,
      scrapedAt: new Date().toISOString()
    };
    
    console.log('[FileFlower] Epidemic scrape result:', result);
    return result;
    
  } catch (error) {
    console.error('[FileFlower] Error scraping Epidemic Sound:', error);
    return null;
  }
}

// ============================================================================
// AUDIOJUNGLE (ENVATO) SCRAPER
// ============================================================================

/**
 * Scrape metadata van een specifieke track element op AudioJungle
 */
function scrapeAudioJungleTrackFromElement(trackElement) {
  try {
    console.log('[FileFlower] Scraping AudioJungle track element...');
    
    let container = trackElement;
    for (let i = 0; i < 15 && container; i++) {
      const className = container.className?.toLowerCase() || '';
      if (className.includes('item') || 
          className.includes('product') || 
          className.includes('track') ||
          className.includes('card') ||
          container.getAttribute('data-item-id')) {
        break;
      }
      container = container.parentElement;
    }
    
    let title = null;
    const titleEl = container?.querySelector('h3 a, .item-name a, [class*="title"] a, .product-name');
    if (titleEl) {
      title = titleEl.innerText?.trim();
    }
    
    const artists = [];
    const authorEl = container?.querySelector('.author a, [class*="author"] a, .by-author a');
    if (authorEl) {
      artists.push(authorEl.innerText?.trim());
    }
    
    const tags = [];
    const tagElements = container?.querySelectorAll('.meta-item a, .tags a, [class*="tag"] a') || [];
    tagElements.forEach(el => {
      const text = el.innerText?.trim();
      if (text && text.length < 50) tags.push(text);
    });
    
    // Parse BPM en duration uit tekst
    const containerText = container?.innerText || '';
    let bpm = null;
    const bpmMatch = containerText.match(/(\d{2,3})\s*BPM/i);
    if (bpmMatch) bpm = parseInt(bpmMatch[1], 10);
    
    let duration = null;
    const durationMatch = containerText.match(/(\d{1,2}):(\d{2})/);
    if (durationMatch) {
      duration = parseInt(durationMatch[1], 10) * 60 + parseInt(durationMatch[2], 10);
    }
    
    let pageUrl = window.location.href;
    const trackLink = container?.querySelector('h3 a, .item-name a');
    if (trackLink?.href) pageUrl = trackLink.href;
    
    return {
      provider: 'audiojungle',
      pageUrl,
      title,
      artists: [...new Set(artists)],
      genres: [],
      moods: [],
      tags: [...new Set(tags)],
      bpm,
      duration,
      scrapedAt: new Date().toISOString()
    };
  } catch (error) {
    console.error('[FileFlower] Error scraping AudioJungle track:', error);
    return null;
  }
}

function scrapeAudioJungle() {
  try {
    console.log('[FileFlower] Scraping AudioJungle page...');
    
    let title = document.querySelector('h1')?.innerText?.trim();
    if (!title) {
      title = document.querySelector('meta[property="og:title"]')?.getAttribute('content')?.split('|')[0]?.trim();
    }
    
    const artists = [];
    const authorEl = document.querySelector('.author a, [class*="author"] a, .by-author a');
    if (authorEl) artists.push(authorEl.innerText?.trim());
    
    const tags = [];
    const genres = [];
    const tagElements = document.querySelectorAll('.item-tags a, .meta-item a, [class*="tag"] a, .sidebar a[href*="/tags/"], a[href*="/category/"]');
    tagElements.forEach(el => {
      const text = el.innerText?.trim();
      const href = el.getAttribute('href') || '';
      if (text && text.length < 50) {
        if (href.includes('/category/') || href.includes('/genre/')) {
          genres.push(text);
        } else {
          tags.push(text);
        }
      }
    });
    
    const allText = document.body.innerText;
    let bpm = null;
    const bpmMatch = allText.match(/(\d{2,3})\s*BPM/i);
    if (bpmMatch) bpm = parseInt(bpmMatch[1], 10);
    
    let duration = null;
    const durationMatch = allText.match(/(\d{1,2}):(\d{2})(?:\s|$)/);
    if (durationMatch) {
      duration = parseInt(durationMatch[1], 10) * 60 + parseInt(durationMatch[2], 10);
    }
    
    return {
      provider: 'audiojungle',
      pageUrl: window.location.href,
      title,
      artists: [...new Set(artists)],
      genres: [...new Set(genres)],
      moods: [],
      tags: [...new Set(tags)],
      bpm,
      duration,
      scrapedAt: new Date().toISOString()
    };
  } catch (error) {
    console.error('[FileFlower] Error scraping AudioJungle:', error);
    return null;
  }
}

// ============================================================================
// MOTION ARRAY SCRAPER
// ============================================================================

function scrapeMotionArrayTrackFromElement(trackElement) {
  try {
    console.log('[FileFlower] Scraping Motion Array track element...');
    
    let container = trackElement;
    for (let i = 0; i < 15 && container; i++) {
      const className = container.className?.toLowerCase() || '';
      if (className.includes('item') || 
          className.includes('product') || 
          className.includes('card') ||
          className.includes('track') ||
          container.getAttribute('data-id')) {
        break;
      }
      container = container.parentElement;
    }
    
    let title = null;
    const titleEl = container?.querySelector('[class*="title"], h3, h4, a[href*="/stock-music/"]');
    if (titleEl) title = titleEl.innerText?.trim();
    
    const artists = [];
    const authorEl = container?.querySelector('[class*="author"] a, [class*="creator"] a, [class*="artist"] a');
    if (authorEl) artists.push(authorEl.innerText?.trim());
    
    const genres = [];
    const moods = [];
    const tagElements = container?.querySelectorAll('[class*="tag"], [class*="category"] a') || [];
    tagElements.forEach(el => {
      const text = el.innerText?.trim();
      if (text && text.length < 50) genres.push(text);
    });
    
    const containerText = container?.innerText || '';
    let bpm = null;
    const bpmMatch = containerText.match(/(\d{2,3})\s*BPM/i);
    if (bpmMatch) bpm = parseInt(bpmMatch[1], 10);
    
    let duration = null;
    const durationMatch = containerText.match(/(\d{1,2}):(\d{2})/);
    if (durationMatch) {
      duration = parseInt(durationMatch[1], 10) * 60 + parseInt(durationMatch[2], 10);
    }
    
    return {
      provider: 'motionarray',
      pageUrl: window.location.href,
      title,
      artists: [...new Set(artists)],
      genres: [...new Set(genres)],
      moods: [...new Set(moods)],
      bpm,
      duration,
      scrapedAt: new Date().toISOString()
    };
  } catch (error) {
    console.error('[FileFlower] Error scraping Motion Array track:', error);
    return null;
  }
}

function scrapeMotionArray() {
  try {
    console.log('[FileFlower] Scraping Motion Array page...');
    
    let title = document.querySelector('h1')?.innerText?.trim();
    if (!title) {
      title = document.querySelector('meta[property="og:title"]')?.getAttribute('content')?.split('|')[0]?.trim();
    }
    
    const artists = [];
    const authorEl = document.querySelector('[class*="author"] a, [class*="creator"] a, [class*="artist"] a, a[href*="/browse/producer/"]');
    if (authorEl) artists.push(authorEl.innerText?.trim());
    
    const genres = [];
    const moods = [];
    const tagElements = document.querySelectorAll('[class*="tag"], [class*="category"] a, a[href*="/browse/genre/"], a[href*="/browse/mood/"]');
    tagElements.forEach(el => {
      const text = el.innerText?.trim();
      const href = el.getAttribute('href') || '';
      if (text && text.length < 50) {
        if (href.includes('/mood/')) {
          moods.push(text);
        } else {
          genres.push(text);
        }
      }
    });
    
    const allText = document.body.innerText;
    let bpm = null;
    const bpmMatch = allText.match(/(\d{2,3})\s*BPM/i);
    if (bpmMatch) bpm = parseInt(bpmMatch[1], 10);
    
    let duration = null;
    const durationMatch = allText.match(/Duration[:\s]*(\d{1,2}):(\d{2})/i);
    if (durationMatch) {
      duration = parseInt(durationMatch[1], 10) * 60 + parseInt(durationMatch[2], 10);
    }
    
    return {
      provider: 'motionarray',
      pageUrl: window.location.href,
      title,
      artists: [...new Set(artists)],
      genres: [...new Set(genres)],
      moods: [...new Set(moods)],
      bpm,
      duration,
      scrapedAt: new Date().toISOString()
    };
  } catch (error) {
    console.error('[FileFlower] Error scraping Motion Array:', error);
    return null;
  }
}

// ============================================================================
// PREMIUMBEAT SCRAPER
// ============================================================================

function scrapePremiumBeatTrackFromElement(trackElement) {
  try {
    console.log('[FileFlower] Scraping PremiumBeat track element...');
    
    let container = trackElement;
    for (let i = 0; i < 15 && container; i++) {
      const className = container.className?.toLowerCase() || '';
      const tagName = container.tagName?.toLowerCase();
      if (className.includes('track') || 
          className.includes('result') || 
          className.includes('item') ||
          tagName === 'article' ||
          tagName === 'li') {
        break;
      }
      container = container.parentElement;
    }
    
    let title = null;
    const titleEl = container?.querySelector('[class*="title"], [class*="name"], h2, h3, a[href*="/track/"]');
    if (titleEl) title = titleEl.innerText?.trim();
    
    const artists = [];
    const artistEl = container?.querySelector('[class*="artist"] a, [class*="author"] a, a[href*="/artist/"]');
    if (artistEl) artists.push(artistEl.innerText?.trim());
    
    const genres = [];
    const moods = [];
    const tagElements = container?.querySelectorAll('[class*="genre"] a, [class*="mood"] a, [class*="tag"] a') || [];
    tagElements.forEach(el => {
      const text = el.innerText?.trim();
      const href = el.getAttribute('href') || '';
      const className = el.className?.toLowerCase() || '';
      if (text && text.length < 50) {
        if (href.includes('/mood') || className.includes('mood')) {
          moods.push(text);
        } else {
          genres.push(text);
        }
      }
    });
    
    const containerText = container?.innerText || '';
    let bpm = null;
    const bpmMatch = containerText.match(/(\d{2,3})\s*BPM/i);
    if (bpmMatch) bpm = parseInt(bpmMatch[1], 10);
    
    let duration = null;
    const durationMatch = containerText.match(/(\d{1,2}):(\d{2})/);
    if (durationMatch) {
      duration = parseInt(durationMatch[1], 10) * 60 + parseInt(durationMatch[2], 10);
    }
    
    return {
      provider: 'premiumbeat',
      pageUrl: window.location.href,
      title,
      artists: [...new Set(artists)],
      genres: [...new Set(genres)],
      moods: [...new Set(moods)],
      bpm,
      duration,
      scrapedAt: new Date().toISOString()
    };
  } catch (error) {
    console.error('[FileFlower] Error scraping PremiumBeat track:', error);
    return null;
  }
}

function scrapePremiumBeat() {
  try {
    console.log('[FileFlower] Scraping PremiumBeat page...');
    
    let title = document.querySelector('h1')?.innerText?.trim();
    if (!title) {
      title = document.querySelector('meta[property="og:title"]')?.getAttribute('content')?.split('|')[0]?.trim();
    }
    
    const artists = [];
    const artistEl = document.querySelector('[class*="artist"] a, a[href*="/artist/"], [class*="author"] a');
    if (artistEl) artists.push(artistEl.innerText?.trim());
    
    const genres = [];
    const moods = [];
    const tagElements = document.querySelectorAll('[class*="genre"] a, [class*="mood"] a, a[href*="/genre/"], a[href*="/mood/"], [class*="tag"] a');
    tagElements.forEach(el => {
      const text = el.innerText?.trim();
      const href = el.getAttribute('href') || '';
      if (text && text.length < 50) {
        if (href.includes('/mood')) {
          moods.push(text);
        } else if (href.includes('/genre')) {
          genres.push(text);
        }
      }
    });
    
    const allText = document.body.innerText;
    let bpm = null;
    const bpmMatch = allText.match(/(\d{2,3})\s*BPM/i);
    if (bpmMatch) bpm = parseInt(bpmMatch[1], 10);
    
    let duration = null;
    const durationMatch = allText.match(/(\d{1,2}):(\d{2})(?:\s|$)/);
    if (durationMatch) {
      duration = parseInt(durationMatch[1], 10) * 60 + parseInt(durationMatch[2], 10);
    }
    
    return {
      provider: 'premiumbeat',
      pageUrl: window.location.href,
      title,
      artists: [...new Set(artists)],
      genres: [...new Set(genres)],
      moods: [...new Set(moods)],
      bpm,
      duration,
      scrapedAt: new Date().toISOString()
    };
  } catch (error) {
    console.error('[FileFlower] Error scraping PremiumBeat:', error);
    return null;
  }
}

// ============================================================================
// POND5 SCRAPER
// ============================================================================

function scrapePond5TrackFromElement(trackElement) {
  try {
    console.log('[FileFlower] Scraping Pond5 track element...');
    
    let container = trackElement;
    for (let i = 0; i < 15 && container; i++) {
      const className = container.className?.toLowerCase() || '';
      if (className.includes('item') || 
          className.includes('result') || 
          className.includes('clip') ||
          className.includes('card') ||
          container.getAttribute('data-id')) {
        break;
      }
      container = container.parentElement;
    }
    
    let title = null;
    const titleEl = container?.querySelector('[class*="title"], h3, h4, a[href*="/stock-music/"]');
    if (titleEl) title = titleEl.innerText?.trim();
    
    const artists = [];
    const artistEl = container?.querySelector('[class*="artist"] a, [class*="author"] a, a[href*="/artist/"]');
    if (artistEl) artists.push(artistEl.innerText?.trim());
    
    const tags = [];
    const tagElements = container?.querySelectorAll('[class*="keyword"] a, [class*="tag"] a') || [];
    tagElements.forEach(el => {
      const text = el.innerText?.trim();
      if (text && text.length < 50) tags.push(text);
    });
    
    const containerText = container?.innerText || '';
    let bpm = null;
    const bpmMatch = containerText.match(/(\d{2,3})\s*BPM/i);
    if (bpmMatch) bpm = parseInt(bpmMatch[1], 10);
    
    let duration = null;
    const durationMatch = containerText.match(/(\d{1,2}):(\d{2})/);
    if (durationMatch) {
      duration = parseInt(durationMatch[1], 10) * 60 + parseInt(durationMatch[2], 10);
    }
    
    return {
      provider: 'pond5',
      pageUrl: window.location.href,
      title,
      artists: [...new Set(artists)],
      genres: [],
      moods: [],
      tags: [...new Set(tags)],
      bpm,
      duration,
      scrapedAt: new Date().toISOString()
    };
  } catch (error) {
    console.error('[FileFlower] Error scraping Pond5 track:', error);
    return null;
  }
}

function scrapePond5() {
  try {
    console.log('[FileFlower] Scraping Pond5 page...');
    
    let title = document.querySelector('h1')?.innerText?.trim();
    if (!title) {
      title = document.querySelector('meta[property="og:title"]')?.getAttribute('content')?.split('|')[0]?.trim();
    }
    
    const artists = [];
    const artistEl = document.querySelector('[class*="artist"] a, a[href*="/artist/"], [class*="author"] a');
    if (artistEl) artists.push(artistEl.innerText?.trim());
    
    const genres = [];
    const tags = [];
    const tagElements = document.querySelectorAll('[class*="keyword"] a, [class*="tag"] a, a[href*="/stock-music/keyword/"], a[href*="/category/"]');
    tagElements.forEach(el => {
      const text = el.innerText?.trim();
      const href = el.getAttribute('href') || '';
      if (text && text.length < 50) {
        if (href.includes('/category/')) {
          genres.push(text);
        } else {
          tags.push(text);
        }
      }
    });
    
    const allText = document.body.innerText;
    let bpm = null;
    const bpmMatch = allText.match(/(\d{2,3})\s*BPM/i);
    if (bpmMatch) bpm = parseInt(bpmMatch[1], 10);
    
    let duration = null;
    const durationMatch = allText.match(/Duration[:\s]*(\d{1,2}):(\d{2})/i);
    if (!durationMatch) {
      const simpleMatch = allText.match(/(\d{1,2}):(\d{2})(?:\s|$)/);
      if (simpleMatch) {
        duration = parseInt(simpleMatch[1], 10) * 60 + parseInt(simpleMatch[2], 10);
      }
    } else {
      duration = parseInt(durationMatch[1], 10) * 60 + parseInt(durationMatch[2], 10);
    }
    
    return {
      provider: 'pond5',
      pageUrl: window.location.href,
      title,
      artists: [...new Set(artists)],
      genres: [...new Set(genres)],
      moods: [],
      tags: [...new Set(tags)],
      bpm,
      duration,
      scrapedAt: new Date().toISOString()
    };
  } catch (error) {
    console.error('[FileFlower] Error scraping Pond5:', error);
    return null;
  }
}

// ============================================================================
// STORYBLOCKS SCRAPER
// ============================================================================

function scrapeStoryblocksTrackFromElement(trackElement) {
  try {
    console.log('[FileFlower] Scraping Storyblocks track element...');
    
    let container = trackElement;
    for (let i = 0; i < 15 && container; i++) {
      const className = container.className?.toLowerCase() || '';
      if (className.includes('item') || 
          className.includes('result') || 
          className.includes('card') ||
          className.includes('track') ||
          container.getAttribute('data-id')) {
        break;
      }
      container = container.parentElement;
    }
    
    let title = null;
    const titleEl = container?.querySelector('[class*="title"], h3, h4, a[href*="/audio/"]');
    if (titleEl) title = titleEl.innerText?.trim();
    
    const artists = [];
    const artistEl = container?.querySelector('[class*="artist"] a, [class*="author"] a');
    if (artistEl) artists.push(artistEl.innerText?.trim());
    
    const genres = [];
    const moods = [];
    const tagElements = container?.querySelectorAll('[class*="tag"] a, [class*="genre"] a, [class*="mood"] a') || [];
    tagElements.forEach(el => {
      const text = el.innerText?.trim();
      const href = el.getAttribute('href') || '';
      if (text && text.length < 50) {
        if (href.includes('/mood')) moods.push(text);
        else genres.push(text);
      }
    });
    
    const containerText = container?.innerText || '';
    let duration = null;
    const durationMatch = containerText.match(/(\d{1,2}):(\d{2})/);
    if (durationMatch) {
      duration = parseInt(durationMatch[1], 10) * 60 + parseInt(durationMatch[2], 10);
    }
    
    return {
      provider: 'storyblocks',
      pageUrl: window.location.href,
      title,
      artists: [...new Set(artists)],
      genres: [...new Set(genres)],
      moods: [...new Set(moods)],
      duration,
      scrapedAt: new Date().toISOString()
    };
  } catch (error) {
    console.error('[FileFlower] Error scraping Storyblocks track:', error);
    return null;
  }
}

function scrapeStoryblocks() {
  try {
    console.log('[FileFlower] Scraping Storyblocks page...');
    
    let title = document.querySelector('h1')?.innerText?.trim();
    if (!title) {
      title = document.querySelector('meta[property="og:title"]')?.getAttribute('content')?.split('|')[0]?.trim();
    }
    
    const artists = [];
    const artistEl = document.querySelector('[class*="artist"] a, [class*="author"] a');
    if (artistEl) artists.push(artistEl.innerText?.trim());
    
    const genres = [];
    const moods = [];
    const tagElements = document.querySelectorAll('[class*="tag"] a, a[href*="/genre/"], a[href*="/mood/"], a[href*="/audio/collections/"]');
    tagElements.forEach(el => {
      const text = el.innerText?.trim();
      const href = el.getAttribute('href') || '';
      if (text && text.length < 50) {
        if (href.includes('/mood')) moods.push(text);
        else genres.push(text);
      }
    });
    
    const allText = document.body.innerText;
    let duration = null;
    const durationMatch = allText.match(/(\d{1,2}):(\d{2})(?:\s|$)/);
    if (durationMatch) {
      duration = parseInt(durationMatch[1], 10) * 60 + parseInt(durationMatch[2], 10);
    }
    
    // Tempo/BPM
    let tempo = null;
    const tempoMatch = allText.match(/Tempo[:\s]*(Slow|Medium|Fast|Very Fast)/i);
    if (tempoMatch) tempo = tempoMatch[1];
    
    return {
      provider: 'storyblocks',
      pageUrl: window.location.href,
      title,
      artists: [...new Set(artists)],
      genres: [...new Set(genres)],
      moods: [...new Set(moods)],
      tempo,
      duration,
      scrapedAt: new Date().toISOString()
    };
  } catch (error) {
    console.error('[FileFlower] Error scraping Storyblocks:', error);
    return null;
  }
}

// ============================================================================
// SHUTTERSTOCK MUSIC SCRAPER
// ============================================================================

function scrapeShutterstockTrackFromElement(trackElement) {
  try {
    console.log('[FileFlower] Scraping Shutterstock track element...');
    
    let container = trackElement;
    for (let i = 0; i < 15 && container; i++) {
      const className = container.className?.toLowerCase() || '';
      if (className.includes('item') || 
          className.includes('result') || 
          className.includes('track') ||
          className.includes('row') ||
          container.getAttribute('data-track-id')) {
        break;
      }
      container = container.parentElement;
    }
    
    let title = null;
    const titleEl = container?.querySelector('[class*="title"], [class*="name"], a[href*="/music/"]');
    if (titleEl) title = titleEl.innerText?.trim();
    
    const artists = [];
    const artistEl = container?.querySelector('[class*="artist"] a, [class*="author"]');
    if (artistEl) artists.push(artistEl.innerText?.trim());
    
    const genres = [];
    const moods = [];
    const tagElements = container?.querySelectorAll('[class*="genre"] a, [class*="mood"] a, [class*="tag"] a') || [];
    tagElements.forEach(el => {
      const text = el.innerText?.trim();
      const href = el.getAttribute('href') || '';
      if (text && text.length < 50) {
        if (href.includes('/mood') || el.className?.toLowerCase().includes('mood')) moods.push(text);
        else genres.push(text);
      }
    });
    
    const containerText = container?.innerText || '';
    let duration = null;
    const durationMatch = containerText.match(/(\d{1,2}):(\d{2})/);
    if (durationMatch) {
      duration = parseInt(durationMatch[1], 10) * 60 + parseInt(durationMatch[2], 10);
    }
    
    return {
      provider: 'shutterstock',
      pageUrl: window.location.href,
      title,
      artists: [...new Set(artists)],
      genres: [...new Set(genres)],
      moods: [...new Set(moods)],
      duration,
      scrapedAt: new Date().toISOString()
    };
  } catch (error) {
    console.error('[FileFlower] Error scraping Shutterstock track:', error);
    return null;
  }
}

function scrapeShutterstock() {
  try {
    console.log('[FileFlower] Scraping Shutterstock Music page...');
    
    let title = document.querySelector('h1')?.innerText?.trim();
    if (!title) {
      title = document.querySelector('meta[property="og:title"]')?.getAttribute('content')?.split('|')[0]?.trim();
    }
    
    const artists = [];
    const artistEl = document.querySelector('[class*="artist"], [class*="author"]');
    if (artistEl) artists.push(artistEl.innerText?.trim());
    
    const genres = [];
    const moods = [];
    const tagElements = document.querySelectorAll('[class*="genre"] a, [class*="mood"] a, a[href*="/music/genre/"], a[href*="/music/mood/"]');
    tagElements.forEach(el => {
      const text = el.innerText?.trim();
      const href = el.getAttribute('href') || '';
      if (text && text.length < 50) {
        if (href.includes('/mood')) moods.push(text);
        else if (href.includes('/genre')) genres.push(text);
      }
    });
    
    const allText = document.body.innerText;
    let duration = null;
    const durationMatch = allText.match(/(\d{1,2}):(\d{2})(?:\s|$)/);
    if (durationMatch) {
      duration = parseInt(durationMatch[1], 10) * 60 + parseInt(durationMatch[2], 10);
    }
    
    let tempo = null;
    const tempoMatch = allText.match(/Tempo[:\s]*(\d+)/i);
    if (tempoMatch) tempo = parseInt(tempoMatch[1], 10);
    
    return {
      provider: 'shutterstock',
      pageUrl: window.location.href,
      title,
      artists: [...new Set(artists)],
      genres: [...new Set(genres)],
      moods: [...new Set(moods)],
      bpm: tempo,
      duration,
      scrapedAt: new Date().toISOString()
    };
  } catch (error) {
    console.error('[FileFlower] Error scraping Shutterstock Music:', error);
    return null;
  }
}

// ============================================================================
// SOUNDSTRIPE SCRAPER
// ============================================================================

function scrapeSoundstripeTrackFromElement(trackElement) {
  try {
    console.log('[FileFlower] Scraping Soundstripe track element...');
    
    let container = trackElement;
    for (let i = 0; i < 15 && container; i++) {
      const className = container.className?.toLowerCase() || '';
      if (className.includes('track') || 
          className.includes('song') || 
          className.includes('row') ||
          className.includes('item') ||
          container.getAttribute('data-track-id')) {
        break;
      }
      container = container.parentElement;
    }
    
    let title = null;
    const titleEl = container?.querySelector('[class*="title"], [class*="name"], a[href*="/song/"], a[href*="/track/"]');
    if (titleEl) title = titleEl.innerText?.trim();
    
    const artists = [];
    const artistEl = container?.querySelector('[class*="artist"] a, a[href*="/artist/"]');
    if (artistEl) artists.push(artistEl.innerText?.trim());
    
    const genres = [];
    const moods = [];
    const tagElements = container?.querySelectorAll('[class*="genre"], [class*="mood"], [class*="tag"]') || [];
    tagElements.forEach(el => {
      const text = el.innerText?.trim();
      const className = el.className?.toLowerCase() || '';
      if (text && text.length < 50) {
        if (className.includes('mood')) moods.push(text);
        else if (className.includes('genre')) genres.push(text);
      }
    });
    
    const containerText = container?.innerText || '';
    let bpm = null;
    const bpmMatch = containerText.match(/(\d{2,3})\s*BPM/i);
    if (bpmMatch) bpm = parseInt(bpmMatch[1], 10);
    
    let duration = null;
    const durationMatch = containerText.match(/(\d{1,2}):(\d{2})/);
    if (durationMatch) {
      duration = parseInt(durationMatch[1], 10) * 60 + parseInt(durationMatch[2], 10);
    }
    
    return {
      provider: 'soundstripe',
      pageUrl: window.location.href,
      title,
      artists: [...new Set(artists)],
      genres: [...new Set(genres)],
      moods: [...new Set(moods)],
      bpm,
      duration,
      scrapedAt: new Date().toISOString()
    };
  } catch (error) {
    console.error('[FileFlower] Error scraping Soundstripe track:', error);
    return null;
  }
}

function scrapeSoundstripe() {
  try {
    console.log('[FileFlower] Scraping Soundstripe page...');
    
    let title = document.querySelector('h1')?.innerText?.trim();
    if (!title) {
      title = document.querySelector('meta[property="og:title"]')?.getAttribute('content')?.split('|')[0]?.trim();
    }
    
    const artists = [];
    const artistEl = document.querySelector('[class*="artist"] a, a[href*="/artist/"]');
    if (artistEl) artists.push(artistEl.innerText?.trim());
    
    const genres = [];
    const moods = [];
    const tagElements = document.querySelectorAll('[class*="genre"] a, [class*="mood"] a, a[href*="/genre/"], a[href*="/mood/"]');
    tagElements.forEach(el => {
      const text = el.innerText?.trim();
      const href = el.getAttribute('href') || '';
      if (text && text.length < 50) {
        if (href.includes('/mood')) moods.push(text);
        else if (href.includes('/genre')) genres.push(text);
      }
    });
    
    const allText = document.body.innerText;
    let bpm = null;
    const bpmMatch = allText.match(/(\d{2,3})\s*BPM/i);
    if (bpmMatch) bpm = parseInt(bpmMatch[1], 10);
    
    let duration = null;
    const durationMatch = allText.match(/(\d{1,2}):(\d{2})(?:\s|$)/);
    if (durationMatch) {
      duration = parseInt(durationMatch[1], 10) * 60 + parseInt(durationMatch[2], 10);
    }
    
    return {
      provider: 'soundstripe',
      pageUrl: window.location.href,
      title,
      artists: [...new Set(artists)],
      genres: [...new Set(genres)],
      moods: [...new Set(moods)],
      bpm,
      duration,
      scrapedAt: new Date().toISOString()
    };
  } catch (error) {
    console.error('[FileFlower] Error scraping Soundstripe:', error);
    return null;
  }
}

// ============================================================================
// UPPBEAT SCRAPER
// ============================================================================

function scrapeUppbeatTrackFromElement(trackElement) {
  try {
    console.log('[FileFlower] Scraping Uppbeat track element...');
    
    let container = trackElement;
    for (let i = 0; i < 15 && container; i++) {
      const className = container.className?.toLowerCase() || '';
      if (className.includes('track') || 
          className.includes('song') || 
          className.includes('row') ||
          className.includes('item') ||
          className.includes('card')) {
        break;
      }
      container = container.parentElement;
    }
    
    let title = null;
    const titleEl = container?.querySelector('[class*="title"], [class*="name"], h3, h4');
    if (titleEl) title = titleEl.innerText?.trim();
    
    const artists = [];
    const artistEl = container?.querySelector('[class*="artist"] a, a[href*="/artist/"]');
    if (artistEl) artists.push(artistEl.innerText?.trim());
    
    const genres = [];
    const moods = [];
    const tags = [];
    const tagElements = container?.querySelectorAll('[class*="tag"], [class*="genre"], [class*="mood"]') || [];
    tagElements.forEach(el => {
      const text = el.innerText?.trim();
      const className = el.className?.toLowerCase() || '';
      if (text && text.length < 50) {
        if (className.includes('mood')) moods.push(text);
        else if (className.includes('genre')) genres.push(text);
        else tags.push(text);
      }
    });
    
    const containerText = container?.innerText || '';
    let duration = null;
    const durationMatch = containerText.match(/(\d{1,2}):(\d{2})/);
    if (durationMatch) {
      duration = parseInt(durationMatch[1], 10) * 60 + parseInt(durationMatch[2], 10);
    }
    
    return {
      provider: 'uppbeat',
      pageUrl: window.location.href,
      title,
      artists: [...new Set(artists)],
      genres: [...new Set(genres)],
      moods: [...new Set(moods)],
      tags: [...new Set(tags)],
      duration,
      scrapedAt: new Date().toISOString()
    };
  } catch (error) {
    console.error('[FileFlower] Error scraping Uppbeat track:', error);
    return null;
  }
}

function scrapeUppbeat() {
  try {
    console.log('[FileFlower] Scraping Uppbeat page...');
    
    let title = document.querySelector('h1')?.innerText?.trim();
    if (!title) {
      title = document.querySelector('meta[property="og:title"]')?.getAttribute('content')?.split('|')[0]?.trim();
    }
    
    const artists = [];
    const artistEl = document.querySelector('[class*="artist"] a, a[href*="/artist/"]');
    if (artistEl) artists.push(artistEl.innerText?.trim());
    
    const genres = [];
    const moods = [];
    const tags = [];
    const tagElements = document.querySelectorAll('[class*="tag"] a, [class*="genre"] a, [class*="mood"] a, a[href*="/genre/"], a[href*="/mood/"]');
    tagElements.forEach(el => {
      const text = el.innerText?.trim();
      const href = el.getAttribute('href') || '';
      if (text && text.length < 50) {
        if (href.includes('/mood')) moods.push(text);
        else if (href.includes('/genre')) genres.push(text);
        else tags.push(text);
      }
    });
    
    const allText = document.body.innerText;
    let duration = null;
    const durationMatch = allText.match(/(\d{1,2}):(\d{2})(?:\s|$)/);
    if (durationMatch) {
      duration = parseInt(durationMatch[1], 10) * 60 + parseInt(durationMatch[2], 10);
    }
    
    return {
      provider: 'uppbeat',
      pageUrl: window.location.href,
      title,
      artists: [...new Set(artists)],
      genres: [...new Set(genres)],
      moods: [...new Set(moods)],
      tags: [...new Set(tags)],
      duration,
      scrapedAt: new Date().toISOString()
    };
  } catch (error) {
    console.error('[FileFlower] Error scraping Uppbeat:', error);
    return null;
  }
}

// ============================================================================
// BMG PRODUCTION MUSIC SCRAPER
// ============================================================================

/**
 * Extract keywords from BMG URL search parameters
 * URL like: /sound-design/tracks?keywords=Drone+or+Rumble&typed=drone%20or%20rumble
 */
function extractBMGUrlKeywords() {
  const keywords = [];
  try {
    const url = new URL(window.location.href);
    
    // Get 'keywords' param (chip selections like "Drone or Rumble")
    const keywordsParam = url.searchParams.get('keywords');
    if (keywordsParam) {
      // Split on " or " and "+" to get individual keywords
      keywordsParam.split(/\s+or\s+|\+/i)
        .map(k => k.trim())
        .filter(k => k && k.length > 1 && k.length < 40)
        .forEach(k => keywords.push(k));
    }
    
    // Get 'typed' param (search box input)
    const typedParam = url.searchParams.get('typed');
    if (typedParam) {
      typedParam.split(/\s+or\s+|\+/i)
        .map(k => k.trim())
        .filter(k => k && k.length > 1 && k.length < 40)
        .forEach(k => keywords.push(k));
    }
    
    // Get category from URL path (e.g., /sound-design/, /music/)
    const pathMatch = url.pathname.match(/\/(sound-design|sfx|music|trailer|cinematic|ambient|electronic|orchestral)/i);
    if (pathMatch) {
      keywords.push(pathMatch[1]);
    }
    
    console.log('[FileFlower] BMG URL keywords:', keywords);
  } catch (e) {
    console.error('[FileFlower] Error parsing BMG URL:', e);
  }
  return [...new Set(keywords)];
}

function scrapeBMGTrackFromElement(trackElement) {
  try {
    console.log('[FileFlower] Scraping BMG Production Music track element...');
    
    // Find track container - walk up the DOM tree
    let container = trackElement?.closest('[data-track-id], [data-track], [class*="track-layout"], [class*="track-layer"], [class*="track-row"], [class*="track-version"], [class*="result"], [class*="pm-track"]');
    if (!container) {
      container = trackElement;
      for (let i = 0; i < 20 && container; i++) {
        const className = container.className?.toLowerCase() || '';
        const tagName = container.tagName?.toLowerCase() || '';
        // BMG uses Angular component tags like pm-track-row
        if (className.includes('track') || 
            className.includes('song') || 
            className.includes('row') ||
            className.includes('result') ||
            tagName.includes('track') ||
            container.getAttribute('data-track')) {
          break;
        }
        container = container.parentElement;
      }
    }
    
    console.log('[FileFlower] Found container:', container?.className?.substring(0, 100));
    
    // Extract title
    let title = container?.getAttribute('data-track-title') ||
                container?.getAttribute('data-title') ||
                container?.getAttribute('data-trackname') ||
                container?.getAttribute('data-name') ||
                null;
    
    if (!title) {
      // BMG titles are often in first text node or specific elements
      const titleEl = container?.querySelector('[class*="track-title"], [class*="track-name"], [class*="version-title"], [class*="title"], h3, h4, h5, strong');
      if (titleEl) title = titleEl.innerText?.split('\n')[0]?.trim();
    }
    if (title) {
      title = title.replace(/\s+/g, ' ').replace(/\u00a0/g, ' ').trim();
      // Remove " - Main" or " - 60s" suffixes for cleaner matching
      title = title.replace(/\s*-\s*(Main|Full|Short|30s|60s|15s|Loop)$/i, '').trim() || title;
    }
    
    console.log('[FileFlower] Title:', title);
    
    // Extract artists
    const artists = [];
    const artistAttr = container?.getAttribute('data-artist') || container?.getAttribute('data-composer');
    if (artistAttr) {
      artistAttr.split(/[,|/]/).map(a => a.trim()).filter(Boolean).forEach(a => artists.push(a));
    }
    const artistEl = container?.querySelector('[class*="artist"], [class*="composer"], [class*="writer"], a[href*="composer"], a[href*="writer"]');
    if (artistEl) artists.push(artistEl.innerText?.trim());
    
    // Extract genres, moods, tags from URL keywords first
    const urlKeywords = extractBMGUrlKeywords();
    const genres = [...urlKeywords]; // URL keywords are usually genres/categories
    const moods = [];
    const tags = [];
    let album = container?.getAttribute('data-album') || container?.getAttribute('data-release') || null;
    
    // Extract tags from DOM elements
    const tagSelectors = [
      '[class*="tag"]',
      '[class*="keyword"]',
      '[class*="descriptor"]',
      '[class*="genre"]',
      '[class*="mood"]',
      '[class*="style"]',
      '[class*="category"]',
      '[class*="track-meta"]',
      '[class*="track-desc"]',
      '[class*="track-info"]'
    ];
    tagSelectors.forEach(selector => {
      const elements = container?.querySelectorAll(selector) || [];
      elements.forEach(el => {
        const text = el.innerText?.trim();
        if (!text || text.length > 100) return;
        const className = el.className?.toLowerCase() || '';
        const href = el.getAttribute?.('href') || '';
        // Split on common separators
        const parts = text.split(/[,;·•|/\n]+/).map(p => p.trim()).filter(Boolean);
        parts.forEach(part => {
          if (part.length > 50 || part.length < 2) return;
          // Skip time durations and numbers
          if (/^\d{1,2}:\d{2}$/.test(part) || /^\d+$/.test(part)) return;
          
          if (className.includes('mood') || href.includes('/mood')) {
            moods.push(part);
          } else if (className.includes('genre') || className.includes('style') || href.includes('/genre')) {
            genres.push(part);
          } else {
            tags.push(part);
          }
        });
      });
    });
    
    // Fallback: extract from ALL text in the track row
    // BMG shows descriptors like "atmospheres, atmospheric, danger, drones, eer..."
    const containerText = container?.innerText || '';
    const lines = containerText.split(/\n+/).map(l => l.replace(/\u00a0/g, ' ').trim()).filter(Boolean);
    
    lines.forEach(line => {
      if (!line || line.length < 3 || line.length > 200) return;
      // Skip title line
      if (title && line.toLowerCase().includes(title.toLowerCase())) return;
      // Skip time durations
      if (/^\d{1,2}:\d{2}$/.test(line)) return;
      // Skip button text
      if (/^(download|play|pause|add|remove|share)$/i.test(line)) return;
      
      // This line might contain comma-separated descriptors
      const parts = line.split(/[,;·•]+/).map(p => p.trim()).filter(Boolean);
      if (parts.length >= 2) {
        // Likely a descriptor line like "atmospheres, atmospheric, danger, drones"
        parts.forEach(part => {
          if (!part || part.length > 40 || part.length < 2) return;
          // Skip numbers and durations
          if (/^\d/.test(part)) return;
          
          // Categorize based on known keywords
          const lower = part.toLowerCase();
          if (lower.match(/mood|feel|emotion|atmosphere/i)) {
            moods.push(part);
          } else if (lower.match(/^(ambient|drone|orches|trailer|cinematic|rock|pop|jazz|hip.?hop|piano|electronic|classical|acoustic|sound design|sfx|textur|tension|dark|scary|eerie|dramatic|horror|mysterious|atmospheric|sombre|ominous)/i)) {
            genres.push(part);
          } else {
            tags.push(part);
          }
        });
      }
    });
    
    // Duration
    let duration = null;
    const durationEl = container?.querySelector('[class*="duration"], time');
    const durationText = durationEl?.innerText || containerText;
    const durationMatch = durationText?.match(/(\d{1,2}):(\d{2})/);
    if (durationMatch) {
      duration = parseInt(durationMatch[1], 10) * 60 + parseInt(durationMatch[2], 10);
    }
    
    console.log('[FileFlower] Scraped genres:', genres);
    console.log('[FileFlower] Scraped tags:', tags);
    
    return {
      provider: 'bmg',
      pageUrl: window.location.href,
      title,
      artists: [...new Set(artists.filter(Boolean))],
      genres: [...new Set(genres.filter(Boolean))],
      moods: [...new Set(moods.filter(Boolean))],
      tags: [...new Set(tags.filter(Boolean))],
      keywords: [...new Set([...genres, ...moods, ...tags].filter(Boolean))],
      album,
      duration,
      scrapedAt: new Date().toISOString()
    };
  } catch (error) {
    console.error('[FileFlower] Error scraping BMG track:', error);
    return null;
  }
}

function scrapeBMG() {
  try {
    console.log('[FileFlower] Scraping BMG Production Music page...');
    
    // Get first track's title (for list view) or page title (for detail view)
    let title = document.querySelector('[class*="track-title"], [class*="track-name"], [class*="version-title"]')?.innerText?.split('\n')[0]?.trim();
    if (!title) {
      title = document.querySelector('h1')?.innerText?.trim();
    }
    if (!title) {
      title = document.querySelector('meta[property="og:title"]')?.getAttribute('content')?.split('|')[0]?.trim();
    }
    if (title) {
      title = title.replace(/\s+/g, ' ').replace(/\u00a0/g, ' ').trim();
      // Remove " - Main" or " - 60s" suffixes for cleaner matching
      title = title.replace(/\s*-\s*(Main|Full|Short|30s|60s|15s|Loop)$/i, '').trim() || title;
    }
    
    const artists = [];
    const artistEl = document.querySelector('[class*="artist"], [class*="composer"], [class*="writer"], a[href*="composer"], a[href*="writer"]');
    if (artistEl) artists.push(artistEl.innerText?.trim());
    
    // Start with URL keywords as genres (these are the user's search filters)
    const urlKeywords = extractBMGUrlKeywords();
    const genres = [...urlKeywords];
    const moods = [];
    const tags = [];
    let album = document.querySelector('[class*="album"], [class*="release"], [class*="collection"]')?.innerText?.trim() || null;
    
    // Extract from DOM elements
    const tagSelectors = [
      '[class*="tag"]',
      '[class*="keyword"]',
      '[class*="descriptor"]',
      '[class*="genre"]',
      '[class*="mood"]',
      '[class*="style"]',
      '[class*="category"]',
      '[class*="chip"]'
    ];
    tagSelectors.forEach(selector => {
      const elements = document.querySelectorAll(selector);
      elements.forEach(el => {
        const text = el.innerText?.trim();
        if (!text || text.length > 100) return;
        const className = el.className?.toLowerCase() || '';
        const href = el.getAttribute('href') || '';
        const parts = text.split(/[,;·•|/\n]+/).map(p => p.trim()).filter(Boolean);
        parts.forEach(part => {
          if (part.length > 50 || part.length < 2) return;
          if (/^\d{1,2}:\d{2}$/.test(part) || /^\d+$/.test(part)) return;
          
          if (className.includes('mood') || href.includes('/mood')) {
            moods.push(part);
          } else if (className.includes('genre') || className.includes('style') || href.includes('/genre')) {
            genres.push(part);
          } else {
            tags.push(part);
          }
        });
      });
    });
    
    // Also look at the first track row's descriptors
    const firstTrackRow = document.querySelector('[class*="track-layout"], [class*="track-row"], [class*="pm-track"]');
    if (firstTrackRow) {
      const rowText = firstTrackRow.innerText || '';
      const lines = rowText.split(/\n+/).map(l => l.trim()).filter(Boolean);
      lines.forEach(line => {
        if (!line || line.length < 3 || line.length > 150) return;
        if (title && line.toLowerCase().includes(title.toLowerCase())) return;
        if (/^\d{1,2}:\d{2}$/.test(line)) return;
        if (/^(download|play|pause|add|remove|share)$/i.test(line)) return;
        
        const parts = line.split(/[,;·•]+/).map(p => p.trim()).filter(Boolean);
        if (parts.length >= 2) {
          parts.forEach(part => {
            if (!part || part.length > 40 || part.length < 2) return;
            if (/^\d/.test(part)) return;
            
            const lower = part.toLowerCase();
            if (lower.match(/^(ambient|drone|orches|trailer|cinematic|rock|pop|jazz|hip.?hop|piano|electronic|classical|acoustic|sound design|sfx|textur|tension|dark|scary|eerie|dramatic|horror|mysterious|atmospheric|sombre|ominous)/i)) {
              genres.push(part);
            } else {
              tags.push(part);
            }
          });
        }
      });
    }
    
    let duration = null;
    const durationEl = document.querySelector('[class*="duration"], time');
    const durationText = durationEl?.innerText || document.body.innerText;
    const durationMatch = durationText?.match(/(\d{1,2}):(\d{2})(?:\s|$)/);
    if (durationMatch) {
      duration = parseInt(durationMatch[1], 10) * 60 + parseInt(durationMatch[2], 10);
    }
    
    console.log('[FileFlower] Page-level BMG genres:', genres);
    console.log('[FileFlower] Page-level BMG tags:', tags);
    
    return {
      provider: 'bmg',
      pageUrl: window.location.href,
      title,
      artists: [...new Set(artists.filter(Boolean))],
      genres: [...new Set(genres.filter(Boolean))],
      moods: [...new Set(moods.filter(Boolean))],
      tags: [...new Set(tags.filter(Boolean))],
      keywords: [...new Set([...genres, ...moods, ...tags].filter(Boolean))],
      album,
      duration,
      scrapedAt: new Date().toISOString()
    };
  } catch (error) {
    console.error('[FileFlower] Error scraping BMG Production Music:', error);
    return null;
  }
}

// ============================================================================
// UNIVERSAL PRODUCTION MUSIC SCRAPER
// ============================================================================

function scrapeUniversalTrackFromElement(trackElement) {
  try {
    console.log('[FileFlower] Scraping Universal Production Music track element...');
    
    let container = trackElement;
    for (let i = 0; i < 15 && container; i++) {
      const className = container.className?.toLowerCase() || '';
      if (className.includes('track') || 
          className.includes('song') || 
          className.includes('row') ||
          className.includes('result')) {
        break;
      }
      container = container.parentElement;
    }
    
    let title = null;
    const titleEl = container?.querySelector('[class*="title"], [class*="name"], h3, h4');
    if (titleEl) title = titleEl.innerText?.trim();
    
    const artists = [];
    const artistEl = container?.querySelector('[class*="artist"], [class*="composer"], [class*="writer"]');
    if (artistEl) artists.push(artistEl.innerText?.trim());
    
    const genres = [];
    const moods = [];
    const tagElements = container?.querySelectorAll('[class*="genre"], [class*="mood"], [class*="category"]') || [];
    tagElements.forEach(el => {
      const text = el.innerText?.trim();
      const className = el.className?.toLowerCase() || '';
      if (text && text.length < 50) {
        if (className.includes('mood')) moods.push(text);
        else genres.push(text);
      }
    });
    
    const containerText = container?.innerText || '';
    let duration = null;
    const durationMatch = containerText.match(/(\d{1,2}):(\d{2})/);
    if (durationMatch) {
      duration = parseInt(durationMatch[1], 10) * 60 + parseInt(durationMatch[2], 10);
    }
    
    return {
      provider: 'universal',
      pageUrl: window.location.href,
      title,
      artists: [...new Set(artists)],
      genres: [...new Set(genres)],
      moods: [...new Set(moods)],
      duration,
      scrapedAt: new Date().toISOString()
    };
  } catch (error) {
    console.error('[FileFlower] Error scraping Universal track:', error);
    return null;
  }
}

function scrapeUniversal() {
  try {
    console.log('[FileFlower] Scraping Universal Production Music page...');
    
    let title = document.querySelector('h1')?.innerText?.trim();
    if (!title) {
      title = document.querySelector('meta[property="og:title"]')?.getAttribute('content')?.split('|')[0]?.trim();
    }
    
    const artists = [];
    const artistEl = document.querySelector('[class*="artist"], [class*="composer"], [class*="writer"]');
    if (artistEl) artists.push(artistEl.innerText?.trim());
    
    const genres = [];
    const moods = [];
    const tagElements = document.querySelectorAll('[class*="genre"] a, [class*="mood"] a, [class*="category"] a');
    tagElements.forEach(el => {
      const text = el.innerText?.trim();
      const className = el.className?.toLowerCase() || '';
      const href = el.getAttribute('href') || '';
      if (text && text.length < 50) {
        if (className.includes('mood') || href.includes('/mood')) moods.push(text);
        else genres.push(text);
      }
    });
    
    const allText = document.body.innerText;
    let duration = null;
    const durationMatch = allText.match(/(\d{1,2}):(\d{2})(?:\s|$)/);
    if (durationMatch) {
      duration = parseInt(durationMatch[1], 10) * 60 + parseInt(durationMatch[2], 10);
    }
    
    return {
      provider: 'universal',
      pageUrl: window.location.href,
      title,
      artists: [...new Set(artists)],
      genres: [...new Set(genres)],
      moods: [...new Set(moods)],
      duration,
      scrapedAt: new Date().toISOString()
    };
  } catch (error) {
    console.error('[FileFlower] Error scraping Universal Production Music:', error);
    return null;
  }
}

// ============================================================================
// MUSICBED SCRAPER
// ============================================================================

function scrapeMusicbedTrackFromElement(trackElement) {
  try {
    console.log('[FileFlower] Scraping Musicbed track element...');
    
    let container = trackElement;
    for (let i = 0; i < 15 && container; i++) {
      const className = container.className?.toLowerCase() || '';
      if (className.includes('track') || 
          className.includes('song') || 
          className.includes('row') ||
          className.includes('card')) {
        break;
      }
      container = container.parentElement;
    }
    
    let title = null;
    const titleEl = container?.querySelector('[class*="title"], [class*="name"], h3, h4, a[href*="/songs/"]');
    if (titleEl) title = titleEl.innerText?.trim();
    
    const artists = [];
    const artistEl = container?.querySelector('[class*="artist"] a, a[href*="/artists/"]');
    if (artistEl) artists.push(artistEl.innerText?.trim());
    
    const genres = [];
    const moods = [];
    const instruments = [];
    const tagElements = container?.querySelectorAll('[class*="genre"], [class*="mood"], [class*="instrument"], [class*="tag"]') || [];
    tagElements.forEach(el => {
      const text = el.innerText?.trim();
      const className = el.className?.toLowerCase() || '';
      if (text && text.length < 50) {
        if (className.includes('mood')) moods.push(text);
        else if (className.includes('instrument')) instruments.push(text);
        else genres.push(text);
      }
    });
    
    const containerText = container?.innerText || '';
    let duration = null;
    const durationMatch = containerText.match(/(\d{1,2}):(\d{2})/);
    if (durationMatch) {
      duration = parseInt(durationMatch[1], 10) * 60 + parseInt(durationMatch[2], 10);
    }
    
    return {
      provider: 'musicbed',
      pageUrl: window.location.href,
      title,
      artists: [...new Set(artists)],
      genres: [...new Set(genres)],
      moods: [...new Set(moods)],
      instruments: [...new Set(instruments)],
      duration,
      scrapedAt: new Date().toISOString()
    };
  } catch (error) {
    console.error('[FileFlower] Error scraping Musicbed track:', error);
    return null;
  }
}

function scrapeMusicbed() {
  try {
    console.log('[FileFlower] Scraping Musicbed page...');
    
    let title = document.querySelector('h1')?.innerText?.trim();
    if (!title) {
      title = document.querySelector('meta[property="og:title"]')?.getAttribute('content')?.split('|')[0]?.trim();
    }
    
    const artists = [];
    const artistEl = document.querySelector('[class*="artist"] a, a[href*="/artists/"]');
    if (artistEl) artists.push(artistEl.innerText?.trim());
    
    const genres = [];
    const moods = [];
    const instruments = [];
    const tagElements = document.querySelectorAll('[class*="genre"] a, [class*="mood"] a, [class*="instrument"] a, a[href*="/genre/"], a[href*="/mood/"], a[href*="/instrument/"]');
    tagElements.forEach(el => {
      const text = el.innerText?.trim();
      const className = el.className?.toLowerCase() || '';
      const href = el.getAttribute('href') || '';
      if (text && text.length < 50) {
        if (className.includes('mood') || href.includes('/mood')) moods.push(text);
        else if (className.includes('instrument') || href.includes('/instrument')) instruments.push(text);
        else if (className.includes('genre') || href.includes('/genre')) genres.push(text);
      }
    });
    
    const allText = document.body.innerText;
    let duration = null;
    const durationMatch = allText.match(/(\d{1,2}):(\d{2})(?:\s|$)/);
    if (durationMatch) {
      duration = parseInt(durationMatch[1], 10) * 60 + parseInt(durationMatch[2], 10);
    }
    
    return {
      provider: 'musicbed',
      pageUrl: window.location.href,
      title,
      artists: [...new Set(artists)],
      genres: [...new Set(genres)],
      moods: [...new Set(moods)],
      instruments: [...new Set(instruments)],
      duration,
      scrapedAt: new Date().toISOString()
    };
  } catch (error) {
    console.error('[FileFlower] Error scraping Musicbed:', error);
    return null;
  }
}

// ============================================================================
// ADOBE STOCK AUDIO SCRAPER
// ============================================================================

function scrapeAdobeStockTrackFromElement(trackElement) {
  try {
    console.log('[FileFlower] Scraping Adobe Stock track element...');
    
    let container = trackElement;
    for (let i = 0; i < 15 && container; i++) {
      const className = container.className?.toLowerCase() || '';
      if (className.includes('item') || 
          className.includes('result') || 
          className.includes('card') ||
          className.includes('track') ||
          container.getAttribute('data-id')) {
        break;
      }
      container = container.parentElement;
    }
    
    let title = null;
    const titleEl = container?.querySelector('[class*="title"], [class*="name"], h3, h4');
    if (titleEl) title = titleEl.innerText?.trim();
    
    const artists = [];
    const artistEl = container?.querySelector('[class*="artist"], [class*="author"], [class*="contributor"]');
    if (artistEl) artists.push(artistEl.innerText?.trim());
    
    const keywords = [];
    const keywordElements = container?.querySelectorAll('[class*="keyword"], [class*="tag"]') || [];
    keywordElements.forEach(el => {
      const text = el.innerText?.trim();
      if (text && text.length < 50) keywords.push(text);
    });
    
    const containerText = container?.innerText || '';
    let duration = null;
    const durationMatch = containerText.match(/(\d{1,2}):(\d{2})/);
    if (durationMatch) {
      duration = parseInt(durationMatch[1], 10) * 60 + parseInt(durationMatch[2], 10);
    }
    
    return {
      provider: 'adobestock',
      pageUrl: window.location.href,
      title,
      artists: [...new Set(artists)],
      genres: [],
      moods: [],
      keywords: [...new Set(keywords)],
      duration,
      scrapedAt: new Date().toISOString()
    };
  } catch (error) {
    console.error('[FileFlower] Error scraping Adobe Stock track:', error);
    return null;
  }
}

function scrapeAdobeStock() {
  try {
    console.log('[FileFlower] Scraping Adobe Stock page...');
    
    let title = document.querySelector('h1')?.innerText?.trim();
    if (!title) {
      title = document.querySelector('meta[property="og:title"]')?.getAttribute('content')?.split('|')[0]?.trim();
    }
    
    const artists = [];
    const artistEl = document.querySelector('[class*="artist"], [class*="author"], [class*="contributor"], a[href*="/contributor/"]');
    if (artistEl) artists.push(artistEl.innerText?.trim());
    
    const keywords = [];
    const keywordElements = document.querySelectorAll('[class*="keyword"] a, [class*="tag"] a, a[href*="/search/audio?k="]');
    keywordElements.forEach(el => {
      const text = el.innerText?.trim();
      if (text && text.length < 50) keywords.push(text);
    });
    
    const allText = document.body.innerText;
    let duration = null;
    const durationMatch = allText.match(/Duration[:\s]*(\d{1,2}):(\d{2})/i);
    if (!durationMatch) {
      const simpleMatch = allText.match(/(\d{1,2}):(\d{2})(?:\s|$)/);
      if (simpleMatch) {
        duration = parseInt(simpleMatch[1], 10) * 60 + parseInt(simpleMatch[2], 10);
      }
    } else {
      duration = parseInt(durationMatch[1], 10) * 60 + parseInt(durationMatch[2], 10);
    }
    
    return {
      provider: 'adobestock',
      pageUrl: window.location.href,
      title,
      artists: [...new Set(artists)],
      genres: [],
      moods: [],
      keywords: [...new Set(keywords)],
      duration,
      scrapedAt: new Date().toISOString()
    };
  } catch (error) {
    console.error('[FileFlower] Error scraping Adobe Stock:', error);
    return null;
  }
}

// ============================================================================
// FREESOUND SCRAPER
// ============================================================================

function scrapeFreesoundTrackFromElement(trackElement) {
  try {
    console.log('[FileFlower] Scraping Freesound track element...');
    
    let container = trackElement;
    for (let i = 0; i < 15 && container; i++) {
      const className = container.className?.toLowerCase() || '';
      if (className.includes('sound') || 
          className.includes('sample') || 
          className.includes('item') ||
          className.includes('result')) {
        break;
      }
      container = container.parentElement;
    }
    
    let title = null;
    const titleEl = container?.querySelector('[class*="title"], [class*="name"], h3, h4, a[href*="/sounds/"]');
    if (titleEl) title = titleEl.innerText?.trim();
    
    const artists = [];
    const artistEl = container?.querySelector('[class*="user"] a, a[href*="/people/"]');
    if (artistEl) artists.push(artistEl.innerText?.trim());
    
    const tags = [];
    const tagElements = container?.querySelectorAll('[class*="tag"] a, a[href*="/search/?q="]') || [];
    tagElements.forEach(el => {
      const text = el.innerText?.trim();
      if (text && text.length < 50) tags.push(text);
    });
    
    const containerText = container?.innerText || '';
    let duration = null;
    const durationMatch = containerText.match(/(\d{1,2}):(\d{2})/);
    if (durationMatch) {
      duration = parseInt(durationMatch[1], 10) * 60 + parseInt(durationMatch[2], 10);
    }
    
    return {
      provider: 'freesound',
      pageUrl: window.location.href,
      title,
      artists: [...new Set(artists)],
      genres: [],
      moods: [],
      tags: [...new Set(tags)],
      duration,
      scrapedAt: new Date().toISOString()
    };
  } catch (error) {
    console.error('[FileFlower] Error scraping Freesound track:', error);
    return null;
  }
}

function scrapeFreesound() {
  try {
    console.log('[FileFlower] Scraping Freesound page...');
    
    let title = document.querySelector('h1')?.innerText?.trim();
    if (!title) {
      title = document.querySelector('.sound-filename, [class*="sound-title"]')?.innerText?.trim();
    }
    if (!title) {
      title = document.querySelector('meta[property="og:title"]')?.getAttribute('content')?.split('|')[0]?.trim();
    }
    
    const artists = [];
    const artistEl = document.querySelector('[class*="user"] a, a[href*="/people/"], .username a');
    if (artistEl) artists.push(artistEl.innerText?.trim());
    
    const tags = [];
    const tagElements = document.querySelectorAll('.tags a, [class*="tag"] a, a[href*="/browse/tags/"]');
    tagElements.forEach(el => {
      const text = el.innerText?.trim();
      if (text && text.length < 50) tags.push(text);
    });
    
    const allText = document.body.innerText;
    let duration = null;
    const durationMatch = allText.match(/Duration[:\s]*(\d{1,2}):(\d{2})/i);
    if (!durationMatch) {
      const simpleMatch = allText.match(/(\d{1,2}):(\d{2})(?:\s|$)/);
      if (simpleMatch) {
        duration = parseInt(simpleMatch[1], 10) * 60 + parseInt(simpleMatch[2], 10);
      }
    } else {
      duration = parseInt(durationMatch[1], 10) * 60 + parseInt(durationMatch[2], 10);
    }
    
    return {
      provider: 'freesound',
      pageUrl: window.location.href,
      title,
      artists: [...new Set(artists)],
      genres: [],
      moods: [],
      tags: [...new Set(tags)],
      duration,
      scrapedAt: new Date().toISOString()
    };
  } catch (error) {
    console.error('[FileFlower] Error scraping Freesound:', error);
    return null;
  }
}

// ============================================================================
// YOUTUBE AUDIO LIBRARY SCRAPER
// ============================================================================

function scrapeYouTubeAudioLibraryTrackFromElement(trackElement) {
  try {
    console.log('[FileFlower] Scraping YouTube Audio Library track element...');
    
    let container = trackElement;
    for (let i = 0; i < 15 && container; i++) {
      const className = container.className?.toLowerCase() || '';
      const tagName = container.tagName?.toLowerCase();
      if (className.includes('track') || 
          className.includes('row') || 
          className.includes('item') ||
          tagName === 'tr' ||
          container.getAttribute('data-row')) {
        break;
      }
      container = container.parentElement;
    }
    
    let title = null;
    const titleEl = container?.querySelector('[class*="title"], [class*="name"], td:first-child');
    if (titleEl) title = titleEl.innerText?.trim();
    
    const artists = [];
    const artistEl = container?.querySelector('[class*="artist"], [class*="author"]');
    if (artistEl) artists.push(artistEl.innerText?.trim());
    
    const genres = [];
    const moods = [];
    // YouTube Audio Library heeft vaak genre en mood kolommen
    const cells = container?.querySelectorAll('td') || [];
    if (cells.length >= 4) {
      // Typische structuur: Title, Artist, Genre, Mood, Duration
      if (cells[2]) genres.push(cells[2].innerText?.trim());
      if (cells[3]) moods.push(cells[3].innerText?.trim());
    }
    
    const containerText = container?.innerText || '';
    let duration = null;
    const durationMatch = containerText.match(/(\d{1,2}):(\d{2})/);
    if (durationMatch) {
      duration = parseInt(durationMatch[1], 10) * 60 + parseInt(durationMatch[2], 10);
    }
    
    return {
      provider: 'youtube',
      pageUrl: window.location.href,
      title,
      artists: [...new Set(artists.filter(a => a))],
      genres: [...new Set(genres.filter(g => g && g.length < 50))],
      moods: [...new Set(moods.filter(m => m && m.length < 50))],
      duration,
      scrapedAt: new Date().toISOString()
    };
  } catch (error) {
    console.error('[FileFlower] Error scraping YouTube Audio Library track:', error);
    return null;
  }
}

function scrapeYouTubeAudioLibrary() {
  try {
    console.log('[FileFlower] Scraping YouTube Audio Library page...');
    
    // YouTube Audio Library is een tabel-gebaseerde interface
    let title = null;
    const selectedRow = document.querySelector('tr.selected, tr[aria-selected="true"], [class*="playing"]');
    if (selectedRow) {
      const titleEl = selectedRow.querySelector('[class*="title"], td:first-child');
      if (titleEl) title = titleEl.innerText?.trim();
    }
    
    if (!title) {
      title = document.querySelector('h1')?.innerText?.trim();
    }
    
    const artists = [];
    const genres = [];
    const moods = [];
    
    if (selectedRow) {
      const cells = selectedRow.querySelectorAll('td');
      if (cells.length >= 4) {
        if (cells[1]) artists.push(cells[1].innerText?.trim());
        if (cells[2]) genres.push(cells[2].innerText?.trim());
        if (cells[3]) moods.push(cells[3].innerText?.trim());
      }
    }
    
    const allText = document.body.innerText;
    let duration = null;
    const durationMatch = allText.match(/(\d{1,2}):(\d{2})(?:\s|$)/);
    if (durationMatch) {
      duration = parseInt(durationMatch[1], 10) * 60 + parseInt(durationMatch[2], 10);
    }
    
    return {
      provider: 'youtube',
      pageUrl: window.location.href,
      title,
      artists: [...new Set(artists.filter(a => a))],
      genres: [...new Set(genres.filter(g => g && g.length < 50))],
      moods: [...new Set(moods.filter(m => m && m.length < 50))],
      duration,
      scrapedAt: new Date().toISOString()
    };
  } catch (error) {
    console.error('[FileFlower] Error scraping YouTube Audio Library:', error);
    return null;
  }
}

// ============================================================================
// MAIN SCRAPER LOGIC
// ============================================================================

function getCurrentProvider() {
  const host = window.location.host.toLowerCase();
  const path = window.location.pathname.toLowerCase();
  
  if (host.includes('artlist.io')) return 'artlist';
  if (host.includes('epidemicsound.com')) return 'epidemic';
  if (host.includes('audiojungle.net')) return 'audiojungle';
  if (host.includes('motionarray.com')) return 'motionarray';
  if (host.includes('premiumbeat.com')) return 'premiumbeat';
  if (host.includes('pond5.com')) return 'pond5';
  if (host.includes('storyblocks.com')) return 'storyblocks';
  if (host.includes('shutterstock.com') && (path.includes('/music') || path.includes('/audio'))) return 'shutterstock';
  if (host.includes('soundstripe.com')) return 'soundstripe';
  if (host.includes('uppbeat.io')) return 'uppbeat';
  if (host.includes('bmgproductionmusic.com') || host.includes('bmgpm.com')) return 'bmg';
  if (host.includes('universalproductionmusic.com')) return 'universal';
  if (host.includes('musicbed.com')) return 'musicbed';
  if (host.includes('stock.adobe.com')) return 'adobestock';
  if (host.includes('freesound.org')) return 'freesound';
  if ((host.includes('youtube.com') && path.includes('/audiolibrary')) || host.includes('studio.youtube.com')) return 'youtube';
  
  return null;
}

function scrapePage() {
  const provider = getCurrentProvider();
  if (!provider) return null;
  
  switch (provider) {
    case 'artlist':
      return scrapeArtlist();
    case 'epidemic':
      return scrapeEpidemic();
    case 'audiojungle':
      return scrapeAudioJungle();
    case 'motionarray':
      return scrapeMotionArray();
    case 'premiumbeat':
      return scrapePremiumBeat();
    case 'pond5':
      return scrapePond5();
    case 'storyblocks':
      return scrapeStoryblocks();
    case 'shutterstock':
      return scrapeShutterstock();
    case 'soundstripe':
      return scrapeSoundstripe();
    case 'uppbeat':
      return scrapeUppbeat();
    case 'bmg':
      return scrapeBMG();
    case 'universal':
      return scrapeUniversal();
    case 'musicbed':
      return scrapeMusicbed();
    case 'adobestock':
      return scrapeAdobeStock();
    case 'freesound':
      return scrapeFreesound();
    case 'youtube':
      return scrapeYouTubeAudioLibrary();
    default:
      return null;
  }
}

function updateMetadata() {
  const meta = scrapePage();
  if (!meta) return;
  
  // Alleen updaten als er significante data is
  if (meta.title || meta.genres?.length > 0 || meta.moods?.length > 0) {
    lastMetadata = meta;
    console.log('[FileFlower] Metadata updated:', meta);
  }
}

// ============================================================================
// EVENT LISTENERS
// ============================================================================

// Luister naar clicks op download buttons
document.addEventListener('click', (e) => {
  const target = e.target.closest('a, button, [role="button"], [class*="download"]');
  if (!target) return;
  
  // Check of dit een download actie is
  const text = target.innerText?.toLowerCase() || '';
  const ariaLabel = target.getAttribute('aria-label')?.toLowerCase() || '';
  const testId = target.getAttribute('data-testid')?.toLowerCase() || '';
  const href = target.getAttribute('href') || '';
  const className = target.className?.toLowerCase() || '';
  
  const isDownloadAction = 
    text.includes('download') ||
    ariaLabel.includes('download') ||
    testId.includes('download') ||
    className.includes('download') ||
    target.hasAttribute('download') ||
    href.includes('download');
  
  if (isDownloadAction) {
    console.log('[FileFlower] Download click detected on:', target);
    
    // Bepaal welke scraper te gebruiken
    const provider = getCurrentProvider();
    let metadata = null;
    
    // Scrape de specifieke track waar op geklikt werd
    switch (provider) {
      case 'artlist':
        metadata = scrapeArtlistTrackFromElement(target);
        break;
      case 'epidemic':
        metadata = scrapeEpidemicTrackFromElement(target);
        break;
      case 'audiojungle':
        metadata = scrapeAudioJungleTrackFromElement(target);
        break;
      case 'motionarray':
        metadata = scrapeMotionArrayTrackFromElement(target);
        break;
      case 'premiumbeat':
        metadata = scrapePremiumBeatTrackFromElement(target);
        break;
      case 'pond5':
        metadata = scrapePond5TrackFromElement(target);
        break;
      case 'storyblocks':
        metadata = scrapeStoryblocksTrackFromElement(target);
        break;
      case 'shutterstock':
        metadata = scrapeShutterstockTrackFromElement(target);
        break;
      case 'soundstripe':
        metadata = scrapeSoundstripeTrackFromElement(target);
        break;
      case 'uppbeat':
        metadata = scrapeUppbeatTrackFromElement(target);
        break;
      case 'bmg':
        metadata = scrapeBMGTrackFromElement(target);
        break;
      case 'universal':
        metadata = scrapeUniversalTrackFromElement(target);
        break;
      case 'musicbed':
        metadata = scrapeMusicbedTrackFromElement(target);
        break;
      case 'adobestock':
        metadata = scrapeAdobeStockTrackFromElement(target);
        break;
      case 'freesound':
        metadata = scrapeFreesoundTrackFromElement(target);
        break;
      case 'youtube':
        metadata = scrapeYouTubeAudioLibraryTrackFromElement(target);
        break;
    }
    
    // Fallback naar page-level metadata als track scraping faalt
    if (!metadata || !metadata.title) {
      console.log('[FileFlower] Track-level scraping failed, using page metadata');
      metadata = lastMetadata;
    }
    
    if (metadata) {
      console.log('[FileFlower] Sending metadata:', metadata);
      
      // Stuur metadata naar background script
      chrome.runtime.sendMessage({
        type: 'TRACK_METADATA',
        metadata: metadata
      }, (response) => {
        if (chrome.runtime.lastError) {
          console.error('[FileFlower] Error sending message:', chrome.runtime.lastError);
        } else {
          console.log('[FileFlower] Metadata sent successfully:', response);
        }
      });
      
      // Update ook lastMetadata voor backup
      lastMetadata = metadata;
    } else {
      console.warn('[FileFlower] No metadata available to send');
    }
  }
}, true);

// Luister ook naar rechtermuisknop context menu (voor "Save link as...")
document.addEventListener('contextmenu', (e) => {
  const target = e.target.closest('a, button, [role="button"]');
  if (!target) return;
  
  const href = target.getAttribute('href') || '';
  const className = target.className?.toLowerCase() || '';
  
  if (href.includes('.wav') || href.includes('.mp3') || href.includes('.aiff') || 
      href.includes('download') || className.includes('download')) {
    
    // Scrape de specifieke track
    const provider = getCurrentProvider();
    let metadata = null;
    
    // Scrape de specifieke track waar op geklikt werd
    switch (provider) {
      case 'artlist':
        metadata = scrapeArtlistTrackFromElement(target);
        break;
      case 'epidemic':
        metadata = scrapeEpidemicTrackFromElement(target);
        break;
      case 'audiojungle':
        metadata = scrapeAudioJungleTrackFromElement(target);
        break;
      case 'motionarray':
        metadata = scrapeMotionArrayTrackFromElement(target);
        break;
      case 'premiumbeat':
        metadata = scrapePremiumBeatTrackFromElement(target);
        break;
      case 'pond5':
        metadata = scrapePond5TrackFromElement(target);
        break;
      case 'storyblocks':
        metadata = scrapeStoryblocksTrackFromElement(target);
        break;
      case 'shutterstock':
        metadata = scrapeShutterstockTrackFromElement(target);
        break;
      case 'soundstripe':
        metadata = scrapeSoundstripeTrackFromElement(target);
        break;
      case 'uppbeat':
        metadata = scrapeUppbeatTrackFromElement(target);
        break;
      case 'bmg':
        metadata = scrapeBMGTrackFromElement(target);
        break;
      case 'universal':
        metadata = scrapeUniversalTrackFromElement(target);
        break;
      case 'musicbed':
        metadata = scrapeMusicbedTrackFromElement(target);
        break;
      case 'adobestock':
        metadata = scrapeAdobeStockTrackFromElement(target);
        break;
      case 'freesound':
        metadata = scrapeFreesoundTrackFromElement(target);
        break;
      case 'youtube':
        metadata = scrapeYouTubeAudioLibraryTrackFromElement(target);
        break;
    }
    
    if (!metadata || !metadata.title) {
      metadata = lastMetadata;
    }
    
    if (metadata) {
      console.log('[FileFlower] Context menu on download, pre-sending metadata');
      chrome.runtime.sendMessage({
        type: 'TRACK_METADATA',
        metadata: metadata
      });
    }
  }
});

// ============================================================================
// MESSAGE HANDLING - Respond to popup requests
// ============================================================================

chrome.runtime.onMessage.addListener((message, sender, sendResponse) => {
  if (message.type === 'GET_METADATA') {
    // Force update and return current metadata
    updateMetadata();
    sendResponse({ metadata: lastMetadata });
    return true;
  }
});

// ============================================================================
// INITIALIZATION
// ============================================================================

function init() {
  if (isInitialized) return;
  isInitialized = true;
  
  console.log('[FileFlower] Content script loaded on', window.location.host);
  
  // Initial scrape
  updateMetadata();
  
  // Observe DOM changes (SPA navigation, dynamic content)
  const observer = new MutationObserver(() => {
    // Debounce updates
    clearTimeout(window._dltoPremiereTimeout);
    window._dltoPremiereTimeout = setTimeout(updateMetadata, 500);
  });
  
  observer.observe(document.documentElement, {
    childList: true,
    subtree: true
  });
  
  // Re-scrape on URL changes (SPA navigation)
  let lastUrl = window.location.href;
  setInterval(() => {
    if (window.location.href !== lastUrl) {
      lastUrl = window.location.href;
      console.log('[FileFlower] URL changed, re-scraping');
      setTimeout(updateMetadata, 1000); // Wait for page to load
    }
  }, 500);
}

// Start
if (document.readyState === 'loading') {
  document.addEventListener('DOMContentLoaded', init);
} else {
  init();
}




