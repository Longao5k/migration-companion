'use client'

import { FormEvent, useState } from 'react'
import { useParams } from 'next/navigation'

export default function InvitationPage() {
  const { invitationId } = useParams<{ invitationId: string }>()
  const [email, setEmail] = useState('')
  const [projectName, setProjectName] = useState('')
  const [error, setError] = useState('')
  const [loading, setLoading] = useState(false)

  async function accept(event: FormEvent) {
    event.preventDefault()
    const secret = window.location.hash.slice(1)
    if (!secret) { setError('邀请链接缺少安全信息，请让所有者重新发送完整链接。'); return }
    setLoading(true); setError('')
    try {
      const apiBase = process.env.NEXT_PUBLIC_API_BASE ?? 'http://127.0.0.1:53001'
      const response = await fetch(`${apiBase}/v1/collaboration-invitations/${invitationId}/accept`, {
        method: 'POST',
        headers: {
          'authorization': 'Bearer local-or-cognito-token',
          'x-dev-account-email': email,
          'content-type': 'application/json',
        },
        body: JSON.stringify({ secret }),
      })
      if (!response.ok) {
        const body = await response.json().catch(() => ({}))
        throw new Error(body.message ?? '无法接受邀请')
      }
      const body = await response.json()
      setProjectName(body.projectName)
      history.replaceState(null, '', location.pathname)
    } catch (reason) {
      setError(reason instanceof Error ? reason.message : '无法接受邀请')
    } finally { setLoading(false) }
  }

  return <main className="share-page"><div className="share-card">
    {!projectName ? <>
      <p className="eyebrow">APP 协作邀请</p><h1>接受项目邀请</h1>
      <p>请使用邀请指定的邮箱。接受后，权限仍由项目所有者控制并可随时撤销。</p>
      <form onSubmit={accept}>
        <label htmlFor="email">登录邮箱</label>
        <input id="email" type="email" value={email} onChange={event => setEmail(event.target.value)} autoComplete="email" required />
        {error && <p className="error" role="alert">{error}</p>}
        <button className="primary" disabled={loading}>{loading ? '正在接受…' : '确认接受邀请'}</button>
      </form>
      <div className="callout">本地开发版用邮箱模拟已验证账号；正式版会先完成邮箱验证码登录。</div>
    </> : <>
      <p className="eyebrow">邀请已接受</p><h1>{projectName}</h1>
      <div className="callout">项目已经加入你的账号。回到 App 刷新后即可按所有者授予的权限查看或协作。</div>
    </>}
  </div></main>
}

