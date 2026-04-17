const githubRepo = 'Dragon-Huang0403/Deckionary';

const r2BaseUrl = String.fromEnvironment(
  'R2_BASE_URL',
  defaultValue: 'https://r2.deckionary.com',
);

const supabaseUrl = String.fromEnvironment(
  'SUPABASE_URL',
  defaultValue: 'http://127.0.0.1:54321', // local dev
);

// Default: well-known local Supabase demo anon key (from `supabase start`).
// Safe to embed — this key is public, only works against localhost, and
// expires in 2032. Override via --dart-define-from-file=env.json for prod.
const supabaseAnonKey = String.fromEnvironment(
  'SUPABASE_ANON_KEY',
  defaultValue:
      'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0',
);

const sentryDsn = String.fromEnvironment(
  'SENTRY_DSN',
  defaultValue: '', // set via --dart-define for dev/prod
);

const sentryEnvironment = String.fromEnvironment(
  'SENTRY_ENVIRONMENT',
  defaultValue: 'development',
);

const bool isDevBuild = sentryEnvironment != 'production';
