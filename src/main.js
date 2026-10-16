import { createApp } from 'vue';
import Framework7 from 'framework7/bundle';
import Framework7Vue, { registerComponents } from 'framework7-vue/bundle';
import 'framework7/css/bundle';
import './css/app.css';

import App from './App.vue';
import { f7params } from './js/f7params.js';
import { supabase } from './js/supabase.js';
import { refreshSession } from './js/store.js';

Framework7.use(Framework7Vue);

const app = createApp(App);
registerComponents(app);
app.mount('#app');

// OAuth callback handled by detectSessionInUrl
refreshSession();
supabase.auth.onAuthStateChange(() => refreshSession());
