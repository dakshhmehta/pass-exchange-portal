<template>
  <f7-page name="detail" ptr @ptr:refresh="onRefresh">
    <f7-navbar :title="meta.name" back-link="Market" />
    <f7-block-title>{{ meta.name }} — Today</f7-block-title>
    <f7-card>
      <f7-card-content>
        <div class="grid grid-cols-3 text-align-center">
          <div><small class="opacity-60">LTP</small><br /><b>{{ ltp == null ? '—' : fmt(ltp) }}</b></div>
          <div><small class="opacity-60">Prev Close</small><br /><b>{{ fmt(meta.prev_close) }}</b></div>
          <div><small class="opacity-60">Volume</small><br /><b>{{ volume }}</b></div>
        </div>
      </f7-card-content>
    </f7-card>

    <!-- Order entry -->
    <f7-block-title>Place Limit Order</f7-block-title>
    <f7-card>
      <f7-card-content>
        <f7-segmented strong tag="p">
          <f7-button :active="side === 'BUY'" @click="side = 'BUY'" color="green">BUY</f7-button>
          <f7-button :active="side === 'SELL'" @click="side = 'SELL'" color="red">SELL</f7-button>
        </f7-segmented>
        <f7-list form class="no-margin">
          <f7-list-input label="Price" type="number" :min="1" :placeholder="`Price at which you want to ${side}`" v-model:value="price" />
          <f7-list-input label="Qty" type="number" :min="1" placeholder="Qty of pass you required" v-model:value="qty" />
        </f7-list>
        <f7-button large fill :color="side === 'BUY' ? 'green' : 'red'" @click="place" :disabled="placing">
          {{ placing ? 'Placing…' : side }}
        </f7-button>
        <p v-if="msg" :class="msgOk ? 'color-green' : 'color-red'">{{ msg }}</p>
        <p class="opacity-60"><small>Limit orders only. Orders expire at midnight.</small></p>
      </f7-card-content>
    </f7-card>

    <!-- Book -->
    <f7-block-title>Order Book (today)</f7-block-title>
    <div class="grid grid-cols-2 grid-gap">
      <f7-card>
        <f7-card-header>Bids</f7-card-header>
        <f7-card-content>
          <div v-for="b in bids" :key="b.price" class="book-row">
            <span class="color-green">{{ fmt(b.price) }}</span><span>{{ b.qty }}</span>
          </div>
          <p v-if="!bids.length" class="opacity-60">No bids</p>
        </f7-card-content>
      </f7-card>
      <f7-card>
        <f7-card-header>Asks</f7-card-header>
        <f7-card-content>
          <div v-for="a in asks" :key="a.price" class="book-row">
            <span class="color-red">{{ fmt(a.price) }}</span><span>{{ a.qty }}</span>
          </div>
          <p v-if="!asks.length" class="opacity-60">No asks</p>
        </f7-card-content>
      </f7-card>
    </div>

    <f7-block-title>Recent Trades</f7-block-title>
    <f7-list v-if="trades.length">
      <f7-list-item
        v-for="t in trades"
        :key="t.id"
        :title="`${t.qty} @ ${fmt(t.price)}`"
        :after="time(t.created_at)"
      />
    </f7-list>
    <f7-block v-else class="opacity-60">No trades today yet.</f7-block>

    <f7-toolbar bottom tabbar>
      <f7-link href="/">Market</f7-link>
      <f7-link href="/orders/">Orders</f7-link>
    </f7-toolbar>
  </f7-page>
</template>

<script setup>
import { ref, onMounted, onUnmounted } from 'vue';
import { f7 } from 'framework7-vue';
import { store, refreshSession, needsProfile, todayStartISO } from '../js/store.js';
import { supabase } from '../js/supabase.js';

const props = defineProps({ f7route: Object });
const code = props.f7route?.params?.code;

const meta = ref({ prev_close: 0, name: '' });
const ltp = ref(null);
const volume = ref(0);
const bids = ref([]);
const asks = ref([]);
const trades = ref([]);

const side = ref('BUY');
const price = ref('');
const qty = ref('');
const placing = ref(false);
const msg = ref('');
const msgOk = ref(false);
let channel = null;

function fmt(n) {
  return Number(n).toLocaleString('en-IN', { maximumFractionDigits: 2 });
}
function time(iso) {
  return new Date(iso).toLocaleTimeString('en-IN', { hour: '2-digit', minute: '2-digit' });
}

async function reload() {
  const since = todayStartISO();
  const { data: inst } = await supabase
    .from('instruments')
    .select('pass_code, name, prev_close')
    .eq('pass_code', code)
    .maybeSingle();
  if (inst) meta.value = inst;

  const { data: ts } = await supabase
    .from('trades')
    .select('id, price, qty, created_at')
    .eq('instrument_code', code)
    .gte('created_at', since)
    .order('created_at', { ascending: false })
    .limit(20);
  trades.value = ts ?? [];
  ltp.value = trades.value.length ? Number(trades.value[0].price) : null;
  volume.value = trades.value.reduce((s, r) => s + Number(r.qty), 0);

  const { data: os } = await supabase
    .from('orders')
    .select('side, price, remaining_qty')
    .eq('instrument_code', code)
    .in('status', ['OPEN', 'PARTIAL'])
    .gte('created_at', since);
  const agg = (rows, s, desc) => {
    const map = new Map();
    for (const r of rows ?? []) {
      if (r.side !== s) continue;
      const p = Number(r.price);
      map.set(p, (map.get(p) ?? 0) + Number(r.remaining_qty));
    }
    return [...map.entries()]
      .map(([p, q]) => ({ price: p, qty: q }))
      .sort((a, b) => (desc ? b.price - a.price : a.price - b.price))
      .slice(0, 10);
  };
  bids.value = agg(os, 'BUY', true);
  asks.value = agg(os, 'SELL', false);
}

async function onRefresh(done) {
  await reload();
  done();
}

async function place() {
  msg.value = '';
  const p = Number(price.value);
  const q = Number(qty.value);
  if (!(p > 0)) {
    msg.value = 'Enter a valid price';
    msgOk.value = false;
    return;
  }
  if (!Number.isInteger(q) || q <= 0) {
    msg.value = 'Enter a valid whole quantity';
    msgOk.value = false;
    return;
  }
  placing.value = true;
  try {
    const { data, error } = await supabase.rpc('place_limit_order', {
      p_instrument: code,
      p_side: side.value,
      p_price: p,
      p_qty: q,
    });
    if (error) throw error;
    const filled = data?.filled ?? 0;
    msg.value = filled > 0 ? `Order placed. Matched ${filled} — see Orders › Matches for contact.` : 'Order placed in book.';
    msgOk.value = true;
    price.value = '';
    qty.value = '';
    await reload();
  } catch (e) {
    msg.value = e.message || 'Order failed';
    msgOk.value = false;
  } finally {
    placing.value = false;
  }
}

onMounted(async () => {
  await refreshSession();
  if (!store.user) {
    f7.views.main.router.navigate('/login/', { reloadCurrent: true });
    return;
  }
  if (needsProfile()) {
    f7.views.main.router.navigate('/profile/', { reloadCurrent: true });
    return;
  }
  await reload();
  channel = supabase
    .channel(`detail-${code}`)
    .on('postgres_changes', { event: '*', schema: 'public', table: 'orders' }, reload)
    .on('postgres_changes', { event: 'INSERT', schema: 'public', table: 'trades' }, reload)
    .subscribe();
});
onUnmounted(() => {
  if (channel) supabase.removeChannel(channel);
});
</script>
