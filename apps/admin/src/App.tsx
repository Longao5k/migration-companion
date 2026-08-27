import { useMemo, useState } from 'react'
import './App.css'

type Importance = 'MAJOR' | 'IMPORTANT' | 'GENERAL'
type ReviewStatus = 'PENDING' | 'VERIFIED' | 'REJECTED' | 'CORRECTED'

type ChangeItem = {
  id: string
  titleZh: string
  importance: Importance
  reviewStatus: ReviewStatus
  oldExcerpt?: string
  newExcerpt?: string
  discoveredAt: string
  source: { name: string; url: string; jurisdiction?: string }
}

const demoQueue: ChangeItem[] = [
  {
    id: 'demo-1',
    titleZh: '南澳州担保要求页面出现实质性变化',
    importance: 'IMPORTANT',
    reviewStatus: 'PENDING',
    oldExcerpt: '申请人需满足当期公布的资格要求。',
    newExcerpt: '申请人需满足更新后的居住、工作及职业要求。',
    discoveredAt: '2026-08-27T08:42:00+09:30',
    source: {
      name: 'Move to South Australia',
      url: 'https://migration.sa.gov.au/how-to-apply/nomination-requirements',
      jurisdiction: 'AU-SA',
    },
  },
  {
    id: 'demo-2',
    titleZh: 'Documents required 页面版式调整',
    importance: 'GENERAL',
    reviewStatus: 'PENDING',
    oldExcerpt: 'Supporting documents',
    newExcerpt: 'Required supporting documents',
    discoveredAt: '2026-08-27T07:18:00+09:30',
    source: {
      name: 'Move to South Australia',
      url: 'https://migration.sa.gov.au/how-to-apply/documents-required',
      jurisdiction: 'AU-SA',
    },
  },
]

function severityLabel(value: Importance) {
  return value === 'MAJOR' ? '重大' : value === 'IMPORTANT' ? '重要' : '一般'
}

function App() {
  const [queue, setQueue] = useState<ChangeItem[]>(demoQueue)
  const [selectedId, setSelectedId] = useState(demoQueue[0].id)
  const [apiKey, setApiKey] = useState('')
  const [notice, setNotice] = useState('演示数据 · 连接 API 后显示实时审核队列')
  const [summary, setSummary] = useState('')
  const [loading, setLoading] = useState(false)
  const selected = useMemo(
    () => queue.find((item) => item.id === selectedId) ?? queue[0],
    [queue, selectedId],
  )

  async function refresh() {
    if (!apiKey) {
      setNotice('请输入本次会话的后台密钥；页面不会保存它。')
      return
    }
    setLoading(true)
    try {
      const response = await fetch('/v1/content/admin/review-queue', {
        headers: { 'x-admin-key': apiKey },
      })
      if (!response.ok) throw new Error(`HTTP ${response.status}`)
      const data = (await response.json()) as ChangeItem[]
      setQueue(data)
      setSelectedId(data[0]?.id ?? '')
      setNotice(`已同步 ${data.length} 条待审核变化`)
    } catch {
      setNotice('连接失败，仍保留演示队列；请检查 API 地址和后台密钥。')
    } finally {
      setLoading(false)
    }
  }

  async function review(status: ReviewStatus) {
    if (!selected) return
    if (!apiKey || selected.id.startsWith('demo-')) {
      const next = queue.filter((item) => item.id !== selected.id)
      setQueue(next)
      setSelectedId(next[0]?.id ?? '')
      setSummary('')
      setNotice(status === 'VERIFIED' ? '演示：已核实并进入发布流程' : '演示：已标记为误报')
      return
    }
    setLoading(true)
    try {
      const response = await fetch(`/v1/content/admin/changes/${selected.id}/review`, {
        method: 'PATCH',
        headers: { 'content-type': 'application/json', 'x-admin-key': apiKey },
        body: JSON.stringify({ status, editorSummaryZh: summary }),
      })
      if (!response.ok) throw new Error(`HTTP ${response.status}`)
      const next = queue.filter((item) => item.id !== selected.id)
      setQueue(next)
      setSelectedId(next[0]?.id ?? '')
      setSummary('')
      setNotice(status === 'VERIFIED' ? '审核完成，可按发布策略通知用户' : '已拒绝该变化')
    } catch {
      setNotice('审核提交失败，没有改变发布状态。')
    } finally {
      setLoading(false)
    }
  }

  return (
    <div className="app-shell">
      <aside className="sidebar">
        <div className="brand-mark">MC</div>
        <div>
          <strong>Migration Companion</strong>
          <span>内容控制台</span>
        </div>
        <nav aria-label="后台主导航">
          <button className="active"><span>⌁</span>审核队列<b>{queue.length}</b></button>
          <button><span>◫</span>已发布内容</button>
          <button><span>⌘</span>官方来源</button>
          <button><span>↻</span>更正记录</button>
          <button><span>◷</span>采集状态</button>
        </nav>
        <div className="sidebar-note">
          <span className="status-dot" />南澳数据单元
          <small>重大与重要变化必须人工核实</small>
        </div>
      </aside>

      <main>
        <header>
          <div>
            <p className="eyebrow">2026 年 8 月 27 日 · AU-SA</p>
            <h1>政策变更审核</h1>
          </div>
          <div className="key-box">
            <input
              type="password"
              value={apiKey}
              onChange={(event) => setApiKey(event.target.value)}
              placeholder="本次会话后台密钥"
              aria-label="后台密钥"
            />
            <button onClick={refresh} disabled={loading}>同步</button>
          </div>
        </header>

        <section className="metrics" aria-label="审核概览">
          <article><span>待审核</span><strong>{queue.length}</strong><small>其中 1 条重要变化</small></article>
          <article><span>来源健康度</span><strong>8 / 8</strong><small className="good">今日均已正常检查</small></article>
          <article><span>最久等待</span><strong>1h 24m</strong><small>目标：重要变化 4 小时内</small></article>
          <article><span>今日误报</span><strong>0</strong><small className="good">未触发错误推送</small></article>
        </section>

        <p className="notice" role="status">{notice}</p>

        <section className="workspace">
          <div className="queue-panel">
            <div className="panel-heading">
              <div><span className="eyebrow">Review queue</span><h2>等待人工判断</h2></div>
              <button className="filter">全部来源⌄</button>
            </div>
            <div className="queue-list">
              {queue.length === 0 && <div className="empty">当前队列已经清空</div>}
              {queue.map((item) => (
                <button
                  key={item.id}
                  className={`queue-item ${selected?.id === item.id ? 'selected' : ''}`}
                  onClick={() => setSelectedId(item.id)}
                >
                  <span className={`severity ${item.importance.toLowerCase()}`}>{severityLabel(item.importance)}</span>
                  <strong>{item.titleZh}</strong>
                  <span>{item.source.name}</span>
                  <time>{new Date(item.discoveredAt).toLocaleTimeString('zh-CN', { hour: '2-digit', minute: '2-digit' })}</time>
                </button>
              ))}
            </div>
          </div>

          <div className="review-panel">
            {!selected ? (
              <div className="empty large">选择一条变化开始审核</div>
            ) : (
              <>
                <div className="review-header">
                  <div>
                    <span className={`severity ${selected.importance.toLowerCase()}`}>{severityLabel(selected.importance)}</span>
                    <h2>{selected.titleZh}</h2>
                    <a href={selected.source.url} target="_blank" rel="noreferrer">打开官方原文 ↗</a>
                  </div>
                  <span className="evidence">证据快照已保存</span>
                </div>

                <div className="diff-grid">
                  <article className="before"><span>上一版本</span><p>{selected.oldExcerpt || '首次记录，无上一版本。'}</p></article>
                  <article className="after"><span>当前版本</span><p>{selected.newExcerpt || '当前页面没有可展示的文字片段。'}</p></article>
                </div>

                <div className="source-facts">
                  <div><span>司法辖区</span><strong>{selected.source.jurisdiction ?? 'AU-SA'}</strong></div>
                  <div><span>发现时间</span><strong>{new Date(selected.discoveredAt).toLocaleString('zh-CN')}</strong></div>
                  <div><span>发布规则</span><strong>人工核实后发布</strong></div>
                </div>

                <label className="summary-field">
                  <span>中文编辑摘要</span>
                  <textarea
                    value={summary}
                    onChange={(event) => setSummary(event.target.value)}
                    placeholder="只概述官方事实，不给出个人资格、路径或申请答案建议。"
                  />
                </label>

                <div className="guardrail">
                  <strong>发布前检查</strong>
                  <span>来源可回溯</span><span>无个人资格判断</span><span>无政府隶属暗示</span>
                </div>
                <div className="actions">
                  <button className="reject" onClick={() => review('REJECTED')} disabled={loading}>标记误报</button>
                  <button className="approve" onClick={() => review('VERIFIED')} disabled={loading}>核实并发布</button>
                </div>
              </>
            )}
          </div>
        </section>
      </main>
    </div>
  )
}

export default App
