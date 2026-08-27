import Link from 'next/link'

export default function Home() {
  return (
    <main className="landing">
      <p className="eyebrow">从南澳开始</p>
      <h1>把申请这件事，<br />理清楚。</h1>
      <p className="lead">核对官方变化，整理自己的材料，并用可控的方式分享。默认从本机开始，不用登录也能建立项目。</p>
      <div className="actions">
        <Link className="primary" href="/account-deletion">账号与数据控制</Link>
        <Link className="secondary" href="/privacy">了解隐私边界</Link>
      </div>
      <section className="feature-grid">
        <article><span>01</span><h2>官方变化有证据</h2><p>重要变化人工核实后才发布，并保留来源、前后差异与更正。</p></article>
        <article><span>02</span><h2>材料默认在本机</h2><p>注册不等于上传；云端文件同步必须按项目明确开启。</p></article>
        <article><span>03</span><h2>分享边界说清楚</h2><p>安全入口可到期、可撤销；已下载或截屏的副本无法远程追回。</p></article>
      </section>
    </main>
  )
}

