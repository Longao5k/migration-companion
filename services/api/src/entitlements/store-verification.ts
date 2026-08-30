/**
 * 商店收据核验是否已经接通。
 *
 * 现状：`/v1/store-events/verified` 这个入口是有的，但**没有任何进程调用它**。
 * 也就是说，一次真实购买的完整链路是：
 *
 *   用户在 Play 付款 → App 提交收据 → 服务端写一条审计记录 → 结束。
 *
 * 权益永远不会激活。而 App 那边在提交成功后显示「购买已提交并由服务端核验」，
 * 并立刻 `completePurchase` 向 Google 确认收款——退款窗口就此关闭。
 * 用户被扣款、拿不到东西、也退不了。
 *
 * 因此在核验接通之前，购买入口必须是关着的：宁可少卖，不可收了钱不发货。
 * 接通 Google Play Developer API 的核验进程之后，把
 * `STORE_VERIFICATION_ENABLED=true` 打开，购买入口自动恢复。
 *
 * 判定用 `=== 'true'` 而不是 `!== 'false'`：没配置时必须是关闭，
 * 不能靠「忘了配」来决定要不要收钱。
 */
export function storeVerificationEnabled(): boolean {
  return process.env.STORE_VERIFICATION_ENABLED === 'true';
}

export const storePurchasesDisabledMessage =
  '订阅购买暂未开放：服务端尚未接通商店收据核验，' +
  '此时付款无法自动开通权益。开放后会在应用内提示。';
