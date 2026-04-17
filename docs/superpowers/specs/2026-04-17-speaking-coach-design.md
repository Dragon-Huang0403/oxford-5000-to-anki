---
title: Speaking Coach Feature — Design Spec
date: 2026-04-17
status: approved
---

# Speaking Coach Feature

## Problem

B1 English learners need a way to practice spontaneous speaking and receive corrections on misused words/phrases to reach B2 fluency. Research shows the key B1-to-B2 gap is spontaneity, natural phrasing, and collocations (~200 guided hours to bridge).

## Solution

A new top-level "Speaking" tab where users:
1. Pick a topic (curated or custom, typed)
2. Speak or type a response (1-2 min)
3. Get AI-powered corrections: what they said, more natural alternative, why
4. Hear natural alternatives via TTS (on demand, cached globally)

## Key Decisions

| Decision | Choice | Rationale |
|---|---|---|
| Stack | OpenAI all-in-one (GPT-4o audio + TTS) | Simplest; swap to Claude later if needed |
| TTS | On-demand only, cached in Supabase | Save tokens; generate once globally |
| Topics | Curated + user-typed; LLM-generated in v2 | Ship fast, expand later |
| Response input | Speak (audio) or type (text) | Flexibility for different environments |
| Backend | Supabase Edge Functions | API keys server-side, swappable |
| Persistence | SpeakingResults synced; TTS audio cached | Full history across devices |
| Navigation | New top-level tab | Core pillar alongside Dictionary and Review |
| Vocabulary integration | Independent v1, vocabulary-driven v2 | Get core loop working first |

## User Flow

1. Speaking tab → browse curated topics by category OR type custom topic
2. Record/input screen → toggle Speak/Type mode → submit
3. Processing → edge function → GPT-4o analysis
4. Results screen → transcript, corrections with TTS play buttons, full natural version
5. Next topic or done

## API Contract

### speaking-analyze

**Request:** multipart (audio + topic) or JSON (text + topic)

**Response:**
```json
{
  "transcript": "...",
  "natural_version": "...",
  "corrections": [
    { "original": "...", "natural": "...", "explanation": "..." }
  ],
  "overall_note": "..."
}
```

### speaking-tts

**Request:** `{ "text": "..." }`
**Response:** audio/mpeg binary (cached in Supabase by SHA-256 hash)

## TTS Caching Flow

1. User taps play → check local SQLite cache → hit? Play.
2. Local miss → call speaking-tts edge function
3. Edge function checks Supabase speaking_audio_cache → hit? Return cached.
4. Supabase miss → call OpenAI TTS → store in Supabase → return audio
5. App caches locally

Audio generated exactly once globally. Second device gets it from Supabase.

## V2 Scope

- LLM-generated topics
- Vocabulary-driven prompts (use SRS words in speaking topics)
- Speaking history analytics
- Swap to Claude for analysis
- Pronunciation scoring
- Streak/gamification
