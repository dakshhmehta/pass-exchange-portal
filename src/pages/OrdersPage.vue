<template>
  <f7-page name="orders" ptr @ptr:refresh="onRefresh">
    <f7-navbar title="Orders & Matches" back-link="Market" />

    <f7-block-title>My Open Orders</f7-block-title>
    <f7-list v-if="orders.length">
      <f7-list-item
        v-for="o in orders"
        :key="o.id"
        :title="o.instruments.name"
        :subtitle="`${o.side} · ${o.status}`"
      >
        <template #after>
          <span class="bidask">
            <span :class="o.side === 'BUY' ? 'color-red' : 'color-green'">
              {{ o.side === 'BUY' ? 'Bid' : 'Ask' }} {{ fmt(o.price) }}
            </span>
            <br />
            <span>Qty {{ o.remaining_qty }}/{{ o.qty }}</span>
          </span>
        </template>
        <template #inner-end>
          <f7-button small outline color="red" @click="cancel(o.id)">Cancel</f7-button>
        </template>
      </f7-list-item>
    </f7-list>
    <f7-block v-else class="opacity-60">No open orders.</f7-block>

    <f7-block-title>My Matches — exchange offline</f7-block-title>
    <f7-block class="opacity-60" v-if="!store.matches.length">
      When your BUY matches a SELL (or vice-versa), the other person's name & mobile appears here so you
      can exchange payment and the pass offline.
    </f7-block>
    <f7-card v-for="m in store.matches" :key="m.trade_id">
      <f7-card-header>
        {{ pname(m.instrument_code) }} · {{ m.my_side }} {{ m.qty }} @ {{ fmt(m.price) }}
        <f7-badge :color="m.completed ? 'green' : 'orange'">{{ m.completed ? 'COMPLETED' : 'MATCHED' }}</f7-badge>
      </f7-card-header>
      <f7-card-content>
        <b>{{ m.counterpart_name || '—' }}</b><br />
        <a :href="`tel:${m.counterpart_mobile}`">{{ m.counterpart_mobile }}</a>
        <br /><small class="opacity-60">{{ new Date(m.created_at).toLocaleString('en-IN') }}</small>
      </f7-card-content>
      <f7-card-footer>
        <f7-button fill small :href="`tel:${m.counterpart_mobile}`">Call</f7-button>
        <f7-button outline small external target="_blank" :href="waLink(m)">WhatsApp</f7-button>
        <f7-button v-if="!m.completed" small outline color="green" @click="dealDone(m.trade_id)">Deal Done</f7-button>
      </f7-card-footer>
    </f7-card>

    <f7-toolbar bottom tabbar>
      <f7-link href="/">Market</f7-link>
      <f7-link tab-link-active href="/orders/">Orders</f7-link>
    </f7-toolbar>
  </f7-page>
</template>

<script setup>
import { ref, onMounted } from 'vue';
import { f7 } from 'framework7-vue';
import { store, refreshSession, needsProfile, loadMyMatches } from '../js/store.js';
import { supabase } from '../js/supabase.js';

const orders = ref([]);
const names = ref({}); // pass_code -> pass name

function pname(code) {
  return names.value[code] || '';
}

function fmt(n) {
  return Number(n).toLocaleString('en-IN', { maximumFractionDigits: 2 });
}

// wa.me needs full international format — normalize Indian mobiles
function waLink(m) {
  let d = (m.counterpart_mobile || '').replace(/\D/g, '');
  if (d.length === 11 && d.startsWith('0')) d = d.slice(1);
  if (d.length === 10) d = '91' + d;
  else if (d.length === 12 && d.startsWith('91')) { /* ok */ }
  const text = encodeURIComponent(
    `Hi ${m.counterpart_name || ''}, we matched on Pass Exchange Portal (${pname(m.instrument_code)}, ${m.qty} @ ${m.price}).`
  );
  return `https://wa.me/${d}?text=${text}`;
}

function dealDone(tradeId) {
  f7.dialog.confirm('Confirm payment & pass exchanged? This marks the deal complete for both sides.', async () => {
    const { error } = await supabase.rpc('mark_match_complete', { p_trade_id: tradeId });
    if (error) f7.dialog.alert(error.message);
    else await reload();
  });
}

async function reload() {
  const { data } = await supabase
    .from('orders')
    .select('id, instrument_code, side, price, qty, remaining_qty, status, created_at, instruments ( name )')
    .eq('user_id', store.user.id)
    .in('status', ['OPEN', 'PARTIAL'])
    .order('created_at', { ascending: false });
  orders.value = data ?? [];
  const { data: insts } = await supabase.from('instruments').select('pass_code, name');
  names.value = Object.fromEntries((insts ?? []).map((i) => [i.pass_code, i.name]));
  await loadMyMatches();
}
async function onRefresh(done) {
  await reload();
  done();
}
async function cancel(id) {
  f7.dialog.confirm('Cancel this order?', async () => {
    const { error } = await supabase.rpc('cancel_my_order', { p_order_id: id });
    if (error) f7.dialog.alert(error.message);
    else await reload();
  });
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
});
</script>
