import MarketPage from '../pages/MarketPage.vue';
import DetailPage from '../pages/DetailPage.vue';
import OrdersPage from '../pages/OrdersPage.vue';
import LoginPage from '../pages/LoginPage.vue';
import ProfilePage from '../pages/ProfilePage.vue';

export default [
  { path: '/', component: MarketPage },
  { path: '/pass/:code/', component: DetailPage },
  { path: '/orders/', component: OrdersPage },
  { path: '/login/', component: LoginPage },
  { path: '/profile/', component: ProfilePage },
];
