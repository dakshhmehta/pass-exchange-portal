<template>
  <f7-page name="profile" :page-content="true">
    <f7-navbar title="Your Profile" back-link="Back" />
    <f7-block>
      <p class="opacity-60">We need your name and mobile number to settle matched trades offline.</p>
    </f7-block>
    <f7-list form>
      <f7-list-input
        label="Name"
        type="text"
        placeholder="Full name"
        v-model:value="name"
        clear-button
      />
      <f7-list-input
        label="Mobile"
        type="tel"
        placeholder="10-digit mobile"
        v-model:value="mobile"
        clear-button
      />
    </f7-list>
    <f7-block>
      <p class="opacity-60"><small>This mobile number will only be shared with potential buyer/seller when order is matched.</small></p>
      <f7-button large fill @click="save" :disabled="busy">
        {{ busy ? 'Saving…' : 'Save & Continue' }}
      </f7-button>
      <p v-if="error" class="color-red">{{ error }}</p>
    </f7-block>
  </f7-page>
</template>

<script setup>
import { ref } from 'vue';
import { f7 } from 'framework7-vue';
import { store, saveProfile } from '../js/store.js';

const googleName =
  store.user?.user_metadata?.full_name || store.user?.user_metadata?.name || '';
const name = ref(store.profile?.name || googleName);
const mobile = ref(store.profile?.mobile ?? '');
const busy = ref(false);
const error = ref('');

async function save() {
  error.value = '';
  if (!name.value.trim()) {
    error.value = 'Name is required';
    return;
  }
  if (!/^\d{10}$/.test(mobile.value.trim())) {
    error.value = 'Enter a valid 10-digit mobile number';
    return;
  }
  busy.value = true;
  try {
    await saveProfile(name.value, mobile.value);
    f7.views.main.router.navigate('/', { reloadCurrent: true });
  } catch (e) {
    error.value = e.message || 'Save failed';
  } finally {
    busy.value = false;
  }
}
</script>
