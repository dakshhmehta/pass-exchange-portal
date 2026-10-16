import { reactive } from 'vue';
import { supabase } from './supabase.js';

// Minimal global store — session, profile, market cache.
export const store = reactive({
  session: null,
  user: null,
  profile: null, // { id, name, mobile }
  profileLoaded: false,
  instruments: [], // [{ pass_code, name, prev_close, ltp, volume, changePct }]
  matches: [], // my filled trades w/ counterpart contact
  matchCount: 0,
});

export async function refreshSession() {
  const { data } = await supabase.auth.getSession();
  store.session = data.session ?? null;
  store.user = data.session?.user ?? null;
  if (store.user) await loadProfile();
  else {
    store.profile = null;
    store.profileLoaded = true;
  }
}

export async function loadProfile() {
  store.profileLoaded = false;
  const { data, error } = await supabase
    .from('profiles')
    .select('id, name, mobile')
    .eq('id', store.user.id)
    .maybeSingle();
  if (error) console.warn('[PassX] loadProfile', error.message);
  store.profile = data ?? null;
  store.profileLoaded = true;
}

export function needsProfile() {
  return store.profileLoaded && store.user && (!store.profile?.name || !store.profile?.mobile);
}

export async function saveProfile(name, mobile) {
  const { error } = await supabase
    .from('profiles')
    .upsert({ id: store.user.id, name: name.trim(), mobile: mobile.trim() });
  if (error) throw error;
  await loadProfile();
}

export async function signInWithGoogle() {
  const redirectTo = `${window.location.origin}/`;
  const { error } = await supabase.auth.signInWithOAuth({
    provider: 'google',
    options: { redirectTo },
  });
  if (error) throw error;
}

export async function signOut() {
  await supabase.auth.signOut();
  store.session = null;
  store.user = null;
  store.profile = null;
  store.matches = [];
  store.matchCount = 0;
}

// ---- Market helpers (today = Asia/Kolkata day) ----
function istToday() {
  return new Date().toLocaleDateString('en-CA', { timeZone: 'Asia/Kolkata' }); // YYYY-MM-DD
}
export function todayStartISO() {
  return new Date(istToday() + 'T00:00:00+05:30').toISOString();
}

export async function loadMarket() {
  const { data: insts, error } = await supabase
    .from('instruments')
    .select('pass_code, name, prev_close')
    .eq('is_active', true)
    .order('pass_code');
  if (error) throw error;
  const since = todayStartISO();
  const out = [];
  for (const i of insts ?? []) {
    const { data: trades } = await supabase
      .from('trades')
      .select('price, qty, created_at')
      .eq('instrument_code', i.pass_code)
      .gte('created_at', since)
      .order('created_at', { ascending: false })
      .limit(500);
    const t = trades ?? [];
    const ltp = t.length ? Number(t[0].price) : null;
    const volume = t.reduce((s, r) => s + Number(r.qty), 0);
    const prev = Number(i.prev_close);
    const changePct = ltp != null && prev > 0 ? ((ltp - prev) / prev) * 100 : 0;
    // Best bid (highest BUY) / best ask (lowest SELL) from today's book
    const { data: book } = await supabase
      .from('orders')
      .select('side, price')
      .eq('instrument_code', i.pass_code)
      .in('status', ['OPEN', 'PARTIAL'])
      .gte('created_at', since)
      .limit(1000);
    let bestBid = null;
    let bestAsk = null;
    for (const o of book ?? []) {
      const p = Number(o.price);
      if (o.side === 'BUY') bestBid = bestBid == null ? p : Math.max(bestBid, p);
      else bestAsk = bestAsk == null ? p : Math.min(bestAsk, p);
    }
    out.push({ ...i, ltp, volume, changePct, bestBid, bestAsk });
  }
  store.instruments = out;
}

export async function loadMyMatches() {
  if (!store.user) return;
  const { data, error } = await supabase.rpc('get_my_matches', {
    p_date: istToday(),
  });
  if (error) {
    console.warn('[PassX] get_my_matches', error.message);
    return;
  }
  store.matches = data ?? [];
  store.matchCount = store.matches.length;
}
