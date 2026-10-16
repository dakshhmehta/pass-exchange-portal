<template>
  <f7-page name="market" ptr @ptr:refresh="onRefresh">
    <f7-navbar title="Pass Exchange Portal">
      <f7-nav-right>
        <f7-link href="/orders/" class="position-relative">
          Matches
          <f7-badge v-if="store.matchCount" color="red">{{ store.matchCount }}</f7-badge>
        </f7-link>
        <f7-link href="/profile/">{{ shortName }}</f7-link>
        <f7-link @click="logout">Logout</f7-link>
      </f7-nav-right>
    </f7-navbar>

    <f7-block-title>Market</f7-block-title>
    <f7-block v-if="loading"><f7-skeleton-text>Loading market…</f7-skeleton-text></f7-block>
    <f7-block v-if="error" class="color-red">{{ error }}</f7-block>
    <f7-block v-if="!loading && !store.instruments.length && !error" class="opacity-60">
      No pass codes yet. Ask admin to add instruments in Supabase.
    </f7-block>

    <f7-list media-list v-if="store.instruments.length">
      <f7-list-item
        v-for="m in store.instruments"
        :key="m.pass_code"
        :link="`/pass/${m.pass_code}/`"
        :title="m.name"
      >
        <template #after>
          <span class="bidask">
            <span class="color-red">Bid {{ m.bestBid == null ? '—' : fmt(m.bestBid) }}</span>
            <br />
            <span class="color-green">Ask {{ m.bestAsk == null ? '—' : fmt(m.bestAsk) }}</span>
          </span>
        </template>
        <template #text>
          LTP {{ m.ltp == null ? '—' : fmt(m.ltp) }} · Prev {{ fmt(m.prev_close) }} · Vol {{ m.volume }}
          <span :class="m.changePct >= 0 ? 'color-green' : 'color-red'">
            ({{ m.changePct >= 0 ? '+' : '' }}{{ m.changePct.toFixed(2) }}%)
          </span>
        </template>
      </f7-list-item>
    </f7-list>

    <f7-toolbar bottom tabbar>
      <f7-link tab-link-active href="/">Market</f7-link>
      <f7-link href="/orders/">Orders</f7-link>
    </f7-toolbar>
  </f7-page>
</template>

<script setup>
import { ref, computed, onMounted, onUnmounted } from 'vue';
import { f7 } from 'framework7-vue';
import { store, refreshSession, needsProfile, loadMarket, loadMyMatches, signOut } from '../js/store.js';
import { supabase } from '../js/supabase.js';

const loading = ref(true);
const error = ref('');
let channel = null;

const shortName = computed(() => store.profile?.name?.split(' ')[0] || store.user?.email || 'Profile');

function fmt(n) {
  return Number(n).toLocaleString('en-IN', { maximumFractionDigits: 2 });
}

async function reload() {
  loading.value = true;
  error.value = '';
  try {
    await loadMarket();
    await loadMyMatches();
  } catch (e) {
    error.value = e.message || 'Failed to load market';
  } finally {
    loading.value = false;
  }
}
async function onRefresh(done) {
  await reload();
  done();
}
async function logout() {
  await signOut();
  f7.views.main.router.navigate('/login/', { reloadCurrent: true });
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
  // Realtime: refresh stats on any new trade
  channel = supabase
    .channel('market-trades')
    .on('postgres_changes', { event: 'INSERT', schema: 'public', table: 'trades' }, reload)
    .subscribe();
});
onUnmounted(() => {
  if (channel) supabase.removeChannel(channel);
});
</script>
