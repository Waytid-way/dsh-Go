import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.119.1';

const SUPABASE_URL = 'https://tcwlebixkpgvpqijpuqw.supabase.co';
// This browser only uses a public publishable key; privileged credentials are forbidden.
const PUBLIC_KEY = 'sb_publishable_18z1aT6yiApi-pmzee-3pQ_U86J67S6';
const supabase = createClient(SUPABASE_URL, PUBLIC_KEY, {
  auth: { persistSession: true, autoRefreshToken: true, detectSessionInUrl: true }
});

const byId = (id) => document.getElementById(id);
const status = byId('status');
const errorEl = byId('error');
const panelIds = ['login-panel', 'signed-in-panel', 'consent-panel'];
const authorizationId = new URLSearchParams(location.search).get('authorization_id');
function visible(id, show) { byId(id).classList.toggle('hidden', !show); }
function error(message) { errorEl.textContent = message || ''; visible('error', !!message); }
function state(message) { status.textContent = message; }
function redirect(url) {
  try {
    const target = new URL(url);
    if (target.protocol !== 'https:' &&
      !(target.protocol === 'http:' && ['localhost', '127.0.0.1', '[::1]'].includes(target.hostname))) {
      throw new Error('Unexpected redirect scheme');
    }
    // Redirect URL comes from Supabase OAuth client registration/approval.
    location.assign(target.href);
  } catch {
    error('Authorization server returned an invalid redirect URL.');
  }
}
async function render() {
  error('');
  for (const id of panelIds) visible(id, false);
  state('Checking Supabase Auth session…');
  await supabase.auth.getSession();
  const { data, error: userError } = await supabase.auth.getUser();
  const user = userError ? null : data?.user;
  if (!user) {
    visible('login-panel', true);
    state('Sign in with the registered development worker account.');
    return;
  }
  visible('signed-in-panel', true);
  if (!authorizationId) {
    state('Signed in. Return to the private DSH Go Coordination plugin to request authorization.');
    return;
  }
  if (!/^[A-Za-z0-9_-]{8,256}$/.test(authorizationId)) {
    error('Invalid authorization_id.');
    return;
  }
  state('Loading authorization details…');
  const response = await supabase.auth.oauth.getAuthorizationDetails(authorizationId);
  if (response.error || !response.data) {
    state('');
    error('Authorization details unavailable: ' + (response.error?.message || 'expired request'));
    return;
  }
  const details = response.data;
  if (!('authorization_id' in details)) {
    state('Already authorized; returning to client.');
    redirect(details.redirect_url);
    return;
  }
  byId('client-name').textContent = details.client?.name || 'Unknown client';
  byId('redirect-uri').textContent = details.redirect_uri || 'Unknown destination';
  const scopesEl = byId('scopes');
  scopesEl.replaceChildren();
  for (const scope of String(details.scope || '(none)').split(/\s+/).filter(Boolean)) {
    const li = document.createElement('li');
    li.textContent = scope;
    scopesEl.appendChild(li);
  }
  visible('consent-panel', true);
  state('Review client, redirect destination and scopes before approving.');
}
byId('send-link').addEventListener('submit', async (event) => {
  event.preventDefault();
  error('');
  const email = byId('email').value.trim();
  if (!email) return error('Enter the worker email.');
  byId('send-link-button').disabled = true;
  state('Sending one-time sign-in email…');
  try {
    const redirectTo = new URL(location.pathname + location.search, location.origin).href;
    const { error: signInError } = await supabase.auth.signInWithOtp({
      email, options: { shouldCreateUser: false, emailRedirectTo: redirectTo }
    });
    if (signInError) throw signInError;
    state('Check the worker mailbox. Never share the OTP or magic link in chat.');
  } catch (e) { error('Sign-in failed: ' + (e?.message || 'unknown')); }
  finally { byId('send-link-button').disabled = false; }
});
byId('verify-code').addEventListener('submit', async (event) => {
  event.preventDefault();
  error('');
  const email = byId('email').value.trim(), otp = byId('otp').value.trim();
  if (!email || !otp) return error('Enter worker email and OTP.');
  byId('verify-button').disabled = true;
  try {
    const { error: verifyError } = await supabase.auth.verifyOtp({ email, token: otp, type: 'email' });
    if (verifyError) throw verifyError;
    await render();
  } catch (e) { error('OTP verification failed: ' + (e?.message || 'unknown')); }
  finally { byId('verify-button').disabled = false; }
});
byId('signout').addEventListener('click', async () => {
  await supabase.auth.signOut();
  await render();
});
async function decide(approve) {
  if (!authorizationId) return;
  byId('approve').disabled = true;
  byId('deny').disabled = true;
  error('');
  state(approve ? 'Approving…' : 'Denying…');
  try {
    const { data, error: decisionError } = approve
      ? await supabase.auth.oauth.approveAuthorization(authorizationId)
      : await supabase.auth.oauth.denyAuthorization(authorizationId);
    if (decisionError || !data?.redirect_url) throw decisionError || new Error('Missing redirect URL');
    redirect(data.redirect_url);
  } catch (e) {
    error('Authorization failed: ' + (e?.message || 'unknown'));
    byId('approve').disabled = false;
    byId('deny').disabled = false;
  }
}
byId('approve').addEventListener('click', () => decide(true));
byId('deny').addEventListener('click', () => decide(false));
render().catch(() => {
  state('');
  error('Could not initialize Supabase Auth.');
});
