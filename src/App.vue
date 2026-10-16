<template>
  <f7-app v-bind="f7params">
    <f7-view main url="/" :push-state="true" class="safe-areas" />
  </f7-app>
</template>

<script setup>
import { f7params } from './js/f7params.js';
</script>
