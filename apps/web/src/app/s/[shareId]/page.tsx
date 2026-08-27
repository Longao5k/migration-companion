'use client'

import { FormEvent, useState } from 'react'
import { useParams } from 'next/navigation'

type SharedContent = {
  projectName: string
  expiresAt: string
  allowDownload: boolean
  warning: string
  items?: Array<{ id: string; title: string; category: string; status: string; note?: string }>
  files?: Array<{ id: string; displayName: string; contentType: string; byteSize: string; downloadUrl?: string | null }>
}

export default function SharePage() {
  const { shareId } = useParams<{ shareId: string }>()
  const [code, setCode] = useState('')
  const [content, setContent] = useState<SharedContent | null>(null)
  const [error, setError] = useState('')
  const [loading, setLoading] = useState(false)

  async function unlock(event: FormEvent) {
    event.preventDefault()
    const secret = window.location.hash.slice(1)
    if (!secret) { setError('链接缺少安全信息，请让分享者重新发送完整链接。'); return }
    setLoading(true); setError('')
    try {
      const apiBase = process.env.NEXT_PUBLIC_API_BASE ?? 'http://127.0.0.1:53001'
      const response = await fetch(`${apiBase}/v1/public/shares/${shareId}/access`, {
        method: 'POST', headers: { 'content-type': 'application/json' },
        body: JSON.stringify({ secret, accessCode: code }),
      })
      if (!response.ok) {
        const body = await response.json().catch(() => ({}))
        throw new Error(body.message ?? '无法打开分享')
      }
      setContent(await response.json())
      history.replaceState(null, '', location.pathname)
    } catch (reason) {
      setError(reason instanceof Error ? reason.message : '无法打开分享')
    } finally { setLoading(false) }
  }

  return <main className="share-page"><div className="share-card">
    {!content ? <>
      <p className="eyebrow">安全分享入口</p><h1>查看分享内容</h1>
      <p>无需安装 App 或注册账号。访问码应由分享者通过另一种方式发送给你。</p>
      <form onSubmit={unlock}><label htmlFor="code">访问码</label>
        <input id="code" value={code} onChange={event => setCode(event.target.value.toUpperCase())} minLength={8} autoComplete="one-time-code" required />
        {error && <p className="error" role="alert">{error}</p>}
        <button className="primary" disabled={loading}>{loading ? '正在核对…' : '安全打开'}</button>
      </form>
    </> : <>
      <p className="eyebrow">有效至 {new Date(content.expiresAt).toLocaleString('zh-CN')}</p>
      <h1>{content.projectName}</h1><div className="callout">{content.warning}</div>
      <div className="shared-items">
        {content.items?.map(item => <div className="shared-item" key={item.id}><strong>{item.title}</strong><br/><small>{item.category} · {item.status}</small>{item.note && <p>{item.note}</p>}</div>)}
        {content.files?.map(file => <div className="shared-item" key={file.id}><strong>{file.displayName}</strong><br/><small>{file.contentType} · {file.byteSize} bytes · {content.allowDownload ? '允许下载' : '仅查看'}</small>{file.downloadUrl && <><br/><a href={file.downloadUrl} rel="noreferrer">下载副本</a></>}</div>)}
      </div>
    </>}
  </div></main>
}
