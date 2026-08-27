import type { Metadata } from 'next'
import Link from 'next/link'
import './globals.css'

export const metadata: Metadata = {
  title: 'Migration Companion',
  description: 'Independent migration information and document workspace.',
}

export default function RootLayout({ children }: Readonly<{ children: React.ReactNode }>) {
  return (
    <html lang="zh-CN">
      <body>
        <header className="site-header">
          <Link className="brand" href="/"><span>MC</span>Migration Companion</Link>
          <nav>
            <Link href="/privacy">隐私</Link>
            <Link href="/terms">条款</Link>
            <Link href="/account-deletion">删除账号</Link>
          </nav>
        </header>
        {children}
        <footer>
          <strong>独立第三方工具，不隶属于澳洲联邦或南澳政府。</strong>
          <span>政策内容以官方原文为准；本产品不提供个人移民法律意见。</span>
        </footer>
      </body>
    </html>
  )
}

