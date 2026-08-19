const { spawn } = require('child_process')
const assert = require('assert/strict')

const port = Number(process.env.DEMO_CHECK_PORT || 4181)
const origin = `http://127.0.0.1:${port}`
let cookie = ''

async function request(path, options = {}) {
  const headers = { ...(options.body ? { 'Content-Type': 'application/json' } : {}), ...(cookie ? { Cookie: cookie } : {}), ...options.headers }
  const response = await fetch(`${origin}${path}`, { ...options, headers, body: options.body ? JSON.stringify(options.body) : undefined })
  const setCookie = response.headers.get('set-cookie')
  if (setCookie) cookie = setCookie.split(';')[0]
  const text = await response.text()
  const payload = response.headers.get('content-type')?.includes('application/x-ndjson')
    ? text.trim().split('\n').filter(Boolean).map((line) => JSON.parse(line))
    : text ? JSON.parse(text) : null
  return { status: response.status, payload }
}

async function expectArray(path, minimum = 1) {
  const result = await request(path)
  assert.equal(result.status, 200, path)
  assert.ok(Array.isArray(result.payload), `${path} should return an array`)
  assert.ok(result.payload.length >= minimum, `${path} should include demo rows`)
  return result.payload
}

async function main() {
  const child = spawn(process.execPath, ['demo-server.js'], {
    cwd: __dirname,
    env: { ...process.env, DEMO_PORT: String(port) },
    stdio: ['ignore', 'pipe', 'inherit'],
  })

  try {
    await new Promise((resolve, reject) => {
      const timer = setTimeout(() => reject(new Error('本地演示服务启动超时')), 5000)
      child.once('exit', (code) => reject(new Error(`本地演示服务提前退出: ${code}`)))
      child.stdout.on('data', (chunk) => {
        if (chunk.toString().includes('本地演示已启动')) { clearTimeout(timer); resolve() }
      })
    })

    assert.equal((await request('/health')).payload.mode, 'local-demo')
    const login = await request('/auth/login', { method: 'POST', body: { username: 'demo', password: 'Demo@123456' } })
    assert.equal(login.status, 200)

    const arrayPaths = [
      '/task-bookkeeping/records', '/custom-fields', '/shop-records', '/company-expenses',
      '/dingtalk-profits', '/saved-links', '/warehouse/warehouses', '/warehouse/products',
      '/warehouse/stocks', '/warehouse/inbound-orders', '/warehouse/outbound-orders',
      '/warehouse/movements', '/admin-users', '/peer-shops', '/mobile-devices',
      '/account-usage-records', '/license-records', '/license-admin/licenses',
      '/api/sycm/latest?period=today', '/api/sycm/collector-devices',
    ]
    for (const path of arrayPaths) await expectArray(path)
    const expenses = await expectArray('/company-expenses')
    const expenseWithAttachment = expenses.find((item) => item.attachment_url)
    assert.ok(expenseWithAttachment, 'demo expense should include an attachment')
    const removedAttachment = await request(`/company-expenses/${expenseWithAttachment.id}/attachment`, { method: 'DELETE' })
    assert.equal(removedAttachment.status, 200)
    assert.equal(removedAttachment.payload.attachment_url, null)

    const objectPaths = [
      '/task-bookkeeping/summary', '/company-expenses/summary', '/warehouse/summary',
      '/system-alerts', '/system-settings', '/dashboard/server-status', '/global-search?q=星河',
      '/ai-api/models', '/ai-api/connections', '/ai-api/chats', '/ai-api/knowledge',
      '/ai-api/files', '/ai-api/prompts', '/ai-api/skills', '/ai-api/tools',
      '/ai-api/notes', '/ai-api/usage', '/ai-api/memories', '/ai-api/workflows',
      '/ai-api/jobs', '/ai-api/shares',
    ]
    for (const path of objectPaths) {
      const result = await request(path)
      assert.equal(result.status, 200, path)
      assert.equal(typeof result.payload, 'object', path)
      assert.ok(!Array.isArray(result.payload), `${path} should return an object`)
    }

    const created = await request('/task-bookkeeping/records', { method: 'POST', body: { shop_name: 'UI 测试店', owner_name: '许经理', order_count: 2, principal_amount: 300, commission_amount: 24, gift_amount: 8 } })
    assert.equal(created.status, 201)
    const updated = await request(`/task-bookkeeping/records/${created.payload.id}`, { method: 'PATCH', body: { signed_status: 'completed' } })
    assert.equal(updated.payload.signed_status, 'completed')
    assert.equal((await request(`/task-bookkeeping/records/${created.payload.id}`, { method: 'DELETE' })).status, 204)

    const peer = await request('/peer-shops', { method: 'POST', body: { shop_name: 'UI 同行测试', remark: '用于表单演示' } })
    assert.equal(peer.status, 201)
    assert.equal((await request(`/peer-shops/${peer.payload.id}`, { method: 'PUT', body: { shop_name: 'UI 同行已修改' } })).payload.shop_name, 'UI 同行已修改')
    assert.equal((await request(`/peer-shops/${peer.payload.id}`, { method: 'DELETE' })).status, 204)

    const product = await request('/warehouse/products', { method: 'POST', body: { sku: 'UI-PHOTO-01', name: '图片测试商品', unit: '件' } })
    assert.equal(product.status, 201)
    const imageForm = new FormData()
    imageForm.append('image', new Blob([Buffer.from('demo-product-image')], { type: 'image/jpeg' }), 'product.jpg')
    const imageResponse = await fetch(`${origin}/warehouse/products/${product.payload.id}/image`, { method: 'POST', headers: { Cookie: cookie }, body: imageForm })
    const imagePayload = await imageResponse.json()
    assert.equal(imageResponse.status, 200)
    assert.ok(imagePayload.image_url.startsWith('data:image/jpeg;base64,'), 'product image should be stored in local demo data')
    assert.equal((await request(`/warehouse/products/${product.payload.id}`, { method: 'DELETE' })).status, 204)

    const chat = await request('/ai-api/chat', { method: 'POST', body: { question: '总结今天经营情况' } })
    assert.ok(chat.payload.content.includes('经营'))
    const stream = await request('/ai-api/chat/stream', { method: 'POST', body: { question: '查看库存' } })
    assert.equal(stream.status, 200)
    assert.ok(stream.payload.some((item) => item.content))

    assert.equal((await request('/demo/reset', { method: 'POST' })).status, 200)
    assert.equal((await request('/task-bookkeeping/not-implemented')).status, 501)
    console.log(`本地演示检查通过：${arrayPaths.length} 个列表、${objectPaths.length} 个对象接口及增删改操作均正常。`)
  } finally {
    child.kill('SIGTERM')
  }
}

main().catch((error) => {
  console.error(error.stack || error)
  process.exitCode = 1
})
