#!/usr/bin/env node
/**
 * DSH Desktop 客户端插件 · 离线预检（不重启 DSH、不写 profile）
 *
 * 校验三道门禁里的 B 和 C，并把 A 需要的 patch 形状做一次组合演练（需提供 DSH 应用目录）。
 *
 * 用法：
 *   node dsh-preflight.mjs <插件源码目录> [--profile desktop]
 *   DSH_APP="/Applications/DSH Desktop.app/Contents/Resources/app.asar.unpacked" \
 *     node dsh-preflight.mjs ~/.dsh/plugins/your-plugin
 *
 * 退出码：0 全部通过 / 1 有 FAIL
 */
import { readFileSync, existsSync, writeFileSync } from 'node:fs'
import { createRequire } from 'node:module'
import { homedir } from 'node:os'
import { join, resolve, basename } from 'node:path'

const args = process.argv.slice(2)
const pluginDir = resolve(args[0] || '.')
const profileIdx = args.indexOf('--profile')
const profileName = profileIdx >= 0 ? args[profileIdx + 1] : 'desktop'
const profileDir = join(homedir(), '.dsh/profiles', profileName)
const appDir = process.env.DSH_APP || '/Applications/DSH Desktop.app/Contents/Resources/app.asar.unpacked'

let ok = true
const pass = (label, detail) => console.log(`  PASS  ${label}${detail ? '  ' + detail : ''}`)
const fail = (label, detail) => { ok = false; console.log(`  FAIL  ${label}${detail ? '  ' + detail : ''}`) }
const info = (msg) => console.log('  ' + msg)

console.log('=== 门禁 C：元数据与 bundle 文件 ===')
if (!existsSync(pluginDir)) {
  console.error('插件目录不存在: ' + pluginDir)
  process.exit(1)
}
let pkg
try {
  pkg = JSON.parse(readFileSync(join(pluginDir, 'package.json'), 'utf8'))
} catch (error) {
  console.error('package.json 读取失败: ' + error.message)
  process.exit(1)
}

const pkgName = String(pkg.name || '')
if (pkgName === '' || pkgName !== basename(pluginDir)) {
  fail('包名与目录名一致', `name=${pkgName} dir=${basename(pluginDir)}（patch 行必须用同一个名字）`)
} else pass('包名与目录名一致', pkgName)

if (pkg.dsh && pkg.dsh.client && pkg.dsh.client.platform === 'web') pass('dsh.client.platform = web')
else fail('dsh.client.platform', '必须是 "web"')

const clientRel = pkg.exports && pkg.exports['./client']
const clientPath = typeof clientRel === 'string' ? join(pluginDir, clientRel) : ''
if (typeof clientRel === 'string' && existsSync(clientPath)) pass('exports["./client"] 存在', clientRel)
else fail('exports["./client"]', '缺失会抛 "declares dsh.client but exports no ./client bundle"')

const hostRel = pkg.exports && pkg.exports['.']
if (typeof hostRel === 'string' && existsSync(join(pluginDir, hostRel))) pass('Host 半存在', hostRel)
else fail('exports["."]', 'Host 半缺失 → fiber 未激活 → 整行被静默跳过')

if (typeof pkg.exports === 'object' && pkg.exports['./package.json'] !== undefined) pass('exports["./package.json"] 保留')
else fail('exports["./package.json"]', '解析逻辑要读它，建议保留')

console.log('\n=== bundle 形状 ===')
if (clientPath && existsSync(clientPath)) {
  const src = readFileSync(clientPath, 'utf8')
  if (src.includes('window.__ModuleLoader__.load(')) pass('外壳格式 __ModuleLoader__.load')
  else fail('外壳格式', '缺少 window.__ModuleLoader__.load({ id, factory })')

  const idMatch = src.match(/id:\s*["']([^"']+)["']/)
  if (idMatch && idMatch[1] === pkgName) pass('bundle id 与包名一致', idMatch[1])
  else fail('bundle id', `期望 ${pkgName}，实际 ${idMatch ? idMatch[1] : '未找到'}`)

  const requires = [...src.matchAll(/require\(\s*["']([^"']+)["']\s*\)/g)].map((m) => m[1])
  const seeds = new Set(['react', 'react/jsx-runtime', 'react-dom', 'react-dom/client'])
  const unsafe = [...new Set(requires)].filter((s) => !seeds.has(s))
  if (unsafe.length === 0) pass('require 只用平台种子词', requires.length ? [...new Set(requires)].join(', ') : '无 require')
  else fail('require 出现非种子模块', unsafe.join(', ') + '（会抛 missed the module table）')

  if (/\bimport\s+[\w{*]/.test(src) || /=>\s*<[A-Za-z]/.test(src)) fail('未使用 ESM import / JSX', 'bundle 必须是纯 JS + createElement')
  else pass('纯 JS（无 import / JSX）')
}

console.log('\n=== 门禁 B：从 profile 能否解析到包 ===')
try {
  const requireFromProfile = createRequire(join(profileDir, 'package.json'))
  const resolved = requireFromProfile.resolve(pkgName + '/package.json')
  pass('profile 可解析', resolved)
} catch (error) {
  fail('profile 不可解析', `${error.code || error.message} ← 这是"插件装了但不出现"最常见的原因（静默）`)
  info(`修复：在 ${profileDir} 执行 dsh plugin --profile ${profileName} add file:${pluginDir}`)
}

console.log('\n=== 门禁 A：组合演练（需要 DSH 应用目录） ===')
const bootIndex = join(appDir, 'node_modules/@deepseek-ai/dsh-app-boot/lib/index.js')
const basePatch = join(appDir, 'node_modules/@deepseek-ai/dsh-base/cordis.patch.yml')
const webPatch = join(appDir, 'node_modules/@deepseek-ai/dsh-web-app/cordis.patch.yml')
if (!existsSync(bootIndex)) {
  info(`跳过：找不到 ${bootIndex}（用 DSH_APP 环境变量指定应用目录）`)
} else {
  const { composeEntries, loadOverlayPatches } = await import('file://' + bootIndex)
  const tmp = join('/tmp', `dsh-preflight-${process.pid}.yml`)
  writeFileSync(tmp, `- insert:\n    - id: ${pkgName}\n      name: ${pkgName}\n`)
  const layers = [loadOverlayPatches('dsh', basePatch), loadOverlayPatches('dsh', webPatch)]
  const realPatch = join(profileDir, 'cordis.patch.yml')
  if (existsSync(realPatch)) layers.push(loadOverlayPatches('dsh', realPatch))
  const warnings = []
  const entries = composeEntries(layers, (m) => warnings.push(m))
  const proposed = composeEntries([...layers, loadOverlayPatches('dsh', tmp)], (m) => warnings.push(m))
  const existing = entries.filter((e) => e.name === pkgName).length
  const hits = proposed.filter((e) => e.name === pkgName).length
  if (existing > 1 || hits > 1) {
    fail('组合里出现重复行', `已安装 ${existing} 行，演练后 ${hits} 行（重复注册会让插件加载两次）`)
  } else if (existing === 1) {
    pass('patch 行已存在且唯一', `组合后 ${proposed.length} 行`)
  } else if (hits === 1) {
    pass('patch 行可进入组合', `组合后 ${proposed.length} 行，命中 1`)
  } else {
    fail('patch 行未进入组合', '检查 cordis.patch.yml 顶层是否为数组、insert 是否不带 id')
  }
  if (warnings.length > 0) fail('patch 告警', warnings.join(' | '))
  else pass('无 patch 告警')
}

console.log('\n结论: ' + (ok ? 'PASS，可以安装并重启 DSH' : 'FAIL，先修复再安装'))
process.exit(ok ? 0 : 1)
