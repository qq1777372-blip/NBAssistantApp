const http = require('http')
const fs = require('fs')
const os = require('os')
const path = require('path')
const {
  DEMO_USERNAME,
  DEMO_PASSWORD,
  compactDate,
  createDemoUser,
  createSeedData,
  dateOnly,
  dateTime,
  monthKey,
} = require('./demo-seed')

const HOST = '127.0.0.1'
const PORT = Number(process.env.DEMO_PORT || 4174)
const WEB_ROOT = path.join(__dirname, 'www')
const SESSION_COOKIE = 'nbassistant_demo=active'

let demoUser = createDemoUser()
let data = createSeedData(demoUser)
const startedAt = Date.now()

function resetDemoData() {
  demoUser = createDemoUser()
  data = createSeedData(demoUser)
}

function json(res, status, payload, headers = {}) {
  const body = Buffer.from(JSON.stringify(payload))
  res.writeHead(status, {
    'Content-Type': 'application/json; charset=utf-8',
    'Content-Length': body.length,
    'Cache-Control': 'no-store',
    ...headers,
  })
  res.end(body)
}

function empty(res, status = 204, headers = {}) {
  res.writeHead(status, { 'Cache-Control': 'no-store', ...headers })
  res.end()
}

function hasSession(req) {
  return String(req.headers.cookie || '').split(';').some((part) => part.trim() === SESSION_COOKIE)
}

async function readJson(req) {
  const chunks = []
  for await (const chunk of req) chunks.push(chunk)
  if (!chunks.length) return {}
  try {
    return JSON.parse(Buffer.concat(chunks).toString('utf8'))
  } catch {
    return {}
  }
}

async function readRaw(req, limit = 25 * 1024 * 1024) {
  const chunks = []
  let size = 0
  for await (const chunk of req) {
    size += chunk.length
    if (size > limit) throw new Error('上传内容超过本地演示限制')
    chunks.push(chunk)
  }
  return Buffer.concat(chunks)
}

function nextId(items) {
  return Math.max(0, ...items.map((item) => Number(item.id || item.source_record_id || 0))) + 1
}

function taskSummary() {
  return {
    total_records: data.tasks.length,
    principal_total: data.tasks.reduce((sum, item) => sum + Number(item.principal_amount || 0), 0),
    commission_total: data.tasks.reduce((sum, item) => sum + Number(item.commission_amount || 0), 0),
    gift_total: data.tasks.reduce((sum, item) => sum + Number(item.gift_amount || 0), 0),
    pending_signed_count: data.tasks.filter((item) => item.signed_status === 'pending').length,
    pending_settlement_count: data.tasks.filter((item) => item.settlement_status === 'pending').length,
  }
}

function expenseSummary() {
  const monthItems = data.expenses.filter((item) => String(item.expense_date).startsWith(monthKey(0)))
  return {
    month_total: monthItems.reduce((sum, item) => sum + Number(item.amount || 0), 0),
    month_record_count: monthItems.length,
    pending_reimbursement_total: monthItems.filter((item) => item.reimbursement_status === 'pending').reduce((sum, item) => sum + Number(item.amount || 0), 0),
  }
}

function warehouseSummary() {
  return {
    warehouse_count: data.warehouses.length,
    product_count: data.products.length,
    total_quantity: data.stocks.reduce((sum, item) => sum + Number(item.available_quantity || 0), 0),
    total_cost: data.stocks.reduce((sum, item) => {
      const product = data.products.find((candidate) => candidate.id === item.product_id)
      return sum + Number(item.available_quantity || 0) * Number(product?.cost_price || 0)
    }, 0),
    low_stock_count: data.stocks.filter((item) => item.is_low_stock).length,
    today_inbound_quantity: data.inbound.filter((item) => String(item.created_at).startsWith(dateOnly(0))).flatMap((item) => item.items).reduce((sum, item) => sum + Number(item.quantity || 0), 0),
    today_outbound_quantity: data.outbound.filter((item) => String(item.created_at).startsWith(dateOnly(0))).flatMap((item) => item.items).reduce((sum, item) => sum + Number(item.quantity || 0), 0),
    pending_outbound_count: data.outbound.filter((item) => item.status === 'pending').length,
  }
}

function alertPayload(onlyOpen = false) {
  const items = onlyOpen ? data.alerts.filter((item) => !item.acknowledged) : data.alerts
  return {
    open_count: data.alerts.filter((item) => !item.acknowledged).length,
    critical_count: data.alerts.filter((item) => !item.acknowledged && item.severity === 'critical').length,
    items,
  }
}

function searchRows(query = '') {
  const needle = query.trim().toLowerCase()
  const matches = (item) => !needle || Object.values(item).join(' ').toLowerCase().includes(needle)
  const result = {
    shop_records: data.shops.map((item) => ({ id: item.id, category: 'shop_record', title: String(item.values.shop_name || '未命名店铺'), subtitle: String(item.values.platform || ''), detail: String(item.values.owner || '') })).filter(matches),
    license_records: data.licenseRecords.map((item) => ({ id: item.id, category: 'license_record', title: item.subject_name, subtitle: item.credit_code, detail: item.legal_representative })).filter(matches),
    account_usage_records: data.accountUsage.map((item) => ({ id: item.id, category: 'account_usage_record', title: item.account_name, subtitle: item.device_name, detail: item.phone_number })).filter(matches),
    task_bookkeeping_records: data.tasks.map((item) => ({ id: item.id, category: 'task_bookkeeping_record', title: item.order_no, subtitle: item.shop_name, detail: item.owner_name })).filter(matches),
  }
  return result
}

function warehouseLines(rows = []) {
  return rows.map((row) => {
    const product = data.products.find((item) => item.id === Number(row.product_id)) || data.products[0]
    return { product_id: product.id, sku: product.sku, product_name: product.name, unit: product.unit, quantity: Number(row.quantity || 1) }
  })
}

function refreshStockState(stock) {
  const product = data.products.find((item) => item.id === stock.product_id)
  stock.available_quantity = Math.max(0, Number(stock.quantity || 0) - Number(stock.locked_quantity || 0))
  stock.is_low_stock = stock.available_quantity <= Number(product?.warning_quantity || 0)
}

function demoAnswer(question = '') {
  const value = String(question).trim()
  if (/库存|仓库/.test(value)) return '当前共有 4 个演示商品，星河保温杯低于库存预警线。建议优先补货，并核对待处理出库单。'
  if (/任务|待办|签收/.test(value)) return '目前有 5 条任务记录，其中 2 条等待签收、2 条等待结算。可以先处理今日重点任务。'
  if (/利润|经营|日报|总结/.test(value)) return '今日店铺整体经营稳定，云帆数码店销售表现领先。需要关注待签收任务、员工垫付费用和低库存商品。'
  return `这是本地模拟回复：已收到“${value || '演示问题'}”。你可以继续测试消息、历史会话、知识库和工作流界面。`
}

async function handleIntegerCollection(req, res, pathname, basePath, collectionKey, defaults = {}) {
  const method = req.method || 'GET'
  const rows = data[collectionKey]
  if (pathname === basePath) {
    if (method === 'GET') { json(res, 200, rows); return true }
    if (method === 'POST') {
      const body = await readJson(req)
      const item = { id: nextId(rows), ...defaults, ...body }
      delete item.password
      rows.unshift(item)
      json(res, 201, item)
      return true
    }
  }
  if (!pathname.startsWith(`${basePath}/`)) return false
  const parts = pathname.slice(basePath.length + 1).split('/')
  const id = Number(parts[0])
  if (!Number.isInteger(id)) return false
  const index = rows.findIndex((item) => item.id === id)
  if (index < 0) { json(res, 404, { detail: '演示记录不存在' }); return true }
  if (parts[1] === 'image' && method === 'POST') {
    await readRaw(req)
    rows[index].image_url = '/favicon.svg'
    json(res, 200, rows[index])
    return true
  }
  if (parts.length === 1 && method === 'DELETE') { rows.splice(index, 1); empty(res); return true }
  if (parts.length === 1 && (method === 'PUT' || method === 'PATCH')) {
    const body = await readJson(req)
    delete body.password
    Object.assign(rows[index], body)
    json(res, 200, rows[index])
    return true
  }
  return false
}

function isApiPath(pathname) {
  const prefixes = [
    '/health', '/demo/', '/dashboard/', '/global-search',
    '/auth/', '/ui-settings/', '/warehouse/', '/task-bookkeeping/', '/company-expenses',
    '/expense-categories', '/dingtalk-profits', '/custom-fields', '/shop-records', '/saved-links',
    '/system-alerts', '/admin-users', '/search', '/system-settings', '/audit-logs', '/peer-shops',
    '/mobile-devices', '/account-usage-records', '/license-records', '/license-admin/',
    '/software-admin/', '/api/sycm/', '/ai-api/',
  ]
  return prefixes.some((prefix) => pathname.startsWith(prefix))
}

async function handleApi(req, res, url) {
  const pathname = url.pathname
  const method = req.method || 'GET'

  if (!isApiPath(pathname)) return false

  if (pathname === '/health') {
    json(res, 200, { status: 'ok', mode: 'local-demo', uptime_seconds: Math.floor((Date.now() - startedAt) / 1000) })
    return true
  }

  if (pathname === '/auth/login' && method === 'POST') {
    const body = await readJson(req)
    if (body.username !== DEMO_USERNAME || body.password !== DEMO_PASSWORD) {
      json(res, 401, { detail: '账号或密码错误，请使用本地演示账号' })
      return true
    }
    json(res, 200, demoUser, { 'Set-Cookie': `${SESSION_COOKIE}; Path=/; HttpOnly; SameSite=Lax` })
    return true
  }

  if (pathname === '/auth/captcha') {
    json(res, 200, { captcha_id: 'local-demo', image_data: '' })
    return true
  }

  if (pathname === '/auth/logout') {
    empty(res, 204, { 'Set-Cookie': 'nbassistant_demo=; Path=/; Max-Age=0; HttpOnly; SameSite=Lax' })
    return true
  }

  if (!hasSession(req)) {
    json(res, 401, { detail: '请先登录本地演示账号' })
    return true
  }

  if (pathname === '/demo/reset' && method === 'POST') {
    resetDemoData()
    json(res, 200, { ok: true, message: '本地演示数据已恢复', records: Object.values(data).filter(Array.isArray).reduce((sum, rows) => sum + rows.length, 0) })
    return true
  }

  if (pathname === '/auth/me') {
    json(res, 200, demoUser)
    return true
  }

  if (pathname === '/auth/profile' && method === 'PATCH') {
    const body = await readJson(req)
    demoUser.display_name = body.display_name || demoUser.display_name
    json(res, 200, demoUser)
    return true
  }

  if (pathname === '/auth/avatar') {
    if (method === 'DELETE') demoUser.avatar_url = null
    if (method === 'POST') { await readRaw(req); demoUser.avatar_url = '/favicon.svg' }
    json(res, 200, demoUser)
    return true
  }

  if (pathname === '/ui-settings/home-modules') {
    if (method === 'PUT') {
      const body = await readJson(req)
      data.homeModules = Array.isArray(body.value) ? body.value : data.homeModules
    }
    json(res, 200, { key: 'home-modules', value: data.homeModules })
    return true
  }

  if (pathname === '/dashboard/server-status') {
    const memoryPercent = (1 - os.freemem() / os.totalmem()) * 100
    json(res, 200, {
      health: 'healthy', hostname: 'NBAssistant 本地演示', operating_system: `${os.type()} ${os.release()}`,
      architecture: os.arch(), cpu_percent: Math.min(99, os.loadavg()[0] * 12), memory_percent: memoryPercent,
      disk_percent: 36.8, database_count: 1, database_connection_status: '本地内存数据正常',
      services: [
        { name: 'demo-api', display_name: '本地模拟服务', active_state: 'active', sub_state: 'running', is_active: true },
        { name: 'demo-data', display_name: '演示数据集', active_state: 'active', sub_state: 'loaded', is_active: true },
        { name: 'native-app', display_name: 'iOS 客户端', active_state: 'active', sub_state: 'ready', is_active: true },
      ],
    })
    return true
  }

  if (pathname === '/global-search') {
    json(res, 200, searchRows(String(url.searchParams.get('q') || '')))
    return true
  }

  if (pathname === '/warehouse/summary') return json(res, 200, warehouseSummary()), true
  if (pathname === '/warehouse/warehouses') {
    if (method === 'GET') return json(res, 200, data.warehouses), true
    if (method === 'POST') {
      const body = await readJson(req)
      const item = { id: nextId(data.warehouses), code: body.code || `WH-${nextId(data.warehouses)}`, name: body.name || '新仓库', address: body.address || null, contact_name: body.contact_name || null, contact_phone: body.contact_phone || null, is_active: body.is_active !== false, remark: body.remark || null }
      data.warehouses.push(item)
      return json(res, 201, item), true
    }
  }
  const warehouseMatch = pathname.match(/^\/warehouse\/warehouses\/(\d+)$/)
  if (warehouseMatch) {
    const index = data.warehouses.findIndex((item) => item.id === Number(warehouseMatch[1]))
    if (index < 0) return json(res, 404, { detail: '仓库不存在' }), true
    if (method === 'DELETE') { data.warehouses.splice(index, 1); return empty(res), true }
    if (method === 'PUT' || method === 'PATCH') Object.assign(data.warehouses[index], await readJson(req))
    return json(res, 200, data.warehouses[index]), true
  }
  if (pathname === '/warehouse/products') {
    if (method === 'GET') return json(res, 200, data.products), true
    if (method === 'POST') {
      const body = await readJson(req)
      const item = { id: nextId(data.products), sku: body.sku || `SKU-${nextId(data.products)}`, name: body.name || '新商品', barcode: body.barcode || null, specification: body.specification || null, unit: body.unit || '件', cost_price: Number(body.cost_price || 0), warning_quantity: Number(body.warning_quantity || 0), is_active: body.is_active !== false, remark: body.remark || null, image_url: '/favicon.svg' }
      data.products.push(item)
      return json(res, 201, item), true
    }
  }
  const productMatch = pathname.match(/^\/warehouse\/products\/(\d+)$/)
  if (productMatch) {
    const index = data.products.findIndex((item) => item.id === Number(productMatch[1]))
    if (index < 0) return json(res, 404, { detail: '商品不存在' }), true
    if (method === 'DELETE') { data.products.splice(index, 1); return empty(res), true }
    if (method === 'PUT' || method === 'PATCH') Object.assign(data.products[index], await readJson(req))
    return json(res, 200, data.products[index]), true
  }
  if (pathname === '/warehouse/stocks') return json(res, 200, data.stocks), true
  if (pathname === '/warehouse/inbound-orders') {
    if (method === 'GET') return json(res, 200, data.inbound), true
    if (method === 'POST') {
      const body = await readJson(req)
      const warehouse = data.warehouses.find((item) => item.id === Number(body.warehouse_id)) || data.warehouses[0]
      const item = { id: nextId(data.inbound), order_no: `RK-${compactDate(0)}-${String(nextId(data.inbound)).padStart(3, '0')}`, warehouse_id: warehouse.id, warehouse_name: warehouse.name, supplier: body.supplier || '', source_type: body.source_type || 'purchase', status: 'pending', items: warehouseLines(body.items), created_at: new Date().toISOString() }
      data.inbound.unshift(item)
      return json(res, 201, item), true
    }
  }
  const inboundMatch = pathname.match(/^\/warehouse\/inbound-orders\/(\d+)$/)
  if (inboundMatch) {
    const index = data.inbound.findIndex((item) => item.id === Number(inboundMatch[1]))
    if (index < 0) return json(res, 404, { detail: '入库单不存在' }), true
    if (method === 'DELETE') { const [removed] = data.inbound.splice(index, 1); return json(res, 200, removed), true }
  }
  if (pathname === '/warehouse/outbound-orders') {
    if (method === 'GET') return json(res, 200, data.outbound), true
    if (method === 'POST') {
      const body = await readJson(req)
      const warehouse = data.warehouses.find((item) => item.id === Number(body.warehouse_id)) || data.warehouses[0]
      const item = { id: nextId(data.outbound), order_no: `CK-${compactDate(0)}-${String(nextId(data.outbound)).padStart(3, '0')}`, warehouse_id: warehouse.id, warehouse_name: warehouse.name, external_order_no: body.external_order_no || null, recipient_name: body.recipient_name || null, recipient_phone: body.recipient_phone || null, recipient_address: body.recipient_address || null, delivery_method: body.delivery_method || 'shipping', status: 'pending', carrier: body.carrier || null, tracking_no: body.tracking_no || null, items: warehouseLines(body.items), created_at: new Date().toISOString() }
      data.outbound.unshift(item)
      return json(res, 201, item), true
    }
  }
  if (pathname === '/warehouse/movements') return json(res, 200, data.movements), true

  const outboundStatusMatch = pathname.match(/^\/warehouse\/outbound-orders\/(\d+)\/status$/)
  if (outboundStatusMatch && method === 'PATCH') {
    const item = data.outbound.find((candidate) => candidate.id === Number(outboundStatusMatch[1]))
    if (!item) return json(res, 404, { detail: '出库单不存在' }), true
    const body = await readJson(req)
    Object.assign(item, body)
    if (['shipped', 'completed'].includes(item.status) && !item._stock_applied) {
      for (const line of item.items) {
        const stock = data.stocks.find((row) => row.warehouse_id === item.warehouse_id && row.product_id === line.product_id)
        if (!stock) continue
        stock.quantity = Math.max(0, stock.quantity - line.quantity)
        refreshStockState(stock)
        data.movements.unshift({ id: nextId(data.movements), movement_type: 'outbound', warehouse_name: item.warehouse_name, sku: line.sku, product_name: line.product_name, quantity_change: -line.quantity, quantity_after: stock.quantity, operator_username: DEMO_USERNAME, reference_no: item.order_no, created_at: new Date().toISOString() })
      }
      item._stock_applied = true
    }
    json(res, 200, item)
    return true
  }

  if (pathname === '/task-bookkeeping/summary') return json(res, 200, taskSummary()), true
  if (pathname === '/task-bookkeeping/owners') {
    if (method === 'POST') {
      const body = await readJson(req)
      const item = { id: nextId(data.owners), name: body.name || '新负责人', owner_name: body.name || '新负责人', created_at: new Date().toISOString() }
      data.owners.push(item)
      return json(res, 201, item), true
    }
    json(res, 200, data.owners)
    return true
  }
  const ownerMatch = pathname.match(/^\/task-bookkeeping\/owners\/(\d+)$/)
  if (ownerMatch && method === 'DELETE') {
    const index = data.owners.findIndex((item) => item.id === Number(ownerMatch[1]))
    if (index >= 0) data.owners.splice(index, 1)
    empty(res)
    return true
  }
  if (pathname === '/task-bookkeeping/shops') {
    json(res, 200, data.shops.map((item) => ({ id: item.id, name: item.values.shop_name, shop_name: item.values.shop_name })))
    return true
  }
  if (pathname === '/task-bookkeeping/records/batch-status' && method === 'PATCH') {
    const body = await readJson(req)
    data.tasks.forEach((item) => {
      if (body.record_ids?.includes(item.id) && ['signed_status', 'settlement_status'].includes(body.field)) item[body.field] = body.value
    })
    json(res, 200, { updated: body.record_ids?.length || 0 })
    return true
  }
  if (pathname === '/task-bookkeeping/records/batch-delete' && method === 'POST') {
    const body = await readJson(req)
    data.tasks = data.tasks.filter((item) => !body.record_ids?.includes(item.id))
    empty(res)
    return true
  }
  if (pathname === '/task-bookkeeping/records') {
    if (method === 'POST') {
      const body = await readJson(req)
      const id = nextId(data.tasks)
      const item = {
        id, order_no: body.order_no || `RW-${compactDate(0)}-${String(id).padStart(3, '0')}`,
        task_time: body.task_time || new Date().toISOString(), shop_name: body.shop_name || '未指定店铺',
        owner_name: body.owner_name || '未分配', order_count: Number(body.order_count || 0),
        principal_amount: Number(body.principal_amount || 0), commission_amount: Number(body.commission_amount || 0),
        gift_amount: Number(body.gift_amount || 0), signed_status: body.signed_status || 'pending',
        settlement_status: body.settlement_status || 'pending', note: body.note || null,
      }
      data.tasks.unshift(item)
      return json(res, 201, item), true
    }
    const query = String(url.searchParams.get('q') || '').toLowerCase()
    const offset = Number(url.searchParams.get('offset') || 0)
    const limit = Number(url.searchParams.get('limit') || 100)
    const items = data.tasks.filter((item) => !query || Object.values(item).join(' ').toLowerCase().includes(query))
    json(res, 200, items.slice(offset, offset + limit))
    return true
  }
  const taskMatch = pathname.match(/^\/task-bookkeeping\/records\/(\d+)$/)
  if (taskMatch) {
    const index = data.tasks.findIndex((item) => item.id === Number(taskMatch[1]))
    if (index < 0) return json(res, 404, { detail: '任务记录不存在' }), true
    if (method === 'DELETE') {
      data.tasks.splice(index, 1)
      return empty(res), true
    }
    if (method === 'PUT' || method === 'PATCH') Object.assign(data.tasks[index], await readJson(req))
    json(res, 200, data.tasks[index])
    return true
  }

  if (pathname === '/custom-fields/reorder' && method === 'POST') {
    const body = await readJson(req)
    for (const [index, id] of (body.field_ids || []).entries()) {
      const field = data.customFields.find((item) => item.id === Number(id))
      if (field) field.sort_order = index + 1
    }
    return empty(res), true
  }
  if (pathname === '/custom-fields') {
    if (method === 'GET') return json(res, 200, data.customFields), true
    if (method === 'POST') {
      const body = await readJson(req)
      const item = { id: nextId(data.customFields), field_name: body.field_name || `field_${Date.now()}`, label: body.label || '新字段', field_type: body.field_type || 'text', required: Boolean(body.required), is_required: Boolean(body.required), is_visible: true, is_builtin: false, sort_order: data.customFields.length + 1 }
      data.customFields.push(item)
      return json(res, 201, item), true
    }
  }
  const customFieldMatch = pathname.match(/^\/custom-fields\/(\d+)$/)
  if (customFieldMatch) {
    const index = data.customFields.findIndex((item) => item.id === Number(customFieldMatch[1]))
    if (index < 0) return json(res, 404, { detail: '字段不存在' }), true
    if (method === 'DELETE') { data.customFields.splice(index, 1); return empty(res), true }
    if (method === 'PUT' || method === 'PATCH') {
      const body = await readJson(req)
      Object.assign(data.customFields[index], body)
      if (Object.hasOwn(body, 'required')) data.customFields[index].is_required = Boolean(body.required)
    }
    return json(res, 200, data.customFields[index]), true
  }
  if (pathname === '/shop-records/batch-delete' && method === 'POST') {
    const body = await readJson(req)
    data.shops = data.shops.filter((item) => !body.record_ids?.includes(item.id))
    return empty(res), true
  }
  if (pathname === '/shop-records') {
    if (method === 'POST') {
      const body = await readJson(req)
      const item = { id: nextId(data.shops), values: body.values || body, created_at: new Date().toISOString(), updated_at: new Date().toISOString() }
      data.shops.unshift(item)
      return json(res, 201, item), true
    }
    json(res, 200, data.shops)
    return true
  }
  const shopMatch = pathname.match(/^\/shop-records\/(\d+)$/)
  if (shopMatch) {
    const index = data.shops.findIndex((item) => item.id === Number(shopMatch[1]))
    if (index < 0) return json(res, 404, { detail: '店铺记录不存在' }), true
    if (method === 'DELETE') {
      data.shops.splice(index, 1)
      return empty(res), true
    }
    if (method === 'PUT' || method === 'PATCH') {
      const body = await readJson(req)
      Object.assign(data.shops[index], body, { values: body.values || data.shops[index].values, updated_at: new Date().toISOString() })
    }
    json(res, 200, data.shops[index])
    return true
  }

  if (pathname === '/company-expenses/summary') return json(res, 200, expenseSummary()), true
  if (pathname === '/expense-categories') {
    if (method === 'PUT') {
      const body = await readJson(req)
      if (Array.isArray(body.categories)) data.expenseCategories = body.categories.filter(Boolean)
    }
    const usage = Object.fromEntries(data.expenseCategories.map((category) => [category, data.expenses.filter((item) => item.category === category).length]))
    json(res, 200, {
      categories: data.expenseCategories,
      is_default: false,
      usage,
      orphan_categories: [...new Set(data.expenses.map((item) => item.category).filter((category) => !data.expenseCategories.includes(category)))],
    })
    return true
  }
  if (pathname === '/company-expenses') {
    if (method === 'POST') {
      const body = await readJson(req)
      const id = nextId(data.expenses)
      const item = {
        id, expense_no: body.expense_no || `FY-${compactDate(0)}-${String(id).padStart(3, '0')}`,
        expense_date: body.expense_date || dateOnly(0), amount: Number(body.amount || 0),
        category: body.category || data.expenseCategories[0], payment_type: body.payment_type || 'company',
        payment_account: body.payment_account || '公司账户', expense_scope: body.expense_scope || '公共费用',
        description: body.description || '', submitter_name: body.submitter_name || demoUser.display_name,
        reimbursement_status: body.reimbursement_status || 'not_required', attachment_url: null,
        created_at: new Date().toISOString(),
      }
      data.expenses.unshift(item)
      return json(res, 201, item), true
    }
    json(res, 200, data.expenses)
    return true
  }
  const expenseAttachmentMatch = pathname.match(/^\/company-expenses\/(\d+)\/attachment$/)
  if (expenseAttachmentMatch && method === 'POST') {
    const item = data.expenses.find((row) => row.id === Number(expenseAttachmentMatch[1]))
    if (!item) return json(res, 404, { detail: '记账记录不存在' }), true
    await readRaw(req)
    item.attachment_url = '/favicon.svg'
    return json(res, 200, item), true
  }
  const expenseMatch = pathname.match(/^\/company-expenses\/(\d+)$/)
  if (expenseMatch) {
    const index = data.expenses.findIndex((item) => item.id === Number(expenseMatch[1]))
    if (index < 0) return json(res, 404, { detail: '记账记录不存在' }), true
    if (method === 'DELETE') {
      data.expenses.splice(index, 1)
      return empty(res), true
    }
    if (method === 'PUT' || method === 'PATCH') Object.assign(data.expenses[index], await readJson(req))
    json(res, 200, data.expenses[index])
    return true
  }

  if (pathname === '/dingtalk-profits/summary') {
    json(res, 200, {
      total_profit: data.profits.reduce((sum, item) => sum + Number(item.profit || 0), 0),
      unique_store_count: new Set(data.profits.map((item) => item.store_name)).size,
      unique_reporter_count: new Set(data.profits.map((item) => item.reporter_name)).size,
    })
    return true
  }
  if (pathname === '/dingtalk-profits/monthly-summary') return json(res, 200, data.monthlyProfits), true
  if (pathname === '/dingtalk-profits') return json(res, 200, data.profits), true

  if (pathname === '/saved-links') {
    if (method === 'POST') {
      const body = await readJson(req)
      const now = new Date().toISOString()
      const item = {
        id: nextId(data.links), title: body.title || '新收藏链接', url: body.url || null,
        category: body.category || null, description: body.description || null,
        author_user_id: demoUser.id, author_username: demoUser.username, author_avatar_url: demoUser.avatar_url,
        images: [], is_pinned: false, sort_order: data.links.length + 1, push_status: 'idle',
        push_scheduled_at: null, push_sent_at: null, push_error: null, created_at: now, updated_at: now,
      }
      data.links.unshift(item)
      return json(res, 201, item), true
    }
    const offset = Number(url.searchParams.get('offset') || 0)
    const limit = Number(url.searchParams.get('limit') || 30)
    json(res, 200, data.links.slice(offset, offset + limit))
    return true
  }
  const linkImagesMatch = pathname.match(/^\/saved-links\/(\d+)\/images\/append$/)
  if (linkImagesMatch && method === 'POST') {
    const item = data.links.find((candidate) => candidate.id === Number(linkImagesMatch[1]))
    if (!item) return json(res, 404, { detail: '链接不存在' }), true
    const raw = await readRaw(req)
    const names = [...raw.toString('latin1').matchAll(/filename="([^"]+)"/g)].map((match) => match[1])
    for (const name of (names.length ? names : ['演示图片.jpg'])) item.images.push({ id: Date.now() + item.images.length, storage_name: name, name, url: '/favicon.svg' })
    item.updated_at = new Date().toISOString()
    return json(res, 200, item), true
  }
  const linkActionMatch = pathname.match(/^\/saved-links\/(\d+)\/(pin|push)$/)
  if (linkActionMatch) {
    const item = data.links.find((candidate) => candidate.id === Number(linkActionMatch[1]))
    if (!item) return json(res, 404, { detail: '链接不存在' }), true
    if (linkActionMatch[2] === 'pin') item.is_pinned = method !== 'DELETE'
    if (linkActionMatch[2] === 'push') {
      const body = method === 'POST' ? await readJson(req) : {}
      item.push_scheduled_at = body.scheduled_at || null
      item.push_status = item.push_scheduled_at ? 'scheduled' : 'sent'
      item.push_sent_at = item.push_scheduled_at ? null : new Date().toISOString()
      item.push_error = null
    }
    item.updated_at = new Date().toISOString()
    json(res, 200, item)
    return true
  }
  const linkMatch = pathname.match(/^\/saved-links\/(\d+)$/)
  if (linkMatch) {
    const index = data.links.findIndex((item) => item.id === Number(linkMatch[1]))
    if (index < 0) return json(res, 404, { detail: '链接不存在' }), true
    if (method === 'DELETE') {
      data.links.splice(index, 1)
      return empty(res), true
    }
    if (method === 'PUT' || method === 'PATCH') Object.assign(data.links[index], await readJson(req), { updated_at: new Date().toISOString() })
    json(res, 200, data.links[index])
    return true
  }

  if (pathname === '/system-alerts') {
    json(res, 200, alertPayload(url.searchParams.get('status_filter') === 'open'))
    return true
  }
  const alertMatch = pathname.match(/^\/system-alerts\/(.+)$/)
  if (alertMatch && method === 'PATCH') {
    const item = data.alerts.find((candidate) => candidate.key === decodeURIComponent(alertMatch[1]))
    if (!item) return json(res, 404, { detail: '提醒不存在' }), true
    Object.assign(item, await readJson(req))
    json(res, 200, item)
    return true
  }

  if (pathname === '/admin-users') {
    if (method === 'POST') {
      const body = await readJson(req)
      const item = { id: nextId(data.adminUsers), username: body.username || `user${nextId(data.adminUsers)}`, display_name: body.display_name || body.username || '新用户', role: body.role || 'viewer', is_active: true, permissions: body.permissions || {} }
      data.adminUsers.push(item)
      return json(res, 201, item), true
    }
    json(res, 200, data.adminUsers)
    return true
  }
  const adminActionMatch = pathname.match(/^\/admin-users\/(\d+)(?:\/(status|password))?$/)
  if (adminActionMatch) {
    const item = data.adminUsers.find((candidate) => candidate.id === Number(adminActionMatch[1]))
    if (!item) return json(res, 404, { detail: '账号不存在' }), true
    if (adminActionMatch[2] !== 'password') Object.assign(item, await readJson(req))
    json(res, 200, item)
    return true
  }

  if (pathname === '/search') {
    const groups = searchRows(String(url.searchParams.get('q') || ''))
    const items = Object.values(groups).flat()
    json(res, 200, items)
    return true
  }

  if (pathname === '/audit-logs') {
    return json(res, 200, [
      { id: 1, action: 'login', username: 'demo', detail: '登录本地演示环境', created_at: dateTime(0, 9) },
      { id: 2, action: 'update', username: 'demo', detail: '更新仓库出库状态', created_at: dateTime(0, 10, 20) },
      { id: 3, action: 'create', username: 'operator', detail: '新增任务记账记录', created_at: dateTime(1, 16, 40) },
    ]), true
  }

  if (pathname === '/account-usage-records/batch-status' && method === 'PATCH') {
    const body = await readJson(req)
    for (const item of data.accountUsage) if ((body.record_ids || []).includes(item.id)) item.is_banned = Boolean(body.is_banned)
    return empty(res), true
  }
  if (await handleIntegerCollection(req, res, pathname, '/peer-shops', 'peerShops', { shop_name: '新同行店铺', shop_url: null, remark: null, image_url: null })) return true
  if (await handleIntegerCollection(req, res, pathname, '/mobile-devices', 'mobileDevices', { device_name: '新设备', primary_card: null, secondary_card: null, remark: null })) return true
  if (await handleIntegerCollection(req, res, pathname, '/account-usage-records', 'accountUsage', { account_name: '新账号', phone_number: null, device_name: null, usage_notes: null, is_banned: false, banned_reason: null })) return true
  if (await handleIntegerCollection(req, res, pathname, '/license-records', 'licenseRecords', { subject_name: '新主体', credit_code: `DEMO-${Date.now()}`, legal_representative: null, issue_date: null, expiry_date: null, remark: null, image_url: null })) return true

  if (pathname === '/software-admin/users') return json(res, 200, data.adminUsers), true
  if (pathname === '/license-admin/stats') return json(res, 200, { total: data.licenses.length, active: data.licenses.filter((item) => item.status === 'active').length, expired: data.licenses.filter((item) => item.status === 'expired').length, devices: data.licenses.flatMap((item) => item.devices).length }), true
  if (pathname === '/license-admin/licenses') {
    if (method === 'GET') return json(res, 200, data.licenses), true
    if (method === 'POST') {
      const body = await readJson(req)
      const count = Math.max(1, Math.min(20, Number(body.count || 1)))
      const generated = Array.from({ length: count }, (_, index) => ({ license_key: `DEMO-${compactDate(0)}-${String(Date.now() + index).slice(-8)}`, plan_name: body.plan_name || '本地演示版', status: 'active', max_devices: Number(body.max_devices || 1), expires_at: dateOnly(-Number(body.duration_days || 365)), devices: [] }))
      data.licenses.unshift(...generated)
      return json(res, 201, generated), true
    }
  }
  const licenseAction = pathname.match(/^\/license-admin\/licenses\/([^/]+)\/(status|unbind)$/)
  if (licenseAction && method === 'POST') {
    const item = data.licenses.find((row) => row.license_key === decodeURIComponent(licenseAction[1]))
    if (!item) return json(res, 404, { detail: '授权码不存在' }), true
    const body = await readJson(req)
    if (licenseAction[2] === 'status') item.status = body.status || item.status
    else item.devices = item.devices.filter((device) => device.device_id !== body.device_id)
    return json(res, 200, item), true
  }

  if (pathname === '/system-settings') {
    if (method === 'PUT' || method === 'PATCH') Object.assign(data.systemSettings, await readJson(req))
    return json(res, 200, data.systemSettings), true
  }

  if (pathname === '/api/sycm/latest') {
    const factor = { today: 0.08, yesterday: 0.075, recent7: 0.45, recent30: 1 }[url.searchParams.get('period')] || 1
    const rows = data.sycmShops.map((shop) => {
      const scaled = { ...shop, overview: {} }
      for (const key of ['uv', 'pv', 'cartByrCnt', 'payByrCnt', 'payAmt']) {
        scaled[key] = Math.round(Number(shop[key] || 0) * factor * 100) / 100
        scaled.overview[key] = { value: scaled[key] }
      }
      return scaled
    })
    return json(res, 200, rows), true
  }
  if (pathname === '/api/sycm/collector-devices') return json(res, 200, data.sycmDevices), true
  if (pathname === '/api/sycm/sync-requests' && method === 'GET') return json(res, 200, data.sycmSyncRequests), true
  if (pathname === '/api/sycm/sync-requests' && method === 'POST') {
    const item = { id: nextId(data.sycmSyncRequests), period: 'today', status: 'completed', created_at: new Date().toISOString() }
    data.sycmSyncRequests.unshift(item)
    return json(res, 201, item), true
  }
  if (pathname === '/api/sycm/sync-requests/latest') return json(res, 200, data.sycmSyncRequests[0] || null), true

  if (pathname.startsWith('/ai-api/')) {
    if (pathname === '/ai-api/models' && method === 'GET') return json(res, 200, { models: data.aiModels }), true
    if (pathname === '/ai-api/models' && method === 'POST') {
      const body = await readJson(req); const item = { id: body.id || `model-${Date.now()}`, name: body.name || '新模型', base_model: body.base_model || 'demo-model', model_type: body.model_type || 'chat', enabled: body.enabled === false ? 0 : 1, hidden: 0, temperature: Number(body.temperature || 0.7), top_p: Number(body.top_p || 1), max_tokens: Number(body.max_tokens || 4096), description: body.description || null, system_prompt: body.system_prompt || null, connection_id: body.connection_id || data.aiConnections[0]?.id || null }; data.aiModels.push(item); return json(res, 201, item), true
    }
    if (pathname === '/ai-api/models/update' && method === 'POST') { const body = await readJson(req); const item = data.aiModels.find((row) => row.id === body.id); if (item) { Object.assign(item, body); item.enabled = body.enabled === false ? 0 : Number(body.enabled ?? item.enabled) }; return empty(res), true }
    if (pathname === '/ai-api/models/delete' && method === 'POST') { const body = await readJson(req); data.aiModels = data.aiModels.filter((item) => item.id !== body.id); return empty(res), true }
    if (pathname === '/ai-api/models/sync' && method === 'POST') return json(res, 200, { total: data.aiModels.length }), true

    if (pathname === '/ai-api/connections' && method === 'GET') return json(res, 200, { connections: data.aiConnections }), true
    if (pathname === '/ai-api/connections/save' && method === 'POST') { const body = await readJson(req); let item = data.aiConnections.find((row) => row.id === body.id); if (!item) { item = { id: body.id || `conn-${Date.now()}`, has_key: Boolean(body.api_key) }; data.aiConnections.push(item) }; Object.assign(item, body, { enabled: body.enabled === false ? 0 : 1, has_key: item.has_key || Boolean(body.api_key) }); delete item.api_key; return empty(res), true }
    if (pathname === '/ai-api/connections/toggle' && method === 'POST') { const body = await readJson(req); const item = data.aiConnections.find((row) => row.id === body.id); if (item) item.enabled = body.enabled ? 1 : 0; return empty(res), true }
    if (pathname === '/ai-api/connections/test' && method === 'POST') return json(res, 200, { message: '本地模拟连接正常' }), true
    if (pathname === '/ai-api/connections/sync' && method === 'POST') return json(res, 200, { total: data.aiModels.length }), true

    if (pathname === '/ai-api/chats' && method === 'GET') return json(res, 200, { chats: data.aiChats }), true
    if (pathname === '/ai-api/chats/save' && method === 'POST') { const body = await readJson(req); let item = data.aiChats.find((row) => row.id === body.id); const now = Math.floor(Date.now() / 1000); if (!item) { item = { id: body.id || `chat-${Date.now()}`, created_at: body.created_at || now }; data.aiChats.unshift(item) }; Object.assign(item, { title: body.title || '新对话', messages: body.messages || [], model_id: body.model_id || null, favorite: Boolean(body.favorite), archived: Boolean(body.archived), folder: body.folder || '', updated_at: now }); return empty(res), true }
    if (pathname === '/ai-api/chats/delete' && method === 'POST') { const body = await readJson(req); data.aiChats = data.aiChats.filter((item) => item.id !== body.id); return empty(res), true }
    if (pathname === '/ai-api/chat' && method === 'POST') { const body = await readJson(req); return json(res, 200, { content: demoAnswer(body.question) }), true }
    if (pathname === '/ai-api/chat/stream' && method === 'POST') { const body = await readJson(req); const answer = demoAnswer(body.question); res.writeHead(200, { 'Content-Type': 'application/x-ndjson; charset=utf-8', 'Cache-Control': 'no-store' }); for (const part of answer.match(/.{1,18}/gu) || [answer]) res.write(`${JSON.stringify({ content: part })}\n`); res.end(); return true }

    if (pathname === '/ai-api/knowledge' && method === 'GET') return json(res, 200, { knowledge: data.aiKnowledge }), true
    if (pathname === '/ai-api/knowledge' && method === 'POST') { const body = await readJson(req); let item = data.aiKnowledge.find((row) => row.id === body.id); if (!item) { item = { id: body.id || `knowledge-${Date.now()}`, description: body.description || null }; data.aiKnowledge.push(item) }; item.name = body.name || item.name || '新知识库'; return empty(res), true }
    if (pathname === '/ai-api/files' && method === 'GET') return json(res, 200, { files: data.aiFiles }), true
    if (pathname === '/ai-api/files/detail' && method === 'GET') { const file = data.aiFiles.find((item) => item.id === url.searchParams.get('id')); if (!file) return json(res, 404, { detail: '文件不存在' }), true; return json(res, 200, { file, chunks: [{ id: `${file.id}-chunk-1`, chunk_index: 0, content: file.content || '本地演示文件内容' }] }), true }
    if (pathname === '/ai-api/documents/import-file' && method === 'POST') { const body = await readJson(req); const file = { id: `file-${Date.now()}`, name: body.filename || body.title || '演示文档.txt', knowledge_id: null, status: 'ready', content: '这是导入后的本地模拟文档内容。' }; data.aiFiles.unshift(file); return json(res, 201, { file }), true }
    if (pathname === '/ai-api/files/assign' && method === 'POST') { const body = await readJson(req); const file = data.aiFiles.find((item) => item.id === body.file_id); if (file) file.knowledge_id = body.knowledge_id; return empty(res), true }
    if (pathname === '/ai-api/files/reprocess' && method === 'POST') return empty(res), true
    if (pathname === '/ai-api/files/delete' && method === 'POST') { const body = await readJson(req); data.aiFiles = data.aiFiles.filter((item) => item.id !== body.id); return empty(res), true }

    const capabilities = { prompts: 'aiPrompts', skills: 'aiSkills', tools: 'aiTools', notes: 'aiNotes' }
    for (const [name, key] of Object.entries(capabilities)) {
      if (pathname === `/ai-api/${name}` && method === 'GET') return json(res, 200, { [name]: data[key] }), true
      if (pathname === `/ai-api/${name}` && method === 'POST') { const body = await readJson(req); const item = { id: body.id || `${name}-${Date.now()}`, ...body, enabled: body.enabled === false ? 0 : 1 }; data[key].push(item); return empty(res), true }
      if (pathname === `/ai-api/${name}/update` && method === 'POST') { const body = await readJson(req); const item = data[key].find((row) => row.id === body.id); if (item) Object.assign(item, body, { enabled: body.enabled === false ? 0 : Number(body.enabled ?? item.enabled ?? 1) }); return empty(res), true }
      if (pathname === `/ai-api/${name}/delete` && method === 'POST') { const body = await readJson(req); data[key] = data[key].filter((item) => item.id !== body.id); return empty(res), true }
    }

    if (pathname === '/ai-api/usage') { const input = data.aiUsage.reduce((sum, item) => sum + item.input_tokens, 0); const output = data.aiUsage.reduce((sum, item) => sum + item.output_tokens, 0); return json(res, 200, { usage: data.aiUsage, summary: { calls: data.aiUsage.length, input_tokens: input, output_tokens: output, cost: 0 } }), true }
    if (pathname === '/ai-api/memories' && method === 'GET') return json(res, 200, { memories: data.aiMemories }), true
    if (pathname === '/ai-api/memories' && method === 'POST') { const body = await readJson(req); let item = data.aiMemories.find((row) => row.id === body.id); if (!item) { item = { id: body.id || `memory-${Date.now()}` }; data.aiMemories.unshift(item) }; Object.assign(item, body, { enabled: body.enabled === false ? 0 : 1 }); return empty(res), true }
    if (pathname === '/ai-api/memories/delete' && method === 'POST') { const body = await readJson(req); data.aiMemories = data.aiMemories.filter((item) => item.id !== body.id); return empty(res), true }
    if (pathname === '/ai-api/workflows' && method === 'GET') return json(res, 200, { workflows: data.aiWorkflows }), true
    if (pathname === '/ai-api/workflows' && method === 'POST') { const body = await readJson(req); let item = data.aiWorkflows.find((row) => row.id === body.id); if (!item) { item = { id: body.id || `workflow-${Date.now()}` }; data.aiWorkflows.unshift(item) }; Object.assign(item, body, { steps: typeof body.steps === 'string' ? body.steps : JSON.stringify(body.steps || []), enabled: body.enabled === false ? 0 : 1 }); return empty(res), true }
    if (pathname === '/ai-api/workflows/delete' && method === 'POST') { const body = await readJson(req); data.aiWorkflows = data.aiWorkflows.filter((item) => item.id !== body.id); return empty(res), true }
    if (pathname === '/ai-api/workflows/run' && method === 'POST') { const body = await readJson(req); const job = { id: `job-${Date.now()}`, kind: '本地工作流', status: 'completed', output: JSON.stringify({ result: `已处理：${body.input || '演示输入'}` }), error: null }; data.aiJobs.unshift(job); return json(res, 200, { job_id: job.id, status: job.status }), true }
    if (pathname === '/ai-api/jobs' && method === 'GET') return json(res, 200, { jobs: data.aiJobs }), true
    if (/^\/ai-api\/jobs\/(retry|cancel|delete)$/.test(pathname) && method === 'POST') { const body = await readJson(req); const action = pathname.split('/').pop(); const job = data.aiJobs.find((item) => item.id === body.id); if (action === 'delete') data.aiJobs = data.aiJobs.filter((item) => item.id !== body.id); else if (job) job.status = action === 'retry' ? 'completed' : 'cancelled'; return empty(res), true }
    if (pathname === '/ai-api/shares') return json(res, 200, { shares: data.aiShares }), true
    if (pathname === '/ai-api/images/generations' && method === 'POST') return json(res, 200, { url: `http://${req.headers.host || `${HOST}:${PORT}`}/favicon.svg` }), true
    if (pathname === '/ai-api/audio/transcriptions' && method === 'POST') return json(res, 200, { text: '请帮我生成今天的经营简报' }), true
    if ((pathname === '/ai-api/search' || pathname === '/ai-api/web-search') && method === 'POST') return json(res, 200, { documents: [{ title: '本地演示资料', content: '经营数据整体稳定，注意待签收任务和低库存商品。', url: 'https://example.com/local-demo' }] }), true
    return json(res, 501, { detail: `该 AI 演示操作暂未实现: ${method} ${pathname}` }), true
  }

  json(res, 501, { detail: `该本地演示操作暂未实现: ${method} ${pathname}` })
  return true
}

const MIME_TYPES = {
  '.html': 'text/html; charset=utf-8',
  '.js': 'text/javascript; charset=utf-8',
  '.css': 'text/css; charset=utf-8',
  '.json': 'application/json; charset=utf-8',
  '.webmanifest': 'application/manifest+json; charset=utf-8',
  '.svg': 'image/svg+xml',
  '.png': 'image/png',
  '.jpg': 'image/jpeg',
  '.jpeg': 'image/jpeg',
  '.webp': 'image/webp',
  '.woff2': 'font/woff2',
}

function serveStatic(req, res, url) {
  const relativePath = decodeURIComponent(url.pathname).replace(/^\/+/, '')
  let filePath = path.join(WEB_ROOT, relativePath || 'index.html')
  if (filePath !== WEB_ROOT && !filePath.startsWith(`${WEB_ROOT}${path.sep}`)) {
    json(res, 403, { detail: '禁止访问' })
    return
  }

  if (!fs.existsSync(filePath) || fs.statSync(filePath).isDirectory()) {
    filePath = path.join(WEB_ROOT, 'index.html')
  }

  try {
    let body = fs.readFileSync(filePath)
    if (path.extname(filePath) === '.js' && body.includes(Buffer.from('https://xiaoxu666.asia'))) {
      const patched = body.toString('utf8').replaceAll('"https://xiaoxu666.asia"', 'window.location.origin')
      body = Buffer.from(patched)
    }
    res.writeHead(200, {
      'Content-Type': MIME_TYPES[path.extname(filePath)] || 'application/octet-stream',
      'Content-Length': body.length,
      'Cache-Control': 'no-store',
    })
    if (req.method === 'HEAD') res.end()
    else res.end(body)
  } catch (error) {
    json(res, 500, { detail: `本地文件读取失败: ${error.message}` })
  }
}

const server = http.createServer(async (req, res) => {
  try {
    const url = new URL(req.url, `http://${HOST}:${PORT}`)
    if (await handleApi(req, res, url)) return
    serveStatic(req, res, url)
  } catch (error) {
    json(res, 500, { detail: `本地演示服务异常: ${error.message}` })
  }
})

server.listen(PORT, HOST, () => {
  console.log(`NBAssistant 本地演示已启动: http://${HOST}:${PORT}`)
  console.log(`账号: ${DEMO_USERNAME}`)
  console.log(`密码: ${DEMO_PASSWORD}`)
})
