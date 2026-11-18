/**
 * Host 半。
 *
 * 纯客户端插件也要有一个能正常激活的 Host 半：Loader 扫描时如果这一行的
 * fiber 未激活（entry.fiber === undefined），会直接跳过，且不报错。
 * 所以这里至少导出 apply()，哪怕是空实现。
 */
export function apply() {}
