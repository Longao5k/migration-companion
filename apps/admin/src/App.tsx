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
  titleEn: string | null
  summaryEn: string | null
  sourceTitle: string
  sourceExcerpt: string | null
  draftAuthor: 'model' | 'editor' | null
  draftModel: string | null
  draftedAt: string | null
  draftChecks: string[]
  sourceUrl: string
  tags: string[]
  publishedAt: string
  isPublished: boolean
  source: Source
}

/** 一条草稿处在哪个阶段。中文那一档的判据和服务端的发布闸门用同一个正则。 */
type DraftState =
  | 'no-source'
  | 'needs-chinese'
  | 'needs-english'
  | 'machine-drafted'
  | 'ready'
  | 'published'

const CJK = /[㐀-鿿]/

function draftState(item: NewsItem): DraftState {
  if (item.isPublished) return 'published'
  // 没有官方原文摘录 = 没有可核对的基准，这条在后台审不了。
  // 排在最前面：它比「缺中文」更严重，因为缺中文一眼看得出来，
  // 没有原文却是**看起来完全正常**的——列表上和其它条目长得一模一样。
  if (!item.sourceExcerpt?.trim()) return 'no-source'
  if (!CJK.test(item.titleZh) || !CJK.test(item.summaryZh)) return 'needs-chinese'
  // 英文缺失单独成一档，而不是并进「待发布」。申请人常要把政策转述给雇主、
  // 律师或职业评估机构，英文那份是给那些场合用的；混在「待发布」里，
  // 少了英文的条目会被当成完整的一条发出去，没人会发现。
  //
  // 只在后台拦，不在服务端拦：英文缺失是完整度问题，不是安全问题，
  // 不该让一条紧急的政策变更因为没写英文而发不出去。
  if (!item.titleEn?.trim() || !item.summaryEn?.trim()) return 'needs-english'
  // 中英俱全 ≠ 可以发布。这两份都是摘要工具一次跑出来的，
  // 「有汉字」这个判据对 73 条模型稿全部成立。把它叫「待发布」并配成绿色，
  // 等于告诉人「已放行，等着发」——而实际含义只是「机器把稿子写完了」。
  if (item.draftAuthor === 'model') return 'machine-drafted'
  return 'ready'
}

const DRAFT_STATE_LABEL: Record<DraftState, string> = {
  'no-source': '无原文',
  'needs-chinese': '待写中文',
  'needs-english': '待写英文',
  'machine-drafted': '未核对',
  ready: '已核对',
  published: '已发布',
}

type SourceHealth = Source & {
  snapshots: Array<{
    contentHash: string
    httpStatus: number
    fetchedAt: string
  }>
  _count: { snapshots: number; changes: number; news: number }
}

// 顺序 = 每天真正要干的活的顺序。
//
// 原先第一项叫「审核队列」，审的却是变更日志（今天 0 条），而真正待审的
// 73 条资讯藏在第二项「已发布内容」里——一个听起来跟审核无关的名字。
// 登录第一屏因此写着「审核队列 0」，实际待审 73。
const nav: Array<{ id: View; icon: string; label: string }> = [
  { id: 'published', icon: '◫', label: '资讯审核' },
  { id: 'review', icon: '⌁', label: '政策变更' },
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
  // 默认落在资讯审核：那是每天真正要干的活。
  // 原先默认是变更队列，登录第一眼看到「0 条待审核」，而实际待审 73。
  const [view, setView] = useState<View>('published')
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
  const [newsTitleEn, setNewsTitleEn] = useState('')
  const [newsSummaryEn, setNewsSummaryEn] = useState('')
  const [newsTags, setNewsTags] = useState('')
  const [newsFilter, setNewsFilter] = useState<'all' | DraftState>('all')
  const [onlyModelDrafts, setOnlyModelDrafts] = useState(false)
  const [selectedIds, setSelectedIds] = useState<Set<string>>(new Set())

  const selected = useMemo(
    () => [...queue, ...changes].find((item) => item.id === selectedId),
    [queue, changes, selectedId],
  )
  const selectedNews = useMemo(
    () => news.find((item) => item.id === selectedNewsId),
    [news, selectedNewsId],
  )
  const visibleNews = useMemo(
    () =>
      news.filter((item) => {
        if (newsFilter !== 'all' && draftState(item) !== newsFilter) return false
        if (onlyModelDrafts && item.draftAuthor !== 'model') return false
        return true
      }),
    [news, newsFilter, onlyModelDrafts],
  )
  // 只有**人核对过**的才可批量发布。
  //
  // 这里原先圈的是 draftState === 'ready'，而 ready 当时的判据只是
  // 「中英文都非空」——两份都是摘要工具一次跑出来的，于是 73 条从没有人
  // 看过的模型稿全部被圈中，页面上最醒目的绿色按钮一次点击就能把它们
  // 推给所有订阅者。这不是审核的加速器，是审核的跳过键。
  //
  // 服务端也已经补上同一道闸（assertHumanReviewed），前端可以出 bug，
  // 闸门不能只在前端。
  const readySelectable = useMemo(
    () => visibleNews.filter((item) => draftState(item) === 'ready'),
    [visibleNews],
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
      // 登录完还要自己点一次「同步」才有数据，是没道理的。
      queueMicrotask(() => void load())
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

  /** 顶部四个指标卡横跨多个页签，必须一次拉齐——否则会把「这一页没加载」显示成 0。 */
  async function loadOverview() {
    const [queueData, newsData, sourceData] = await Promise.all([
      request<ChangeItem[]>('/v1/content/admin/review-queue'),
      request<NewsItem[]>('/v1/content/admin/news'),
      request<Source[]>('/v1/content/admin/sources'),
    ])
    setQueue(queueData)
    setNews(newsData)
    setSources(sourceData)
    return { queueData, newsData }
  }

  async function load(target: View = view) {
    setLoading(true)
    try {
      if (target === 'review') {
        const { queueData, newsData } = await loadOverview()
        setSelectedId(queueData[0]?.id ?? '')
        const drafts = newsData.filter((item) => !item.isPublished).length
        setNotice(
          queueData.length === 0 && drafts > 0
            ? `没有待审核的政策变化。「已发布内容」里有 ${drafts} 条新闻草稿待发布。`
            : `已同步 ${queueData.length} 条待审核变化`,
        )
      } else if (target === 'published') {
        const [changeData, newsData, sourceData] = await Promise.all([
          request<ChangeItem[]>('/v1/content/admin/changes'),
          request<NewsItem[]>('/v1/content/admin/news'),
          request<Source[]>('/v1/content/admin/sources'),
        ])
        setChanges(changeData)
        setNews(newsData)
        setSources(sourceData)
        // 不要在这里动 selectedId。
        //
        // 原先它会选中第一条已发布变更，于是页面底部的「发布更正」编辑器
        // 自动展开——而 saveNewsDraft 每次保存后都会调 load('published')。
        // 结果是：每审完一条资讯，页面下方就弹出一个和资讯审核毫无关系、
        // 却能误触的发布动作。连审 73 条就是弹 73 次。
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
    // 未保存的修改不能静默丢弃。
    //
    // 原先无条件覆盖表单的五个 state：改了一半 A 条、手滑点了 B 条的「核对」，
    // A 的修改无声消失。73 条连着审，这一定会发生至少一次，
    // 而且发生时没有任何提示——你以为存过了。
    if (selectedNews && selectedNews.id !== item.id && hasUnsavedEdits()) {
      const ok = window.confirm(
        `《${selectedNews.titleZh || selectedNews.sourceTitle}》有未保存的修改，` +
          '切换到另一条会丢掉它们。要继续吗？',
      )
      if (!ok) return
    }
    setSelectedNewsId(item.id)
    // 点「编辑」之后要让表单出现在眼前。
    // 原先什么都不做：在第 30 条的位置点编辑，表单在两千像素以外的页顶，
    // 屏幕上毫无变化，看起来像没反应。
    requestAnimationFrame(() => {
      const form = document.querySelector('.editor-form')
      form?.scrollIntoView({ behavior: 'smooth', block: 'start' })
      const first = form?.querySelector('input') as HTMLInputElement | null
      first?.focus()
    })
    setNewsTitle(item.titleZh)
    setNewsSummary(item.summaryZh)
    setNewsTitleEn(item.titleEn || '')
    setNewsSummaryEn(item.summaryEn || '')
    setNewsTags(item.tags.join(', '))
  }

  /** 批量发布。逐条走服务端闸门，失败的留在列表里并说明原因。 */
  async function publishSelected() {
    setLoading(true)
    const failures: string[] = []
    let done = 0
    for (const id of selectedIds) {
      try {
        await request(`/v1/content/admin/news/${id}`, {
          method: 'PATCH',
          body: JSON.stringify({ isPublished: true }),
        })
        done += 1
      } catch (error) {
        const item = news.find((entry) => entry.id === id)
        failures.push(
          `${item?.titleZh || item?.sourceTitle || id}：${
            error instanceof Error ? error.message : '未知错误'
          }`,
        )
      }
    }
    setSelectedIds(new Set())
    await load('published')
    setNotice(
      failures.length === 0
        ? `已发布 ${done} 条。`
        : `已发布 ${done} 条，${failures.length} 条未通过：${failures.slice(0, 3).join('；')}`,
    )
    setLoading(false)
  }

  /** 表单里是否有相对已保存内容的改动。 */
  function hasUnsavedEdits(): boolean {
    if (!selectedNews) return false
    return (
      newsTitle.trim() !== (selectedNews.titleZh || '').trim() ||
      newsSummary.trim() !== (selectedNews.summaryZh || '').trim() ||
      newsTitleEn.trim() !== (selectedNews.titleEn || '').trim() ||
      newsSummaryEn.trim() !== (selectedNews.summaryEn || '').trim() ||
      newsTags.trim() !== selectedNews.tags.join(', ').trim()
    )
  }

  /** 保存后要打开的下一条：当前筛选列表里，排在这条之后的第一条未核对草稿。 */
  function nextUnchecked(currentId: string): NewsItem | undefined {
    const index = visibleNews.findIndex((item) => item.id === currentId)
    return visibleNews
      .slice(index + 1)
      .find((item) => draftState(item) === 'machine-drafted')
  }

  async function saveNewsDraft(
    event: FormEvent<HTMLFormElement>,
    advance = false,
  ) {
    event.preventDefault()
    if (!selectedNews) return
    setLoading(true)
    try {
      await request(`/v1/content/admin/news/${selectedNews.id}`, {
        method: 'PATCH',
        body: JSON.stringify({
          titleZh: newsTitle.trim(),
          summaryZh: newsSummary.trim(),
          titleEn: newsTitleEn.trim(),
          summaryEn: newsSummaryEn.trim(),
          tags: newsTags.split(/[,，]/).map((tag) => tag.trim()).filter(Boolean),
          // 人改过就不再是模型稿，标记跟着变——列表上的「模型稿」提示才准确。
          //
          // 这个标记只有在英文也在同一个表单里能看见时才诚实：以前保存只写中文，
          // 却把整条标成「已人工核对」，而英文那半从没在这个界面上出现过。
          draftAuthor: 'editor',
        }),
      })
      // 保存后不再无条件收起编辑器。
      //
      // 原先是 setSelectedNewsId('')，右栏立刻翻回「新增新闻」表单——
      // 一个在审核流程里完全用不到的表单。73 条就是 73 次「保存 → 表单消失 →
      // 滚回列表 → 找下一条 → 点编辑 → 滚回顶部」。
      const next = advance ? nextUnchecked(selectedNews.id) : undefined
      await load('published')
      if (next) {
        editNews(next)
        setNotice(`已核对，进入下一条（${nextUnchecked(next.id) ? '后面还有' : '这是最后一条'}）`)
      } else if (advance) {
        setSelectedNewsId('')
        setNotice('这一批已经核对完了。勾选「已核对」的条目即可批量发布。')
      } else {
        setNotice('已保存并标记为已核对；确认原文链接后即可发布。')
      }
    } catch (error) {
      setNotice(`编辑稿未保存：${error instanceof Error ? error.message : '未知错误'}`)
    } finally {
      setLoading(false)
    }
  }

  // 审核进度：审到一半合上电脑，第二天回来要能一眼知道还剩多少。
  const uncheckedCount = news.filter(
    (item) => !item.isPublished && item.draftAuthor === 'model',
  ).length
  const checkedCount = news.filter(
    (item) => !item.isPublished && draftState(item) === 'ready',
  ).length
  const enabledCount = sources.filter((item) => item.enabled).length
  const healthyCount = health.filter((item) => item.lastSuccessAt && !item.lastFailureCode).length

  // 未登录时只给登录页，不给控制台外壳。
  // 原先把登录框塞在仪表盘头部，未登录的人会看到一整套侧栏和四个显示 0 的指标卡，
  // 分不清是「没数据」还是「没登录」。
  if (!token) {
    return (
      <div className="login-shell">
        <form
          className="login-card"
          onSubmit={(event) => {
            event.preventDefault()
            void signIn()
          }}
        >
          <div className="brand-mark">W</div>
          <h1>Waymark 内容控制台</h1>
          <p className="login-hint">
            这里可以审核政策变化、发布中文资讯。账号由服务器上直接创建。
          </p>
          <label>
            邮箱
            <input
              type="email"
              value={email}
              onChange={(event) => setEmail(event.target.value)}
              autoComplete="username"
              required
              autoFocus
            />
          </label>
          <label>
            密码
            <input
              type="password"
              value={password}
              onChange={(event) => setPassword(event.target.value)}
              autoComplete="current-password"
              required
            />
          </label>
          <button type="submit" disabled={loading}>
            {loading ? '登录中…' : '登录'}
          </button>
          {notice && <p className="login-notice">{notice}</p>}
          <p className="login-foot">会话 8 小时后过期，凭据不写入浏览器存储。</p>
        </form>
      </div>
    )
  }

  return (
    <div className="app-shell">
      <aside className="sidebar">
        <div className="brand-mark">W</div>
        <div><strong>Waymark</strong><span>内容控制台</span></div>
        <nav aria-label="后台主导航">
          {nav.map((item) => (
            <button key={item.id} className={view === item.id ? 'active' : ''} onClick={() => openView(item.id)}>
              <span>{item.icon}</span>{item.label}
              {/* 徽章显示的必须是「还没干完的活」，不是「这个页面有多少条」。 */}
              {item.id === 'published' && uncheckedCount > 0 && <b>{uncheckedCount}</b>}
              {item.id === 'review' && queue.length > 0 && <b>{queue.length}</b>}
            </button>
          ))}
        </nav>
        <div className="sidebar-note"><span className="status-dot" />南澳数据单元<small>重大与重要变化必须人工核实</small></div>
      </aside>

      <main>
        <header>
          <div><h1>{nav.find((item) => item.id === view)?.label}</h1></div>
          <div className="key-box">
            <span className="signed-in">{signedInAs}</span>
            <button onClick={() => load()} disabled={loading}>
              {loading ? '同步中' : '同步'}
            </button>
            <button onClick={signOut}>退出</button>
          </div>
        </header>

        <section className="metrics" aria-label="运营概览">
          {/* 第一格原先显示的是变更队列（今天是 0），而实际待核对的资讯有 73 条。
              登录第一屏写着「待审核 0」、实际待审 73，是这个后台最误导人的一处。 */}
          <article><span>待核对资讯</span><strong>{uncheckedCount}</strong><small>模型稿，逐字对照原文后保存</small></article>
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
              <div className="panel-heading">
                <div>
                  <h2>资讯审核</h2>
                  <small>
                    已核对 {checkedCount} / 待核对 {uncheckedCount}
                    {checkedCount > 0 && ' —— 勾选已核对的可批量发布'}
                  </small>
                </div>
              </div>

              {/* 73 条平铺、无筛选、无批量，只能逐条点——这是「审不完」的直接原因。 */}
              <div className="list-toolbar">
                {([
                  'all',
                  'machine-drafted',
                  'ready',
                  'no-source',
                  'needs-chinese',
                  'needs-english',
                  'published',
                ] as const).map((key) => (
                  <button
                    key={key}
                    className={newsFilter === key ? 'filter active' : 'filter'}
                    onClick={() => { setNewsFilter(key); setSelectedIds(new Set()) }}
                  >
                    {key === 'all' ? '全部' : DRAFT_STATE_LABEL[key]}
                    <span className="count">
                      {key === 'all'
                        ? news.length
                        : news.filter((item) => draftState(item) === key).length}
                    </span>
                  </button>
                ))}
                <label className="filter-check">
                  <input
                    type="checkbox"
                    checked={onlyModelDrafts}
                    onChange={(event) => setOnlyModelDrafts(event.target.checked)}
                  />
                  只看模型稿
                </label>
              </div>

              {readySelectable.length > 0 && (
                <div className="bulk-bar">
                  <label>
                    <input
                      type="checkbox"
                      checked={
                        selectedIds.size > 0 && selectedIds.size === readySelectable.length
                      }
                      onChange={(event) =>
                        setSelectedIds(
                          event.target.checked
                            ? new Set(readySelectable.map((item) => item.id))
                            : new Set(),
                        )
                      }
                    />
                    全选可发布的 {readySelectable.length} 条
                  </label>
                  <button
                    className="approve"
                    disabled={loading || selectedIds.size === 0}
                    onClick={() => void publishSelected()}
                  >
                    发布已核对的 {selectedIds.size} 条
                  </button>
                </div>
              )}

              {visibleNews.length === 0 && (
                <div className="empty">这个筛选下没有条目。</div>
              )}
              {visibleNews.map((item) => {
                const state = draftState(item)
                return (
                  <article className="management-card" key={item.id}>
                    <div>
                      {state === 'ready' && (
                        <input
                          type="checkbox"
                          checked={selectedIds.has(item.id)}
                          onChange={(event) => {
                            const next = new Set(selectedIds)
                            if (event.target.checked) next.add(item.id)
                            else next.delete(item.id)
                            setSelectedIds(next)
                          }}
                        />
                      )}
                      <span className={`state-pill ${state}`}>{DRAFT_STATE_LABEL[state]}</span>
                      {item.draftAuthor === 'model' && (
                        <span className="state-pill model" title="模型起草，需逐字对照原文">
                          模型稿
                        </span>
                      )}
                      <strong>{item.titleZh || item.sourceTitle}</strong>
                      <small>
                        {item.source.name} · {formatTime(item.publishedAt)}
                      </small>
                    </div>
                    <span className="card-actions">
                      <button onClick={() => editNews(item)} disabled={loading}>
                        {state === 'machine-drafted' ? '核对' : '编辑'}
                      </button>
                      {/* 发布是不可撤的：撤下能改状态，但推送已经发出去了。
                          它此前和「编辑」长成一对灰按钮，还没有二次确认。 */}
                      <button
                        className={item.isPublished ? undefined : 'publish'}
                        onClick={() => {
                          if (item.isPublished) return void toggleNews(item)
                          const ok = window.confirm(
                            `发布《${item.titleZh || item.sourceTitle}》？
` +
                              '订阅了对应辖区与标签的用户会立刻收到推送，推送发出后收不回来。',
                          )
                          if (ok) void toggleNews(item)
                        }}
                        disabled={
                          loading ||
                          state === 'machine-drafted' ||
                          (state === 'no-source' && item.draftAuthor !== 'editor')
                        }
                        title={
                          state === 'machine-drafted'
                            ? '这条还没人核对过。请先点「核对」逐字对照原文并保存。'
                            : state === 'no-source' && item.draftAuthor !== 'editor'
                              ? '这条没有官方原文摘录。请先点「核对」，打开官方页面逐项核对并保存。'
                              : undefined
                        }
                      >
                        {item.isPublished ? '撤下' : '发布'}
                      </button>
                    </span>
                  </article>
                )
              })}
            </div>
            {selectedNews ? <form
              className="editor-form"
              onSubmit={(event) => saveNewsDraft(event, true)}
              // 连审时手不必离开键盘。73 条逐条填表，每次 4 次鼠标往返，
              // 光是往返就足以让人中途放弃。
              onKeyDown={(event) => {
                if ((event.ctrlKey || event.metaKey) && event.key === 'Enter') {
                  event.preventDefault()
                  void saveNewsDraft(event as unknown as FormEvent<HTMLFormElement>, true)
                }
              }}
            >
              <h2>编辑新闻草稿</h2>

              {/* 原文和译稿必须同屏。原先原文被中文摘要覆盖掉了，审核只能开外部
                  浏览器对照——而我们的规则是「人工核实后才发布」，核实工具里
                  却没有被核实的那个东西。变更审核页早就是左右对照，这里照抄。 */}
              <div className="source-pane">
                <span className="pane-label">官方原文</span>
                <strong>{selectedNews.sourceTitle}</strong>
                <p className="source-excerpt">
                  {selectedNews.sourceExcerpt ||
                    '这条没有留存官方原文摘录。它的中英摘要是由上一版摘要转写的，' +
                      '其中的数字从未与官方页面比对过——必须打开官方页面逐个核对。' +
                      '核对完保存，这一下就是你对此负责的记号；未保存前服务端不允许发布。'}
                </p>
                <a href={selectedNews.sourceUrl} target="_blank" rel="noreferrer">
                  打开官方页面 ↗
                </a>
              </div>

              {/* 有机器痕迹就显示，不只看 draftAuthor。
                  已发布的 5 条种子内容中文是人写的、英文是模型补的，
                  draftAuthor 是 null——按老条件它们什么提示都没有，
                  而那几段英文确实没有人看过。 */}
              {(selectedNews.draftAuthor === 'model' ||
                selectedNews.draftChecks.length > 0) && (
                <div className="model-warning">
                  <p>
                    {selectedNews.draftAuthor === 'model'
                      ? '中英两份都由模型起草，请逐字对照左侧原文，两份都要看。'
                      : '中文为人工撰写，英文摘要由模型起草——英文那份仍需对照原文核对。'}
                    它写出过带建议口吻的句子。
                    <strong>保存即代表你已核对</strong>
                    {selectedNews.draftAuthor === 'model'
                      ? '——保存之后这条才允许发布。'
                      : '。'}
                  </p>
                  {/* 机器验过什么、没验什么，直接摊开。
                      这份信息此前只打在起草工具的 console 日志里，一个字都没进到
                      这个界面——于是每条都得当成完全没核过来审，白花力气。 */}
                  {selectedNews.draftChecks.length > 0 && (
                    <ul className="draft-checks">
                      {selectedNews.draftChecks.map((line) => (
                        <li key={line}>{line}</li>
                      ))}
                    </ul>
                  )}
                  <small className="draft-origin">
                    {selectedNews.draftModel
                      ? `起草模型 ${selectedNews.draftModel}`
                      : '起草模型未记录'}
                    {selectedNews.draftedAt
                      ? ` · ${formatTime(selectedNews.draftedAt)}`
                      : ''}
                    {selectedNews.draftedAt &&
                      ' · 官方页面在这之后改过的话，这份稿子就是过期的'}
                  </small>
                </div>
              )}

              <label>中文标题<input required maxLength={240} value={newsTitle} onChange={(event) => setNewsTitle(event.target.value)} /></label>
              <label>中文原创摘要<textarea required maxLength={2000} value={newsSummary} onChange={(event) => setNewsSummary(event.target.value)} /></label>

              {/* 英文稿必须在同一个表单里。它会随发布一起上线，给申请人转述给雇主、
                  律师和职业评估机构用——之前它在库里、在 App 里，唯独不在这个
                  审核界面上，等于绕过了「人工核实后发布」这道闸。 */}
              <label>英文标题<input maxLength={240} value={newsTitleEn} onChange={(event) => setNewsTitleEn(event.target.value)} placeholder="留空则 App 内不显示英文" /></label>
              <label>英文摘要<textarea maxLength={2000} value={newsSummaryEn} onChange={(event) => setNewsSummaryEn(event.target.value)} placeholder="与中文陈述同一组事实，数字必须一致" /></label>

              <label>标签（逗号分隔）<input value={newsTags} onChange={(event) => setNewsTags(event.target.value)} /></label>
              <div className="editor-actions">
                <button className="approve" disabled={loading}>
                  核对无误，保存并下一条 <kbd>Ctrl+Enter</kbd>
                </button>
                <button
                  type="button"
                  onClick={(event) =>
                    saveNewsDraft(event as unknown as FormEvent<HTMLFormElement>, false)
                  }
                  disabled={loading}
                >
                  只保存
                </button>
                <button type="button" onClick={() => setSelectedNewsId('')} disabled={loading}>
                  取消
                </button>
              </div>
            </form> : <form className="editor-form" onSubmit={createNews}>
              <h2>新增新闻</h2>
              <label>批准来源<select name="sourceId" required defaultValue=""><option value="" disabled>选择来源</option>{sources.filter((item) => item.enabled).map((item) => <option key={item.id} value={item.id}>{item.name}</option>)}</select></label>
              <label>中文标题<input name="titleZh" required maxLength={240} /></label>
              <label>中文原创摘要<textarea name="summaryZh" required maxLength={2000} /></label>
              <label>原文标题<input name="sourceTitle" required maxLength={240} /></label>
              <label>原文链接<input name="sourceUrl" type="url" required /></label>
              <label>标签（逗号分隔）<input name="tags" placeholder="190, 职业清单" /></label>
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
              <div className="panel-heading"><div><h2>来源注册表</h2></div></div>
              {sources.map((source) => <article className="management-card" key={source.id}><div><span className={`state-pill ${source.enabled ? 'online' : ''}`}>{source.enabled ? '启用' : '停用'}</span><strong>{source.name}</strong><small>{source.jurisdiction} · {source.url}</small></div><button onClick={() => toggleSource(source)} disabled={loading}>{source.enabled ? '停用' : '启用'}</button></article>)}
            </div>
            <form className="editor-form" onSubmit={createSource}>
              <h2>登记候选来源</h2>
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
          <section className="table-panel"><div className="panel-heading"><div><h2>不可无痕删除的更正记录</h2></div></div>{corrections.length === 0 && <div className="empty">当前没有更正记录。</div>}{corrections.map((item) => <article className="audit-row" key={item.id}><span>{formatTime(item.verifiedAt)}</span><strong>{item.titleZh}</strong><p>{item.correctionNote}</p><a href={item.source.url} target="_blank" rel="noreferrer">核对官方原文 ↗</a></article>)}</section>
        )}

        {view === 'health' && (
          <section className="table-panel"><div className="panel-heading"><div><h2>采集与证据状态</h2></div></div>{health.length === 0 && <div className="empty">采集器还没上报过，不能据此认为来源正常。</div>}{health.map((item) => <article className="health-row" key={item.id}><span className={`health-dot ${item.lastFailureCode ? 'bad' : item.lastSuccessAt ? '' : 'unknown'}`} /><div><strong>{item.name}</strong><small>{item.jurisdiction} · 最近检查 {formatTime(item.lastCheckedAt)}</small></div><div><b>{item._count.snapshots}</b><small>证据快照</small></div><div><b>{item.lastFailureCode || '正常'}</b><small>{item.lastFailureCode ? `失败 ${formatTime(item.lastFailureAt)}` : `成功 ${formatTime(item.lastSuccessAt)}`}</small></div></article>)}</section>
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
    <div className="queue-panel"><div className="panel-heading"><div><h2>等待人工判断</h2></div></div><div className="queue-list">{items.length === 0 && <div className="empty">当前没有待审核的政策变化。</div>}{items.map((item) => <button key={item.id} className={`queue-item ${selectedId === item.id ? 'selected' : ''}`} onClick={() => { setSelectedId(item.id); setSummary(item.editorSummaryZh || '') }}><span className={`severity ${item.importance.toLowerCase()}`}>{severityLabel(item.importance)}</span><strong>{item.titleZh}</strong><span>{item.source.name}</span><time>{formatTime(item.discoveredAt)}</time></button>)}</div></div>
    <div className="review-panel">{!selected ? <div className="empty large">选择一条变化开始审核</div> : <><div className="review-header"><div><span className={`severity ${selected.importance.toLowerCase()}`}>{severityLabel(selected.importance)}</span><h2>{selected.titleZh}</h2><a href={selected.source.url} target="_blank" rel="noreferrer">打开官方原文 ↗</a></div></div><div className="diff-grid"><article className="before"><span>上一版本</span><p>{selected.oldExcerpt || '首次记录，无上一版本。'}</p></article><article className="after"><span>当前版本</span><p>{selected.newExcerpt || '当前页面没有可展示的文字片段。'}</p></article></div><div className="source-facts"><div><span>司法辖区</span><strong>{selected.source.jurisdiction}</strong></div><div><span>发现时间</span><strong>{formatTime(selected.discoveredAt)}</strong></div><div><span>发布规则</span><strong>{selected.importance === 'GENERAL' ? '可标待核实，不推送' : '人工核实后发布'}</strong></div></div><label className="summary-field"><span>中文编辑摘要</span><textarea value={summary} onChange={(event) => setSummary(event.target.value)} placeholder="只概述官方事实，不给出个人资格、路径或申请答案建议。" /></label><div className="guardrail"><strong>发布前检查</strong><span>来源可回溯</span><span>无个人资格判断</span><span>无政府隶属暗示</span></div><div className="actions"><button className="reject" onClick={() => onReview('REJECTED')} disabled={loading}>标记误报</button><button className="approve" onClick={() => onReview('VERIFIED')} disabled={loading || !summary.trim()}>核实并发布</button></div></>}</div>
  </section>
}

export default App
