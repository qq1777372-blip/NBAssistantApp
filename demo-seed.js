const DEMO_USERNAME = 'demo'
const DEMO_PASSWORD = 'Demo@123456'

function pad(value) {
  return String(value).padStart(2, '0')
}

function dateValue(daysAgo = 0) {
  const value = new Date()
  value.setHours(12, 0, 0, 0)
  value.setDate(value.getDate() - daysAgo)
  return value
}

function dateOnly(daysAgo = 0) {
  const value = dateValue(daysAgo)
  return `${value.getFullYear()}-${pad(value.getMonth() + 1)}-${pad(value.getDate())}`
}

function dateTime(daysAgo = 0, hour = 9, minute = 0) {
  return `${dateOnly(daysAgo)}T${pad(hour)}:${pad(minute)}:00`
}

function monthKey(offset = 0) {
  const value = new Date()
  value.setDate(1)
  value.setMonth(value.getMonth() + offset)
  return `${value.getFullYear()}-${pad(value.getMonth() + 1)}`
}

function compactDate(daysAgo = 0) {
  return dateOnly(daysAgo).replaceAll('-', '')
}

function epochSeconds(daysAgo = 0) {
  return Math.floor(dateValue(daysAgo).getTime() / 1000)
}

function createDemoUser() {
  return {
    id: 1,
    username: DEMO_USERNAME,
    display_name: '本地演示管理员',
    avatar_url: '/favicon.svg',
    role: 'superadmin',
    is_active: true,
    permissions: {},
  }
}

function createSeedData(demoUser = createDemoUser()) {
  const shops = [
    { id: 201, values: { shop_name: '星河生活馆', platform: '天猫', owner: '许经理', status: '正常运营', monthly_sales: 128600 }, created_at: dateTime(96, 10), updated_at: dateTime(0, 9) },
    { id: 202, values: { shop_name: '青木优选', platform: '淘宝', owner: '李晓雨', status: '正常运营', monthly_sales: 86320 }, created_at: dateTime(69, 11, 20), updated_at: dateTime(1, 18, 30) },
    { id: 203, values: { shop_name: '云帆数码店', platform: '京东', owner: '陈一凡', status: '活动筹备', monthly_sales: 214900 }, created_at: dateTime(54, 14, 15), updated_at: dateTime(2, 16, 10) },
    { id: 204, values: { shop_name: '南风家居', platform: '抖音商城', owner: '许经理', status: '正常运营', monthly_sales: 72580 }, created_at: dateTime(39, 9, 45), updated_at: dateTime(3, 12, 40) },
  ]

  const products = [
    { id: 611, name: '星河保温杯', sku: 'XM-CUP-01', barcode: '690000000001', specification: '350ml', unit: '件', cost_price: 48, warning_quantity: 15, is_active: true, remark: '热销款', image_url: '/favicon.svg' },
    { id: 612, name: '青木收纳盒', sku: 'QM-BOX-02', barcode: '690000000002', specification: '大号', unit: '件', cost_price: 22.5, warning_quantity: 20, is_active: true, remark: '常规款', image_url: '/favicon.svg' },
    { id: 613, name: '云帆无线键盘', sku: 'YF-KEY-03', barcode: '690000000003', specification: '蓝牙双模', unit: '件', cost_price: 126, warning_quantity: 10, is_active: true, remark: '办公款', image_url: '/favicon.svg' },
    { id: 614, name: '南风香薰礼盒', sku: 'NF-GIFT-04', barcode: '690000000004', specification: '四件套', unit: '盒', cost_price: 68, warning_quantity: 12, is_active: true, remark: '节日礼赠', image_url: '/favicon.svg' },
  ]

  return {
    homeModules: ['sycm', 'company-expenses', 'tasks', 'profits', 'shops', 'warehouse', 'links', 'ai-workspace', 'owners'],
    expenseCategories: ['办公用品', '快递物流', '餐饮招待', '差旅交通', '软件服务', '广告推广', '采购货款', '其他消费'],
    owners: [
      { id: 1, name: '许经理', owner_name: '许经理', created_at: dateTime(15, 9) },
      { id: 2, name: '李晓雨', owner_name: '李晓雨', created_at: dateTime(13, 10, 20) },
      { id: 3, name: '陈一凡', owner_name: '陈一凡', created_at: dateTime(11, 14, 30) },
    ],
    tasks: [
      { id: 101, order_no: `RW-${compactDate(0)}-001`, task_time: dateTime(0, 9, 15), shop_name: '星河生活馆', owner_name: '许经理', order_count: 12, principal_amount: 3580, commission_amount: 286.4, gift_amount: 96, signed_status: 'pending', settlement_status: 'pending', note: '今日重点跟进' },
      { id: 102, order_no: `RW-${compactDate(1)}-008`, task_time: dateTime(1, 15, 40), shop_name: '青木优选', owner_name: '李晓雨', order_count: 8, principal_amount: 2160, commission_amount: 172.8, gift_amount: 64, signed_status: 'completed', settlement_status: 'pending', note: '已核对订单' },
      { id: 103, order_no: `RW-${compactDate(2)}-015`, task_time: dateTime(2, 11, 5), shop_name: '云帆数码店', owner_name: '陈一凡', order_count: 5, principal_amount: 4990, commission_amount: 249.5, gift_amount: 40, signed_status: 'completed', settlement_status: 'completed', note: '已完成结算' },
      { id: 104, order_no: `RW-${compactDate(3)}-006`, task_time: dateTime(3, 16, 25), shop_name: '南风家居', owner_name: '许经理', order_count: 10, principal_amount: 3280, commission_amount: 262.4, gift_amount: 80, signed_status: 'pending', settlement_status: 'completed', note: '等待物流签收' },
      { id: 105, order_no: `RW-${compactDate(4)}-003`, task_time: dateTime(4, 10, 30), shop_name: '星河生活馆', owner_name: '李晓雨', order_count: 6, principal_amount: 1880, commission_amount: 150.4, gift_amount: 48, signed_status: 'completed', settlement_status: 'completed', note: '样例完成任务' },
    ],
    customFields: [
      { id: 1, field_name: 'shop_name', label: '店铺名称', field_type: 'text', required: true, is_required: true, is_visible: true, is_builtin: true, sort_order: 1 },
      { id: 2, field_name: 'platform', label: '所属平台', field_type: 'text', required: true, is_required: true, is_visible: true, is_builtin: true, sort_order: 2 },
      { id: 3, field_name: 'owner', label: '负责人', field_type: 'text', required: false, is_required: false, is_visible: true, is_builtin: true, sort_order: 3 },
      { id: 4, field_name: 'status', label: '运营状态', field_type: 'text', required: false, is_required: false, is_visible: true, is_builtin: true, sort_order: 4 },
      { id: 5, field_name: 'monthly_sales', label: '本月销售额', field_type: 'number', required: false, is_required: false, is_visible: true, is_builtin: false, sort_order: 5 },
    ],
    shops,
    expenses: [
      { id: 301, expense_no: `FY-${compactDate(0)}-001`, expense_date: dateOnly(0), amount: 1280, category: '广告推广', payment_account: '公司支付宝', payment_type: 'company', expense_scope: '公共费用', description: '周末活动信息流投放', submitter_name: '许经理', reimbursement_status: 'not_required', attachment_url: null, created_at: dateTime(0, 9, 36) },
      { id: 302, expense_no: `FY-${compactDate(1)}-006`, expense_date: dateOnly(1), amount: 468.5, category: '快递物流', payment_account: '顺丰月结', payment_type: 'company', expense_scope: '公共费用', description: '样品及售后件寄送', submitter_name: '李晓雨', reimbursement_status: 'not_required', attachment_url: null, created_at: dateTime(1, 17, 25) },
      { id: 303, expense_no: `FY-${compactDate(2)}-003`, expense_date: dateOnly(2), amount: 236, category: '餐饮招待', payment_account: '员工垫付', payment_type: 'employee', expense_scope: '公共费用', description: '供应商沟通工作餐', submitter_name: '陈一凡', reimbursement_status: 'pending', attachment_url: '/favicon.svg', attachment_name: '餐饮发票.svg', created_at: dateTime(2, 13, 5) },
      { id: 304, expense_no: `FY-${compactDate(4)}-011`, expense_date: dateOnly(4), amount: 899, category: '软件服务', payment_account: '企业微信支付', payment_type: 'company', expense_scope: '公共费用', description: '客服工具年度续费', submitter_name: '许经理', reimbursement_status: 'not_required', attachment_url: null, created_at: dateTime(4, 10, 18) },
    ],
    profits: [
      { source_record_id: 401, store_name: '星河生活馆', report_date: dateOnly(0), reporter_name: '许经理', profit: 12680 },
      { source_record_id: 402, store_name: '青木优选', report_date: dateOnly(0), reporter_name: '李晓雨', profit: 8320 },
      { source_record_id: 403, store_name: '云帆数码店', report_date: dateOnly(1), reporter_name: '陈一凡', profit: 18960 },
      { source_record_id: 404, store_name: '南风家居', report_date: dateOnly(1), reporter_name: '许经理', profit: -860 },
    ],
    monthlyProfits: [
      { month: monthKey(-5), total_profit: 28600 },
      { month: monthKey(-4), total_profit: 34200 },
      { month: monthKey(-3), total_profit: 31850 },
      { month: monthKey(-2), total_profit: 41600 },
      { month: monthKey(-1), total_profit: 38900 },
      { month: monthKey(0), total_profit: 39060 },
    ],
    links: [
      { id: 501, title: '本周运营复盘与下周计划', url: 'https://example.com/operations-review', category: 'tutorial:运营资料', description: '# 本周经营概况\n\n## 核心结论\n\n**重点：** 本周整体经营稳定，利润保持增长。\n\n> 库存预警需要优先处理。\n\n- 核对低库存商品\n- 跟进待签收任务\n\n1. 完成数据复核\n2. 安排下周活动\n\n- [x] 汇总经营数据\n- [ ] 完成活动报名\n\n::: align-center\n内部运营资料\n:::\n\n[查看运营说明](https://example.com/operations-review)\n\n![运营看板](/favicon.svg)', author_user_id: 1, author_username: 'demo', author_avatar_url: '/favicon.svg', images: [{ id: 1, storage_name: 'demo-cover.svg', name: '运营看板.svg', url: '/favicon.svg' }], is_pinned: true, sort_order: 1, push_status: 'sent', push_scheduled_at: null, push_sent_at: dateTime(0, 8, 35), push_error: null, created_at: dateTime(0, 8, 30), updated_at: dateTime(0, 8, 35) },
      { id: 502, title: '仓库盘点操作清单', url: 'https://example.com/warehouse-checklist', category: '仓储管理', description: '月中盘点流程和差异处理注意事项。', author_user_id: 2, author_username: 'operator', author_avatar_url: null, images: [], is_pinned: false, sort_order: 2, push_status: 'scheduled', push_scheduled_at: dateTime(-1, 9), push_sent_at: null, push_error: null, created_at: dateTime(1, 14, 20), updated_at: dateTime(1, 14, 20) },
      { id: 503, title: '平台活动报名时间表', url: 'https://example.com/campaign-calendar', category: '活动排期', description: '主要平台下月活动报名节点。', author_user_id: 1, author_username: 'demo', author_avatar_url: '/favicon.svg', images: [], is_pinned: false, sort_order: 3, push_status: 'idle', push_scheduled_at: null, push_sent_at: null, push_error: null, created_at: dateTime(2, 11, 10), updated_at: dateTime(2, 11, 10) },
      { id: 504, title: '异常订单处理记录', url: null, category: '售后复盘', description: '记录退款原因与处理结论，供运营团队复盘。', author_user_id: 1, author_username: 'demo', author_avatar_url: '/favicon.svg', images: [], is_pinned: false, sort_order: 4, push_status: 'failed', push_scheduled_at: null, push_sent_at: null, push_error: '演示环境未配置钉钉机器人', created_at: dateTime(3, 16), updated_at: dateTime(3, 16) },
    ],
    alerts: [
      { key: 'inventory-low-1', category: 'inventory', severity: 'critical', title: '库存低于预警值', description: 'SKU XM-CUP-01 可用库存仅剩 8 件。', acknowledged: false, occurred_at: dateTime(0, 8, 45) },
      { key: 'task-pending-1', category: 'task', severity: 'warning', title: '任务等待签收', description: '2 条任务仍处于待签收状态。', acknowledged: false, occurred_at: dateTime(0, 9, 20) },
      { key: 'outbound-delay-1', category: 'outbound', severity: 'info', title: '出库单待处理', description: `CK-${compactDate(0)}-003 正在等待拣货。`, acknowledged: true, occurred_at: dateTime(0, 10, 5) },
    ],
    warehouses: [
      { id: 601, code: 'SH-01', name: '上海一号仓', address: '上海市松江区', contact_name: '许经理', contact_phone: '138****6008', is_active: true, remark: '主仓' },
      { id: 602, code: 'HZ-02', name: '杭州周转仓', address: '杭州市余杭区', contact_name: '李晓雨', contact_phone: '139****2166', is_active: true, remark: '周转仓' },
    ],
    products,
    stocks: [
      { warehouse_id: 601, warehouse_name: '上海一号仓', product_id: 611, sku: 'XM-CUP-01', product_name: '星河保温杯', unit: '件', quantity: 10, locked_quantity: 2, available_quantity: 8, is_low_stock: true, image_url: '/favicon.svg' },
      { warehouse_id: 601, warehouse_name: '上海一号仓', product_id: 612, sku: 'QM-BOX-02', product_name: '青木收纳盒', unit: '件', quantity: 126, locked_quantity: 8, available_quantity: 118, is_low_stock: false, image_url: '/favicon.svg' },
      { warehouse_id: 602, warehouse_name: '杭州周转仓', product_id: 613, sku: 'YF-KEY-03', product_name: '云帆无线键盘', unit: '件', quantity: 48, locked_quantity: 6, available_quantity: 42, is_low_stock: false, image_url: '/favicon.svg' },
      { warehouse_id: 602, warehouse_name: '杭州周转仓', product_id: 614, sku: 'NF-GIFT-04', product_name: '南风香薰礼盒', unit: '盒', quantity: 26, locked_quantity: 0, available_quantity: 26, is_low_stock: false, image_url: '/favicon.svg' },
    ],
    inbound: [
      { id: 631, order_no: `RK-${compactDate(1)}-002`, warehouse_id: 601, warehouse_name: '上海一号仓', supplier: '华东供应链', source_type: 'purchase', status: 'completed', total_quantity: 80, items: [{ product_id: 612, sku: 'QM-BOX-02', product_name: '青木收纳盒', unit: '件', quantity: 80 }], created_at: dateTime(1, 10, 30) },
      { id: 632, order_no: `RK-${compactDate(0)}-001`, warehouse_id: 602, warehouse_name: '杭州周转仓', supplier: '云帆科技', source_type: 'purchase', status: 'pending', total_quantity: 30, items: [{ product_id: 613, sku: 'YF-KEY-03', product_name: '云帆无线键盘', unit: '件', quantity: 30 }], created_at: dateTime(0, 9, 10) },
    ],
    outbound: [
      { id: 641, order_no: `CK-${compactDate(0)}-003`, warehouse_id: 601, warehouse_name: '上海一号仓', external_order_no: 'DEMO-ORDER-003', recipient_name: '张先生', recipient_phone: '138****6008', recipient_address: '上海市浦东新区', delivery_method: 'shipping', status: 'pending', carrier: null, tracking_no: null, items: [{ product_id: 611, sku: 'XM-CUP-01', product_name: '星河保温杯', unit: '件', quantity: 12 }], created_at: dateTime(0, 10) },
      { id: 642, order_no: `CK-${compactDate(1)}-009`, warehouse_id: 602, warehouse_name: '杭州周转仓', external_order_no: 'DEMO-ORDER-009', recipient_name: '王女士', recipient_phone: '139****2166', recipient_address: '杭州市西湖区', delivery_method: 'shipping', status: 'shipped', carrier: '顺丰速运', tracking_no: `SF-DEMO-${compactDate(1)}`, items: [{ product_id: 613, sku: 'YF-KEY-03', product_name: '云帆无线键盘', unit: '件', quantity: 6 }], created_at: dateTime(1, 16, 20) },
    ],
    movements: [
      { id: 651, movement_type: 'inbound', product_name: '青木收纳盒', sku: 'QM-BOX-02', warehouse_name: '上海一号仓', quantity_change: 80, quantity_after: 126, operator_username: 'demo', reference_no: `RK-${compactDate(1)}-002`, created_at: dateTime(1, 11) },
      { id: 652, movement_type: 'outbound', product_name: '云帆无线键盘', sku: 'YF-KEY-03', warehouse_name: '杭州周转仓', quantity_change: -6, quantity_after: 48, operator_username: 'demo', reference_no: `CK-${compactDate(1)}-009`, created_at: dateTime(1, 17) },
    ],
    adminUsers: [
      { ...demoUser },
      { id: 2, username: 'operator', display_name: '运营专员', role: 'editor', is_active: true, permissions: { dashboard: 'write', links: 'write', task_bookkeeping: 'write', warehouse: 'read' } },
      { id: 3, username: 'viewer', display_name: '数据访客', role: 'viewer', is_active: true, permissions: { dashboard: 'read', links: 'read', task_bookkeeping: 'read' } },
    ],
    peerShops: [
      { id: 701, shop_name: '晴空生活旗舰店', shop_url: 'https://example.com/qingkong', remark: '家居类目同行，重点观察内容投放', image_url: '/favicon.svg' },
      { id: 702, shop_name: '北辰数码专营店', shop_url: 'https://example.com/beichen', remark: '数码类目同行，价格策略稳定', image_url: '/favicon.svg' },
    ],
    mobileDevices: [
      { id: 711, device_name: '运营一号机', primary_card: '138****1234', secondary_card: '189****6608', remark: '星河生活馆日常运营' },
      { id: 712, device_name: '仓库扫码机', primary_card: '139****2166', secondary_card: null, remark: '仅用于仓储作业' },
    ],
    accountUsage: [
      { id: 721, account_name: 'demo-service-account', phone_number: '138****1234', device_name: '运营一号机', usage_notes: '店铺客服与活动报名', is_banned: false, banned_reason: null },
      { id: 722, account_name: 'legacy-account', phone_number: '137****9921', device_name: '备用设备', usage_notes: '历史账号，暂不使用', is_banned: true, banned_reason: '连续登录失败' },
    ],
    licenseRecords: [
      { id: 731, subject_name: '上海星河示例有限公司', credit_code: 'DEMO-91310000-001', legal_representative: '许经理', issue_date: dateOnly(720), expiry_date: dateOnly(-720), remark: '主运营主体', image_url: '/favicon.svg' },
      { id: 732, subject_name: '杭州青木电子商务有限公司', credit_code: 'DEMO-91330000-002', legal_representative: '李晓雨', issue_date: dateOnly(540), expiry_date: dateOnly(-30), remark: '即将到期演示数据', image_url: '/favicon.svg' },
    ],
    licenses: [
      { license_key: 'DEMO-LOCAL-2026-A', plan_name: '本地演示专业版', status: 'active', max_devices: 3, expires_at: dateOnly(-365), devices: [{ device_id: 'SIM-IP17P-001', device_name: 'iPhone 17 Pro 模拟器', platform: 'iOS', app_version: '1.3.5' }] },
      { license_key: 'DEMO-LOCAL-2026-B', plan_name: '本地演示标准版', status: 'disabled', max_devices: 1, expires_at: dateOnly(-30), devices: [] },
    ],
    systemSettings: {
      system_name: '内部管理系统（本地演示）', system_subtitle: '任务记账与店铺后台', license_expiry_days: 30,
      stale_task_days: 3, login_failure_threshold: 3, session_duration_hours: 168, low_stock_alert_enabled: true,
      pending_outbound_alert_enabled: true, task_alert_enabled: true, security_alert_enabled: true,
      data_alert_enabled: true, profit_stale_days: 3,
    },
    sycmShops: [
      { id: 801, shopId: 'shop-201', shopName: '星河生活馆', overview: { uv: { value: 8620 }, pv: { value: 21450 }, cartByrCnt: { value: 736 }, payByrCnt: { value: 418 }, payAmt: { value: 128600 } }, uv: 8620, pv: 21450, cartByrCnt: 736, payByrCnt: 418, payAmt: 128600 },
      { id: 802, shopId: 'shop-202', shopName: '青木优选', overview: { uv: { value: 6490 }, pv: { value: 15820 }, cartByrCnt: { value: 510 }, payByrCnt: { value: 312 }, payAmt: { value: 86320 } }, uv: 6490, pv: 15820, cartByrCnt: 510, payByrCnt: 312, payAmt: 86320 },
      { id: 803, shopId: 'shop-203', shopName: '云帆数码店', overview: { uv: { value: 10380 }, pv: { value: 28640 }, cartByrCnt: { value: 802 }, payByrCnt: { value: 386 }, payAmt: { value: 214900 } }, uv: 10380, pv: 28640, cartByrCnt: 802, payByrCnt: 386, payAmt: 214900 },
    ],
    sycmDevices: [
      { deviceId: 'collector-mac-01', deviceName: '运营采集器', online: true, shopCount: 3, sessionState: 'ready', sessionDetail: '千牛会话正常' },
      { deviceId: 'collector-backup-02', deviceName: '备用采集器', online: false, shopCount: 1, sessionState: 'offline', sessionDetail: '最近在线：昨天 18:30' },
    ],
    sycmSyncRequests: [{ id: 1, period: 'today', status: 'completed', created_at: dateTime(0, 8) }],
    aiConnections: [
      { id: 'conn-demo-openai', name: '演示 OpenAI 兼容接口', base_url: 'https://api.example.com/v1', provider_type: 'openai', purpose: 'general', enabled: 1, has_key: true },
      { id: 'conn-demo-image', name: '演示图片模型接口', base_url: 'https://image.example.com/v1', provider_type: 'openai', purpose: 'image', enabled: 1, has_key: true },
    ],
    aiModels: [
      { id: 'model-demo-chat', name: '演示智能助手', base_model: 'demo-chat-1', model_type: 'chat', enabled: 1, hidden: 0, temperature: 0.7, top_p: 1, max_tokens: 4096, description: '用于本地功能展示，不访问外部服务', system_prompt: '你是运营管理演示助手。', connection_id: 'conn-demo-openai', provider_id: 'openai', provider_name: 'OpenAI', sync_source: '演示 OpenAI 兼容接口' },
      { id: 'model-demo-image', name: '演示图片生成', base_model: 'demo-image-1', model_type: 'image', enabled: 1, hidden: 0, temperature: null, top_p: null, max_tokens: null, description: '返回本地演示图片', system_prompt: null, connection_id: 'conn-demo-image', provider_id: 'openai', provider_name: 'OpenAI', sync_source: '演示图片模型接口' },
      { id: 'model-demo-audio', name: '演示语音转写', base_model: 'demo-audio-1', model_type: 'audio', enabled: 1, hidden: 0, temperature: null, top_p: null, max_tokens: null, description: '返回固定的本地转写内容', system_prompt: null, connection_id: 'conn-demo-openai', provider_id: 'openai', provider_name: 'OpenAI', sync_source: '演示 OpenAI 兼容接口' },
    ],
    aiChats: [
      { id: 'chat-demo-1', title: '今日经营简报', messages: [{ id: 'msg-1', role: 'user', content: '帮我总结今天的经营情况' }, { id: 'msg-2', role: 'assistant', content: '今日四个店铺整体运营稳定，云帆数码店销售额领先，需要重点处理 2 条待签收任务和 1 条库存预警。' }], model_id: 'model-demo-chat', favorite: true, archived: false, folder: '运营复盘', created_at: epochSeconds(1), updated_at: epochSeconds(0) },
    ],
    aiKnowledge: [
      { id: 'knowledge-operations', name: '运营制度', description: '日常运营流程与复盘模板' },
      { id: 'knowledge-warehouse', name: '仓储手册', description: '入库、出库和盘点规范' },
    ],
    aiFiles: [
      { id: 'file-weekly-review', name: '周运营复盘模板.md', knowledge_id: 'knowledge-operations', status: 'ready', content: '复盘应包含核心指标、异常问题、负责人和下一步行动。' },
      { id: 'file-stock-check', name: '仓库盘点流程.txt', knowledge_id: 'knowledge-warehouse', status: 'ready', content: '盘点前冻结库存，完成实盘后记录差异并由负责人复核。' },
    ],
    aiPrompts: [{ id: 'prompt-summary', title: '经营简报', command: 'summary', content: '请根据当前经营数据生成简明日报。', enabled: 1 }],
    aiSkills: [{ id: 'skill-analysis', name: '经营数据分析', description: '分析销售、利润和库存风险', content: '优先识别异常指标并给出行动建议。', enabled: 1 }],
    aiTools: [{ id: 'tool-search', name: '本地资料搜索', description: '搜索演示知识库', content: null, kind: 'function', enabled: 1 }],
    aiNotes: [{ id: 'note-campaign', title: '下月活动提醒', command: null, content: '星河生活馆需要在下周三前完成活动报名。', enabled: 1 }],
    aiUsage: [
      { id: 'usage-1', operation: 'chat', model_id: 'model-demo-chat', input_tokens: 386, output_tokens: 214, latency_ms: 680, created_at: dateTime(0, 9, 20) },
      { id: 'usage-2', operation: 'knowledge_search', model_id: 'model-demo-chat', input_tokens: 128, output_tokens: 76, latency_ms: 240, created_at: dateTime(1, 15, 40) },
    ],
    aiMemories: [{ id: 'memory-1', content: '经营日报需要优先展示利润、待办和库存预警。', source_chat_id: 'chat-demo-1', enabled: 1 }],
    aiWorkflows: [{ id: 'workflow-daily', name: '生成经营日报', description: '根据输入内容生成日报结构', steps: JSON.stringify([{ type: 'prompt', content: '把 {{input}} 整理成经营日报。' }]), enabled: 1 }],
    aiJobs: [{ id: 'job-1', kind: '经营日报', status: 'completed', output: JSON.stringify({ result: '日报已生成：经营稳定，需处理库存预警。' }), error: null }],
    aiShares: [{ id: 'share-demo-1', title: '今日经营简报', created_at: dateTime(0, 12) }],
  }
}

module.exports = {
  DEMO_USERNAME,
  DEMO_PASSWORD,
  compactDate,
  createDemoUser,
  createSeedData,
  dateOnly,
  dateTime,
  epochSeconds,
  monthKey,
}
