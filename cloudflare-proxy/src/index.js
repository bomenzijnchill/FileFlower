/**
 * FileFlower Proxy Worker
 *
 * Endpoints:
 * - POST /api/analyze-folder-structure — Proxied folder structure analyse naar Anthropic Claude API
 * - POST /api/feedback — Feedback email verzenden via Resend API
 *
 * Secrets (via wrangler secret put):
 * - ANTHROPIC_API_KEY
 * - RESEND_API_KEY
 */

const ANTHROPIC_API_URL = 'https://api.anthropic.com/v1/messages';
const ANTHROPIC_MODEL = 'claude-haiku-4-5-20251001';
const ANTHROPIC_VERSION = '2023-06-01';

const SYSTEM_PROMPT = `You are an expert in video/audio production folder structures. You analyze folder trees and determine which folders correspond to which media asset types.

Given a folder tree structure, identify the best matching folder path for each of these asset types:
- Music: Background music, songs, instrumentals, soundtrack files
- SFX: Sound effects, foley, ambience, impacts, swooshes
- VO: Voice-over, narration, dialogue recordings
- Graphic: Static images, photos, illustrations, logos, thumbnails
- MotionGraphic: Motion graphic templates, animated titles, lower thirds, animated overlays
- StockFootage: Stock video clips, B-roll footage, video downloads

Important rules:
- Return the RELATIVE path from the project root (e.g. "03_Audio/01_Music", not an absolute path)
- If a folder could match multiple types, choose the most specific match
- If you cannot confidently identify a folder for a type, set it to null
- Look for common naming patterns: numbered prefixes (01_, 02_), Dutch/English/German names
- Consider the folder hierarchy: audio folders often contain music/sfx/vo subfolders
- "Muziek" = Music, "Geluidseffecten" = SFX, "Vormgeving" = Graphics in Dutch

Respond with ONLY a valid JSON object in this exact format:
{
  "mapping": {
    "Music": "path/to/music" or null,
    "SFX": "path/to/sfx" or null,
    "VO": "path/to/vo" or null,
    "Graphic": "path/to/graphics" or null,
    "MotionGraphic": "path/to/motion" or null,
    "StockFootage": "path/to/footage" or null
  },
  "description": "Brief description of the folder structure pattern"
}`;

// Rate limiting voor feedback endpoint
const FEEDBACK_RATE_LIMIT = new Map();
const MAX_FEEDBACK_PER_HOUR = 5;

function checkFeedbackRateLimit(deviceId) {
  const now = Date.now();
  const entry = FEEDBACK_RATE_LIMIT.get(deviceId);

  if (!entry || now > entry.resetTime) {
    FEEDBACK_RATE_LIMIT.set(deviceId, { count: 1, resetTime: now + 3600000 });
    return true;
  }

  if (entry.count >= MAX_FEEDBACK_PER_HOUR) {
    return false;
  }

  entry.count++;
  return true;
}

function escapeHtml(str) {
  return str
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;');
}

// --- Route handlers ---

async function handleAnalyzeFolderStructure(request, env, corsHeaders) {
  if (!env.ANTHROPIC_API_KEY) {
    return new Response(JSON.stringify({ error: 'API key not configured' }), {
      status: 500,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });
  }

  try {
    const body = await request.json();
    const folderTree = body.folderTree;

    if (!folderTree || typeof folderTree !== 'string') {
      return new Response(JSON.stringify({ error: 'Missing or invalid folderTree' }), {
        status: 400,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }

    const deviceId = request.headers.get('X-Device-Id') || 'unknown';
    console.log(`Analyze request from device: ${deviceId}, tree length: ${folderTree.length}`);

    const anthropicResponse = await fetch(ANTHROPIC_API_URL, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'x-api-key': env.ANTHROPIC_API_KEY,
        'anthropic-version': ANTHROPIC_VERSION,
      },
      body: JSON.stringify({
        model: ANTHROPIC_MODEL,
        max_tokens: 500,
        system: SYSTEM_PROMPT,
        messages: [
          {
            role: 'user',
            content: `Analyze this folder structure and map each asset type to the correct folder path:\n\n${folderTree}`,
          },
        ],
      }),
    });

    if (!anthropicResponse.ok) {
      const errorText = await anthropicResponse.text();
      console.error(`Anthropic API error: ${anthropicResponse.status} - ${errorText.substring(0, 200)}`);
      return new Response(JSON.stringify({ error: 'AI analysis failed', status: anthropicResponse.status }), {
        status: 502,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }

    const responseData = await anthropicResponse.json();

    return new Response(JSON.stringify(responseData), {
      status: 200,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });

  } catch (error) {
    console.error(`Worker error: ${error.message}`);
    return new Response(JSON.stringify({ error: 'Internal server error', message: error.message }), {
      status: 500,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });
  }
}

async function handleFeedback(request, env, corsHeaders) {
  const deviceId = request.headers.get('X-Device-Id') || 'unknown';

  if (!checkFeedbackRateLimit(deviceId)) {
    return new Response(JSON.stringify({ error: 'Too many feedback requests. Please try again later.' }), {
      status: 429,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });
  }

  if (!env.RESEND_API_KEY) {
    return new Response(JSON.stringify({ error: 'Email service not configured' }), {
      status: 500,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });
  }

  try {
    const body = await request.json();
    const { type, name, email, message, appVersion, osVersion } = body;

    // Input validatie
    if (!type || !['featureRequest', 'bugReport'].includes(type)) {
      return new Response(JSON.stringify({ error: 'Invalid feedback type' }), {
        status: 400,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }
    if (!name || typeof name !== 'string' || name.length > 200) {
      return new Response(JSON.stringify({ error: 'Invalid name' }), {
        status: 400,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }
    if (!email || typeof email !== 'string' || email.length > 200 || !email.includes('@')) {
      return new Response(JSON.stringify({ error: 'Invalid email' }), {
        status: 400,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }
    if (!message || typeof message !== 'string' || message.length > 5000) {
      return new Response(JSON.stringify({ error: 'Invalid message (max 5000 chars)' }), {
        status: 400,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }

    const subject = type === 'featureRequest'
      ? 'Feature Request - FileFlower'
      : 'Bug Report - FileFlower';

    const htmlBody = `
      <h2>${type === 'featureRequest' ? 'Feature Request' : 'Bug Report'}</h2>
      <p><strong>From:</strong> ${escapeHtml(name)} (${escapeHtml(email)})</p>
      <p><strong>Message:</strong></p>
      <p>${escapeHtml(message).replace(/\n/g, '<br>')}</p>
      <hr>
      <p><small>App Version: ${escapeHtml(appVersion || 'unknown')}<br>
      macOS: ${escapeHtml(osVersion || 'unknown')}<br>
      Device ID: ${escapeHtml(deviceId)}</small></p>
    `;

    console.log(`Feedback from device: ${deviceId}, type: ${type}, name: ${name}`);

    const resendResponse = await fetch('https://api.resend.com/emails', {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${env.RESEND_API_KEY}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        from: 'FileFlower Feedback <feedback@fileflower.com>',
        to: ['info@fileflower.com'],
        reply_to: email,
        subject: subject,
        html: htmlBody,
      }),
    });

    if (!resendResponse.ok) {
      const errorText = await resendResponse.text();
      console.error(`Resend API error: ${resendResponse.status} - ${errorText.substring(0, 200)}`);
      return new Response(JSON.stringify({ error: 'Failed to send feedback' }), {
        status: 502,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }

    return new Response(JSON.stringify({ success: true }), {
      status: 200,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });

  } catch (error) {
    console.error(`Feedback error: ${error.message}`);
    return new Response(JSON.stringify({ error: 'Internal server error' }), {
      status: 500,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });
  }
}

// --- Main router ---

export default {
  async fetch(request, env) {
    const corsHeaders = {
      'Access-Control-Allow-Origin': '*',
      'Access-Control-Allow-Methods': 'POST, OPTIONS',
      'Access-Control-Allow-Headers': 'Content-Type, X-Device-Id',
    };

    if (request.method === 'OPTIONS') {
      return new Response(null, { headers: corsHeaders });
    }

    if (request.method !== 'POST') {
      return new Response(JSON.stringify({ error: 'Method not allowed' }), {
        status: 405,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }

    const url = new URL(request.url);

    switch (url.pathname) {
      case '/api/analyze-folder-structure':
        return handleAnalyzeFolderStructure(request, env, corsHeaders);
      case '/api/feedback':
        return handleFeedback(request, env, corsHeaders);
      default:
        return new Response(JSON.stringify({ error: 'Not found' }), {
          status: 404,
          headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        });
    }
  },
};
