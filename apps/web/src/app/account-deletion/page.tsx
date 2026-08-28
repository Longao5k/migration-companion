'use client'

import { useState } from 'react'

export default function AccountDeletionPage() {
  const [acknowledged, setAcknowledged] = useState(false)
  const deleteAuthUrl = process.env.NEXT_PUBLIC_DELETE_AUTH_URL
  return <main className="content-page">
    <p className="eyebrow">账号与数据控制</p><h1>删除账号</h1>
    <p>你可以在 App 的“我的 → 删除账号与数据”发起完整删除。此网页提供同一操作的外部入口；为防止他人冒用邮箱删除你的材料，必须先通过账号身份验证。</p>
    <div className="callout"><strong>删除前请确认</strong><ul>
      <li>安全分享、协作邀请和云端项目访问会立即撤销。</li>
      <li>云端主数据目标在确认后 7 天内删除；隔离备份按说明最长 35 天淘汰。</li>
      <li>当前设备上你选择保留的本机项目不会因删除云账号自动消失。</li>
    </ul></div>
    <label><input style={{width:'auto',marginRight:8}} type="checkbox" checked={acknowledged} onChange={event=>setAcknowledged(event.target.checked)} />我已理解账号删除与取消商店订阅是两件事</label>
    {deleteAuthUrl ? <a className={`primary ${acknowledged ? '' : 'disabled'}`} aria-disabled={!acknowledged} href={acknowledged ? deleteAuthUrl : undefined}>验证身份并发起删除</a> : <p className="error">上线阻塞：尚未配置 Cognito 删除流程和正式支持联系方式。本页不可作为商店提交版本。</p>}
  </main>
}

