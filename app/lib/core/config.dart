const githubRepo = 'Dragon-Huang0403/Deckionary';

const r2BaseUrl = String.fromEnvironment(
  'R2_BASE_URL',
  defaultValue: 'https://r2.deckionary.com',
);

const supabaseUrl = String.fromEnvironment(
  'SUPABASE_URL',
  defaultValue: 'http://127.0.0.1:54321', // local dev
);

const supabaseAnonKey = String.fromEnvironment(
  'SUPABASE_ANON_KEY',
  defaultValue: '', // set via --dart-define for dev/prod
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
