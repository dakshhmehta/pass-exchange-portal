<template>
  <f7-page name="login">
    <f7-navbar title="Pass Exchange Portal" />
    <f7-block class="text-align-center" style="margin-top: 15vh">
      <h2>Pass Exchange Portal</h2>
      <p class="opacity-60">Sign in to trade passes</p>
      <f7-button large fill @click="login" :disabled="busy">
        {{ busy ? 'Opening Google…' : 'Sign in with Google' }}
      </f7-button>
      <p v-if="error" class="color-red">{{ error }}</p>
      <p v-if="misconfigured" class="color-red">
        Supabase env vars missing. Add <code>VITE_SUPABASE_URL</code> /
        <code>VITE_SUPABASE_ANON_KEY</code>.
      </p>
    </f7-block>
  </f7-page>
</template>

<script setup>
import { ref } from 'vue';
import { signInWithGoogle } from '../js/store.js';

const busy = ref(false);
const error = ref('');
const misconfigured = !import.meta.env.VITE_SUPABASE_URL || !import.meta.env.VITE_SUPABASE_ANON_KEY;

async function login() {
  busy.value = true;
  error.value = '';
  try {
    await signInWithGoogle();
  } catch (e) {
    error.value = e.message || 'Sign-in failed';
    busy.value = false;
  }
}
</script>
