import { useMemo, useState } from 'react'
import type { FormEvent } from 'react'
import './App.css'

type Importance = 'MAJOR' | 'IMPORTANT' | 'GENERAL'
type ReviewStatus = 'PENDING' | 'VERIFIED' | 'REJECTED' | 'CORRECTED'
type View = 'review' | 'published' | 'sources' | 'corrections' | 'health'

type Source = {
  id: string
  name: string
  url: string
  jurisdiction: string
  sourceType: string
  enabled: boolean
  licenseNote?: string
  lastCheckedAt?: string
  lastSuccessAt?: string
  lastFailureAt?: string
  lastFailureCode?: string
}

type ChangeItem = {
  id: string
  titleZh: string
  importance: Importance
  reviewStatus: ReviewStatus
  oldExcerpt?: string
  newExcerpt?: string
  context?: string
  editorSummaryZh?: string
  correctionNote?: string
  discoveredAt: string
  publishedAt?: string
  verifiedAt?: string
  tags?: string[]
  source: Source
}

type NewsItem = {
  id: string
  sourceId: string
  titleZh: string
  summaryZh: string
  sourceTitle: string
  sourceUrl: string
  tags: string[]
  publishedAt: string
  isPublished: boolean
  source: Source
}

type SourceHealth = Source & {
  snapshots: Array<{
    contentHash: string
    httpStatus: number
    fetchedAt: string
  }>
  _count: { snapshots: number; changes: number; news: number }
}

const nav: Array<{ id: View; icon: string; label: string }> = [
  { id: 'review', icon: '⌁', label: '审核队列' },
  { id: 'published', icon: '◫', label: '已发布内容' },
  { id: 'sources', icon: '⌘', label: '官方来源' },
  { id: 'corrections', icon: '↻', label: '更正记录' },
  { id: 'health', icon: '◷', label: '采集状态' },
]

function severityLabel(value: Importance) {
  return value === 'MAJOR' ? '重大' : value === 'IMPORTANT' ? '重要' : '一般'
}

function formatTime(value?: string) {
  return value ? new Date(value).toLocaleString('zh-CN') : '暂无记录'
}

function App() {
  const [view, setView] = useState<View>('review')
  const [email, setEmail] = useState('')
  const [password, setPassword] = useState('')
  const [token, setToken] = useState('')
  const [signedInAs, setSignedInAs] = useState('')
  const [notice, setNotice] = useState('请登录后台账号。会话 8 小时后过期，凭据不写入浏览器存储。')
  const [loading, setLoading] = useState(false)
  const [queue, setQueue] = useState<ChangeItem[]>([])
  const [changes, setChanges] = useState<ChangeItem[]>([])
  const [news, setNews] = useState<NewsItem[]>([])
  const [sources, setSources] = useState<Source[]>([])
  const [corrections, setCorrections] = useState<ChangeItem[]>([])
  const [health, setHealth] = useState<SourceHealth[]>([])
  const [selectedId, setSelectedId] = useState('')
  const [summary, setSummary] = useState('')
  const [correctionNote, setCorrectionNote] = useState('')
  const [selectedNewsId, setSelectedNewsId] = useState('')
  const [newsTitle, setNewsTitle] = useState('')
  const [newsSummary, setNewsSummary] = useState('')
  const [newsTags, setNewsTags] = useState('')

  const selected = useMemo(
    () => [...queue, ...changes].find((item) => item.id === selectedId),
    [queue, changes, selectedId],
  )
  const selectedNews = useMemo(
    () => news.find((item) => item.id === selectedNewsId),
    [news, selectedNewsId],
  )

  async function request<T>(path: string, init?: RequestInit): Promise<T> {
    if (!token) throw new Error('请先登录')
    const response = await fetch(path, {
      ...init,
      headers: {
        authorization: `Bearer ${token}`,
        ...(init?.body ? { 'content-type': 'application/json' } : {}),
        ...init?.headers,
      },
    })
    const payload = (await response.json().catch(() => null)) as { message?: string } | null
    if (response.status === 401) {
      // 会话过期后继续拿旧 token 请求，每一步都会报一句无关的错。
      // 直接清掉，让界面回到登录态。
      setToken('')
      setSignedInAs('')
      throw new Error('会话已过期，请重新登录')
    }
    if (!response.ok) throw new Error(payload?.message || `HTTP ${response.status}`)
    return payload as T
  }

  async function signIn() {
    setLoading(true)
    try {
      const response = await fetch('/v1/auth/admin', {
        method: 'POST',
        headers: { 'content-type': 'application/json' },
        body: JSON.stringify({ email: email.trim(), password }),
      })
      const payload = (await response.json().catch(() => null)) as
        | { accessToken?: string; email?: string; message?: string }
        | null
      if (!response.ok || !payload?.accessToken) {
        throw new Error(payload?.message || `登录失败（HTTP ${response.status}）`)
      }
      setToken(payload.accessToken)
      setSignedInAs(payload.email ?? email.trim())
      // 密码用完就从内存里抹掉，不留在 React 状态里等着被 devtools 看见。
      setPassword('')
      setNotice('已登录。会话 8 小时后过期。')
    } catch (error) {
      setNotice(error instanceof Error ? error.message : '登录失败')
    } finally {
      setLoading(false)
    }
  }

  function signOut() {
    setToken('')
    setSignedInAs('')
    setPassword('')
    setNotice('已退出。')
  }

  async function load(target: View = view) {
    setLoading(true)
    try {
      if (target === 'review') {
        const data = await request<ChangeItem[]>('/v1/content/admin/review-queue')
        setQueue(data)
        setSelectedId(data[0]?.id ?? '')
        setNotice(`已同步 ${data.length} 条待审核变化`)
      } else if (target === 'published') {
        const [changeData, newsData, sourceData] = await Promise.all([
          request<ChangeItem[]>('/v1/content/admin/changes'),
          request<NewsItem[]>('/v1/content/admin/news'),
          request<Source[]>('/v1/content/admin/sources'),
        ])
        setChanges(changeData)
        setNews(newsData)
        setSources(sourceData)
        const first = changeData.find((item) => item.publishedAt)
        setSelectedId(first?.id ?? '')
        setNotice(`已同步 ${newsData.length} 条新闻与 ${changeData.length} 条变更记录`)
      } else if (target === 'sources') {
        const data = await request<Source[]>('/v1/content/admin/sources')
        setSources(data)
        setNotice(`已同步 ${data.length} 个来源`)
      } else if (target === 'corrections') {
        const data = await request<ChangeItem[]>('/v1/content/admin/corrections')
        setCorrections(data)
        setNotice(`已同步 ${data.length} 条更正记录`)
      } else {
        const data = await request<SourceHealth[]>('/v1/content/admin/source-health')
        setHealth(data)
        setNotice(`已同步 ${data.length} 个来源的采集状态`)
      }
    } catch (error) {
      setNotice(`同步失败：${error instanceof Error ? error.message : '未知错误'}`)
    } finally {
      setLoading(false)
    }
  }

  function openView(next: View) {
    setView(next)
    setSelectedId('')
    setSummary('')
    setCorrectionNote('')
    if (token) void load(next)
  }

  async function review(status: ReviewStatus) {
    if (!selected) return
    setLoading(true)
    try {
      await request(`/v1/content/admin/changes/${selected.id}/review`, {
        method: 'PATCH',
        body: JSON.stringify({
          status,
          ...(summary.trim() ? { editorSummaryZh: summary.trim() } : {}),
          ...(correctionNote.trim() ? { correctionNote: correctionNote.trim() } : {}),
        }),
      })
      setSummary('')
      setCorrectionNote('')
      setNotice(status === 'CORRECTED' ? '更正已发布并保留原记录' : '审核结果已保存')
      await load(view)
    } catch (error) {
      setNotice(`审核未保存：${error instanceof Error ? error.message : '未知错误'}`)
    } finally {
      setLoading(false)
    }
  }

  async function toggleSource(source: Source) {
    setLoading(true)
    try {
      await request(`/v1/content/admin/sources/${source.id}`, {
        method: 'PATCH',
        body: JSON.stringify({ enabled: !source.enabled }),
      })
      await load('sources')
    } catch (error) {
      setNotice(`来源未更新：${error instanceof Error ? error.message : '未知错误'}`)
    } finally {
      setLoading(false)
    }
  }

  async function createSource(event: FormEvent<HTMLFormElement>) {
    event.preventDefault()
    const form = new FormData(event.currentTarget)
    setLoading(true)
    try {
      await request('/v1/content/admin/sources', {
        method: 'POST',
        body: JSON.stringify({
          name: form.get('name'),
          url: form.get('url'),
          jurisdiction: form.get('jurisdiction'),
          sourceType: 'official',
          licenseNote: form.get('licenseNote'),
          enabled: false,
        }),
      })
      event.currentTarget.reset()
      setNotice('来源已保存为停用状态；完成条款与页面级复核后再启用。')
      await load('sources')
    } catch (error) {
      setNotice(`来源未保存：${error instanceof Error ? error.message : '未知错误'}`)
    } finally {
      setLoading(false)
    }
  }

  async function createNews(event: FormEvent<HTMLFormElement>) {
    event.preventDefault()
    const form = new FormData(event.currentTarget)
    const publishedAt = new Date(String(form.get('publishedAt'))).toISOString()
    setLoading(true)
    try {
      await request('/v1/content/admin/news', {
        method: 'POST',
        body: JSON.stringify({
          sourceId: form.get('sourceId'),
          titleZh: form.get('titleZh'),
          summaryZh: form.get('summaryZh'),
          sourceTitle: form.get('sourceTitle'),
          sourceUrl: form.get('sourceUrl'),
          tags: String(form.get('tags') || '').split(/[,，]/).map((tag) => tag.trim()).filter(Boolean),
          publishedAt,
          isPublished: form.get('isPublished') === 'on',
        }),
      })
      event.currentTarget.reset()
      setNotice('新闻已保存；只有明确勾选发布且时间已到的内容才会进入 App。')
      await load('published')
    } catch (error) {
      setNotice(`新闻未保存：${error instanceof Error ? error.message : '未知错误'}`)
    } finally {
      setLoading(false)
    }
  }

  async function toggleNews(item: NewsItem) {
    setLoading(true)
    try {
      await request(`/v1/content/admin/news/${item.id}`, {
        method: 'PATCH',
        body: JSON.stringify({ isPublished: !item.isPublished }),
      })
      await load('published')
    } catch (error) {
      setNotice(`新闻状态未更新：${error instanceof Error ? error.message : '未知错误'}`)
    } finally {
      setLoading(false)
    }
  }

  function editNews(item: NewsItem) {
    setSelectedNewsId(item.id)
    setNewsTitle(item.titleZh)
    setNewsSummary(item.summaryZh)
    setNewsTags(item.tags.join(', '))
  }

  async function saveNewsDraft(event: FormEvent<HTMLFormElement>) {
    event.preventDefault()
    if (!selectedNews) return
    setLoading(true)
    try {
      await request(`/v1/content/admin/news/${selectedNews.id}`, {
        method: 'PATCH',
        body: JSON.stringify({
          titleZh: newsTitle.trim(),
          summaryZh: newsSummary.trim(),
          tags: newsTags.split(/[,，]/).map((tag) => tag.trim()).filter(Boolean),
        }),
      })
      setNotice('中文编辑稿已保存；确认事实和原文链接后再发布。')
      setSelectedNewsId('')
      await load('published')
    } catch (error) {
      setNotice(`编辑稿未保存：${error instanceof Error ? error.message : '未知错误'}`)
    } finally {
      setLoading(false)
    }
  }

  const enabledCount = sources.filter((item) => item.enabled).length
  const healthyCount = health.filter((item) => item.lastSuccessAt && !item.lastFailureCode).length

  return (
    <div className="app-shell">
      <aside className="sidebar">
        <div className="brand-mark">MC</div>
        <div><strong>Migration Companion</strong><span>内容控制台</span></div>
        <nav aria-label="后台主导航">
          {nav.map((item) => (
            <button key={item.id} className={view === item.id ? 'active' : ''} onClick={() => openView(item.id)}>
              <span>{item.icon}</span>{item.label}
              {item.id === 'review' && <b>{queue.length}</b>}
            </button>
          ))}
        </nav>
        <div className="sidebar-note"><span className="status-dot" />南澳数据单元<small>重大与重要变化必须人工核实</small></div>
      </aside>

      <main>
        <header>
          <div><p className="eyebrow">AU-SA · 第一阶段</p><h1>{nav.find((item) => item.id === view)?.label}</h1></div>
          <div className="key-box">
            {token ? (
              <>
                <span className="signed-in">{signedInAs}</span>
                <button onClick={() => load()} disabled={loading}>{loading ? '同步中' : '同步'}</button>
                <button onClick={signOut}>退出</button>
              </>
            ) : (
              <form
                onSubmit={(event) => {
                  event.preventDefault()
                  void signIn()
                }}
              >
                <input type="email" value={email} onChange={(event) => setEmail(event.target.value)} placeholder="管理员邮箱" aria-label="管理员邮箱" autoComplete="username" required />
                <input type="password" value={password} onChange={(event) => setPassword(event.target.value)} placeholder="密码" aria-label="密码" autoComplete="current-password" required />
                <button type="submit" disabled={loading}>{loading ? '登录中' : '登录'}</button>
              </form>
            )}
          </div>
        </header>

        <section className="metrics" aria-label="运营概览">
          <article><span>待审核</span><strong>{queue.length}</strong><small>重大/重要不自动发布</small></article>
          <article><span>已发布新闻</span><strong>{news.filter((item) => item.isPublished).length}</strong><small>摘要必须回到原文</small></article>
          <article><span>启用来源</span><strong>{enabledCount}</strong><small>新增来源默认停用</small></article>
          <article><span>健康来源</span><strong>{health.length ? `${healthyCount}/${health.length}` : '—'}</strong><small>故障不会生成政策结论</small></article>
        </section>
        <p className="notice" role="status">{notice}</p>

        {view === 'review' && (
          <ChangeWorkspace items={queue} selected={selected} selectedId={selectedId} setSelectedId={setSelectedId} summary={summary} setSummary={setSummary} loading={loading} onReview={review} />
        )}

        {view === 'published' && (
          <section className="management-grid">
            <div className="management-list">
              <div className="panel-heading"><div><span className="eyebrow">News</span><h2>新闻与发布状态</h2></div></div>
              {news.length === 0 && <div className="empty">尚无新闻。先同步或创建第一条。</div>}
              {news.map((item) => (
                <article className="management-card" key={item.id}>
                  <div><span className={`state-pill ${item.isPublished ? 'online' : ''}`}>{item.isPublished ? '已发布' : '草稿'}</span><strong>{item.titleZh}</strong><small>{item.source.name} · {formatTime(item.publishedAt)}</small></div>
                  <span className="card-actions"><button onClick={() => editNews(item)} disabled={loading}>编辑</button><button onClick={() => toggleNews(item)} disabled={loading}>{item.isPublished ? '撤下' : '发布'}</button></span>
                </article>
              ))}
            </div>
            {selectedNews ? <form className="editor-form" onSubmit={saveNewsDraft}>
              <span className="eyebrow">Editorial draft</span><h2>编辑新闻草稿</h2>
              <label>中文标题<input required maxLength={240} value={newsTitle} onChange={(event) => setNewsTitle(event.target.value)} /></label>
              <label>中文原创摘要<textarea required maxLength={2000} value={newsSummary} onChange={(event) => setNewsSummary(event.target.value)} /></label>
              <label>标签（逗号分隔）<input value={newsTags} onChange={(event) => setNewsTags(event.target.value)} /></label>
              <p className="guard-copy">原文：<a href={selectedNews.sourceUrl} target="_blank" rel="noreferrer">{selectedNews.sourceTitle} ↗</a></p>
              <button className="approve" disabled={loading}>保存编辑稿</button>
              <button type="button" onClick={() => setSelectedNewsId('')} disabled={loading}>取消</button>
            </form> : <form className="editor-form" onSubmit={createNews}>
              <span className="eyebrow">Create news</span><h2>新增新闻</h2>
              <label>批准来源<select name="sourceId" required defaultValue=""><option value="" disabled>选择来源</option>{sources.filter((item) => item.enabled).map((item) => <option key={item.id} value={item.id}>{item.name}</option>)}</select></label>
              <label>中文标题<input name="titleZh" required maxLength={240} /></label>
              <label>中文原创摘要<textarea name="summaryZh" required maxLength={2000} /></label>
              <label>原文标题<input name="sourceTitle" required maxLength={240} /></label>
              <label>原文链接<input name="sourceUrl" type="url" required /></label>
              <label>标签（逗号分隔）<input name="tags" placeholder="SA, 190, 491" /></label>
              <label>官方发布时间<input name="publishedAt" type="datetime-local" required /></label>
              <label className="check-row"><input name="isPublished" type="checkbox" />保存后立即发布</label>
              <p className="guard-copy">只写事实性摘要，不判断个人资格，不复制官方网页全文。</p>
              <button className="approve" disabled={loading}>保存新闻</button>
            </form>}
            <div className="management-list full-width">
              <div className="panel-heading"><div><span className="eyebrow">Published changes</span><h2>已公开变更与更正</h2></div></div>
              {changes.filter((item) => item.publishedAt).map((item) => (
                <button className={`wide-row ${selectedId === item.id ? 'selected' : ''}`} key={item.id} onClick={() => { setSelectedId(item.id); setSummary(item.editorSummaryZh || ''); setCorrectionNote('') }}>
                  <span className={`severity ${item.importance.toLowerCase()}`}>{severityLabel(item.importance)}</span><strong>{item.titleZh}</strong><small>{item.reviewStatus} · {formatTime(item.publishedAt)}</small>
                </button>
              ))}
              {selected?.publishedAt && <div className="correction-editor"><h3>发布更正</h3><textarea value={summary} onChange={(event) => setSummary(event.target.value)} placeholder="修订后的中文摘要" /><textarea value={correctionNote} onChange={(event) => setCorrectionNote(event.target.value)} placeholder="必须说明更正了什么" /><button className="approve" onClick={() => review('CORRECTED')} disabled={loading || !summary.trim() || !correctionNote.trim()}>发布更正并保留记录</button></div>}
            </div>
          </section>
        )}

        {view === 'sources' && (
          <section className="management-grid">
            <div className="management-list">
              <div className="panel-heading"><div><span className="eyebrow">Registry</span><h2>来源注册表</h2></div></div>
              {sources.map((source) => <article className="management-card" key={source.id}><div><span className={`state-pill ${source.enabled ? 'online' : ''}`}>{source.enabled ? '启用' : '停用'}</span><strong>{source.name}</strong><small>{source.jurisdiction} · {source.url}</small></div><button onClick={() => toggleSource(source)} disabled={loading}>{source.enabled ? '停用' : '启用'}</button></article>)}
            </div>
            <form className="editor-form" onSubmit={createSource}>
              <span className="eyebrow">Add source</span><h2>登记候选来源</h2>
              <label>名称<input name="name" required maxLength={160} /></label>
              <label>HTTPS 地址<input name="url" type="url" required /></label>
              <label>司法辖区<select name="jurisdiction" defaultValue="AU-SA"><option value="AU-SA">AU-SA 南澳</option><option value="AU-FED">AU-FED 联邦上游</option></select></label>
              <label>授权/引用备注<textarea name="licenseNote" maxLength={1000} required /></label>
              <p className="guard-copy">新增后保持停用；确认 robots、条款、版权和页面级第三方内容后再启用。</p>
              <button className="approve" disabled={loading}>保存为停用</button>
            </form>
          </section>
        )}

        {view === 'corrections' && (
          <section className="table-panel"><div className="panel-heading"><div><span className="eyebrow">Audit trail</span><h2>不可无痕删除的更正记录</h2></div></div>{corrections.length === 0 && <div className="empty">当前没有更正记录。</div>}{corrections.map((item) => <article className="audit-row" key={item.id}><span>{formatTime(item.verifiedAt)}</span><strong>{item.titleZh}</strong><p>{item.correctionNote}</p><a href={item.source.url} target="_blank" rel="noreferrer">核对官方原文 ↗</a></article>)}</section>
        )}

        {view === 'health' && (
          <section className="table-panel"><div className="panel-heading"><div><span className="eyebrow">Crawler health</span><h2>采集与证据状态</h2></div></div>{health.length === 0 && <div className="empty">尚无 Worker 上报；这不等于来源健康。</div>}{health.map((item) => <article className="health-row" key={item.id}><span className={`health-dot ${item.lastFailureCode ? 'bad' : item.lastSuccessAt ? '' : 'unknown'}`} /><div><strong>{item.name}</strong><small>{item.jurisdiction} · 最近检查 {formatTime(item.lastCheckedAt)}</small></div><div><b>{item._count.snapshots}</b><small>证据快照</small></div><div><b>{item.lastFailureCode || '正常'}</b><small>{item.lastFailureCode ? `失败 ${formatTime(item.lastFailureAt)}` : `成功 ${formatTime(item.lastSuccessAt)}`}</small></div></article>)}</section>
        )}
      </main>
    </div>
  )
}

function ChangeWorkspace({ items, selected, selectedId, setSelectedId, summary, setSummary, loading, onReview }: {
  items: ChangeItem[]
  selected?: ChangeItem
  selectedId: string
  setSelectedId: (id: string) => void
  summary: string
  setSummary: (value: string) => void
  loading: boolean
  onReview: (status: ReviewStatus) => Promise<void>
}) {
  return <section className="workspace">
    <div className="queue-panel"><div className="panel-heading"><div><span className="eyebrow">Review queue</span><h2>等待人工判断</h2></div></div><div className="queue-list">{items.length === 0 && <div className="empty">同步后显示真实队列；当前不使用演示数据冒充。</div>}{items.map((item) => <button key={item.id} className={`queue-item ${selectedId === item.id ? 'selected' : ''}`} onClick={() => { setSelectedId(item.id); setSummary(item.editorSummaryZh || '') }}><span className={`severity ${item.importance.toLowerCase()}`}>{severityLabel(item.importance)}</span><strong>{item.titleZh}</strong><span>{item.source.name}</span><time>{formatTime(item.discoveredAt)}</time></button>)}</div></div>
    <div className="review-panel">{!selected ? <div className="empty large">选择一条变化开始审核</div> : <><div className="review-header"><div><span className={`severity ${selected.importance.toLowerCase()}`}>{severityLabel(selected.importance)}</span><h2>{selected.titleZh}</h2><a href={selected.source.url} target="_blank" rel="noreferrer">打开官方原文 ↗</a></div><span className="evidence">证据元数据已登记</span></div><div className="diff-grid"><article className="before"><span>上一版本</span><p>{selected.oldExcerpt || '首次记录，无上一版本。'}</p></article><article className="after"><span>当前版本</span><p>{selected.newExcerpt || '当前页面没有可展示的文字片段。'}</p></article></div><div className="source-facts"><div><span>司法辖区</span><strong>{selected.source.jurisdiction}</strong></div><div><span>发现时间</span><strong>{formatTime(selected.discoveredAt)}</strong></div><div><span>发布规则</span><strong>{selected.importance === 'GENERAL' ? '可标待核实，不推送' : '人工核实后发布'}</strong></div></div><label className="summary-field"><span>中文编辑摘要</span><textarea value={summary} onChange={(event) => setSummary(event.target.value)} placeholder="只概述官方事实，不给出个人资格、路径或申请答案建议。" /></label><div className="guardrail"><strong>发布前检查</strong><span>来源可回溯</span><span>无个人资格判断</span><span>无政府隶属暗示</span></div><div className="actions"><button className="reject" onClick={() => onReview('REJECTED')} disabled={loading}>标记误报</button><button className="approve" onClick={() => onReview('VERIFIED')} disabled={loading || !summary.trim()}>核实并发布</button></div></>}</div>
  </section>
}

export default App
